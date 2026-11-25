using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json.Nodes;
using AuthLens.Api;
using Microsoft.Data.Sqlite;
using AuthLens.Application.Backups;

namespace AuthLens.Tests;

public sealed class ServerPreflightTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-preflight-").FullName;
    private string[] Options(bool wrongHost = false, bool expired = false)
    {
        using var certificate = TestCertificates.Create(["server.example.test"], [IPAddress.Parse("10.23.1.9")],
            from: DateTimeOffset.UtcNow.AddDays(-30), to: DateTimeOffset.UtcNow.AddDays(expired ? -1 : 30));
        var pfx = Path.Combine(_root, "server.pfx");
        var password = Path.Combine(_root, "certificate-password");
        File.WriteAllBytes(pfx, certificate.Export(X509ContentType.Pfx, "synthetic-preflight-password"));
        File.WriteAllText(password, "synthetic-preflight-password");
        return ["--data-dir", Path.Combine(_root, "absent-data"), "--listen", "10.23.1.9", "--port", "18799", "--network",
            "--allowed-hosts", wrongHost ? "wrong.example.test" : "server.example.test,10.23.1.9", "--cert", pfx, "--cert-password-file", password];
    }

    [Fact]
    public void Inspection_uses_host_TLS_policy_without_creating_data_token_or_persistent_key_storage()
    {
        var options = Options();
        using (var inspected = ServerConfiguration.Parse(options, _ => null, inspection: true).Certificate)
        {
            Assert.NotNull(inspected);
            if (OperatingSystem.IsWindows()) Assert.True(CertificatePolicy.HasEphemeralKey(inspected));
        }
        var result = MaintenanceCommands.ServerPreflight(options);
        Assert.True((bool)result["validated"]!);
        Assert.True((bool)result["read_only"]!);
        Assert.False((bool)result["database_opened_read_only"]!);
        Assert.False((bool)result["data_modified"]!);
        Assert.False(Directory.Exists(Path.Combine(_root, "absent-data")));
        Assert.DoesNotContain("synthetic-preflight-password", result.ToJsonString());
        Assert.Equal(2, Directory.GetFiles(_root).Length);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void Invalid_certificate_names_and_expiry_fail_before_data_initialization(bool wrongHost, bool expired)
    {
        var error = Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ServerPreflight(Options(wrongHost, expired)));
        Assert.Contains("certificate", error.Message, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("synthetic-preflight-password", error.Message);
        Assert.False(Directory.Exists(Path.Combine(_root, "absent-data")));
    }

    [Fact]
    public void Inspection_does_not_create_or_replace_an_existing_token_or_data_file()
    {
        var options = Options();
        var data = options[1]; Directory.CreateDirectory(data);
        var token = Path.Combine(data, "api-token"); File.WriteAllText(token, "synthetic-existing-sentinel");
        MaintenanceCommands.ServerPreflight(options);
        Assert.Equal("synthetic-existing-sentinel", File.ReadAllText(token));
        Assert.Single(Directory.GetFiles(data));
    }

    [Fact]
    public void Existing_database_is_verified_read_only_and_foreign_key_failures_are_refused()
    {
        var options = Options(); var data = options[1]; Directory.CreateDirectory(data);
        var database = Path.Combine(data, "authlens.sqlite3");
        using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Pooling = false }.ToString()))
        {
            connection.Open(); using var command = connection.CreateCommand();
            command.CommandText = "CREATE TABLE Parent(Id INTEGER PRIMARY KEY); CREATE TABLE Child(Id INTEGER PRIMARY KEY, ParentId INTEGER REFERENCES Parent(Id));";
            command.ExecuteNonQuery();
        }
        var before = File.ReadAllBytes(database);
        var keyError = Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ServerPreflight(options));
        Assert.Contains("configured host backup key", keyError.Message);
        Assert.Equal(before, File.ReadAllBytes(database));
        _ = BackupKeys.Create(Path.Combine(_root, "recovery.key"), data);
        var result = MaintenanceCommands.ServerPreflight(options);
        Assert.True((bool)result["database_opened_read_only"]!);
        Assert.False((bool)result["data_modified"]!);
        Assert.Equal(before, File.ReadAllBytes(database));
        using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Pooling = false }.ToString()))
        {
            connection.Open(); using var command = connection.CreateCommand();
            command.CommandText = "PRAGMA foreign_keys=OFF; INSERT INTO Child VALUES(1,999);"; command.ExecuteNonQuery();
        }
        before = File.ReadAllBytes(database);
        var error = Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ServerPreflight(options));
        Assert.Contains("integrity/foreign-key", error.Message);
        Assert.Equal(before, File.ReadAllBytes(database));
    }

    private string[] Endpoint(string[] dns, IPAddress[] ips, string listen, string? allowed, bool network = true)
    {
        using var certificate = TestCertificates.Create(dns, ips);
        var pfx = Path.Combine(_root, $"endpoint-{Guid.NewGuid():N}.pfx");
        var password = Path.Combine(_root, $"endpoint-{Guid.NewGuid():N}-password");
        File.WriteAllBytes(pfx, certificate.Export(X509ContentType.Pfx, "synthetic-endpoint-password"));
        File.WriteAllText(password, "synthetic-endpoint-password");
        var options = new List<string> { "--data-dir", Path.Combine(_root, "absent-data"), "--listen", listen, "--port", "18799", "--cert", pfx, "--cert-password-file", password };
        if (network) options.Add("--network");
        if (allowed is not null) { options.Add("--allowed-hosts"); options.Add(allowed); }
        return options.ToArray();
    }

    // D-004: the bind address is not an endpoint identity unless clients use it (it is an allowed host); DNS-only CA certificates are valid then.
    [Fact]
    public void Bind_address_is_required_only_when_it_is_an_allowed_host()
    {
        var dnsOnly = Endpoint(["enp-emea-dash1.example.test", "enp-emea-dash1"], [], "10.26.1.55", "enp-emea-dash1.example.test,enp-emea-dash1");
        Assert.True((bool)MaintenanceCommands.ServerPreflight(dnsOnly)["validated"]!);
        var info = MaintenanceCommands.CertificateInfo(dnsOnly);
        Assert.True((bool)info["usable"]!);
        Assert.Empty(info["missing_identities"]!.AsArray());
        Assert.Equal(2, info["required_identities"]!.AsArray().Count);

        var ipAccess = Endpoint(["enp-emea-dash1.example.test"], [], "10.26.1.55", "enp-emea-dash1.example.test,10.26.1.55");
        var error = Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ServerPreflight(ipAccess));
        Assert.Contains("'10.26.1.55'", error.Message);
        var missing = MaintenanceCommands.CertificateInfo(ipAccess);
        Assert.False((bool)missing["usable"]!);
        Assert.Equal("10.26.1.55", (string)missing["missing_identities"]!.AsArray().Single()!);

        var covered = Endpoint(["enp-emea-dash1.example.test"], [IPAddress.Parse("10.26.1.55")], "10.26.1.55", "enp-emea-dash1.example.test,10.26.1.55");
        Assert.True((bool)MaintenanceCommands.ServerPreflight(covered)["validated"]!);
    }

    [Fact]
    public void Runtime_and_preflight_share_the_identity_rule_including_wildcards_and_loopback()
    {
        var wildcard = Endpoint(["*.example.test"], [], "10.26.1.55", "lens.example.test");
        Assert.True((bool)MaintenanceCommands.ServerPreflight(wildcard)["validated"]!);
        var settings = ServerConfiguration.Parse(wildcard, _ => null, inspection: true);
        Assert.Equal(["lens.example.test"], CertificatePolicy.RequiredIdentities(settings));
        settings.Certificate!.Dispose();

        // Loopback: the local probe and browser address the loopback listen address.
        var loopback = Endpoint(["localhost"], [IPAddress.Loopback], "127.0.0.1", null, network: false);
        var local = ServerConfiguration.Parse(loopback, _ => null, inspection: true);
        Assert.Equal(["127.0.0.1"], CertificatePolicy.RequiredIdentities(local));
        local.Certificate!.Dispose();
        Assert.True((bool)MaintenanceCommands.ServerPreflight(loopback)["validated"]!);
        var dnsLoopback = Endpoint(["localhost"], [], "127.0.0.1", null, network: false);
        Assert.Contains("'127.0.0.1'", Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ServerPreflight(dnsLoopback)).Message);
    }

    [Fact]
    public void Preflight_and_info_describe_the_certificate_without_secret_material()
    {
        var options = Options();
        var described = (JsonObject)MaintenanceCommands.ServerPreflight(options)["certificate"]!;
        Assert.Matches("^[0-9A-F]{64}$", (string)described["thumbprint_sha256"]!);
        Assert.Contains("server.example.test", described["dns_names"]!.AsArray().Select(n => (string)n!));
        Assert.True((bool)described["self_signed"]!);
        var info = MaintenanceCommands.CertificateInfo(options);
        Assert.True((bool)info["read_only"]!);
        Assert.DoesNotContain("synthetic-preflight-password", info.ToJsonString());
        Assert.False(Directory.Exists(Path.Combine(_root, "absent-data")));
    }

    [Fact]
    public void Public_certificate_export_is_create_only_and_never_contains_the_private_key()
    {
        var options = Options();
        var target = Path.Combine(_root, "AuthLens-server.cer");
        var result = MaintenanceCommands.ExportPublicCertificate(options, target);
        Assert.False((bool)result["private_key_included"]!);
        using (var exported = X509CertificateLoader.LoadCertificateFromFile(target)) Assert.False(exported.HasPrivateKey);
        Assert.DoesNotContain("PRIVATE KEY", System.Text.Encoding.ASCII.GetString(File.ReadAllBytes(target)));
        var before = File.ReadAllBytes(target);
        Assert.Contains("already exists", Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ExportPublicCertificate(options, target)).Message);
        Assert.Equal(before, File.ReadAllBytes(target));
        Assert.Contains("directory", Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ExportPublicCertificate(options, _root)).Message);
        Assert.Contains(".cer", Assert.Throws<InvalidOperationException>(() => MaintenanceCommands.ExportPublicCertificate(options, Path.Combine(_root, "server.pfx.copy"))).Message);
    }

    public void Dispose() { Directory.Delete(_root, true); }
}
