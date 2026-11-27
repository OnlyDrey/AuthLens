using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Api;
using Microsoft.AspNetCore.Builder;

namespace AuthLens.Tests;

/// <summary>NAV-6: the combined PR/PO Release Access matrix. Distinct-user totals come from the backend, per row and release type, per type and for PR
/// and PO combined; a user with both types or several strategies counts once, identically named strategies stay separate per type, filters apply, and
/// each total reconciles with the drill-down population.</summary>
public sealed class ReleaseAccessMatrixTests : IAsyncLifetime
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-release-matrix-").FullName;
    private readonly string _token = HostSettings.NewToken();
    private WebApplication _app = null!;
    private HttpClient _client = null!;

    private const string Active = "20000101;99991231";
    private static string Row(string user, string role, string group) => $"{user};{role};{group};Syn;{user};{user.ToLowerInvariant()}@example.invalid;{Active};{Active};;A";
    private static readonly string Users = Csv.UsersHeader + "\n" + string.Join("\n",
        Row("U1", "ZO:MM:N:PR_REL_ST_G1_S1:ALL", "GRP_A"),   // U1: PR and PO, the same strategy name under both types, and a second PR strategy
        Row("U1", "ZO:MM:N:PO_REL_ST_G1_S1:ALL", "GRP_A"),
        Row("U1", "ZO:MM:N:PR_REL_ST_G1_S2:ALL", "GRP_A"),
        Row("U2", "ZO:MM:N:PR_REL_ST_G1_S2:ALL", "GRP_A"),
        Row("U3", "ZO:MM:N:PO_REL_ST_G2_S1:ALL", "GRP_A"),
        Row("U4", "ZO:MM:N:PR_REL_ST_G1_S1:ALL", "GRP_B"),
        Row("U5", "ZO:MM:UNPARSED_RELEASE", "GRP_A")) + "\n"; // a release role whose name is not parsed: Table only, never in the matrix

    public async Task InitializeAsync()
    {
        _app = AuthLensHost.Build(new HostSettings { DataDirectory = Path.Combine(_root, "data"), Port = 0, AccessToken = _token, JsonConsoleLogging = false });
        await _app.StartAsync();
        _client = new HttpClient { BaseAddress = new Uri(_app.Urls.First()) };
        _client.DefaultRequestHeaders.Add(RequestBoundary.TokenHeader, _token);
        foreach (var (source, csv) in new[] { ("roles", Csv.Roles(2)), ("users", Users) })
        {
            var job = JsonNode.Parse(await (await _client.PostAsync($"/api/v1/imports/{source}", new StringContent(csv, Encoding.UTF8, "text/csv"))).Content.ReadAsStringAsync())!;
            for (var i = 0; i < 400 && (string)JsonNode.Parse(await _client.GetStringAsync($"/api/v1/jobs/{(long)job["id"]!}"))!["status"]! != "Completed"; i++) await Task.Delay(50);
        }
    }

    public async Task DisposeAsync()
    {
        _client.Dispose();
        await _app.StopAsync();
        await _app.DisposeAsync();
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        try { Directory.Delete(_root, true); } catch (IOException) { }
    }

    private async Task<JsonNode> Get(string path) => JsonNode.Parse(await _client.GetStringAsync(path))!;

    /// <summary>Total for (user group, type or null, release group or null, strategy or null).</summary>
    private static int Total(JsonNode page, string? type, string? group, string userGroup = "", string? strategy = null) => (int)page["matrix_totals"]!.AsArray()
        .Single(t => (string)t!["user_group"]! == userGroup && (string?)t["document_type"] == type && (string?)t["release_group"] == group && (string?)t["release_strategy"] == strategy)!["distinct_users"]!;

    private static int Cell(JsonNode page, string type, string group, string strategy) => (int)page["matrix"]!.AsArray()
        .Single(c => (string)c!["document_type"]! == type && (string)c["release_group"]! == group && (string)c["release_strategy"]! == strategy)!["user_count"]!;

    private async Task<int> Drill(string query) => (int)(await Get("/api/access/release-assignments?status=all&parsed=true&" + query))["distinct_users"]!;

    [Fact]
    public async Task Combined_totals_count_each_user_once_and_keep_types_and_strategies_apart()
    {
        var page = await Get("/api/access/releases?status=all&matrix_complete=true&matrix_totals=true");
        // PR and PO stay separate dimensions in the data: strategy S1 is a PR cell and a PO cell with their own distinct-user counts.
        Assert.Equal((2, 1, 2, 1), (Cell(page, "PR", "G1", "S1"), Cell(page, "PO", "G1", "S1"), Cell(page, "PR", "G1", "S2"), Cell(page, "PO", "G2", "S1")));
        // The matrix shows one S1 column for both types: its G1 cell is {U1, U4} = 2, not PR 2 + PO 1 = 3 (U1 holds S1 under PR and PO).
        Assert.Equal((2, 2, 1), (Total(page, null, "G1", strategy: "S1"), Total(page, null, "G1", strategy: "S2"), Total(page, null, "G2", strategy: "S1")));
        // Strategy column totals over all Release Groups: S1 {U1, U3, U4} = 3, S2 {U1, U2} = 2.
        Assert.Equal((3, 2), (Total(page, null, null, strategy: "S1"), Total(page, null, null, strategy: "S2")));
        Assert.Equal(Total(page, null, "G1", strategy: "S1"), await Drill("release_group=G1&strategy=S1"));
        Assert.Equal(Total(page, null, null, strategy: "S1"), await Drill("strategy=S1"));
        // Row G1: PR {U1, U2, U4}, PO {U1}, combined {U1, U2, U4} = 3, not 3 + 1 and not the sum of the PR cells (2 + 2).
        Assert.Equal((3, 1, 3), (Total(page, "PR", "G1"), Total(page, "PO", "G1"), Total(page, null, "G1")));
        Assert.Equal((1, 1), (Total(page, "PO", "G2"), Total(page, null, "G2")));
        Assert.DoesNotContain(page["matrix_totals"]!.AsArray(), t => (string?)t!["document_type"] == "PR" && (string?)t["release_group"] == "G2"); // no PR in G2
        // Whole matrix: PR {U1, U2, U4}, PO {U1, U3}, combined {U1, U2, U3, U4} = 4 (U1 once; the unparsed U5 is not in the matrix).
        Assert.Equal((3, 2, 4), (Total(page, "PR", null), Total(page, "PO", null), Total(page, null, null)));

        // Each total reconciles with its drill-down population (parsed releases, the total's type and group).
        Assert.Equal(Total(page, null, "G1"), await Drill("release_group=G1"));
        Assert.Equal(Total(page, "PR", "G1"), await Drill("release_group=G1&document_type=PR"));
        Assert.Equal(Total(page, "PO", null), await Drill("document_type=PO"));
        Assert.Equal(Total(page, null, null), await Drill(""));
        Assert.Equal(5, (int)(await Get("/api/access/release-assignments?status=all"))["distinct_users"]!); // without parsed=true the Table population includes U5
    }

    [Fact]
    public async Task Totals_follow_the_matrix_filters_and_the_SAP_User_Group_comparison()
    {
        var filtered = await Get("/api/access/releases?status=all&matrix_complete=true&matrix_totals=true&strategies=S1");
        Assert.Equal((2, 1, 2, 3), (Total(filtered, "PR", "G1"), Total(filtered, "PO", "G1"), Total(filtered, null, "G1"), Total(filtered, null, null)));
        Assert.Equal(Total(filtered, null, "G1"), await Drill("release_group=G1&strategies=S1"));
        Assert.Equal(Total(filtered, null, null), await Drill("strategies=S1"));

        var pr = await Get("/api/access/releases?status=all&matrix_complete=true&matrix_totals=true&document_type=PR");
        Assert.Equal((3, 3), (Total(pr, "PR", null), Total(pr, null, null))); // a single release type: the combined total equals that type
        Assert.DoesNotContain(pr["matrix_totals"]!.AsArray(), t => (string?)t!["document_type"] == "PO");

        var groups = await Get("/api/access/releases?status=all&matrix_complete=true&matrix_totals=true&group_by_user_group=true");
        Assert.Equal((3, 1), (Total(groups, null, null, "GRP_A"), Total(groups, null, null, "GRP_B")));
        Assert.Equal((1, 1), (Total(groups, "PR", "G1", "GRP_B"), Total(groups, null, "G1", "GRP_B")));
        Assert.Equal(Total(groups, null, "G1", "GRP_A"), await Drill("release_group=G1&group=GRP_A"));

        var narrowed = await Get("/api/access/releases?status=all&matrix_complete=true&matrix_totals=true&usernames=u1");
        Assert.Equal((1, 1, 1), (Total(narrowed, "PR", "G1"), Total(narrowed, "PO", "G1"), Total(narrowed, null, null))); // subject filters: U1 alone, once for PR (two strategies), PO and both
    }
}
