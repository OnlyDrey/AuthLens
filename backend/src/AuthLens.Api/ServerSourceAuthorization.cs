using System.Net;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace AuthLens.Api;

/// <summary>Exact-file administrator authority. Outside restorable data, authenticated to this host token and data path.
/// Restoring settings never grants filesystem authority. No directory browsing, share credentials or wildcard grants.</summary>
public static class ServerSourceAuthorization
{
    private static readonly object Gate = new();
    private sealed record Document(int Schema, string Data, Dictionary<string, string> Files);
    private sealed record Envelope(string Payload, string Signature);
    private static string Data(HostSettings host) => OperatingSystem.IsWindows() ? Path.GetFullPath(host.DataDirectory).TrimEnd('\\', '/').ToUpperInvariant() : Path.GetFullPath(host.DataDirectory).TrimEnd('/');
    public static string DirectoryPath(HostSettings host) => Path.Combine(Path.GetDirectoryName(Path.GetFullPath(host.DataDirectory).TrimEnd(Path.DirectorySeparatorChar))!,
        ".authlens-source-policy-" + Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Data(host))))[..16]);
    private static byte[] Sign(HostSettings host, string text) => HMACSHA256.HashData(Encoding.UTF8.GetBytes(host.AccessToken), Encoding.UTF8.GetBytes("AuthLens-source-authority-v1\0" + text));
    private static void NoLinks(string path)
    {
        for (string? item = path; item is not null; item = Path.GetDirectoryName(item))
            if ((File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0) throw new SourcePolicyException();
    }
    private static Document Read(HostSettings host)
    {
        var directory = DirectoryPath(host);
        try { NoLinks(directory); }
        catch (DirectoryNotFoundException) { return new(1, Data(host), []); }
        catch (FileNotFoundException) { return new(1, Data(host), []); }
        var path = Path.Combine(directory, "authority.json");
        try
        {
            NoLinks(path);
            if (new FileInfo(path).Length > 32768) throw new SourcePolicyException();
            var envelope = JsonSerializer.Deserialize<Envelope>(File.ReadAllText(path)) ?? throw new SourcePolicyException();
            if (!CryptographicOperations.FixedTimeEquals(Sign(host, envelope.Payload), Convert.FromHexString(envelope.Signature))) throw new SourcePolicyException();
            var doc = JsonSerializer.Deserialize<Document>(envelope.Payload) ?? throw new SourcePolicyException();
            if (doc.Schema != 1 || doc.Data != Data(host) || doc.Files.Count > 4 || doc.Files.Any(p => !V1DataSources.Names.ContainsKey(p.Key))) throw new SourcePolicyException();
            return doc;
        }
        catch (FileNotFoundException) { if (Directory.EnumerateFileSystemEntries(directory).Any()) throw new SourcePolicyException(); return new(1, Data(host), []); }
        catch (Exception error) when (error is JsonException or FormatException) { throw new SourcePolicyException(); }
    }
    public static bool Allows(HostSettings host, string? source, string path)
    {
        if (source is null) return false;
        lock (Gate) return Read(host).Files.TryGetValue(source, out var approved) && string.Equals(approved, path, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    }
    public static void Approve(HostSettings host, string source, string path)
    {
        if (!V1DataSources.Names.ContainsKey(source)) throw new SourcePolicyException();
        path = ServerSourcePolicy.Canonical(path); // purely lexical: no network authentication before explicit approval
        // Application internals are never web-authorized source locations. Managed CSV copies already have a separate trusted boundary.
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var root = Path.GetDirectoryName(Path.GetFullPath(host.DataDirectory).TrimEnd(Path.DirectorySeparatorChar))!;
        if (path.StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, comparison)) throw new SourcePolicyException();
        lock (Gate)
        {
            var doc = Read(host);
            var directory = DirectoryPath(host);
            if (!Directory.Exists(directory))
            {
                if (OperatingSystem.IsWindows())
                {
                    var security = new DirectorySecurity(); security.SetAccessRuleProtection(true, false);
                    foreach (var sid in new[] { WindowsIdentity.GetCurrent().User!, new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
                        security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
                    new DirectoryInfo(directory).Create(security);
                }
                else Directory.CreateDirectory(directory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }
            NoLinks(directory);
            doc.Files[source] = path;
            var payload = JsonSerializer.Serialize(doc);
            var temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                File.WriteAllText(temporary, JsonSerializer.Serialize(new Envelope(payload, Convert.ToHexStringLower(Sign(host, payload)))));
                File.Move(temporary, Path.Combine(directory, "authority.json"), true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
    }
    public static void CheckNetworkTarget(string path)
    {
        if (!OperatingSystem.IsWindows() || !path.StartsWith(@"\\", StringComparison.Ordinal)) return;
        var parts = path[2..].Split('\\');
        if (parts.Length < 3 || parts[0].Length == 0 || parts[1].Length == 0 || parts[1].EndsWith('$') || parts[0].Contains('@')) throw new SourcePolicyException();
        // No SMB request is issued to an unapproved/public target. Enterprise DNS and SMB signing/referral policy remain host responsibilities.
        var addresses = Dns.GetHostAddresses(parts[0]);
        if (addresses.Length == 0 || addresses.Any(a => !IPAddress.IsLoopback(a) && !NetworkPolicy.IsPrivate(a))) throw new SourcePolicyException();
    }
}
