using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using AuthLens.Api;

namespace AuthLens.Tests;

/// <summary>GET /api/dashboard and /api/saved-filters in the v1 shapes: real snapshot aggregates (null with a reason when a source is missing or not
/// migrated, never zero-filled) and saved-filter CRUD with v1 validation, optimistic concurrency and persistence across restarts.</summary>
public sealed class DashboardAndSavedFiltersTests : IAsyncLifetime
{
    private readonly string _root = Directory.CreateTempSubdirectory("saplens-dash-").FullName;
    private readonly string _token = HostSettings.NewToken();
    private WebApplication _app = null!;
    private HttpClient _client = null!;

    public Task InitializeAsync() => Start();

    private async Task Start()
    {
        _app = AuthLensHost.Build(new HostSettings { DataDirectory = Path.Combine(_root, "data"), Port = 0, AccessToken = _token, JsonConsoleLogging = false });
        await _app.StartAsync();
        _client = new HttpClient { BaseAddress = new Uri(_app.Urls.First()) };
        _client.DefaultRequestHeaders.Add(RequestBoundary.TokenHeader, _token);
    }

    private async Task Stop()
    {
        _client.Dispose();
        await _app.StopAsync();
        await _app.DisposeAsync();
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
    }

    public async Task DisposeAsync()
    {
        await Stop();
        try { Directory.Delete(_root, true); } catch (IOException) { }
    }

    private async Task Import(string source, string csv)
    {
        var job = JsonNode.Parse(await (await _client.PostAsync($"/api/v1/imports/{source}", new StringContent(csv, Encoding.UTF8, "text/csv"))).Content.ReadAsStringAsync())!;
        for (var i = 0; i < 200 && (string)JsonNode.Parse(await _client.GetStringAsync($"/api/v1/jobs/{(long)job["id"]!}"))!["status"]! != "Completed"; i++) await Task.Delay(50);
    }

    private static JsonNode Metric(JsonNode dashboard, string id) => dashboard["metrics"]!.AsArray().Single(m => (string)m!["id"]! == id)!;

    [Fact]
    public async Task Dashboard_reports_unavailable_sources_as_null_with_a_reason_and_counts_the_active_snapshots()
    {
        var empty = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard"))!;
        Assert.Null((int?)Metric(empty, "roles")["value"]);
        Assert.Equal("Source not loaded", (string?)Metric(empty, "roles")["unavailable_reason"]);
        Assert.Equal("User Access CSV not loaded", (string?)Metric(empty, "users")["unavailable_reason"]);
        Assert.Null(empty["role_distribution"]);
        Assert.Null(empty["assignment_distribution"]);
        Assert.Null(empty["review_population"]);

        await Import("roles", Csv.Roles(10));
        const string active = "20000101;99991231";
        var lines = Enumerable.Range(0, 7).Select(r => $"USER0001;ZC:FI:ROLE_{r:D4};GRP_FIN;First;Last;;;;{active};;A")
            .Append("USER0001;ZC:FI:ROLE_0007;GRP_FIN;First;Last;;;;20000101;20010101;;A")   // expired
            .Append("USER0001;ZC:FI:ROLE_0008;GRP_FIN;First;Last;;;;20990101;99991231;;A")   // future
            .Append($"USER0002;ZC:FI:ROLE_0001;GRP_FIN;First;Last;;;;{active};;A");
        await Import("users", Csv.UsersHeader + "\n" + string.Join("\n", lines) + "\n");
        var dashboard = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard"))!;
        Assert.Equal(10, (int)Metric(dashboard, "roles")["value"]!);
        Assert.Equal(30, (int)Metric(dashboard, "mappings")["value"]!);
        Assert.Equal(1, (int)Metric(dashboard, "areas")["value"]!);
        Assert.Equal(2, (int)Metric(dashboard, "users")["value"]!);
        Assert.Equal(10, (int)Metric(dashboard, "assignments")["value"]!);
        Assert.Equal(2, (int)Metric(dashboard, "assigned_users")["value"]!);
        Assert.Equal(1, (int)Metric(dashboard, "expired")["value"]!);
        Assert.Equal(1, (int)Metric(dashboard, "future")["value"]!);
        Assert.Null(Metric(dashboard, "expired")["unavailable_reason"]);
        Assert.Equal(10, (int)dashboard["role_distribution"]!["FI"]!);
        Assert.Equal(1, (int)dashboard["assignment_distribution"]!["0–5"]!);
        Assert.Equal(1, (int)dashboard["assignment_distribution"]!["6–10"]!);
        Assert.Equal(0, (int)dashboard["assignment_distribution"]!["31+"]!);
        Assert.Equal(2, (int)dashboard["review_population"]!);
        // Not migrated yet: explicit null with a reason, never an estimate.
        Assert.Equal((0, 0, 2, 0), ((int)Metric(dashboard, "account_review")["value"]!, (int)Metric(dashboard, "reviewed")["value"]!, (int)Metric(dashboard, "pending")["value"]!, (int)Metric(dashboard, "outdated")["value"]!));
        Assert.Null((int?)Metric(dashboard, "position_changes")["value"]);
        Assert.Equal("Employee Directory not loaded", (string?)Metric(dashboard, "position_changes")["unavailable_reason"]);
        Assert.Equal("Employee Directory disabled", (string?)Metric(dashboard, "employees")["unavailable_reason"]);
        Assert.Equal("Enable Employee Directory in Feature Settings.", (string?)Metric(dashboard, "email_matches")["unavailable_reason"]);
        Assert.Equal("Current local snapshots only; no historical trends or effective-authorization claims.", (string)dashboard["notice"]!);
        Assert.Equal(3, dashboard["sources"]!.AsArray().Count);
    }

    [Fact]
    public async Task Dashboard_population_filters_combine_OR_within_and_AND_between_dimensions_and_scope_access_metrics()
    {
        await Import("roles", Csv.Roles(4));                                        // ROLE_0000 T000-T002, ROLE_0001 T003-T005, ROLE_0002 T006-T008
        const string open = "20000101;99991231";
        await Import("users", Csv.UsersHeader + "\n" + string.Join("\n",
            $"USER0001;ZC:FI:ROLE_0000;GRP_FIN;First;Last;;{open};{open};;A",
            $"USER0001;ZC:FI:ROLE_0002;GRP_FIN;First;Last;;{open};{open};;A",
            $"USER0002;ZC:FI:ROLE_0001;GRP_HR;First;Last;;{open};{open};;S",
            $"USER0003;ZC:FI:ROLE_0002;GRP_HR;First;Last;;20000101;20010101;{open};;A") + "\n");
        async Task<JsonNode> Get(string query) => JsonNode.Parse(await _client.GetStringAsync("/api/dashboard" + query))!;
        var all = await Get("");
        Assert.Equal(3, (int)Metric(all, "users")["value"]!);
        Assert.Equal(3, (int)Metric(all, "assigned_roles")["value"]!);
        Assert.Equal(9, (int)Metric(all, "assigned_tcodes")["value"]!);
        Assert.Equal(4, (int)all["role_distribution"]!["FI"]!);                     // no population: the whole catalogue
        Assert.Null(all["population_usernames"]);

        var hr = await Get("?user_groups=GRP_HR");
        Assert.Equal(2, (int)Metric(hr, "users")["value"]!);
        Assert.Equal(2, (int)Metric(hr, "assigned_roles")["value"]!);              // ROLE_0001 and ROLE_0002 (current role validity)
        Assert.Equal(6, (int)Metric(hr, "assigned_mappings")["value"]!);
        Assert.Equal(4, (int)Metric(hr, "roles")["value"]!);                       // catalogue metrics stay global and are labelled so
        Assert.Contains("roles", hr["scope"]!["global_metrics"]!.AsArray().Select(m => (string)m!));
        Assert.Equal("population", (string)hr["scope"]!["role_distribution"]!);
        Assert.Equal(2, (int)hr["role_distribution"]!["FI"]!);
        Assert.Equal(new[] { "USER0002", "USER0003" }, hr["population_usernames"]!.AsArray().Select(u => (string)u!));
        // OR inside a dimension, AND between dimensions.
        Assert.Equal(3, (int)Metric(await Get("?user_groups=GRP_HR&user_groups=GRP_FIN"), "users")["value"]!);
        Assert.Equal(1, (int)Metric(await Get("?user_groups=GRP_HR&user_types=S"), "users")["value"]!);
        Assert.Equal(2, (int)Metric(await Get("?roles=ZC:FI:ROLE_0002"), "users")["value"]!);                     // users holding the role
        Assert.Equal(1, (int)Metric(await Get("?roles=ZC:FI:ROLE_0002&user_groups=GRP_FIN"), "users")["value"]!);
        Assert.Equal(1, (int)Metric(await Get("?tcodes=T004"), "users")["value"]!);
        // Role and transaction filters may be met by different assignments of the same user (documented user-population semantics).
        Assert.Equal(1, (int)Metric(await Get("?roles=ZC:FI:ROLE_0000&tcodes=T007"), "users")["value"]!);
        Assert.Equal(1, (int)Metric(await Get("?account_states=expired"), "users")["value"]!);
        Assert.Equal(0, (int)Metric(await Get("?user_groups=GRP_UNKNOWN"), "users")["value"]!);              // an empty population is reported, not hidden
        var options = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard/filter-options"))!;
        Assert.Contains(options["user_groups"]!.AsArray(), o => (string)o!["value"]! == "GRP_HR" && (int)o["count"]! == 2);
        Assert.Contains(options["account_states"]!.AsArray(), o => (string)o!["value"]! == "expired");
        Assert.Contains(options["tcodes"]!.AsArray(), o => (string)o!["value"]! == "T004");
        Assert.False((bool)options["directory_available"]!);
        Assert.Empty(options["departments"]!.AsArray());                           // no directory: no invented directory values
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/dashboard?" + string.Join("&", Enumerable.Range(0, 201).Select(i => $"tcodes=T{i}")))).StatusCode);
    }

    [Fact]
    public async Task Dashboard_access_modes_role_types_suffixes_lock_and_governance_dimensions()
    {
        await Import("roles", Csv.Roles(4));                                        // ROLE_0000 T000-T002, ROLE_0001 T003-T005, ROLE_0002 T006-T008
        const string open = "20000101;99991231";
        await Import("users", Csv.UsersHeader + "\n" + string.Join("\n",
            $"USER0001;ZC:FI:ROLE_0000;GRP_FIN;First;Last;;{open};{open};;A",
            $"USER0001;ZC:FI:ROLE_0002;GRP_FIN;First;Last;;{open};{open};;A",
            $"USER0002;ZC:FI:AP:N100;GRP_HR;First;Last;;{open};{open};X;A",              // locked; organizational suffix N100 under two stems
            $"USER0002;ZC:MM:PO:N100;GRP_HR;First;Last;;{open};{open};X;A",
            $"USER0003;ZO:MM:PLANT:PR_REL_ST_01_02:N100;GRP_HR;First;Last;;{open};20000101;20000102;;A") + "\n");   // expired release role
        async Task<JsonNode> Get(string query) => JsonNode.Parse(await _client.GetStringAsync("/api/dashboard" + query))!;
        int Users(JsonNode d) => (int)Metric(d, "users")["value"]!;
        // Population (default): role and code may come from different current assignments; matching: one assignment must carry both.
        Assert.Equal(1, Users(await Get("?roles=ZC:FI:ROLE_0000&tcodes=T007")));
        var matching = await Get("?roles=ZC:FI:ROLE_0000&tcodes=T007&access_scope=matching");
        Assert.Equal(0, Users(matching));
        Assert.Equal("matching_access", (string)matching["scope"]!["access_semantics"]!);
        var population = await Get("?roles=ZC:FI:ROLE_0000");
        Assert.Equal(2, (int)Metric(population, "assigned_roles")["value"]!);                         // the user's complete current access
        Assert.Equal(1, (int)Metric(await Get("?roles=ZC:FI:ROLE_0000&access_scope=matching"), "assigned_roles")["value"]!);   // only the matching role
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/dashboard?access_scope=other")).StatusCode);
        // Role type and organizational suffix use currently valid assignments only (USER0003's release role has expired).
        Assert.Equal(0, Users(await Get("?role_types=release")));
        Assert.Equal(2, Users(await Get("?role_types=business")));
        Assert.Equal(1, Users(await Get("?org_suffixes=N100")));
        Assert.Equal(1, Users(await Get("?lock_states=locked")));
        // Governance: review status from the current Account Review evaluation; SoD risk needs enabled SoD with a matrix.
        Assert.Equal(3, Users(await Get("?review_states=pending")));
        Assert.Equal(0, Users(await Get("?review_states=completed")));
        Assert.Equal(HttpStatusCode.Conflict, (await _client.GetAsync("/api/dashboard?sod_risks=R001")).StatusCode);
        var options = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard/filter-options"))!;
        Assert.Contains(options["org_suffixes"]!.AsArray(), o => (string)o!["value"]! == "N100" && (int)o["count"]! == 1);
        Assert.DoesNotContain(options["role_types"]!.AsArray(), o => (string)o!["value"]! == "release");
        Assert.Contains(options["lock_states"]!.AsArray(), o => (string)o!["value"]! == "locked");
        Assert.Contains(options["review_states"]!.AsArray(), o => (string)o!["value"]! == "pending" && (int)o["count"]! == 3);
        Assert.False((bool)options["sod_available"]!);
        Assert.Empty(options["sod_risks"]!.AsArray());
    }

    [Fact]
    public async Task Dashboard_SoD_risk_filter_selects_users_with_current_findings_and_keeps_their_complete_access()
    {
        foreach (var source in new[] { "roles", "users", "sod" })
            await Import(source, File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "sod", "analysis", source + ".sod.txt")));
        var settings = JsonNode.Parse(await _client.GetStringAsync("/api/configuration"))!["settings"]!.AsObject();
        settings["features"]!["sod"] = true;
        Assert.True((await _client.PostAsync("/api/configuration", new StringContent(settings.ToJsonString(), Encoding.UTF8, "application/json"))).IsSuccessStatusCode);
        var options = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard/filter-options"))!;
        Assert.True((bool)options["sod_available"]!);
        var risk = options["sod_risks"]!.AsArray().First()!;
        var dashboard = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard?sod_risks=" + Uri.EscapeDataString((string)risk["value"]!)))!;
        Assert.Equal((int)risk["count"]!, (int)Metric(dashboard, "users")["value"]!);
        // The SoD summary for the same population evaluates every conflict of those users (an access filter never hides a conflicting role).
        var overview = await _client.GetAsync("/api/sod/overview?sod_risks=" + Uri.EscapeDataString((string)risk["value"]!));
        Assert.Equal(HttpStatusCode.OK, overview.StatusCode);
        var all = JsonNode.Parse(await _client.GetStringAsync("/api/dashboard"))!;
        Assert.True((int)Metric(dashboard, "assigned_roles")["value"]! <= (int)Metric(all, "assigned_roles")["value"]!);
    }

    [Theory]
    [InlineData(0, "0–5")]
    [InlineData(5, "0–5")]
    [InlineData(6, "6–10")]
    [InlineData(20, "11–20")]
    [InlineData(21, "21–30")]
    [InlineData(31, "31+")]
    public void Assignment_bands_match_v1(int count, string band) => Assert.Equal(band, V1Dashboard.Band(count));

    private async Task<(HttpStatusCode Status, JsonNode? Body)> Save(object body)
    {
        var response = await _client.PostAsJsonAsync("/api/saved-filters", body);
        return (response.StatusCode, JsonNode.Parse(await response.Content.ReadAsStringAsync()));
    }

    [Fact]
    public async Task Saved_filters_create_update_rename_delete_and_survive_a_restart()
    {
        Assert.Empty(JsonNode.Parse(await _client.GetStringAsync("/api/saved-filters"))!["items"]!.AsArray());
        var (status, created) = await Save(new { name = "  Finance users ", view = "users", filters = new { search = "FI", groups = new[] { "GRP_FIN" }, descending = true, expired = 1 } });
        Assert.Equal(HttpStatusCode.OK, status);
        Assert.Equal("Finance users", (string)created!["name"]!);
        Assert.Matches("^[a-f0-9]{32}$", (string)created["id"]!);
        Assert.Equal(1, (int)created["filter_schema"]!);
        Assert.Equal((string)created["created"]!, (string)created["modified"]!);
        var id = (string)created["id"]!;
        var (_, second) = await Save(new { name = "Roles", view = "roles", filters = new { search = "X" } });

        // Duplicate names are compared case-insensitively per view; the same name in another view is allowed.
        Assert.Equal(HttpStatusCode.Conflict, (await Save(new { name = "FINANCE USERS", view = "users", filters = new { } })).Status);
        Assert.Equal(HttpStatusCode.OK, (await Save(new { name = "Finance users", view = "review", filters = new { } })).Status);

        // Updates need the current modified stamp; a stale one is refused.
        var (updatedStatus, updated) = await Save(new { name = "Finance users", view = "users", filters = new { search = "CO" }, id, expected = (string)created["modified"]! });
        Assert.Equal(HttpStatusCode.OK, updatedStatus);
        Assert.Equal("CO", (string)updated!["filters"]!["search"]!);
        Assert.Equal((string)created["created"]!, (string)updated["created"]!);
        var stale = await Save(new { name = "Finance users", view = "users", filters = new { }, id, expected = (string)created["modified"]! });
        Assert.Equal(HttpStatusCode.Conflict, stale.Status);
        Assert.Equal("Saved filter changed. Reload before updating.", (string)stale.Body!["detail"]!);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Save(new { name = "Moved", view = "roles", filters = new { }, id, expected = (string)updated["modified"]! })).Status);
        Assert.Equal(HttpStatusCode.NotFound, (await Save(new { name = "Ghost", view = "users", filters = new { }, id = "0123", expected = "x" })).Status);

        // Rename keeps the filters and ignores the allow-list.
        var (_, renamed) = await Save(new { name = "Renamed", view = "users", filters = new { anything = "x" }, id, expected = (string)updated["modified"]!, rename = true });
        Assert.Equal("Renamed", (string)renamed!["name"]!);
        Assert.Equal("CO", (string)renamed["filters"]!["search"]!);

        // v1 order: a saved entry moves to the end.
        var names = JsonNode.Parse(await _client.GetStringAsync("/api/saved-filters"))!["items"]!.AsArray().Select(i => (string)i!["name"]!).ToList();
        Assert.Equal(["Roles", "Finance users", "Renamed"], names);

        await Stop();
        await Start();
        var items = JsonNode.Parse(await _client.GetStringAsync("/api/saved-filters"))!["items"]!.AsArray();
        Assert.Equal(3, items.Count);
        Assert.Equal((string)renamed["modified"]!, (string)items.Single(i => (string)i!["id"]! == id)!["modified"]!);

        var staleDelete = await _client.PostAsJsonAsync("/api/saved-filters/delete", new { id, expected = (string)created["modified"]! });
        Assert.Equal(HttpStatusCode.Conflict, staleDelete.StatusCode);
        var delete = await _client.PostAsJsonAsync("/api/saved-filters/delete", new { id, expected = (string)renamed["modified"]! });
        Assert.Equal("deleted", (string)JsonNode.Parse(await delete.Content.ReadAsStringAsync())!["status"]!);
        Assert.Equal(HttpStatusCode.NotFound, (await _client.PostAsJsonAsync("/api/saved-filters/delete", new { id, expected = "x" })).StatusCode);
        Assert.Equal(2, JsonNode.Parse(await _client.GetStringAsync("/api/saved-filters"))!["items"]!.AsArray().Count);
        Assert.NotNull(second);
    }

    [Fact]
    public async Task Saved_filter_validation_matches_v1()
    {
        async Task<JsonNode> Refused(object body)
        {
            var (status, detail) = await Save(body);
            Assert.Equal(HttpStatusCode.UnprocessableEntity, status);
            return detail!["detail"]!;
        }
        Assert.Equal("Unsupported filter fields; result datasets cannot be saved.", (string)(await Refused(new { name = "A", view = "roles", filters = new { rows = new[] { "x" } } }))!);
        Assert.Equal("extra_forbidden", (string)(await Refused(new { name = "A", view = "roles", filters = new { }, extra = 1 }))[0]!["type"]!);
        Assert.Equal("literal_error", (string)(await Refused(new { name = "A", view = "unknown", filters = new { } }))[0]!["type"]!);
        Assert.Contains("nonempty readable name", (string)(await Refused(new { name = "   ", view = "roles", filters = new { } }))[0]!["msg"]!);
        Assert.Equal("string_too_long", (string)(await Refused(new { name = new string('a', 81), view = "roles", filters = new { } }))[0]!["type"]!);
        Assert.Contains("bounded scalar", (string)(await Refused(new { name = "A", view = "roles", filters = new { search = 1.5 } }))[0]!["msg"]!);
        Assert.Contains("bounded scalar", (string)(await Refused(new { name = "A", view = "roles", filters = new { search = new { nested = 1 } } }))[0]!["msg"]!);
        Assert.Contains("too long", (string)(await Refused(new { name = "A", view = "roles", filters = new { search = new string('x', 513) } }))[0]!["msg"]!);
        Assert.Contains("too large", (string)(await Refused(new { name = "A", view = "users", filters = new { usernames = new string('é', 3000) } }))[0]!["msg"]!);
        Assert.Equal("too_long", (string)(await Refused(new { name = "A", view = "roles", filters = Enumerable.Range(0, 41).ToDictionary(i => $"k{i}", _ => "v") }))[0]!["type"]!);
        // 12 000 characters are allowed for usernames only.
        Assert.Equal(HttpStatusCode.OK, (await Save(new { name = "Many users", view = "users", filters = new { usernames = new string('U', 12000) } })).Status);
        Assert.DoesNotContain(JsonNode.Parse(await _client.GetStringAsync("/api/saved-filters"))!["items"]!.AsArray(), i => (string)i!["name"]! == "A");
    }

    [Fact]
    public async Task Python_json_length_matches_json_dumps()
    {
        // json.dumps({"a": [1, "é\n"], "b": true}) == '{"a": [1, "\\u00e9\\n"], "b": true}'
        Assert.Equal("{\"a\": [1, \"\\u00e9\\n\"], \"b\": true}", V1SavedFilters.PyJson(JsonNode.Parse("{\"a\":[1,\"é\\n\"],\"b\":true}"), ensureAscii: true));
        Assert.Equal("{\"a\": \"é\"}", V1SavedFilters.PyJson(JsonNode.Parse("{\"a\":\"é\"}"), ensureAscii: false));
        await Task.CompletedTask;
    }
}
