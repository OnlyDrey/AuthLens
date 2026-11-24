using AuthLens.Application;
using AuthLens.Domain.Roles;
using AuthLens.Domain.Text;

namespace AuthLens.Api;

/// <summary>Current organizational view selection. Reuses existing memberships, direct managers and exact-name normalization.</summary>
public static class SubjectSelection
{
    public static string Key(string username) => RoleNames.NormalizeUsername(username);
    public static async Task<(HashSet<string>? Names, IResult? Error)> ResolveAsync(IServiceProvider services, IQueryCollection query, CancellationToken ct, bool includeSearch = false)
    {
        var groups = query["functional_groups"].OfType<string>().Where(v => v.Length > 0).Distinct().ToList();
        var managers = query["managers"].OfType<string>().Where(v => v.Length > 0).Distinct().ToList();
        var exact = V1Access.ParseUsernames(string.Join(' ', query["usernames"].OfType<string>()));
        var search = includeSearch ? (query["search"].FirstOrDefault() ?? "").Trim() : "";
        // Feature-specific legacy username text syntax remains with its existing handler.
        var legacyUsername = includeSearch ? (query["username"].FirstOrDefault() ?? "").Trim() : "";
        if (groups.Count > 50 || managers.Count > 50 || exact.Requested.Count > 500 || exact.Invalid.Count > 0 || search.Length > 256 || legacyUsername.Length > 512)
            return (null, Results.Json(new { detail = "Choose at most 50 Functional Groups or managers and 500 valid exact SAP usernames." }, statusCode: 422));
        if (groups.Count == 0 && managers.Count == 0 && exact.Requested.Count == 0 && search.Length == 0 && legacyUsername.Length == 0) return (null, null);
        var snapshot = await services.GetRequiredService<SnapshotService>().GetAsync(ct);
        var settings = await services.GetRequiredService<V1Settings>().GetAsync(ct);
        if ((bool?)settings["features"]?["user_role_mapping"] == false || snapshot.Ids.Users is null)
            return (null, Results.Json(new { detail = "Organizational and exact SAP username filters require enabled, loaded User–Role Mapping data." }, statusCode: 409));
        Func<AuthLens.Domain.Users.SapUser, bool>? keep = null;
        if (groups.Count > 0 || managers.Count > 0)
        {
            var directory = managers.Count > 0 ? V1Employees.Available(snapshot, settings) : null;
            var data = groups.Count > 0 ? await services.GetRequiredService<FunctionalGroupStore>().ReadAsync(ct) : new System.Text.Json.Nodes.JsonObject();
            keep = V1FunctionalGroups.Selection(snapshot, directory, data, groups, managers);
        }
        var requested = exact.Requested.Select(Key).ToHashSet(StringComparer.Ordinal);
        return (snapshot.Users.Users.Values.Where(u => (keep is null || keep(u)) && (requested.Count == 0 || requested.Contains(Key(u.Username)))
                && (legacyUsername.Length == 0 || TextMatching.TextMatches(u.Username, legacyUsername))
                && (search.Length == 0 || TextMatching.TextMatches(string.Join(' ', new[] { u.Username }.Concat(u.Groups).Concat(u.Names.Select(n => n.First + " " + n.Last))), search)))
            .Select(u => Key(u.Username)).ToHashSet(StringComparer.Ordinal), null);
    }
}
