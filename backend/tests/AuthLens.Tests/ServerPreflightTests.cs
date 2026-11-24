using System.Net;
using System.Security.Cryptography.X509Certificates;
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

    public void Dispose() { Directory.Delete(_root, true); }
}
