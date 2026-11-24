using System.Text.Json;
using AuthLens.Api;

namespace AuthLens.Tests;

public sealed class ServerSourcePolicyTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-source-policy-").FullName;
    public void Dispose() => Directory.Delete(_root, true);
    private HostSettings Host(params string[] roots) => new() { DataDirectory = Path.Combine(_root, "data"), SourceRoots = roots, AccessToken = HostSettings.NewToken() };

    [Fact]
    public void Explicit_roots_and_managed_sources_are_allowed_but_siblings_and_traversal_are_not()
    {
        var approved = Directory.CreateDirectory(Path.Combine(_root, "approved")).FullName;
        var file = Path.Combine(approved, "source.csv"); File.WriteAllText(file, "test");
        Assert.Equal(file, ServerSourcePolicy.Resolve(Host(approved), file));
        Assert.Throws<SourcePolicyException>(() => ServerSourcePolicy.Resolve(Host(), file));
        var sibling = Directory.CreateDirectory(approved + "-other").FullName;
        Assert.Throws<SourcePolicyException>(() => ServerSourcePolicy.Resolve(Host(approved), Path.Combine(sibling, "source.csv")));
        Assert.Throws<SourcePolicyException>(() => ServerSourcePolicy.Resolve(Host(approved), Path.Combine(approved, "..", "approved", "source.csv")));
        Assert.Throws<FileNotFoundException>(() => ServerSourcePolicy.Resolve(Host(approved), Path.Combine(approved, "missing.csv")));
        var managed = Directory.CreateDirectory(Path.Combine(_root, "data", "sources")).FullName;
        file = Path.Combine(managed, "source.csv"); File.WriteAllText(file, "test");
        Assert.Equal(file, ServerSourcePolicy.Resolve(Host(), file));
    }

    [Theory]
    [InlineData("relative.csv")]
    [InlineData("https://example.invalid/file.csv")]
    [InlineData("")]
    public void Arbitrary_browser_paths_are_denied(string path) => Assert.Throws<SourcePolicyException>(() => ServerSourcePolicy.Resolve(Host(), path));

    [Fact]
    public void Exact_authority_is_source_bound_host_bound_and_tamper_evident()
    {
        var host = Host();
        var path = Path.Combine(Path.GetTempPath(), "enterprise-" + Guid.NewGuid().ToString("N") + ".csv");
        ServerSourceAuthorization.Approve(host, "roles", path);
        Assert.True(ServerSourceAuthorization.Allows(host, "roles", path));
        Assert.False(ServerSourceAuthorization.Allows(host, "users", path));
        Assert.False(ServerSourceAuthorization.Allows(host, "roles", path + ".csv"));
        Assert.Throws<SourcePolicyException>(() => ServerSourceAuthorization.Allows(Host(), "roles", path)); // different protected host token
        var policy = Path.Combine(ServerSourceAuthorization.DirectoryPath(host), "authority.json");
        File.WriteAllText(policy, "{\"Payload\":\"{}\",\"Signature\":\"00\"}");
        Assert.Throws<SourcePolicyException>(() => ServerSourceAuthorization.Allows(host, "roles", path));
        Assert.Equal("admin", V1Auth.Permission("GET", "/api/server/sources/roles"));
        Assert.Equal("admin", V1Auth.Permission("POST", "/api/server/sources/roles/authorize"));
    }

    [Fact]
    public void Operator_policy_is_strict_and_separate_from_restorable_settings()
    {
        Assert.Empty(ServerSourcePolicy.Parse(null));
        Assert.Equal(_root, Assert.Single(ServerSourcePolicy.Parse(JsonSerializer.Serialize(new[] { _root }))));
        Assert.Throws<InvalidOperationException>(() => ServerSourcePolicy.Parse("[\"relative\"]"));
        Assert.Throws<InvalidOperationException>(() => ServerSourcePolicy.Parse("{\"roots\":[]}"));
        var configured = ServerConfiguration.Parse(["--data-dir", _root, "--source-dir", _root], _ => null, inspection: true);
        Assert.Equal(_root, Assert.Single(configured.SourceRoots));
        if (OperatingSystem.IsWindows())
            Assert.Equal(@"\\files.example.invalid\exports\AuthLens", Assert.Single(ServerSourcePolicy.Parse(JsonSerializer.Serialize(new[] { @"\\files.example.invalid\exports\AuthLens" }))));
        Assert.Equal("admin", V1Auth.Permission("POST", "/api/data-sources/roles/select"));
        Assert.Equal("policy_prohibited", V1Refresh.Category(new SourcePolicyException()).Category);
        Assert.Equal("access_denied", V1Refresh.Category(new UnauthorizedAccessException("secret path")).Category);
        Assert.DoesNotContain("secret", V1Refresh.Category(new UnauthorizedAccessException("secret path")).Message);
    }
}
