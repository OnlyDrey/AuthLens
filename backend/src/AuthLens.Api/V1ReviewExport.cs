using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Application;
using AuthLens.Domain.Roles;
using AuthLens.Domain.Sod;

namespace AuthLens.Api;

/// <summary>Configurable Work Queue export: <c>GET /api/sod/queue/export/configured</c>. Two exportable units, both built on the authoritative review state
/// of the selected review context and the applied Work Queue filters (server side, across every page):
/// <list type="bullet">
/// <item><c>unit=role_removal</c>: one row per exact SAP user and role whose every visible assignment of that exact role is decided
/// <c>Removal required</c> (the assignment decision <c>Remove</c>). A user and role with differing assignment decisions is ambiguous and is
/// excluded and counted; activity and risk decisions never become role removals (the remediation model calls them Investigate).</item>
/// <item><c>unit=review_items</c>: the Work Queue items (role, activity and risk reviews), filtered by review type and lifecycle state.</item>
/// </list>
/// Columns are explicit and ordered; nothing unselected is appended. Identifiers (username, role, review item) are written exactly; free text
/// gets the existing formula guard. UTF-8 with BOM, ';' or ',' with quoting only where a value needs it. <c>preview=true</c> returns the same rows
/// as JSON (first 10) with totals. Nothing is written to decisions, remediation or evidence.</summary>
public static partial class V1SodGovernance
{
    private static readonly Dictionary<string, string> ExportColumns = new(Ordinal)
    {
        ["username"] = "SAP username", ["role"] = "Role name", ["role_description"] = "Role description", ["review_type"] = "Review type",
        ["item"] = "Review item", ["risks"] = "Risks", ["employee"] = "Employee name", ["user_group"] = "SAP user group",
        ["functional_group"] = "Functional group", ["department"] = "Department", ["manager"] = "Manager", ["review_status"] = "Review status",
        ["review_comment"] = "Review comment", ["reviewed_by"] = "Reviewed by", ["review_date"] = "Review date",
    };
    private static readonly HashSet<string> RoleRemovalColumns = ["username", "role", "role_description", "employee", "user_group", "functional_group", "department", "manager", "review_status", "review_comment", "reviewed_by", "review_date"];
    private static readonly HashSet<string> ReviewItemColumns = ["username", "review_type", "item", "risks", "role_description", "employee", "user_group", "functional_group", "department", "manager", "review_status", "review_comment", "reviewed_by", "review_date"];
    /// <summary>Columns that need current data (catalogue, SAP names, Employee Directory, Functional Groups): refused for frozen periods.</summary>
    private static readonly HashSet<string> CurrentOnlyColumns = ["role_description", "employee", "functional_group", "department", "manager"];
    private static readonly HashSet<string> IdentifierColumns = ["username", "role", "item"];
    private static readonly string[] ExportLifecycles = ["Pending", "Approved", "Keep", "Accepted", "Conditional", "Removal required", "Investigate", "Rejected", "Outdated"];
    private static readonly Dictionary<string, string> KindLabels = new(Ordinal) { ["assignment"] = "Role review", ["activity"] = "Activity review", ["acceptance"] = "Risk review" };

    private sealed record ExportRow(string User, string Sort, Dictionary<string, string> Values);

    private static async Task<IResult> ReviewExportAsync(HttpContext http, CancellationToken ct)
    {
        var (q, error) = await QueryAsync(http, ct);
        if (error is not null) return error;
        var query = http.Request.Query;
        var unit = query["unit"].FirstOrDefault() ?? "role_removal";
        var columns = query["columns"].OfType<string>().Where(c => c.Length > 0).ToList();
        var delimiter = (query["delimiter"].FirstOrDefault() ?? "semicolon") switch { "semicolon" => ';', "comma" => ',', _ => '\0' };
        var decisions = query["decisions"].OfType<string>().Where(d => d.Length > 0).ToHashSet(Ordinal);
        var kinds = query["kinds"].OfType<string>().Where(k => k.Length > 0).ToHashSet(Ordinal);
        var preview = query["preview"].FirstOrDefault() is "true" or "1";
        if (unit is not ("role_removal" or "review_items")) return Bad("Choose the role_removal or review_items export.");
        if (delimiter == '\0') return Bad("Choose the semicolon or comma delimiter.");
        if (columns.Count == 0) return Bad("Select at least one export column.");
        var allowed = unit == "role_removal" ? RoleRemovalColumns : ReviewItemColumns;
        if (columns.Any(c => !allowed.Contains(c)) || columns.Distinct(Ordinal).Count() != columns.Count) return Bad("Select supported, distinct export columns for this export.");
        if (decisions.Any(d => !ExportLifecycles.Contains(d)) || kinds.Any(k => !KindLabels.ContainsKey(k))) return Bad("Choose supported review types and decision states.");
        if (unit == "role_removal" && (decisions.Count > 0 || kinds.Count > 0)) return Bad("The role removal export has a fixed eligibility rule; decision and review type filters do not apply.");

        var services = http.RequestServices;
        var (scope, items, _) = await QueueAsync(http, q!, "", "", ct);
        var frozen = scope.Bundle.Context != "current";
        if (frozen && columns.FirstOrDefault(CurrentOnlyColumns.Contains) is { } current)
            return Bad($"{ExportColumns[current]} needs current data; frozen review-period evidence does not contain it and current data is never substituted.");

        // Current organizational data, only when a selected column needs it.
        Func<string, string> employee = _ => "", functional = _ => "", department = _ => "", manager = _ => "", description = _ => "";
        if (columns.Any(CurrentOnlyColumns.Contains))
        {
            var snapshot = await services.GetRequiredService<SnapshotService>().GetAsync(ct);
            var settings = await services.GetRequiredService<V1Settings>().GetAsync(ct);
            var byKey = snapshot.Users.Users.Values.GroupBy(u => SubjectSelection.Key(u.Username)).ToDictionary(g => g.Key, g => g.First(), Ordinal);
            var directory = V1Employees.Available(snapshot, settings);
            var owners = directory is not null ? AuthLens.Domain.Directory.EmployeeDirectory.SapEmailOwners(snapshot.Users.Users.Values) : null;
            Dictionary<string, object?>? Matched(string user) =>
                directory is not null && byKey.TryGetValue(SubjectSelection.Key(user), out var sap) && directory.MatchSapIdentity(sap, owners!) is ("matched", { } e) ? e : null;
            employee = user => byKey.TryGetValue(SubjectSelection.Key(user), out var sap) ? string.Join("; ", sap.Names.Select(n => $"{n.First} {n.Last}".Trim()).Where(n => n.Length > 0).Distinct(Ordinal)) : "";
            department = user => Matched(user) is { } e && e.TryGetValue("department", out var v) ? v?.ToString() ?? "" : "";
            manager = user => Matched(user)?["manager"] is Dictionary<string, object?> m ? (string?)m["name"] ?? (string?)m["email"] ?? "" : "";
            if (columns.Contains("functional_group"))
            {
                var data = await services.GetRequiredService<FunctionalGroupStore>().ReadAsync(ct);
                var classes = FunctionalGroupStore.ClassificationMap(data);
                var labels = FunctionalGroupStore.ListGroups(data).ToDictionary(g => (string)g["id"]!, g => (string)g["name"]!, Ordinal);
                functional = user => string.Join("; ", V1FunctionalGroups.GroupKeys(classes, user).Where(k => k != "unassigned").Select(k => labels.GetValueOrDefault(k, k)));
            }
            description = role => snapshot.Catalogue.Roles.TryGetValue(role, out var r) || snapshot.Catalogue.Roles.TryGetValue(RoleNames.Normalize(role), out r) ? r.Text ?? "" : "";
        }
        Dictionary<string, string> Organization(string user) => new(Ordinal)
        {
            ["employee"] = columns.Contains("employee") ? employee(user) : "", ["functional_group"] = columns.Contains("functional_group") ? functional(user) : "",
            ["department"] = columns.Contains("department") ? department(user) : "", ["manager"] = columns.Contains("manager") ? manager(user) : "",
        };

        var rows = new List<ExportRow>();
        var ambiguous = 0;
        if (unit == "role_removal")
        {
            foreach (var (user, entry) in scope.View.OrderBy(p => SodViews.Fold(p.Key), Ordinal))
                foreach (var byRole in SodViews.Shown(entry).GroupBy(a => a.Role, Ordinal).OrderBy(g => g.Key, Ordinal))
                {
                    var states = byRole.Select(a => (Assignment: a, State: scope.State.Items["assignment"][a.Id])).ToList();
                    var removal = states.Count(s => s.State.Lifecycle == "Removal required");
                    if (removal == 0) continue;
                    if (removal < states.Count) { ambiguous++; continue; }   // differing decisions for the same exact role: not an operational removal
                    var events = states.Select(s => s.State.Event).OfType<SodDecisionEvent>().OrderBy(e => e.Timestamp, Ordinal).ToList();
                    var values = Organization(user);
                    values["username"] = user; values["role"] = byRole.Key; values["review_status"] = "Removal required";
                    values["role_description"] = columns.Contains("role_description") ? description(byRole.Key) : "";
                    values["user_group"] = string.Join("; ", states.Select(s => s.Assignment.UserGroup).Where(g => g.Length > 0).Distinct(Ordinal).Order(Ordinal));
                    values["review_comment"] = string.Join(" | ", events.Select(e => e.Justification).Where(j => j.Length > 0).Distinct(Ordinal));
                    values["reviewed_by"] = string.Join("; ", events.Select(e => e.Reviewer).Where(r => r.Length > 0).Distinct(Ordinal));
                    values["review_date"] = events.LastOrDefault()?.Timestamp ?? "";
                    rows.Add(new ExportRow(user, SodViews.Fold(user) + "\u0000" + byRole.Key, values));
                }
        }
        else
        {
            foreach (var item in items)
            {
                var life = (string)item["lifecycle"]! is { Length: > 0 } l ? l : "Pending";
                var kind = (string)item["kind"]!;
                if (life is "Historical" or "Resolved" || !KindLabels.ContainsKey(kind)) continue;
                if (kinds.Count > 0 && !kinds.Contains(kind) || decisions.Count > 0 && !decisions.Contains(life)) continue;
                var user = (string)item["user"]!;
                var e = item["event"] as JsonObject;
                var values = Organization(user);
                values["username"] = user; values["review_type"] = KindLabels[kind]; values["item"] = (string?)item["ref"] ?? "";
                values["risks"] = string.Join("; ", (item["risks"] as JsonArray ?? []).Select(r => (string)r!));
                values["role_description"] = columns.Contains("role_description") && kind == "assignment" ? description(values["item"]) : "";
                values["user_group"] = string.Join("; ", (item["groups"] as JsonArray ?? []).Select(g => (string)g!));
                values["review_status"] = life; values["review_comment"] = (string?)e?["justification"] ?? ""; values["reviewed_by"] = (string?)e?["reviewer"] ?? "";
                values["review_date"] = (string?)e?["timestamp"] ?? "";
                rows.Add(new ExportRow(user, SodViews.Fold(user) + "\u0000" + kind + "\u0000" + values["item"], values));
            }
        }
        rows = [.. rows.OrderBy(r => r.Sort, Ordinal)];
        var formulaIdentifiers = rows.Count(r => columns.Any(c => IdentifierColumns.Contains(c) && V1Csv.Cell(r.Values[c]) != r.Values[c]));
        string[] Cells(ExportRow row) => [.. columns.Select(c => IdentifierColumns.Contains(c) ? row.Values[c] : V1Csv.Cell(row.Values[c]))];
        if (preview)
        {
            var info = await InfoAsync(http, scope.Bundle, ct);
            info["unit"] = unit; info["columns"] = new JsonArray([.. columns.Select(c => (JsonNode)new JsonObject { ["key"] = c, ["label"] = ExportColumns[c] })]);
            info["rows"] = new JsonArray([.. rows.Take(10).Select(r => (JsonNode)new JsonArray([.. Cells(r).Select(v => (JsonNode?)v)]))]);
            info["total_rows"] = rows.Count; info["users"] = rows.Select(r => r.User).Distinct(Ordinal).Count();
            info["excluded_ambiguous"] = ambiguous; info["identifier_formula_warnings"] = formulaIdentifiers;
            return Json(info);
        }
        var csv = new StringBuilder("﻿");
        string Quote(string value) => value.IndexOfAny([delimiter, '"', '\r', '\n']) >= 0 ? "\"" + value.Replace("\"", "\"\"", StringComparison.Ordinal) + "\"" : value;
        csv.Append(string.Join(delimiter, columns.Select(c => Quote(ExportColumns[c])))).Append("\r\n");
        foreach (var row in rows) csv.Append(string.Join(delimiter, Cells(row).Select(Quote))).Append("\r\n");
        var name = unit == "role_removal" ? "role-removal" : "review-items";
        http.Response.Headers["Content-Disposition"] = $"attachment; filename=\"authlens-sod-{name}-{DateTime.Now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)}.csv\"";
        http.Response.Headers.CacheControl = "no-store";
        return Results.Text(csv.ToString(), "text/csv; charset=utf-8");
    }
}
