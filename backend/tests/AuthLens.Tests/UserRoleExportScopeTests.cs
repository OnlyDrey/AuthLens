using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Api;
using AuthLens.Domain.Csv;
using Microsoft.AspNetCore.Builder;

namespace AuthLens.Tests;

public sealed class UserRoleExportScopeTests : IAsyncLifetime
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-role-export-").FullName;
    private WebApplication _app = null!;
    private HttpClient _client = null!;
    public async Task InitializeAsync()
    {
        var token = HostSettings.NewToken();
        _app = AuthLensHost.Build(new HostSettings { DataDirectory = Path.Combine(_root, "data"), Port = 0, AccessToken = token, JsonConsoleLogging = false });
        await _app.StartAsync();
        _client = new HttpClient { BaseAddress = new Uri(_app.Urls.First()) };
        _client.DefaultRequestHeaders.Add(RequestBoundary.TokenHeader, token);
        var roles = "FUNCTION_KEY,AGR_NAME,TEXT,CHILD_AGR,TCODE\nMM,ZC:MM:A,Alpha,ZS:A,T01\nFI,ZC:FI:B,Beta,ZS:B,T02\nSD,ZC:SD:EXTRA,Unrelated,ZS:EXTRA,T03\nMM,ZC:MM:BUY:*,Purchasing,ZS:BUY,T04\n";
        var users = "USERNAME,ROLE_NAME,USER_GROUP,ROLE_VALID_FROM,ROLE_VALID_TO,USER_VALID_FROM,USER_VALID_TO\n"
            + string.Join('\n', new[] { ("ALICE", "ZC:MM:A", "G1"), ("ALICE", "ZC:MM:A", "G2"), ("ALICE", "ZC:FI:B", "G1"), ("ALICE", "ZC:SD:EXTRA", "G1"), ("ALICE", "ZC:MM:BUY:ENP", "G1"),
                ("BOB", "ZC:MM:A", "G1"), ("BOB", "ZC:SD:EXTRA", "G1"), ("CHARLIE", "ZC:FI:B", "G1"), ("CHARLIE", "ZC:SD:EXTRA", "G1"), ("DAN", "ZC:MM:A", "OTHER") }
                .Select(row => $"{row.Item1},{row.Item2},{row.Item3},20200101,99991231,20200101,99991231")) + "\n";
        foreach (var (source, csv) in new[] { ("roles", roles), ("users", users) })
        {
            var response = await _client.PostAsync($"/api/v1/imports/{source}", new StringContent(csv, Encoding.UTF8, "text/csv"));
            response.EnsureSuccessStatusCode();
            var job = JsonNode.Parse(await response.Content.ReadAsStringAsync())!;
            string status = "";
            for (var i = 0; i < 200; i++)
            {
                status = (string)JsonNode.Parse(await _client.GetStringAsync($"/api/v1/jobs/{(long)job["id"]!}"))!["status"]!;
                if (status is "Completed" or "Failed") break;
                await Task.Delay(50);
            }
            Assert.Equal("Completed", status);
        }
    }
    public async Task DisposeAsync()
    {
        _client.Dispose(); await _app.StopAsync(); await _app.DisposeAsync();
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools(); Directory.Delete(_root, true);
    }
    private async Task<List<string[]>> Export(string query = "", string[]? selected = null)
    {
        var url = "/api/access/exports/users?" + query;
        HttpResponseMessage response;
        if (selected is null) response = await _client.GetAsync(url);
        else
        {
            var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(new JsonObject { ["selected_usernames"] = new JsonArray(selected.Select(name => (JsonNode?)JsonValue.Create(name)).ToArray()) }.ToJsonString(), Encoding.UTF8, "application/json") };
            request.Headers.Add("Origin", _client.BaseAddress!.GetLeftPart(UriPartial.Authority));
            response = await _client.SendAsync(request);
        }
        response.EnsureSuccessStatusCode();
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal("efbbbf", Convert.ToHexStringLower(bytes[..3]));
        var text = Encoding.UTF8.GetString(bytes);
        Assert.StartsWith("\ufeff\"USERNAME\";", text);
        var rows = CsvReader.Read(new StringReader(text.TrimStart('\ufeff')), ';').ToList();
        Assert.Equal(13, rows[0].Length);
        rows.RemoveAt(0);
        Assert.Equal(rows.Count.ToString(), response.Headers.GetValues("X-SAP-Lens-Assignment-Count").Single());
        return rows;
    }
    [Fact]
    public async Task Exact_role_scope_excludes_unrelated_roles_and_listing_count_agrees()
    {
        var rows = await Export("roles=ZC:MM:A");
        Assert.Equal(4, rows.Count); Assert.All(rows, row => Assert.Equal("ZC:MM:A", row[5]));
        Assert.Equal(new[] { "ALICE", "BOB", "DAN" }, rows.Select(row => row[0]).Distinct().Order().ToArray());
        var page = JsonNode.Parse(await _client.GetStringAsync("/api/access/users?roles=ZC:MM:A"))!;
        Assert.Equal(rows.Count, (int)page["export_assignments"]!);
    }
    [Theory]
    [InlineData("and", 3, 1)]
    [InlineData("or", 6, 4)]
    public async Task Multiple_roles_are_OR_and_transaction_user_matching_retains_AND_OR(string mode, int count, int users)
    {
        var rows = await Export($"roles=ZC:MM:A&roles=ZC:FI:B&tcodes=T01&tcodes=T02&transaction_mode={mode}");
        Assert.Equal(count, rows.Count); Assert.Equal(users, rows.Select(row => row[0]).Distinct().Count());
        Assert.All(rows, row => Assert.Contains(row[5], new[] { "ZC:MM:A", "ZC:FI:B" }));
    }
    [Theory]
    [InlineData("ZC:MM:*", 5)]
    [InlineData("ZC:MM:BUY:*", 1)]
    [InlineData(" zc:mm:a ", 4)]
    public async Task Prefix_patterns_and_normalized_exact_names_share_user_and_export_matching(string role, int count)
    {
        var rows = await Export("roles=" + Uri.EscapeDataString(role));
        Assert.Equal(count, rows.Count); Assert.DoesNotContain(rows, row => row[5] == "ZC:SD:EXTRA");
    }
    [Fact]
    public async Task No_role_filter_preserves_full_access_and_csv_contract()
    {
        var rows = await Export(); Assert.Equal(10, rows.Count);
        Assert.Equal(3, rows.Count(row => row[5] == "ZC:SD:EXTRA"));
    }
    [Fact]
    public async Task Selected_users_are_intersected_with_every_active_filter_not_substituted_for_them()
    {
        var rows = await Export("roles=ZC:MM:A&groups=G1&search=ALICE", ["alice", "BOB", "CHARLIE", "DAN"]);
        Assert.Equal(2, rows.Count); Assert.All(rows, row => Assert.Equal("ALICE", row[0]));
        Assert.Contains(rows, row => row[4] == "G2" && row[12] == "No"); // group is a user filter; role scope is independent evidence
        var exact = await Export("roles=ZC:MM:A&groups=G1&usernames=BOB,DAN", ["ALICE", "BOB", "DAN"]);
        Assert.Single(exact); Assert.Equal("BOB", exact[0][0]);
    }
    [Fact]
    public async Task All_matching_ignores_paging_selected_scope_is_explicit_and_nonmatching_selection_never_falls_back()
    {
        Assert.Equal(4, (await Export("roles=ZC:MM:A&offset=0&limit=1")).Count);
        var selected = await Export("roles=ZC:MM:A", ["BOB"]); Assert.Single(selected); Assert.Equal("BOB", selected[0][0]);
        Assert.Empty(await Export("roles=ZC:MM:A", ["CHARLIE", "MISSING"]));
    }
    // #35 export scope: matching (default) keeps the role-filter rows; all_assignments exports every assignment of the same user population.
    private static string[] Keys(List<string[]> rows) => [.. rows.Select(row => $"{row[0]}|{row[5]}|{row[4]}").Order(StringComparer.Ordinal)];
    [Fact]
    public async Task All_assignments_exports_every_assignment_of_matching_users_and_only_of_them()
    {
        var matching = await Export("roles=ZC:MM:A");
        var all = await Export("roles=ZC:MM:A&export_scope=all_assignments");
        Assert.Equal(Keys(matching), Keys(await Export("roles=ZC:MM:A&export_scope=matching"))); // explicit matching = absent parameter
        Assert.Equal(new[] { "ALICE", "BOB", "DAN" }, all.Select(row => row[0]).Distinct().Order().ToArray()); // same population; CHARLIE stays out
        Assert.Equal(8, all.Count); // ALICE 5 (matching and non-matching), BOB 2, DAN 1
        Assert.Equal(5, all.Count(row => row[0] == "ALICE"));
        Assert.Contains(all, row => row[0] == "ALICE" && row[5] == "ZC:SD:EXTRA" && row[12] == "No"); // non-matching rows are marked by MATCHED_FILTER
        Assert.All(all.Where(row => row[5] == "ZC:MM:A"), row => Assert.Equal("Yes", row[12]));
        Assert.Equal(Keys(all).Length, Keys(all).Distinct().Count()); // no duplicate rows
        Assert.Subset(Keys(all).ToHashSet(), Keys(matching).ToHashSet());
    }
    [Theory]
    [InlineData("and", 1, 5)]
    [InlineData("or", 4, 10)]
    public async Task All_assignments_keeps_AND_OR_user_matching(string mode, int users, int count)
    {
        var rows = await Export($"roles=ZC:MM:A&roles=ZC:FI:B&tcodes=T01&tcodes=T02&transaction_mode={mode}&export_scope=all_assignments");
        Assert.Equal(users, rows.Select(row => row[0]).Distinct().Count()); Assert.Equal(count, rows.Count);
        var matching = await Export($"roles=ZC:MM:A&roles=ZC:FI:B&tcodes=T01&tcodes=T02&transaction_mode={mode}");
        Assert.Equal(matching.Select(row => row[0]).Distinct().Order(), rows.Select(row => row[0]).Distinct().Order());
    }
    [Fact]
    public async Task All_assignments_with_user_filters_without_role_filters_empty_results_and_selection()
    {
        var combined = await Export("roles=ZC:MM:A&groups=G1&search=ALICE&export_scope=all_assignments");
        Assert.Equal(5, combined.Count); Assert.All(combined, row => Assert.Equal("ALICE", row[0]));
        Assert.Equal(Keys(await Export()), Keys(await Export("export_scope=all_assignments"))); // no role filter: both scopes export everything
        Assert.Equal(Keys(await Export("groups=G1")), Keys(await Export("groups=G1&export_scope=all_assignments")));
        Assert.Empty(await Export("roles=ZC:MM:A&search=NOBODY&export_scope=all_assignments"));
        var selected = await Export("roles=ZC:MM:A&export_scope=all_assignments", ["BOB"]);
        Assert.Equal(2, selected.Count); Assert.All(selected, row => Assert.Equal("BOB", row[0]));
        Assert.Empty(await Export("roles=ZC:MM:A&export_scope=all_assignments", ["CHARLIE"])); // a selection never widens the population
    }
    [Fact]
    public async Task Export_scope_reconciles_listing_count_and_report_preview_and_rejects_unknown_values()
    {
        foreach (var scope in new[] { "", "&export_scope=matching", "&export_scope=all_assignments" })
        {
            var rows = await Export("roles=ZC:MM:A" + scope);
            var page = JsonNode.Parse(await _client.GetStringAsync("/api/access/users?roles=ZC:MM:A" + scope))!;
            Assert.Equal(rows.Count, (int)page["export_assignments"]!);
            Assert.Equal(3, (int)page["total"]!); // the displayed population does not depend on the scope
            var preview = JsonNode.Parse(await _client.GetStringAsync("/api/access/exports/users?roles=ZC:MM:A&preview=true" + scope))!;
            Assert.Equal(rows.Count, (int)preview["total_rows"]!);
        }
        foreach (var url in new[] { "/api/access/exports/users?export_scope=everything", "/api/access/users?export_scope=ALL_ASSIGNMENTS" })
            Assert.Equal((HttpStatusCode)422, (await _client.GetAsync(url)).StatusCode);
    }
    [Fact]
    public async Task Selected_export_validates_body_and_uses_existing_authenticated_export_permission()
    {
        foreach (var body in new[] { "{}", "{\"selected_usernames\":[]}", "{\"selected_usernames\":[1]}", "{\"selected_usernames\":[\"BOB\"],\"all\":true}" })
        {
            var request = new HttpRequestMessage(HttpMethod.Post, "/api/access/exports/users") { Content = new StringContent(body, Encoding.UTF8, "application/json") };
            request.Headers.Add("Origin", _client.BaseAddress!.GetLeftPart(UriPartial.Authority));
            Assert.Equal((HttpStatusCode)422, (await _client.SendAsync(request)).StatusCode);
        }
        Assert.Equal("export", V1Auth.Permission("POST", "/api/access/exports/users"));
        Assert.Equal("unknown", V1Auth.Permission("DELETE", "/api/access/exports/users"));
    }
}
