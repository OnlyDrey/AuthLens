using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Application.Backups;

namespace AuthLens.Tests;

/// <summary>Backup cryptography: scrypt against RFC 7914, the SLBAK3 segmented AES-256-GCM envelope (boundaries, tampering, truncation, wrong keys), and
/// decryption of SAP Lens 1 SLBAK2 archives written by v1 backup_crypto (Fixtures/backups, tools/backup_v1_reference.py).</summary>
public sealed class BackupCryptoTests
{
    private static string Fixture(string name) => Path.Combine(AppContext.BaseDirectory, "Fixtures", "backups", name);

    [Theory]
    [InlineData("", "", 16, 1, 1, "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")]
    [InlineData("password", "NaCl", 1024, 8, 16, "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")]
    public void Scrypt_matches_rfc_7914(string password, string salt, int n, int r, int p, string expected) =>
        Assert.Equal(expected, Convert.ToHexStringLower(Scrypt.Derive(Encoding.ASCII.GetBytes(password), Encoding.ASCII.GetBytes(salt), n, r, p, 64)));

    [Fact]
    public void Key_status_distinguishes_configuration_states_without_exposing_material()
    {
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable(BackupKeys.EnvironmentVariable))) return; // host-level override would mask the data-directory pointer
        var root = Directory.CreateTempSubdirectory("authlens-key-status-").FullName;
        try
        {
            var data = Directory.CreateDirectory(Path.Combine(root, "data")).FullName;
            var keys = Directory.CreateDirectory(Path.Combine(root, "keys")).FullName;
            var path = Path.Combine(keys, "host.key");
            Assert.Equal("not_configured", (string)BackupKeys.Status(data)["state"]!);
            Assert.False((bool)BackupKeys.Status(data)["configured"]!);
            var created = BackupKeys.Create(path, data);
            Assert.Equal("usable", (string)created["state"]!); Assert.True((bool)created["usable"]!); Assert.True((bool)created["escrow_pending"]!);
            var material = File.ReadAllText(path).Trim();
            Assert.DoesNotContain(material, created.ToJsonString()); Assert.DoesNotContain(path, created.ToJsonString());
            if (OperatingSystem.IsWindows())
            {
                var info = new FileInfo(path); var security = info.GetAccessControl();
                var deny = new System.Security.AccessControl.FileSystemAccessRule(System.Security.Principal.WindowsIdentity.GetCurrent().User!, System.Security.AccessControl.FileSystemRights.ReadData, System.Security.AccessControl.AccessControlType.Deny);
                security.AddAccessRule(deny); info.SetAccessControl(security);
                try { var status = BackupKeys.Status(data); Assert.Equal("inaccessible", (string)status["state"]!); Assert.True((bool)status["configured"]!); Assert.False((bool)status["escrow_verified"]!); }
                finally { security.RemoveAccessRule(deny); info.SetAccessControl(security); }
            }
            else
            {
                File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.GroupRead);
                Assert.Equal("unsafe_permissions", (string)BackupKeys.Status(data)["state"]!);
                File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            }
            File.WriteAllText(path, "not-a-key\n");
            Assert.Equal("invalid", (string)BackupKeys.Status(data)["state"]!);
            File.Delete(path);
            var missing = BackupKeys.Status(data);
            Assert.Equal("missing", (string)missing["state"]!); Assert.True((bool)missing["configured"]!); Assert.False((bool)missing["usable"]!);
            Assert.Contains("do not create a new key", (string)missing["action"]!);
            File.WriteAllText(Path.Combine(data, "backup-key-location.json"), "{");
            Assert.Equal("location_unreadable", (string)BackupKeys.Status(data)["state"]!);
        }
        finally { Directory.Delete(root, true); }
    }

    private static byte[] Seal(byte[] plain, string passphrase, byte[]? host)
    {
        using var output = new MemoryStream();
        BackupArchive.Seal(new MemoryStream(plain), output, passphrase, host);
        return output.ToArray();
    }

    private static byte[] Unseal(byte[] archive, string secret, byte[]? host)
    {
        using var output = new MemoryStream();
        BackupArchive.Unseal(new MemoryStream(archive), output, secret, host);
        return output.ToArray();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(BackupArchive.Segment - 1)]
    [InlineData(BackupArchive.Segment)]
    [InlineData(BackupArchive.Segment + 1)]
    [InlineData(2 * BackupArchive.Segment)]
    public void Host_key_archives_round_trip_at_segment_boundaries(int size)
    {
        var host = RandomNumberGenerator.GetBytes(32);
        var plain = RandomNumberGenerator.GetBytes(size);
        Assert.Equal(plain, Unseal(Seal(plain, "", host), "", host));
    }

    [Fact]
    public void Passphrase_archives_round_trip_and_wrong_secrets_tampering_and_truncation_fail()
    {
        var plain = RandomNumberGenerator.GetBytes(BackupArchive.Segment + 5000);
        const string passphrase = "Synthetic backup passphrase æøå";
        var archive = Seal(plain, passphrase, null);
        Assert.Equal(plain, Unseal(archive, passphrase, null));
        Assert.Throws<BackupException>(() => Unseal(archive, "Wrong backup passphrase!!", null));
        Assert.Throws<BackupException>(() => Unseal(archive, "short", null));
        var tampered = (byte[])archive.Clone();
        tampered[^100] ^= 1;
        Assert.Throws<BackupException>(() => Unseal(tampered, passphrase, null));
        var header = (byte[])archive.Clone();
        header[20] ^= 1;                                                              // inside the authenticated header
        Assert.Throws<BackupException>(() => Unseal(header, passphrase, null));
        // Dropping the final segment leaves a non-final segment last: refused, never accepted as a shorter archive.
        Assert.Throws<BackupException>(() => Unseal(archive[..(archive.Length - (5000 + BackupArchive.Tag))], passphrase, null));
        Assert.Throws<BackupException>(() => Unseal(archive[..30], passphrase, null));
    }

    [Fact]
    public void Local_key_operations_preserve_existing_archives_and_audit_without_key_material()
    {
        var root = Directory.CreateTempSubdirectory("saplens-local-keys-").FullName;
        try
        {
            var data = Path.Combine(root, "data"); var first = Path.Combine(root, "host.key"); var copy = Path.Combine(root, "recovery.key");
            BackupKeys.Create(first, data);
            var key = BackupKeys.Host(data)!; var sealedArchive = Seal([1, 2, 3], "", key);
            Assert.Throws<BackupException>(() => BackupKeys.Create(Path.Combine(root, "replacement.key"), data));
            Assert.False(File.Exists(Path.Combine(root, "replacement.key")));
            BackupKeys.Export(copy, data);
            Assert.Equal(key, BackupKeys.Host(data));
            Assert.Throws<BackupException>(() => BackupKeys.Export(copy, data));
            Assert.True((bool)BackupKeys.VerifyFile(copy, data, "synthetic-operator", DateTimeOffset.UtcNow)["escrow_verified"]!);
            Assert.Equal([1, 2, 3], Unseal(sealedArchive, File.ReadAllText(copy).Trim(), null));
            var different = Path.Combine(root, "other.key"); BackupKeys.WritePrivate(different, Encoding.ASCII.GetBytes(Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))));
            Assert.Throws<BackupException>(() => BackupKeys.Use(different, data));
            Assert.Equal(key, BackupKeys.Host(data));
            var audit = File.ReadAllText(Path.Combine(data, "backup-key-audit.jsonl"));
            Assert.Contains("recovery.exported", audit); Assert.Contains("recovery.verified", audit);
            Assert.DoesNotContain(Convert.ToBase64String(key), audit);
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void A_host_key_archive_needs_the_matching_key_or_its_recovery_copy()
    {
        var host = RandomNumberGenerator.GetBytes(32);
        var archive = Seal([1, 2, 3], "", host);
        Assert.Throws<BackupException>(() => Unseal(archive, "", RandomNumberGenerator.GetBytes(32)));
        Assert.Equal([1, 2, 3], Unseal(archive, Convert.ToBase64String(host), null));     // the escrowed recovery copy on another host
    }

    [Theory]
    [InlineData("v1-host.slbak")]
    [InlineData("v1-passphrase.slbak")]
    public void Sap_lens_1_archives_decrypt(string name)
    {
        var keys = JsonNode.Parse(File.ReadAllText(Fixture("keys.json")))!;
        var host = Convert.FromBase64String((string)keys["host_key"]!);
        using var stream = File.OpenRead(Fixture(name));
        var plain = name.Contains("host") ? BackupArchive.UnsealV1(stream, "", host) : BackupArchive.UnsealV1(stream, (string)keys["passphrase"]!, null);
        Assert.Equal(File.ReadAllBytes(Fixture("payload.bin")), plain);
        using var again = File.OpenRead(Fixture(name));
        Assert.Throws<BackupException>(() => BackupArchive.UnsealV1(again, "Wrong v1 backup passphrase", RandomNumberGenerator.GetBytes(32)));
    }
}
