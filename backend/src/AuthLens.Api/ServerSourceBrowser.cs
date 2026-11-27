namespace AuthLens.Api;

/// <summary>
/// WP33 host file picker: lists folders and CSV files on the AuthLens server for source selection, as the running service identity. Never a general
/// file manager (no create, rename, move, delete or content read) and never a filesystem-wide browser:
/// <list type="bullet">
/// <item>Only approved browse roots are listed: operator roots (AUTHLENS_SOURCE_ROOTS) and folders an administrator approved in Data Sources. A path
/// outside them is refused before the filesystem or network is touched, so an unapproved UNC target receives no SMB request.</item>
/// <item>Paths are canonicalized lexically first (no traversal, device path or alternate data stream); every directory from the volume root to the
/// listed folder must be a plain directory (no junction or symbolic link), and reparse points inside are skipped, never followed.</item>
/// <item>UNC targets must resolve to private addresses before any SMB contact (the same rule as source reads).</item>
/// <item>The AuthLens installation (data, keys, TLS, backups, deployment state) can never be a root, and entries inside it are never listed.</item>
/// <item>Authorization is enforced by the request boundary: browsing requires administration.</item>
/// </list>
/// </summary>
public static class ServerSourceBrowser
{
    public const int MaxEntries = 2000;
    /// <summary>Upper bound for one listing request, so an unavailable share cannot hold a request indefinitely.</summary>
    public static readonly TimeSpan BrowseTimeout = TimeSpan.FromSeconds(15);

    public sealed record Entry(string Name, string Path, string Kind, long? Size, DateTimeOffset? Modified, bool Supported);
    public sealed record Crumb(string Name, string Path);
    public sealed record Listing(string Host, string Path, string Root, string? Parent, IReadOnlyList<Crumb> Breadcrumbs, IReadOnlyList<Entry> Entries, bool Truncated, bool Network);
    public sealed record Location(string Name, string Path, string Kind, bool Network);

    /// <summary>Starting points: approved roots, and the folders of configured sources that lie inside an approved root. Reads no folder.</summary>
    public static IReadOnlyList<Location> Locations(HostSettings host, IEnumerable<string> configuredPaths)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
        var seen = new HashSet<string>(comparison);
        var result = new List<Location>();
        void Add(string path, string kind, string? name = null)
        {
            if (!seen.Add(path)) return;
            var label = name ?? (System.IO.Path.GetFileName(path) is { Length: > 0 } leaf ? leaf : path);
            result.Add(new(label, path, kind, path.StartsWith(@"\\", StringComparison.Ordinal)));
        }
        foreach (var root in host.SourceRoots) { try { Add(ServerSourcePolicy.CanonicalDirectory(root), "operator"); } catch (SourcePolicyException) { } }
        try { foreach (var root in ServerSourceAuthorization.Roots(host)) Add(root, "approved"); } catch (SourcePolicyException) { }
        foreach (var path in configuredPaths.Where(p => !string.IsNullOrWhiteSpace(p)))
        {
            try
            {
                var folder = System.IO.Path.GetDirectoryName(ServerSourcePolicy.Canonical(path));
                if (folder is not null && ServerSourcePolicy.BrowseRoot(host, folder) is not null) Add(folder, "configured");
            }
            catch (SourcePolicyException) { }
        }
        return result;
    }

    /// <summary>One folder inside an approved root. <paramref name="query"/> filters names (case-insensitive substring) in this folder;
    /// <paramref name="allFiles"/> also lists other files, marked unsupported. Errors surface as SourcePolicyException, UnauthorizedAccessException,
    /// DirectoryNotFoundException or IOException for the caller to classify.</summary>
    public static Listing Browse(HostSettings host, string path, string? query = null, bool allFiles = false)
    {
        if (host.Mode != HostMode.Server) throw new SourcePolicyException();
        var directory = ServerSourcePolicy.CanonicalDirectory(path);
        var root = ServerSourcePolicy.BrowseRoot(host, directory) ?? throw new SourcePolicyException();
        var installation = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(host.DataDirectory).TrimEnd(System.IO.Path.DirectorySeparatorChar))!;
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        bool Private(string item) => string.Equals(item, installation, comparison) || item.StartsWith(Path.TrimEndingDirectorySeparator(installation) + System.IO.Path.DirectorySeparatorChar, comparison);
        if (Private(directory)) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
        var network = directory.StartsWith(@"\\", StringComparison.Ordinal);
        // No SMB request before the target is known to be an approved, private enterprise address.
        if (network) ServerSourceAuthorization.CheckNetworkTarget(directory + System.IO.Path.DirectorySeparatorChar + "x.csv");
        for (string? item = directory; item is not null; item = System.IO.Path.GetDirectoryName(item))
        {
            var attributes = File.GetAttributes(item);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
            if (item == directory && (attributes & FileAttributes.Directory) == 0) throw new SourcePolicyException(SourcePolicyFailure.NotAFile);
        }
        var options = new EnumerationOptions { IgnoreInaccessible = true, RecurseSubdirectories = false, ReturnSpecialDirectories = false,
            AttributesToSkip = FileAttributes.ReparsePoint | FileAttributes.System | FileAttributes.Hidden | FileAttributes.Device };
        var entries = new List<Entry>();
        var truncated = false;
        var filter = query?.Trim() ?? "";
        foreach (var info in new DirectoryInfo(directory).EnumerateFileSystemInfos("*", options))
        {
            if (filter.Length > 0 && !info.Name.Contains(filter, StringComparison.OrdinalIgnoreCase)) continue;
            if (Private(info.FullName)) continue;
            var isDirectory = (info.Attributes & FileAttributes.Directory) != 0;
            var supported = !isDirectory && string.Equals(info.Extension, ".csv", StringComparison.OrdinalIgnoreCase) && !info.Name.Contains(':');
            if (!isDirectory && !supported && !allFiles) continue;
            if (entries.Count >= MaxEntries) { truncated = true; break; }
            entries.Add(new(info.Name, info.FullName, isDirectory ? "directory" : "file", isDirectory ? null : ((FileInfo)info).Length,
                new DateTimeOffset(info.LastWriteTimeUtc, TimeSpan.Zero), supported));
        }
        entries.Sort((a, b) => a.Kind != b.Kind ? (a.Kind == "directory" ? -1 : 1) : StringComparer.OrdinalIgnoreCase.Compare(a.Name, b.Name));
        var crumbs = new List<Crumb>();
        for (string? item = directory; item is not null; item = System.IO.Path.GetDirectoryName(item))
        {
            crumbs.Insert(0, new(System.IO.Path.GetFileName(item) is { Length: > 0 } leaf ? leaf : item, item));
            if (string.Equals(item, root, comparison)) break;
        }
        var parent = string.Equals(directory, root, comparison) ? null : System.IO.Path.GetDirectoryName(directory);
        return new(Environment.MachineName, directory, root, parent, crumbs, entries, truncated, network);
    }
}
