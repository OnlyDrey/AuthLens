using AuthLens.Api;

namespace AuthLens.Tests;

/// <summary>WP33 host file picker and approved browse folders (FILE-003, FILE-004): only approved roots are listed, nothing outside them is touched
/// (no SMB contact for unapproved UNC paths), links are never followed, AuthLens private state is never exposed, and approval refuses broad or
/// system locations. Temporary folders only.</summary>
public sealed class ServerSourceBrowserTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-browse-").FullName;
    private readonly Func<IEnumerable<string>> _systemLocations = ServerSourcePolicy.SystemLocations;
    public ServerSourceBrowserTests() => ServerSourcePolicy.SystemLocations = () => [];   // temporary folders live in the user profile
    public void Dispose()
    {
        ServerSourcePolicy.SystemLocations = _systemLocations;
        foreach (var link in Directory.EnumerateDirectories(_root, "*", SearchOption.AllDirectories).Where(d => (File.GetAttributes(d) & FileAttributes.ReparsePoint) != 0).ToList())
            Directory.Delete(link);
        Directory.Delete(_root, true);
    }
    private HostSettings Host(params string[] roots)
    {
        var data = Path.Combine(_root, "install", "data");
        Directory.CreateDirectory(data);
        return new() { DataDirectory = data, SourceRoots = roots, AccessToken = "synthetic-browse-token-0123456789abcdef" };
    }
    private string Exports()
    {
        var exports = Directory.CreateDirectory(Path.Combine(_root, "exports")).FullName;
        File.WriteAllText(Path.Combine(exports, "users.csv"), "a,b\n1,2\n");
        File.WriteAllText(Path.Combine(exports, "Roles.CSV"), "a\n1\n");
        File.WriteAllText(Path.Combine(exports, "notes.txt"), "x");
        var hidden = Path.Combine(exports, "hidden.csv"); File.WriteAllText(hidden, "x"); File.SetAttributes(hidden, FileAttributes.Hidden);
        Directory.CreateDirectory(Path.Combine(exports, "2026", "november"));
        File.WriteAllText(Path.Combine(exports, "2026", "november", "employees.csv"), "a\n1\n");
        return exports;
    }

    [Fact]
    public void An_operator_root_lists_folders_first_then_csv_files_with_breadcrumbs_and_no_hidden_or_unsupported_entries()
    {
        var exports = Exports();
        var listing = ServerSourceBrowser.Browse(Host(exports), exports);
        Assert.Equal(new[] { "2026", "Roles.CSV", "users.csv" }, listing.Entries.Select(e => e.Name));
        Assert.Equal("directory", listing.Entries[0].Kind);
        Assert.All(listing.Entries.Skip(1), e => { Assert.True(e.Supported); Assert.NotNull(e.Size); Assert.NotNull(e.Modified); });
        Assert.Null(listing.Parent);                                                   // the root has no parent inside the browsing scope
        var nested = ServerSourceBrowser.Browse(Host(exports), Path.Combine(exports, "2026", "november"));
        Assert.Equal(Path.Combine(exports, "2026"), nested.Parent);
        Assert.Equal(new[] { "exports", "2026", "november" }, nested.Breadcrumbs.Select(c => c.Name));
        var all = ServerSourceBrowser.Browse(Host(exports), exports, allFiles: true);
        Assert.Contains(all.Entries, e => e.Name == "notes.txt" && !e.Supported);
        Assert.DoesNotContain(all.Entries, e => e.Name == "hidden.csv");
        Assert.Equal(new[] { "users.csv" }, ServerSourceBrowser.Browse(Host(exports), exports, "USER").Entries.Select(e => e.Name));
    }

    [Fact]
    public void Paths_outside_approved_roots_are_refused_before_the_filesystem_or_network_is_touched()
    {
        var exports = Exports();
        var sibling = Directory.CreateDirectory(exports + "-other").FullName;
        Assert.Equal(SourcePolicyFailure.Authorization, Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), sibling)).Failure);
        // A folder that does not exist outside the roots: refused by policy, not by the filesystem (it was never looked at).
        Assert.Equal(SourcePolicyFailure.Authorization, Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), Path.Combine(_root, "never-created"))).Failure);
        // An unapproved UNC folder fails at once on policy: no DNS lookup or SMB request is made (TEST-NET address that would time out).
        var started = DateTime.UtcNow;
        Assert.Equal(SourcePolicyFailure.Authorization, Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), @"\\192.0.2.10\share\exports")).Failure);
        Assert.True(DateTime.UtcNow - started < TimeSpan.FromSeconds(2));
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), Path.Combine(exports, "..", Path.GetFileName(sibling))));
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), exports + ":stream"));
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), "relative"));
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(new HostSettings { DataDirectory = Path.Combine(_root, "d"), Mode = HostMode.Desktop, SourceRoots = [exports], AccessToken = "synthetic-browse-token-0123456789abcdef" }, exports));
    }

    [Fact]
    public void Junctions_are_skipped_inside_a_root_and_refused_as_a_browse_target()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exports = Exports();
        var outside = Directory.CreateDirectory(Path.Combine(_root, "outside")).FullName;
        File.WriteAllText(Path.Combine(outside, "secret.csv"), "x");
        var junction = Path.Combine(exports, "link");
        var mklink = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c mklink /J \"{junction}\" \"{outside}\"") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true })!;
        mklink.WaitForExit();
        Assert.True(Directory.Exists(junction));
        Assert.DoesNotContain(ServerSourceBrowser.Browse(Host(exports), exports).Entries, e => e.Name == "link");
        Assert.Equal(SourcePolicyFailure.UnsafePath, Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(Host(exports), junction)).Failure);
    }

    [Fact]
    public void The_AuthLens_installation_is_never_listed_even_below_a_broad_operator_root()
    {
        Exports();
        var host = Host(_root);
        var listing = ServerSourceBrowser.Browse(host, _root);
        Assert.DoesNotContain(listing.Entries, e => e.Name == "install");
        Assert.Contains(listing.Entries, e => e.Name == "exports");
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(host, Path.Combine(_root, "install", "data")));
    }

    [Fact]
    public void Administrators_approve_specific_folders_but_never_volume_share_installation_or_system_roots()
    {
        var exports = Exports();
        var host = Host();
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(host, exports));
        Assert.Equal(exports, ServerSourceAuthorization.ApproveRoot(host, exports + Path.DirectorySeparatorChar));
        Assert.Equal(new[] { exports }, ServerSourceAuthorization.Roots(host));
        Assert.Contains(ServerSourceBrowser.Browse(host, exports).Entries, e => e.Name == "users.csv");
        // Files below an approved folder are authorized for validation without an exact grant.
        Assert.Equal(Path.Combine(exports, "users.csv"), ServerSourcePolicy.Resolve(host, Path.Combine(exports, "users.csv"), "users"));
        Assert.Equal("approved_folder", ServerSourcePolicy.Authorization(host, "users", Path.Combine(exports, "users.csv")));
        foreach (var refused in new[] { Path.GetPathRoot(exports)!, @"\\fileserver.example.org\share", Path.Combine(_root, "install"), Path.Combine(_root, "install", "data", "x"), _root })
            Assert.Throws<SourcePolicyException>(() => ServerSourceAuthorization.ApproveRoot(host, refused));
        ServerSourcePolicy.SystemLocations = () => [_root];
        Assert.Throws<SourcePolicyException>(() => ServerSourceAuthorization.ApproveRoot(host, Path.Combine(_root, "exports", "2026")));
        Assert.True(ServerSourceAuthorization.RevokeRoot(host, exports));
        Assert.Throws<SourcePolicyException>(() => ServerSourceBrowser.Browse(host, exports));
        Assert.Throws<SourcePolicyException>(() => ServerSourcePolicy.Resolve(host, Path.Combine(exports, "users.csv"), "users"));
    }

    [Fact]
    public void Exact_file_authority_written_before_browse_folders_still_reads_and_keeps_its_grants()
    {
        var exports = Exports();
        var host = Host();
        ServerSourceAuthorization.Approve(host, "users", Path.Combine(exports, "users.csv"));
        Assert.Empty(ServerSourceAuthorization.Roots(host));
        ServerSourceAuthorization.ApproveRoot(host, Path.Combine(exports, "2026"));
        Assert.Equal(Path.Combine(exports, "users.csv"), ServerSourceAuthorization.Approved(host, "users"));    // exact grants survive a folder approval
        var locations = ServerSourceBrowser.Locations(host, [Path.Combine(exports, "2026", "november", "employees.csv"), Path.Combine(exports, "users.csv")]);
        Assert.Contains(locations, l => l.Kind == "approved" && l.Path == Path.Combine(exports, "2026"));
        Assert.Contains(locations, l => l.Kind == "configured" && l.Path == Path.Combine(exports, "2026", "november"));
        Assert.DoesNotContain(locations, l => l.Path == exports);                         // a configured file outside every root adds no browse location
    }
}
