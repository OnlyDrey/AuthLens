using System.Text.Json;

namespace AuthLens.Api;

/// <summary>Operator-owned authority, separate from restorable application settings. No credentials or browser-defined roots.</summary>
public static class ServerSourcePolicy
{
    public static IReadOnlyList<string> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            var roots = JsonSerializer.Deserialize<string[]>(json) ?? throw new JsonException();
            if (roots.Length > 32 || roots.Any(r => string.IsNullOrWhiteSpace(r) || !Path.IsPathFullyQualified(r) || r.Contains("://", StringComparison.Ordinal)))
                throw new JsonException();
            return roots.Select(Path.GetFullPath).Distinct(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal).ToArray();
        }
        catch (Exception error) when (error is JsonException or ArgumentException or NotSupportedException)
        { throw new InvalidOperationException("AUTHLENS_SOURCE_ROOTS must be a JSON array of at most 32 absolute source directories."); }
    }

    public static string Canonical(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length > 4096 || !Path.IsPathFullyQualified(path) || path.Contains("://", StringComparison.Ordinal) || path.Contains('\0'))
            throw new SourcePolicyException(SourcePolicyFailure.InvalidPath);
        if (!string.Equals(Path.GetExtension(path), ".csv", StringComparison.OrdinalIgnoreCase))
            // A local folder is named as such; a UNC path is never touched before authorization (no outbound SMB authentication).
            throw new SourcePolicyException(!path.StartsWith(@"\\", StringComparison.Ordinal) && !path.StartsWith("//", StringComparison.Ordinal) && Directory.Exists(path)
                ? SourcePolicyFailure.NotAFile : SourcePolicyFailure.InvalidPath);
        var full = Path.GetFullPath(path);
        // On Windows refuse device paths and alternate data streams as well as traversal spellings.
        if (path.Split(['/', '\\']).Any(p => p is "." or "..") || OperatingSystem.IsWindows() &&
            (full.StartsWith(@"\\?\", StringComparison.Ordinal) || full.StartsWith(@"\\.\", StringComparison.Ordinal) || full[Path.GetPathRoot(full)!.Length..].Contains(':')))
            throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
        return full;
    }

    public static string Resolve(HostSettings host, string path, string? source = null)
    {
        if (host.Mode != HostMode.Server) return path;
        var full = Canonical(path);
        if (!InApprovedRoot(host, full) && !ServerSourceAuthorization.Allows(host, source, full))
            throw new SourcePolicyException();
        ServerSourceAuthorization.CheckNetworkTarget(full);
        // Check every ancestor, including the approved directory. Never follow junctions or symlinks.
        // Operators must prevent untrusted writers from replacing directories during a read.
        for (string? item = full; item is not null; item = Path.GetDirectoryName(item))
        {
            var attributes = File.GetAttributes(item); // preserves missing/access-denied errors; File.Exists would hide them
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
            if (item == full && (attributes & FileAttributes.Directory) != 0) throw new SourcePolicyException(SourcePolicyFailure.NotAFile);
        }
        return full;
    }

    /// <summary>Lexical containment in the managed upload folder or an operator-approved root, at a directory boundary. No filesystem access.</summary>
    public static bool InApprovedRoot(HostSettings host, string full)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        return host.SourceRoots.Prepend(Path.Combine(host.DataDirectory, "sources")).Any(root =>
            full.StartsWith(Path.EndsInDirectorySeparator(Path.GetFullPath(root)) ? Path.GetFullPath(root) : Path.GetFullPath(root) + Path.DirectorySeparatorChar, comparison));
    }

    /// <summary>How a configured path is authorized, without touching the source location: not_applicable (Desktop), none, managed, approved_root,
    /// exact, required (reauthorization needed, e.g. after restore or revocation) or invalid (path or authority refused).</summary>
    public static string Authorization(HostSettings host, string? source, string path)
    {
        if (host.Mode != HostMode.Server) return "not_applicable";
        if (string.IsNullOrWhiteSpace(path)) return "none";
        try
        {
            var full = Canonical(path);
            var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
            var managed = Path.GetFullPath(Path.Combine(host.DataDirectory, "sources"));
            if (full.StartsWith(Path.TrimEndingDirectorySeparator(managed) + Path.DirectorySeparatorChar, comparison)) return "managed";
            if (InApprovedRoot(host, full)) return "approved_root";
            return ServerSourceAuthorization.Allows(host, source, full) ? "exact" : "required";
        }
        catch (Exception error) when (error is SourcePolicyException or IOException or UnauthorizedAccessException) { return "invalid"; }
    }
}

/// <summary>Why a server source path was refused: authorization (the default: not authorized exactly or by an approved directory), an invalid path
/// (not an absolute .csv path), a folder instead of a file, or an unsafe form (device path, alternate data stream, traversal, junction or link).</summary>
public enum SourcePolicyFailure { Authorization, InvalidPath, NotAFile, UnsafePath }

public sealed class SourcePolicyException(SourcePolicyFailure failure = SourcePolicyFailure.Authorization) : ArgumentException(failure switch
{
    SourcePolicyFailure.InvalidPath => "Enter the absolute path of a .csv file on the AuthLens server, for example D:\\Exports\\users.csv or \\\\server.domain.local\\share\\users.csv. Browser uploads remain available.",
    SourcePolicyFailure.NotAFile => "The path names a folder, not a CSV file. Enter the complete path of the .csv file.",
    SourcePolicyFailure.UnsafePath => "The path uses an unsupported form (device path, alternate data stream, traversal, junction or symbolic link). Use a plain path to the CSV file.",
    _ => "Server source paths prohibited by policy. An administrator must authorize this exact source in Data Sources, or the server operator must approve its directory. Browser uploads remain available.",
})
{
    public SourcePolicyFailure Failure { get; } = failure;
}
public sealed class EmptySourceException() : IOException("The CSV contains no usable records (empty or header only). Previous data is retained.");
public sealed class SourceChangedException() : IOException("Source changed since validation.");
