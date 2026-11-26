using System.Text.Json.Nodes;
using AuthLens.Application;
using AuthLens.Domain.Sod;

namespace AuthLens.Api;

/// <summary>WP37: <c>GET /api/sod/reviews/overview</c>, the operational Reviews Overview for one review context and the applied Work Queue
/// population filters. Every figure is derived from the same authoritative models as the existing pages, never recomputed independently:
/// the Work Queue items (<c>QueueAsync</c>: lifecycle, review coverage with manual or derived provenance, the frozen evidence of a period),
/// the remediation rows and actions (<c>RemediationDataAsync</c>, the Remediation page and the report's removal follow-up) and the period
/// index. Historical and resolved items are left out exactly as the Work Queue user progress does. A user in several groups counts in each
/// group row and once in every distinct total.</summary>
public static partial class V1SodGovernance
{
    private static readonly string[] ReviewKinds = ["assignment", "activity", "acceptance"];
    private static readonly string[] OverviewGroupings = ["sap_user_group", "functional_group", "manager", "department", "site"];

    private static async Task<IResult> ReviewsOverviewAsync(HttpContext http, CancellationToken ct)
    {
        var (q, error) = await QueryAsync(http, ct);
        if (error is not null) return error;
        var groupBy = http.Request.Query["group_by"].FirstOrDefault() ?? "sap_user_group";
        if (!OverviewGroupings.Contains(groupBy)) return Bad("Choose sap_user_group, functional_group, manager, department or site.");
        var services = http.RequestServices;
        var (scope, items, _) = await QueueAsync(http, q!, "", "", ct);
        var b = scope.Bundle;

        // ---- items: coverage, workload and decisions per review type; per user progress
        var coverage = new JsonObject();
        var decisions = new JsonObject();
        var users = new Dictionary<string, ReviewUser>(Ordinal);
        var historical = 0;
        foreach (var kind in ReviewKinds)
        {
            coverage[kind] = new JsonObject { ["total"] = 0, ["covered"] = 0, ["manual"] = 0, ["derived"] = 0, ["pending"] = 0, ["outdated"] = 0, ["investigate"] = 0 };
            decisions[kind] = new JsonObject();
        }
        foreach (var item in items)
        {
            var life = (string)item["lifecycle"]!;
            if (life is "Historical" or "Resolved") { historical++; continue; }
            var kind = (string)item["kind"]!;
            if (coverage[kind] is not JsonObject c) continue;   // only the three access-review types
            var reviewed = item["review_coverage"]?["reviewed"] is JsonValue r ? (bool)r : SodScope.Decided.Contains(life);
            var provenance = (string?)item["review_coverage"]?["provenance"] ?? "";
            void Bump(JsonObject target, string name) => target[name] = ((int?)target[name] ?? 0) + 1;
            Bump(c, "total");
            if (reviewed) { Bump(c, "covered"); Bump(c, provenance.StartsWith("Explicit", StringComparison.Ordinal) || provenance.Length == 0 ? "manual" : "derived"); }
            else if (life == "Outdated") Bump(c, "outdated");
            else if (life == "Investigate") Bump(c, "investigate");
            else Bump(c, "pending");
            Bump(decisions[kind]!.AsObject(), life.Length == 0 ? "Pending" : life);
            var user = (string)item["user"]!;
            if (!users.TryGetValue(user, out var row)) users[user] = row = new ReviewUser();
            row.Groups.UnionWith((item["groups"] as JsonArray ?? []).Select(g => (string)g!));
            row.Total++; if (reviewed) row.Decided++; if (life == "Outdated") row.Outdated++; if (life == "Removal required") row.Removal++;
        }
        foreach (var kind in ReviewKinds)
        {
            var c = coverage[kind]!.AsObject();
            c["outstanding"] = (int)c["total"]! - (int)c["covered"]!;   // pending + outdated + investigate, each item once
        }
        var people = users.Where(p => p.Value.Total > 0).ToList();
        int Count(Func<ReviewUser, bool> test) => people.Count(p => test(p.Value));
        var progress = new JsonObject
        {
            ["users"] = people.Count, ["complete"] = Count(u => u.Decided == u.Total), ["requiring_review"] = Count(u => u.Decided < u.Total),
            ["partial"] = Count(u => u.Decided > 0 && u.Decided < u.Total), ["not_started"] = Count(u => u.Decided == 0),
            ["with_outdated"] = Count(u => u.Outdated > 0), ["with_removal"] = Count(u => u.Removal > 0), ["historical_items"] = historical,
        };

        // ---- remediation: the Remediation page rows and actions; removal follow-up as in Reports and Evidence (one row per exact assignment)
        var (_, remediationRows, remediationSummary, actions, verify, reference) = await RemediationDataAsync(http, q!, ct);
        var removals = new Dictionary<string, JsonObject>(Ordinal);
        foreach (var row in remediationRows.Where(r => (string?)r["recommended"] == "Remove assignment")) removals.TryAdd((string)row["assignment_id"]!, row);
        var tracked = removals.Values.Where(r => (string?)r["action_status"] != "Not tracked").ToList();
        var (verification, _) = SodScope.RemovalVerification(actions, verify, reference);
        var remediation = new JsonObject
        {
            ["removal_recommended"] = removals.Count,
            ["awaiting_action"] = removals.Count - tracked.Count,
            ["open_actions"] = actions.Count(a => (string?)a["status"] is "Open" or "In progress"),
            ["overdue"] = remediationRows.Where(r => (bool)r["overdue"]!).Select(r => (string?)r["assignment_id"]).Distinct().Count(),
            ["completed_actions"] = actions.Count(a => (string?)a["status"] == "Completed"),
            ["verified_removals"] = (int)verification["verified"]!, ["verification"] = verification,
            ["investigate"] = (int?)remediationSummary["Investigate assignment"] ?? 0, ["compensating_controls"] = (int?)remediationSummary["Apply compensating control"] ?? 0,
        };

        // ---- review periods: global within the authorized scope (lifecycle states of the existing model only)
        var index = await services.GetRequiredService<SodPeriodStore>().ReadAsync(ct);
        var periods = index["items"]!.AsArray().OfType<JsonObject>().ToList();
        var states = new JsonObject();
        foreach (var period in periods) { var s = (string?)period["state"] ?? ""; states[s] = ((int?)states[s] ?? 0) + 1; }
        var periodSummary = new JsonObject
        {
            ["scope"] = "global", ["total"] = periods.Count, ["states"] = states,
            ["open"] = periods.Count(p => (string?)p["state"] is "Draft" or "In review"), ["awaiting_approval"] = periods.Count(p => (string?)p["state"] == "Ready for approval"),
            ["approved"] = periods.Count(p => (string?)p["state"] == "Approved"), ["closed"] = periods.Count(p => (string?)p["state"] == "Closed"),
            ["rejected"] = periods.Count(p => (string?)p["state"] == "Rejected"),
        };

        // ---- organizational progress: SAP User Group from the evidence itself; directory and Functional Group dimensions only for current evidence
        var current = b.Context == "current";
        var groups = new JsonObject { ["group_by"] = groupBy, ["available"] = true, ["reason"] = null, ["rows"] = new JsonArray() };
        Func<string, IEnumerable<(string Key, string Label)>>? keys = null;
        if (groupBy == "sap_user_group") keys = user => users[user].Groups.Count > 0 ? users[user].Groups.Select(g => (g, g)) : [("", "No SAP User Group")];
        else if (!current)
        {
            groups["available"] = false;
            groups["reason"] = "Frozen period evidence records SAP User Groups only; Functional Group, manager, department and site were not captured, and current data is never substituted.";
        }
        else
        {
            var snapshot = await services.GetRequiredService<SnapshotService>().GetAsync(ct);
            var settings = await services.GetRequiredService<V1Settings>().GetAsync(ct);
            var directory = V1Employees.Available(snapshot, settings);
            var byKey = snapshot.Users.Users.Values.GroupBy(u => SubjectSelection.Key(u.Username)).ToDictionary(g => g.Key, g => g.First(), Ordinal);
            var owners = directory is not null ? AuthLens.Domain.Directory.EmployeeDirectory.SapEmailOwners(snapshot.Users.Users.Values) : null;
            Dictionary<string, object?>? Employee(string user) =>
                directory is not null && byKey.TryGetValue(SubjectSelection.Key(user), out var sap) && directory.MatchSapIdentity(sap, owners!) is ("matched", { } e) ? e : null;
            if (groupBy == "functional_group")
            {
                var data = await services.GetRequiredService<FunctionalGroupStore>().ReadAsync(ct);
                var classes = FunctionalGroupStore.ClassificationMap(data);
                var labels = V1FunctionalGroups.Options(snapshot, directory, data)["functional_groups"]!.AsArray().OfType<JsonObject>().ToDictionary(o => (string)o["value"]!, o => (string)o["label"]!, Ordinal);
                keys = user => V1FunctionalGroups.GroupKeys(classes, user).Select(k => (k, labels.GetValueOrDefault(k, k)));
            }
            else if (directory is null)
            {
                groups["available"] = false;
                groups["reason"] = "Manager, department and site need an enabled Employee Directory with matched identities.";
            }
            else if (groupBy == "manager")
            {
                var labels = V1FunctionalGroups.Options(snapshot, directory, new JsonObject())["managers"]!.AsArray().OfType<JsonObject>().ToDictionary(o => (string)o["value"]!, o => (string)o["label"]!, Ordinal);
                keys = user => { var key = V1FunctionalGroups.ManagerKey(Employee(user)); return [(key, labels.GetValueOrDefault(key, "No manager"))]; };
            }
            else
            {
                var field = groupBy == "department" ? "department" : "site";
                keys = user => Employee(user) is { } e && e.TryGetValue(field, out var v) && v?.ToString() is { Length: > 0 } text ? [(text, text)] : [("", "Unmatched or not recorded")];
            }
        }
        if (keys is not null)
        {
            var table = new Dictionary<string, (string Label, int Users, int Complete)>(Ordinal);
            foreach (var (user, value) in people)
                foreach (var (key, label) in keys(user).DistinctBy(k => k.Key))
                {
                    var (rowLabel, rowUsers, rowComplete) = table.TryGetValue(key, out var found) ? found : (label, 0, 0);
                    table[key] = (rowLabel, rowUsers + 1, rowComplete + (value.Decided == value.Total ? 1 : 0));
                }
            groups["rows"] = new JsonArray([.. table.OrderBy(p => p.Value.Label, StringComparer.OrdinalIgnoreCase).Select(p => (JsonNode)new JsonObject
            {
                ["key"] = p.Key, ["label"] = p.Value.Label, ["users"] = p.Value.Users, ["complete"] = p.Value.Complete, ["requiring_review"] = p.Value.Users - p.Value.Complete,
            })]);
            groups["distinct_users"] = people.Count;
        }

        var result = await InfoAsync(http, b, ct);
        // "coverage" already holds the context coverage of InfoAsync.
        result["progress"] = progress; result["review_coverage"] = coverage; result["decisions"] = decisions; result["remediation"] = remediation;
        result["periods"] = periodSummary; result["groups"] = groups; result["filtered"] = QueueFilterNames.Concat(["functional_groups", "managers"]).Any(n => q!.S(n).Length > 0 || q!.L(n).Count > 0);
        return Json(result);
    }

    private sealed class ReviewUser
    {
        public int Total, Decided, Outdated, Removal;
        public SortedSet<string> Groups { get; } = new(StringComparer.Ordinal);
    }
}
