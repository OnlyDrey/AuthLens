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

    /// <summary>Canonical form of a directory path (WP33 browsing): absolute, no device path, alternate data stream or traversal spelling, no
    /// trailing separator except a volume root. Purely lexical.</summary>
    public static string CanonicalDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length > 4096 || !Path.IsPathFullyQualified(path) || path.Contains("://", StringComparison.Ordinal) || path.Contains('\0'))
            throw new SourcePolicyException(SourcePolicyFailure.InvalidPath);
        if (path.Split(['/', '\\']).Any(p => p is "." or "..")) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
        var full = Path.GetFullPath(path);
        if (OperatingSystem.IsWindows() && (full.StartsWith(@"\\?\", StringComparison.Ordinal) || full.StartsWith(@"\\.\", StringComparison.Ordinal) || full[Path.GetPathRoot(full)!.Length..].Contains(':')))
            throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
        var root = Path.GetPathRoot(full)!;
        return full.Length > root.Length ? Path.TrimEndingDirectorySeparator(full) : full;
    }

    /// <summary>Whether a folder may be approved for browsing: not a volume or share root, not inside or above the AuthLens installation, and not a
    /// Windows, program or user-profile location. Lexical only.</summary>
    public static void AssertBrowsableRoot(HostSettings host, string folder)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        bool Within(string item, string container) => !string.IsNullOrEmpty(container) && (string.Equals(item, Path.TrimEndingDirectorySeparator(container), comparison)
            || item.StartsWith(Path.TrimEndingDirectorySeparator(container) + Path.DirectorySeparatorChar, comparison));
        var root = Path.GetPathRoot(folder)!;
        var shareRoot = folder.StartsWith(@"\\", StringComparison.Ordinal) && folder[2..].Split('\\', StringSplitOptions.RemoveEmptyEntries).Length <= 2;
        if (string.Equals(Path.TrimEndingDirectorySeparator(root), folder, comparison) || shareRoot) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
        var installation = Path.GetDirectoryName(Path.GetFullPath(host.DataDirectory).TrimEnd(Path.DirectorySeparatorChar))!;
        foreach (var location in new[] { installation, Path.GetFullPath(host.DataDirectory) }.Concat(SystemLocations()))
            if (Within(folder, location) || Within(location, folder)) throw new SourcePolicyException(SourcePolicyFailure.UnsafePath);
    }

    /// <summary>Windows, program and user-profile locations that are never approved for browsing. Tests replace it to use temporary folders.</summary>
    internal static Func<IEnumerable<string>> SystemLocations = () => [Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) is { Length: > 0 } profile ? Path.GetDirectoryName(profile) ?? "" : ""];
    /// <summary>The approved browse root that contains a directory (operator roots from AUTHLENS_SOURCE_ROOTS and administrator-approved folders), or
    /// null. Lexical, at a directory boundary.</summary>
    public static string? BrowseRoot(HostSettings host, string directory)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        foreach (var root in host.SourceRoots.Select(r => CanonicalDirectory(r)).Concat(SafeRoots(host)))
            if (string.Equals(directory, root, comparison) || directory.StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, comparison)) return root;
        return null;
    }

    private static IEnumerable<string> SafeRoots(HostSettings host)
    {
        try { return ServerSourceAuthorization.Roots(host); }
        catch (SourcePolicyException) { return []; } // an invalid authority document grants nothing
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
        return host.SourceRoots.Prepend(Path.Combine(host.DataDirectory, "sources")).Concat(SafeRoots(host)).Any(root =>
            full.StartsWith(Path.EndsInDirectorySeparator(Path.GetFullPath(root)) ? Path.GetFullPath(root) : Path.GetFullPath(root) + Path.DirectorySeparatorChar, comparison));
    }

    /// <summary>How a configured path is authorized, without touching the source location: not_applicable (Desktop), none, managed, approved_root
    /// (operator directory), approved_folder (administrator-approved browse folder),
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
            if (host.SourceRoots.Any(root => full.StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar, comparison))) return "approved_root";
            if (InApprovedRoot(host, full)) return "approved_folder";
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
