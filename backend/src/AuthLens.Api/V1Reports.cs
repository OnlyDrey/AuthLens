using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Application;
using AuthLens.Application.Accounts;
using AuthLens.Domain.Analysis;
using AuthLens.Domain.Roles;

namespace AuthLens.Api;

/// <summary>One column of a configurable CSV report: a stable key, the header label, whether it is mandatory and whether it is selected by default.</summary>
public sealed record CsvColumn(string Key, string Label, bool Required = false, bool Default = true);

/// <summary>NAV-4: the shared configurable CSV writer of report exports. Columns are validated against the report's definition and written in the requested
/// order (the default selection in definition order when none is requested). Every field is quoted and gets the existing spreadsheet-formula guard, as
/// the exports it serves always did, so a report with its default columns is byte-compatible with its earlier export. <c>preview=true</c> returns the
/// first ten rows and the totals as JSON instead of the file. Nothing is written anywhere.</summary>
public static class ConfigurableCsv
{
    public sealed record Options(int[] Selected, char Delimiter, bool Preview, bool Requested);

    public static (Options? Value, IResult? Error) Parse(IQueryCollection q, IReadOnlyList<CsvColumn> columns, char defaultDelimiter)
    {
        var keys = q["columns"].OfType<string>().Where(c => c.Length > 0).ToList();
        var delimiterText = q["delimiter"].FirstOrDefault();
        var delimiter = delimiterText switch { null or "" => defaultDelimiter, "semicolon" => ';', "comma" => ',', _ => '\0' };
        if (delimiter == '\0') return (null, Bad("Choose the semicolon or comma delimiter."));
        var index = columns.Select((c, i) => (c.Key, i)).ToDictionary(p => p.Key, p => p.i, StringComparer.Ordinal);
        if (keys.Any(k => !index.ContainsKey(k)) || keys.Distinct(StringComparer.Ordinal).Count() != keys.Count) return (null, Bad("Select supported, distinct columns for this report."));
        var selected = keys.Count > 0 ? keys.Select(k => index[k]).ToArray() : [.. columns.Select((c, i) => (c, i)).Where(p => p.c.Default).Select(p => p.i)];
        if (selected.Length == 0) return (null, Bad("Select at least one column."));
        var missing = columns.Where((c, i) => c.Required && !selected.Contains(i)).Select(c => c.Label).ToList();
        if (missing.Count > 0) return (null, Bad("Required columns cannot be left out: " + string.Join(", ", missing) + "."));
        var preview = q["preview"].FirstOrDefault() is "true" or "1";
        return (new Options(selected, delimiter, preview, keys.Count > 0 || !string.IsNullOrEmpty(delimiterText) || preview), null);
    }

    /// <summary>The CSV (or its preview) of <paramref name="rows"/>; each row holds one value per column definition, in definition order.</summary>
    public static IResult Render(HttpContext http, string fileName, IReadOnlyList<CsvColumn> columns, Options options, IReadOnlyList<string?[]> rows, Dictionary<string, object?>? extra = null)
    {
        string Field(string? value) => "\"" + V1Csv.Cell(value).Replace("\"", "\"\"", StringComparison.Ordinal) + "\"";
        if (options.Preview)
        {
            var info = new Dictionary<string, object?>
            {
                ["columns"] = options.Selected.Select(i => new { key = columns[i].Key, label = columns[i].Label }).ToList(),
                ["rows"] = rows.Take(10).Select(r => options.Selected.Select(i => V1Csv.Cell(r[i])).ToList()).ToList(),
                ["total_rows"] = rows.Count,
            };
            foreach (var (k, v) in extra ?? []) info[k] = v;
            return Results.Json(info);
        }
        var csv = new StringBuilder("﻿");
        csv.Append(string.Join(options.Delimiter, options.Selected.Select(i => Field(columns[i].Label)))).Append("\r\n");
        foreach (var row in rows) csv.Append(string.Join(options.Delimiter, options.Selected.Select(i => Field(row[i])))).Append("\r\n");
        http.Response.Headers["Content-Disposition"] = $"attachment; filename=\"{fileName}\"";
        http.Response.Headers["X-AuthLens-Row-Count"] = rows.Count.ToString(System.Globalization.CultureInfo.InvariantCulture);
        http.Response.Headers.CacheControl = "no-store";
        return Results.Text(csv.ToString(), "text/csv; charset=utf-8");
    }

    public static IResult Bad(string detail) => Results.Json(new { detail }, statusCode: 422);
}

/// <summary>NAV-4: the Reports module's report catalogue and availability, and the server-side Account Review, Position Changes and Compare Users exports
/// (moved from the browser so the page export and Reports share one implementation). Report pages and reports are offered per account from the existing
/// permissions, the SoD feature switch and loaded data; every report endpoint keeps its own authorization, independent of what the navigation shows.</summary>
public static class V1Reports
{
    public static readonly CsvColumn[] AccountReviewColumns =
    [
        new("username", "Username", Required: true), new("user_group", "User group"), new("full_name", "Full name"), new("sap_validity", "SAP validity"),
        new("lock_status", "SAP lock status"), new("ad_status", "AD account status"), new("directory_match", "Directory match"), new("findings", "Findings"),
        new("license_classification", "License group classification"), new("review_state", "Review state"), new("reviewer", "Reviewer"),
        new("reviewed_at", "Reviewed at"), new("rationale", "Rationale"), new("evidence_version", "Evidence version"),
        new("reviewed_evidence_version", "Reviewed evidence version"), new("stale", "Stale decision"),
    ];

    /// <summary>Position Changes: only what the Employee Directory imports recorded. The detection time is when a changed value was first seen in an
    /// import, not the date the organizational change happened (that date is not in the data).</summary>
    public static readonly CsvColumn[] PositionColumns =
    [
        new("username", "Username", Required: true), new("full_name", "Full name"), new("user_group", "User group"), new("changed", "Changed fields"),
        new("previous_department", "Previous department"), new("current_department", "Current department"), new("previous_title", "Previous job title"),
        new("current_title", "Current job title"), new("detected_at", "First seen in an import"), new("previous_imported_at", "Previous import", Default: false),
        new("current_imported_at", "Current import", Default: false), new("change_review", "Position change review"), new("review_state", "Review state"),
        new("reviewer", "Reviewer"), new("reviewed_at", "Reviewed at"), new("rationale", "Rationale"),
    ];

    public static readonly CsvColumn[] ComparisonColumns =
    [
        new("username", "Username", Required: true), new("user_group", "User group"), new("compared_with", "Compared with"), new("category", "Category"),
        new("kind", "Kind"), new("identifier", "Identifier", Required: true), new("side", "Side"), new("assigned_role", "Assigned role"), new("valid_from", "Valid from"),
        new("valid_to", "Valid to"), new("assignment_status", "Assignment status"), new("catalogue_match", "Catalogue match"), new("validity", "Validity view"),
        new("as_of", "As of"),
    ];

    /// <summary>Release exports keep their v1 headers (and byte-identical output without report options).</summary>
    public static readonly CsvColumn[] ReleaseRoleColumns =
    [
        new("role_name", "ROLE_NAME", Required: true), new("role_description", "ROLE_DESCRIPTION"), new("release_area", "RELEASE_AREA"), new("release_group", "RELEASE_GROUP"),
        new("release_strategy", "RELEASE_STRATEGY"), new("document_type", "PR_PO"),
    ];

    public static readonly CsvColumn[] AssignmentColumns =
    [
        new("username", "USERNAME", Required: true), new("first_name", "FIRST_NAME"), new("last_name", "LAST_NAME"), new("email", "EMAIL"), new("user_group", "USER_GROUP"),
        new("role_name", "ROLE_NAME", Required: true), new("valid_from", "ROLE_VALID_FROM"), new("valid_to", "ROLE_VALID_TO"), new("assignment_status", "ASSIGNMENT_STATUS"),
        new("document_type", "PR_PO"), new("release_group", "RELEASE_GROUP"), new("release_strategy", "RELEASE_STRATEGY"), new("matched", "MATCHED_FILTER"),
    ];

    private sealed record Report(string Id, string Page, string Title, string Description, string[] Formats, bool Sod, string Data, CsvColumn[]? Columns, string[] Contexts);

    /// <summary>The report catalogue, in page order. Data: "users" needs the User–Role Mapping, "directory" the Employee Directory, "sod" the SoD evidence.</summary>
    private static readonly Report[] Catalogue =
    [
        new("formal_review", "review", "Formal review report", "The access review of one review period, frozen at approval: scope, decisions, exceptions and sign-off.", ["docx", "pdf"], true, "sod", null, ["period"]),
        new("access_removal", "review", "Access removal report", "Recommended role removals with their decisions and follow-up, from the current evidence or a frozen review period.", ["docx", "pdf", "csv"], true, "sod", null, ["current", "period"]),
        new("work_queue", "review", "Work Queue export", "Role removals (exact user and role, all assignments decided Remove) or review items of the Work Queue population.", ["csv"], true, "sod", null, ["current", "period"]),
        new("follow_up_actions", "review", "Follow-up actions", "Tracked remediation and investigation actions with owner, due date and status.", ["csv"], true, "sod", null, ["current", "period"]),
        new("account_review", "review", "Account Review", "Account and license review findings and decisions per SAP account (current data).", ["csv"], false, "users", AccountReviewColumns, ["current"]),
        new("position_changes", "review", "Position Changes", "Department and job title changes between Employee Directory imports with their review decisions (current data).", ["csv"], false, "directory", PositionColumns, ["current"]),
        new("user_directory", "access", "User Directory", "Role assignments of the matching SAP users, with the evidence flag of the applied role and transaction filters (current data).", ["csv"], false, "users", null, ["current"]),
        new("compare_users", "access", "Compare Users", "Role or transaction coverage of two SAP users with every assignment interval as evidence (current data).", ["csv"], false, "users", ComparisonColumns, ["current"]),
        new("release_roles", "access", "Release role list", "Distinct PR/PO release roles of the filtered population (current data).", ["csv"], false, "users", ReleaseRoleColumns, ["current"]),
        new("release_assignments", "access", "Release assignments", "Every user–release-role assignment of the filtered population (current data).", ["csv"], false, "users", AssignmentColumns, ["current"]),
        new("risk_matrix", "sod", "Risk Matrix", "Users against SoD risks for the filtered population.", ["csv"], true, "sod", null, ["current", "period"]),
        new("activity_matrix", "sod", "Activity Matrix", "Users against SoD activities for the filtered population.", ["csv"], true, "sod", null, ["current", "period"]),
        new("heatmap", "sod", "SAP User Group heatmap", "Distinct users per SAP User Group and risk or activity (the heatmap's data, not the chart).", ["csv"], true, "sod", null, ["current", "period"]),
        new("explorer", "sod", "Access Explorer", "Findings, assignments, roles or role conflicts of the Access Explorer views.", ["csv"], true, "sod", null, ["current", "period"]),
        new("analysis", "sod", "SoD analysis", "The SoD analysis findings with their supporting evidence.", ["csv"], true, "sod", null, ["current"]),
        new("remediation", "sod", "Remediation", "Remediation recommendations derived from review decisions.", ["csv"], true, "sod", null, ["current", "period"]),
        new("ruleset", "sod", "SoD ruleset", "The configured SoD risks, functions and transactions.", ["csv"], true, "sod", null, ["current"]),
        new("evidence_periods", "evidence", "Review periods and frozen evidence", "Review periods with their lifecycle state and the integrity checksum of the frozen evidence; reports regenerated from it.", [], true, "sod", null, ["period"]),
    ];
    private static readonly string[] Pages = ["review", "access", "sod", "evidence"];

    private static bool Can(HttpContext http, string permission) => AccountStore.Permissions[permission].Contains(Actors.Current(http).Role);

    public static void Map(RouteGroupBuilder api)
    {
        api.MapGet("/reports/availability", async (HttpContext http, SnapshotService snapshots, V1Settings store, CancellationToken ct) =>
        {
            var settings = await store.GetAsync(ct);
            var snapshot = await snapshots.GetAsync(ct);
            var sodEnabled = (bool?)settings["features"]?["sod"] == true;
            var mapping = ((bool?)settings["features"]?["user_role_mapping"] ?? true) && snapshot.Ids.Users is not null;
            var directory = snapshot.Directory is not null;
            var read = Can(http, "read") && Can(http, "export");
            string? Reason(Report r) => !read ? "Your account cannot export reports."
                : r.Sod && !sodEnabled ? "SoD is turned off in Features."
                : r.Data == "users" && !mapping ? "No validated User Access data is loaded."
                : r.Data == "directory" && (!mapping || !directory) ? "Position changes need the User Access data and an Employee Directory import."
                : null;
            // A report whose module is turned off is not offered at all; one that only lacks data is listed as unavailable with its reason.
            var offered = Catalogue.Where(r => !(r.Sod && !sodEnabled)).ToList();
            var reports = offered.Select(r => new
            {
                id = r.Id, page = r.Page, title = r.Title, description = r.Description, formats = r.Formats, contexts = r.Contexts,
                available = Reason(r) is null, reason = Reason(r),
                columns = r.Columns?.Select(c => new { key = c.Key, label = c.Label, required = c.Required, @default = c.Default }).ToList(),
            }).ToList();
            var pages = Pages.Where(p => reports.Any(r => r.page == p && r.available)).ToList();
            return Results.Ok(new { pages, reports, sod_enabled = sodEnabled });
        });

        api.MapGet("/account-review/export", async (HttpContext http, IServiceProvider services, CancellationToken ct) =>
        {
            var (options, invalid) = ConfigurableCsv.Parse(http.Request.Query, AccountReviewColumns, ',');
            if (invalid is not null) return invalid;
            var list = await V1AccountReview.ListRowsAsync(http, services, ct);
            if (list.Error is not null) return list.Error;
            if (!list.Loaded) return Results.Json(new { detail = "No validated User Access dataset is loaded." }, statusCode: 409);
            var rows = list.Rows.Select(r =>
            {
                var decision = r["decision"] as Dictionary<string, object?>;
                return new string?[]
                {
                    (string)r["username"]!, string.Join(" / ", (List<string>)r["groups"]!), (string?)r["name"], Text(r["sap_validity"]), Text(r["lock_status"]), Text(r["ad_status"]),
                    Text(r["match_status"]), string.Join(" / ", ((List<string>)r["findings"]!).Select(f => V1AccountReview.Findings.GetValueOrDefault(f, f))),
                    (bool)r["unlicensed"]! ? "Configured unlicensed group" : "Not classified", Text(r["review_state"]), Text(decision?.GetValueOrDefault("reviewer")),
                    Text(decision?.GetValueOrDefault("timestamp")), Text(decision?.GetValueOrDefault("rationale")), Text(r["evidence_version"]), Text(decision?.GetValueOrDefault("evidence_version")), (bool)r["stale"]! ? "Yes" : "No",
                };
            }).ToList();
            http.Response.Headers["X-SAP-Lens-Data-Revision"] = list.Generation;
            return ConfigurableCsv.Render(http, $"authlens-account-review-review-{Day()}.csv", AccountReviewColumns, options!, rows);
        });

        api.MapGet("/account-review/positions/export", async (HttpContext http, IServiceProvider services, CancellationToken ct) =>
        {
            var (options, invalid) = ConfigurableCsv.Parse(http.Request.Query, PositionColumns, ',');
            if (invalid is not null) return invalid;
            if (string.IsNullOrEmpty(http.Request.Query["position_status"].FirstOrDefault())) return ConfigurableCsv.Bad("Choose position_status pending, reviewed or all.");
            var list = await V1AccountReview.ListRowsAsync(http, services, ct);
            if (list.Error is not null) return list.Error;
            if (!list.Loaded || list.Directory is null) return Results.Json(new { detail = "Position changes need the User Access data and an Employee Directory import." }, statusCode: 409);
            var rows = list.Rows.Where(r => r["position_change"] is Dictionary<string, object?>).Select(r =>
            {
                var change = (Dictionary<string, object?>)r["position_change"]!;
                var decision = r["decision"] as Dictionary<string, object?>;
                var fields = (change["fields"] as JsonArray ?? []).Select(f => (string?)f == "title" ? "Job title" : (string?)f == "department" ? "Department" : (string?)f).ToList();
                return new string?[]
                {
                    (string)r["username"]!, (string?)r["name"], string.Join(" / ", (List<string>)r["groups"]!), string.Join(" and ", fields),
                    (string?)change["previous_department"], (string?)change["current_department"], (string?)change["previous_title"], (string?)change["current_title"],
                    (string?)change["detected_at"], (string?)change["previous_imported_at"], (string?)change["current_imported_at"], (bool)change["open"]! ? "Pending" : "Reviewed",
                    Text(r["review_state"]), Text(decision?.GetValueOrDefault("reviewer")), Text(decision?.GetValueOrDefault("timestamp")), Text(decision?.GetValueOrDefault("rationale")),
                };
            }).ToList();
            http.Response.Headers["X-SAP-Lens-Data-Revision"] = list.Generation;
            return ConfigurableCsv.Render(http, $"authlens-position-changes-{Day()}.csv", PositionColumns, options!, rows);
        });

        api.MapGet("/user-comparison/export", async (HttpContext http, SnapshotService snapshots, CancellationToken ct) =>
        {
            var q = http.Request.Query;
            var (options, invalid) = ConfigurableCsv.Parse(q, ComparisonColumns, ',');
            if (invalid is not null) return invalid;
            var (left, right) = (q["user_a"].FirstOrDefault() ?? "", q["user_b"].FirstOrDefault() ?? "");
            var validity = q["validity"].FirstOrDefault() ?? "active";
            var kind = q["kind"].FirstOrDefault() ?? "roles";
            var difference = q["difference"].FirstOrDefault() ?? "";
            var sort = q["sort"].FirstOrDefault() ?? "identifier";
            if (left.Length is 0 or > 512 || right.Length is 0 or > 512 || !V1Access.Validities.Contains(validity) || kind is not ("roles" or "transactions")
                || difference is not ("" or "shared" or "a" or "b") || sort is not ("identifier" or "difference" or "a" or "b")) return Results.Json(new { detail = "Invalid comparison parameters." }, statusCode: 422);
            var snapshot = await snapshots.GetAsync(ct);
            var today = V1Access.Today();
            var asOf = today.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            ComparisonResult result;
            try { result = UserComparison.Compare(snapshot.Catalogue, snapshot.Users, left, right, validity, today); }
            catch (NotFoundException error) { return Results.Json(new { detail = error.Message }, statusCode: 404); }
            var areas = new HashSet<string>(q["areas"].OfType<string>().Where(a => a.Length > 0), StringComparer.Ordinal);
            var (search, descending) = (q["search"].FirstOrDefault() ?? "", V1Access.Flag(q, "descending"));
            var rows = new List<string?[]>();
            void Add(string side, string identifier, string category, object evidence)
            {
                var (user, other) = side == "a" ? (left, right) : (right, left);
                if (evidence is Dictionary<string, object?> a)
                    rows.Add([user, Text(a.GetValueOrDefault("user_group")), other, category, kind, identifier, side, Text(a.GetValueOrDefault("role_name")),
                        Text(a.GetValueOrDefault("valid_from")), Text(a.GetValueOrDefault("valid_to")), Text(a.GetValueOrDefault("status")), Text(a.GetValueOrDefault("match_status")), validity, asOf]);
                else rows.Add([user, "", other, category, kind, identifier, side, (string)evidence, "", "", "", "", validity, asOf]);
            }
            if (kind == "roles")
                foreach (var r in UserComparison.Select(result.Roles, difference, areas, search, sort, descending, r => r.Identifier, r => r.Difference, r => r.Areas, r => r.Description, r => r.A.Count, r => r.B.Count))
                { foreach (var e in r.A) Add("a", r.Identifier, r.Difference, e); foreach (var e in r.B) Add("b", r.Identifier, r.Difference, e); }
            else
                foreach (var r in UserComparison.Select(result.Transactions, difference, areas, search, sort, descending, r => r.Identifier, r => r.Difference, r => r.Areas, _ => "", r => r.A.Count, r => r.B.Count))
                { foreach (var e in r.A) Add("a", r.Identifier, r.Difference, e); foreach (var e in r.B) Add("b", r.Identifier, r.Difference, e); }
            return ConfigurableCsv.Render(http, $"authlens-user-comparison-review-{asOf}.csv", ComparisonColumns, options!, rows);
        });
    }

    private static string? Text(object? value) => value switch { null => null, string s => s, JsonNode n => n.GetValueKind() == System.Text.Json.JsonValueKind.String ? (string?)n : n.ToJsonString(), _ => Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) };
    private static string Day() => DateTime.Now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
}
