using AuthLens.Application;
using AuthLens.Domain.Roles;
using AuthLens.Domain.Text;
using AuthLens.Domain.Users;

namespace AuthLens.Api;

/// <summary>Current population selection shared by every analytical view (Dashboard, SoD overview, Account Review, Release Roles, Employees).
/// Reuses existing memberships, direct managers and exact-name normalization. WP30 adds SAP (user group, user type, account validity, lock
/// status), Employee Directory (department, site, job title, AD account state; matched identities only), access (role, transaction code, role
/// type, organizational suffix) and governance (SoD risk, account review status) dimensions. Values combine with OR inside a dimension and with
/// AND between dimensions. Access filters consider currently valid assignments only. In the default user-population mode a user matches an
/// access dimension when any current assignment matches it, so role and transaction filters may be met by different assignments of the same
/// user; with <c>access_scope=matching</c> one current assignment must match every access filter at once, and access metrics count only those
/// assignments. Governance dimensions use the current evaluation (current SoD findings, current review state), never historical snapshots.</summary>
public static class SubjectSelection
{
    public static string Key(string username) => RoleNames.NormalizeUsername(username);
    public static readonly string[] Dimensions = ["user_groups", "user_types", "account_states", "lock_states", "departments", "sites", "titles", "ad_states",
        "roles", "tcodes", "role_types", "org_suffixes", "sod_risks", "review_states"];
    private static readonly string[] AccessDimensions = ["roles", "tcodes", "role_types", "org_suffixes"];
    public const int MaxValues = 200;

    /// <summary>SAP account validity from the imported account intervals: valid, future, expired or unknown (lock status is separate).</summary>
    public static string AccountState(SapUser user, DateOnly today)
    {
        var states = user.Accounts.Select(a => SapDates.IntervalStatus(a.ValidFrom, a.ValidTo, today)).ToList();
        return states.Contains("active") ? "valid" : states.Contains("future") ? "future" : states.Contains("expired") ? "expired" : "unknown";
    }
    /// <summary>locked when every account record is locked, unlocked when none is, unknown otherwise (as Account Review).</summary>
    public static string LockState(SapUser user)
    {
        var locks = user.Accounts.Select(a => a.Locked).ToHashSet();
        return locks.Count > 0 && locks.SetEquals([true]) ? "locked" : locks.Count > 0 && locks.SetEquals([false]) ? "unlocked" : "unknown";
    }
    public static bool IsCurrent(Assignment a, DateOnly today) => SapDates.IntervalStatus(a.ValidFrom, a.ValidTo, today) == "active";
    public static bool MatchingAccess(IQueryCollection query) => (query["access_scope"].FirstOrDefault() ?? "") == "matching";

    /// <summary>Organizational suffixes: final segments of business roles that occur under at least two role stems (the Access Package rule).</summary>
    public static HashSet<string> Suffixes(Snapshot snapshot) =>
        AccessPackage.NamingEvidence(snapshot.Catalogue.Ordered.Select(r => r.AgrName).Concat(snapshot.Users.Assignments.Select(a => a.RoleName))).Keys.ToHashSet(StringComparer.Ordinal);
    public static string? Suffix(string role, HashSet<string> suffixes)
    {
        var name = RoleNames.Normalize(role);
        if (RoleNames.Scope(name) != "business" || !name.Contains(':')) return null;
        var last = name[(name.LastIndexOf(':') + 1)..];
        return suffixes.Contains(last) ? last : null;
    }

    private static Dictionary<string, List<string>> Read(IQueryCollection query) =>
        Dimensions.ToDictionary(d => d, d => query[d].OfType<string>().Select(v => v.Trim()).Where(v => v.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList());

    /// <summary>Per-dimension assignment tests (attributes only; validity is checked by the caller). Null when no access dimension is active.</summary>
    private static Dictionary<string, Func<Assignment, bool>> AccessTests(Snapshot snapshot, Dictionary<string, List<string>> d)
    {
        var tests = new Dictionary<string, Func<Assignment, bool>>(StringComparer.Ordinal);
        if (d["roles"].Count > 0)
        {
            var roles = d["roles"].Select(RoleNames.Normalize).ToHashSet(StringComparer.Ordinal);
            tests["roles"] = a => roles.Contains(RoleNames.Normalize(a.RoleName)) || a.CatalogueRoles.Any(r => roles.Contains(RoleNames.Normalize(r)));
        }
        if (d["tcodes"].Count > 0) { var codes = d["tcodes"].ToHashSet(StringComparer.OrdinalIgnoreCase); tests["tcodes"] = a => a.Tcodes.Any(codes.Contains); }
        if (d["role_types"].Count > 0) { var types = d["role_types"].ToHashSet(StringComparer.OrdinalIgnoreCase); tests["role_types"] = a => types.Contains(RoleNames.Scope(a.RoleName)); }
        if (d["org_suffixes"].Count > 0)
        {
            var known = Suffixes(snapshot);
            var wanted = d["org_suffixes"].Select(RoleNames.Normalize).ToHashSet(StringComparer.Ordinal);
            tests["org_suffixes"] = a => Suffix(a.RoleName, known) is { } s && wanted.Contains(s);
        }
        return tests;
    }

    /// <summary>Assignment filter for access metrics in the matching-access mode: every active access filter must match the same assignment.</summary>
    public static Func<Assignment, bool>? MatchingAssignments(Snapshot snapshot, IQueryCollection query)
    {
        if (!MatchingAccess(query)) return null;
        var tests = AccessTests(snapshot, Read(query));
        return tests.Count == 0 ? null : a => tests.Values.All(t => t(a));
    }

    public static async Task<(HashSet<string>? Names, IResult? Error)> ResolveAsync(IServiceProvider services, IQueryCollection query, CancellationToken ct, bool includeSearch = false)
    {
        var groups = query["functional_groups"].OfType<string>().Where(v => v.Length > 0).Distinct().ToList();
        var managers = query["managers"].OfType<string>().Where(v => v.Length > 0).Distinct().ToList();
        var exact = V1Access.ParseUsernames(string.Join(' ', query["usernames"].OfType<string>()));
        var search = includeSearch ? (query["search"].FirstOrDefault() ?? "").Trim() : "";
        // Feature-specific legacy username text syntax remains with its existing handler.
        var legacyUsername = includeSearch ? (query["username"].FirstOrDefault() ?? "").Trim() : "";
        var dimensions = Read(query);
        var scope = query["access_scope"].FirstOrDefault() ?? "";
        if (groups.Count > 50 || managers.Count > 50 || exact.Requested.Count > 500 || exact.Invalid.Count > 0 || search.Length > 256 || legacyUsername.Length > 512
            || dimensions.Values.Any(v => v.Count > MaxValues || v.Any(x => x.Length > 200)))
            return (null, Results.Json(new { detail = "Choose at most 50 Functional Groups or managers, 500 valid exact SAP usernames and 200 values per filter." }, statusCode: 422));
        if (scope is not ("" or "population" or "matching"))
            return (null, Results.Json(new { detail = "access_scope must be population or matching." }, statusCode: 422));
        if (groups.Count == 0 && managers.Count == 0 && exact.Requested.Count == 0 && search.Length == 0 && legacyUsername.Length == 0 && dimensions.Values.All(v => v.Count == 0)) return (null, null);
        var snapshot = await services.GetRequiredService<SnapshotService>().GetAsync(ct);
        var settings = await services.GetRequiredService<V1Settings>().GetAsync(ct);
        if ((bool?)settings["features"]?["user_role_mapping"] == false || snapshot.Ids.Users is null)
            return (null, Results.Json(new { detail = "Organizational and exact SAP username filters require enabled, loaded User–Role Mapping data." }, statusCode: 409));
        Func<SapUser, bool>? keep = null;
        if (groups.Count > 0 || managers.Count > 0)
        {
            var directory = managers.Count > 0 ? V1Employees.Available(snapshot, settings) : null;
            var data = groups.Count > 0 ? await services.GetRequiredService<FunctionalGroupStore>().ReadAsync(ct) : new System.Text.Json.Nodes.JsonObject();
            keep = V1FunctionalGroups.Selection(snapshot, directory, data, groups, managers);
        }
        // Governance dimensions: the current SoD evaluation and the current account review state.
        HashSet<string>? sodUsers = null, reviewUsers = null;
        if (dimensions["sod_risks"].Count > 0)
        {
            var risks = dimensions["sod_risks"].ToHashSet(StringComparer.Ordinal);
            var model = await SodModelAsync(services, settings, ct);
            if (model is null) return (null, Results.Json(new { detail = "SoD risk filters require enabled SoD with a loaded SoD matrix." }, statusCode: 409));
            sodUsers = model.Where(p => p.Value.Findings.Keys.Any(risks.Contains)).Select(p => Key(p.Key)).ToHashSet(StringComparer.Ordinal);
        }
        if (dimensions["review_states"].Count > 0)
        {
            var wanted = dimensions["review_states"].ToHashSet(StringComparer.OrdinalIgnoreCase);
            var rows = (await V1AccountReview.CurrentAsync(services, ct)).Rows;
            reviewUsers = rows.Where(r => ReviewStates(r).Any(wanted.Contains)).Select(r => Key((string)r["username"]!)).ToHashSet(StringComparer.Ordinal);
        }
        var requested = exact.Requested.Select(Key).ToHashSet(StringComparer.Ordinal);
        var more = Dimensional(snapshot, settings, dimensions, scope == "matching");
        return (snapshot.Users.Users.Values.Where(u => (keep is null || keep(u)) && (more is null || more(u)) && (requested.Count == 0 || requested.Contains(Key(u.Username)))
                && (sodUsers is null || sodUsers.Contains(Key(u.Username))) && (reviewUsers is null || reviewUsers.Contains(Key(u.Username)))
                && (legacyUsername.Length == 0 || TextMatching.TextMatches(u.Username, legacyUsername))
                && (search.Length == 0 || TextMatching.TextMatches(string.Join(' ', new[] { u.Username }.Concat(u.Groups).Concat(u.Names.Select(n => n.First + " " + n.Last))), search)))
            .Select(u => Key(u.Username)).ToHashSet(StringComparer.Ordinal), null);
    }

    /// <summary>Review status of one Account Review row: completed, or pending (outdated reviews are also pending, as on the dashboard).</summary>
    private static IEnumerable<string> ReviewStates(Dictionary<string, object?> row)
    {
        if (V1AccountReview.Has(row, "reviewed")) { yield return "completed"; yield break; }
        yield return "pending";
        if ((bool)row["stale"]!) yield return "outdated";
    }

    /// <summary>The current SoD user model, or null when SoD is disabled or its inputs are not loaded.</summary>
    private static async Task<IReadOnlyDictionary<string, AuthLens.Domain.Sod.SodUserEntry>?> SodModelAsync(IServiceProvider services, System.Text.Json.Nodes.JsonObject settings, CancellationToken ct)
    {
        if ((bool?)settings["features"]?["sod"] != true) return null;
        try { return SodScope.Model(await SodScope.LoadAsync(services, "current", "active", null, ct)); }
        catch (OperationCanceledException) { throw; }
        catch (Exception) { return null; }   // missing matrix or mapping: reported as unavailable, never as an empty population
    }

    private static Func<SapUser, bool>? Dimensional(Snapshot snapshot, System.Text.Json.Nodes.JsonObject settings, Dictionary<string, List<string>> d, bool matching)
    {
        var plain = d.Where(p => p.Key is not ("sod_risks" or "review_states")).ToList();
        if (plain.All(p => p.Value.Count == 0)) return null;
        var ci = StringComparer.OrdinalIgnoreCase;
        HashSet<string> Set(string key) => d[key].ToHashSet(ci);
        var (userGroups, userTypes, accountStates, lockStates) = (Set("user_groups"), Set("user_types"), Set("account_states"), Set("lock_states"));
        var (departments, sites, titles, adStates) = (Set("departments"), Set("sites"), Set("titles"), Set("ad_states"));
        var access = AccessTests(snapshot, d);
        var needsDirectory = departments.Count + sites.Count + titles.Count + adStates.Count > 0;
        var directory = needsDirectory ? V1Employees.Available(snapshot, settings) : null;
        var owners = directory is not null ? AuthLens.Domain.Directory.EmployeeDirectory.SapEmailOwners(snapshot.Users.Users.Values) : null;
        var today = DateOnly.FromDateTime(DateTime.Now);
        return user =>
        {
            if (userGroups.Count > 0 && !user.Groups.Concat(user.Accounts.Select(a => a.UserGroup)).Any(userGroups.Contains)) return false;
            if (userTypes.Count > 0 && !user.Accounts.Select(a => a.UserType).Any(userTypes.Contains)) return false;
            if (accountStates.Count > 0 && !accountStates.Contains(AccountState(user, today))) return false;
            if (lockStates.Count > 0 && !lockStates.Contains(LockState(user))) return false;
            if (access.Count > 0)
            {
                var current = user.Assignments.Where(a => IsCurrent(a, today)).ToList();
                if (matching ? !current.Any(a => access.Values.All(t => t(a))) : !access.Values.All(t => current.Any(t))) return false;
            }
            if (needsDirectory)
            {
                // Directory dimensions apply to reliably matched identities only; an unmatched user never matches them (never inferred).
                if (directory is null || directory.MatchSapIdentity(user, owners!) is not ("matched", { } employee)) return false;
                string Field(string name) => employee.TryGetValue(name, out var value) ? value?.ToString() ?? "" : "";
                if (departments.Count > 0 && !departments.Contains(Field("department"))) return false;
                if (sites.Count > 0 && !sites.Contains(Field("site"))) return false;
                if (titles.Count > 0 && !titles.Contains(Field("title"))) return false;
                if (adStates.Count > 0 && !adStates.Contains(Field("account_status"))) return false;
            }
            return true;
        };
    }

    /// <summary>Selectable values with user counts for each dimension, from the current snapshots and evaluations only (nothing invented).
    /// Directory values come from matched identities; access values from currently valid assignments; large dimensions keep the 2,000 most
    /// frequent values. SoD and review values are listed only when that evaluation is available.</summary>
    public static async Task<Dictionary<string, object?>> OptionsAsync(IServiceProvider services, Snapshot snapshot, System.Text.Json.Nodes.JsonObject settings, CancellationToken ct)
    {
        var users = snapshot.Users.Users.Values.ToList();
        var today = DateOnly.FromDateTime(DateTime.Now);
        static object[] Count(IEnumerable<string> values, int limit = 2000) => values.Where(v => !string.IsNullOrWhiteSpace(v)).GroupBy(v => v, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(g => g.Count()).ThenBy(g => g.Key, StringComparer.OrdinalIgnoreCase).Take(limit).Select(g => (object)new { value = g.Key, count = g.Count() }).ToArray();
        var directory = V1Employees.Available(snapshot, settings);
        var matched = new List<Dictionary<string, object?>>();
        if (directory is not null)
        {
            var owners = AuthLens.Domain.Directory.EmployeeDirectory.SapEmailOwners(users);
            foreach (var user in users) if (directory.MatchSapIdentity(user, owners) is ("matched", { } employee)) matched.Add(employee);
        }
        string F(Dictionary<string, object?> e, string name) => e.TryGetValue(name, out var v) ? v?.ToString() ?? "" : "";
        var suffixes = Suffixes(snapshot);
        List<Assignment> Current(SapUser u) => u.Assignments.Where(a => IsCurrent(a, today)).ToList();
        var result = new Dictionary<string, object?>
        {
            ["user_groups"] = Count(users.SelectMany(u => u.Groups.Concat(u.Accounts.Select(a => a.UserGroup)).Distinct(StringComparer.OrdinalIgnoreCase))),
            ["user_types"] = Count(users.SelectMany(u => u.Accounts.Select(a => a.UserType).Distinct(StringComparer.OrdinalIgnoreCase))),
            ["account_states"] = Count(users.Select(u => AccountState(u, today))),
            ["lock_states"] = Count(users.Select(LockState)),
            ["departments"] = Count(matched.Select(e => F(e, "department"))), ["sites"] = Count(matched.Select(e => F(e, "site"))),
            ["titles"] = Count(matched.Select(e => F(e, "title"))), ["ad_states"] = Count(matched.Select(e => F(e, "account_status"))),
            ["roles"] = Count(users.SelectMany(u => Current(u).Select(a => RoleNames.Normalize(a.RoleName)).Distinct(StringComparer.Ordinal))),
            ["tcodes"] = Count(users.SelectMany(u => Current(u).SelectMany(a => a.Tcodes).Distinct(StringComparer.OrdinalIgnoreCase))),
            ["role_types"] = Count(users.SelectMany(u => Current(u).Select(a => RoleNames.Scope(a.RoleName)).Distinct(StringComparer.Ordinal))),
            ["org_suffixes"] = Count(users.SelectMany(u => Current(u).Select(a => Suffix(a.RoleName, suffixes)).OfType<string>().Distinct(StringComparer.Ordinal))),
            ["directory_available"] = directory is not null, ["matched_identities"] = matched.Count,
        };
        var model = await SodModelAsync(services, settings, ct);
        result["sod_available"] = model is not null;
        result["sod_risks"] = model is null ? Array.Empty<object>() : Count(model.Values.SelectMany(e => e.Findings.Keys));
        var rows = (await V1AccountReview.CurrentAsync(services, ct)).Rows;
        result["review_states"] = Count(rows.SelectMany(ReviewStates));
        return result;
    }
}
