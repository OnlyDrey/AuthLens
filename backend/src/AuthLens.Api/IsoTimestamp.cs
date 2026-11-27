using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace AuthLens.Api;

/// <summary>Repairs ISO timestamps that earlier builds wrote with a regional time separator ("2026-11-27T08.05.00+00:00" under, for example, a
/// da-DK or fi-FI service account; see <see cref="AuthLensHost.UseInvariantCulture"/>). Only that exact shape is rewritten to ':'; the instant
/// itself is unchanged, nothing is invented, and every other value is returned as it is.</summary>
public static partial class IsoTimestamp
{
    [GeneratedRegex(@"^(\d{4}-\d{2}-\d{2})T(\d{2})\.(\d{2})\.(\d{2})(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$")]
    private static partial Regex Dotted();

    public static string? Repair(string? value) =>
        value is null ? null : Dotted().Match(value) is { Success: true } m ? $"{m.Groups[1].Value}T{m.Groups[2].Value}:{m.Groups[3].Value}:{m.Groups[4].Value}{m.Groups[5].Value}{m.Groups[6].Value}" : value;

    /// <summary>A copy of a JSON string node with a repaired timestamp; other nodes are copied unchanged.</summary>
    public static JsonNode? Repair(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<string>(out var text) ? JsonValue.Create(Repair(text)) : node?.DeepClone();
}
