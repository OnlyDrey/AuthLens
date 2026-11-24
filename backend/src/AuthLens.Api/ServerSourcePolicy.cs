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
        if (string.IsNullOrWhiteSpace(path) || path.Length > 4096 || !Path.IsPathFullyQualified(path) || path.Contains("://", StringComparison.Ordinal)
            || path.Contains('\0') || !string.Equals(Path.GetExtension(path), ".csv", StringComparison.OrdinalIgnoreCase))
            throw new SourcePolicyException();
        var full = Path.GetFullPath(path);
        // On Windows refuse device paths and alternate data streams as well as traversal spellings.
        if (path.Split(['/', '\\']).Any(p => p is "." or "..") || OperatingSystem.IsWindows() &&
            (full.StartsWith(@"\\?\", StringComparison.Ordinal) || full.StartsWith(@"\\.\", StringComparison.Ordinal) || full[Path.GetPathRoot(full)!.Length..].Contains(':')))
            throw new SourcePolicyException();
        return full;
    }

    public static string Resolve(HostSettings host, string path, string? source = null)
    {
        if (host.Mode != HostMode.Server) return path;
        var full = Canonical(path);
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var roots = host.SourceRoots.Prepend(Path.Combine(host.DataDirectory, "sources"));
        if (!roots.Any(root => full.StartsWith(Path.EndsInDirectorySeparator(Path.GetFullPath(root)) ? Path.GetFullPath(root) : Path.GetFullPath(root) + Path.DirectorySeparatorChar, comparison))
            && !ServerSourceAuthorization.Allows(host, source, full))
            throw new SourcePolicyException();
        ServerSourceAuthorization.CheckNetworkTarget(full);
        // Check every ancestor, including the approved directory. Never follow junctions or symlinks.
        // Operators must prevent untrusted writers from replacing directories during a read.
        for (string? item = full; item is not null; item = Path.GetDirectoryName(item))
        {
            var attributes = File.GetAttributes(item); // preserves missing/access-denied errors; File.Exists would hide them
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new SourcePolicyException();
        }
        return full;
    }
}

public sealed class SourcePolicyException() : ArgumentException("Server source paths prohibited by policy. An administrator must authorize this exact source in Data Sources, or the server operator must approve its directory. Browser uploads remain available.");
public sealed class SourceChangedException() : IOException("Source changed since validation.");
