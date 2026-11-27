using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using AuthLens.Api;
using Microsoft.AspNetCore.Builder;

namespace AuthLens.Tests;

/// <summary>NAV-4: report availability (per report, independent of the SoD module), the server-side Account Review, Position Changes and Compare Users
/// exports that replaced the browser builders, and the shared configurable columns of the access exports.</summary>
public sealed class ReportsTests : IAsyncLifetime
{
    private readonly string _root = Directory.CreateTempSubdirectory("authlens-reports-").FullName;
    private readonly string _token = HostSettings.NewToken();
    private WebApplication _app = null!;
    private HttpClient _client = null!;

    private const string Active = "20000101;99991231";
    private static readonly string Users = Csv.UsersHeader + "\n"
        + $"USER0001;ZC:FI:ROLE_0001;GRP_FIN;Ada;One;ada@example.invalid;{Active};{Active};;A\n"
        + $"USER0002;ZC:FI:ROLE_0002;GRP_FIN;Bo;Two;bo@example.invalid;{Active};{Active};;A\n"
        + $"USER0002;ZO:MM:N:PR_REL_ST_G1_S1:ALL;GRP_FIN;Bo;Two;bo@example.invalid;{Active};{Active};;A\n"
        + $"SVC0001;ZC:FI:ROLE_0001;GRP_TECH;;;;{Active};{Active};;S\n";

    public async Task InitializeAsync()
    {
        _app = AuthLensHost.Build(new HostSettings { DataDirectory = Path.Combine(_root, "data"), Port = 0, AccessToken = _token, JsonConsoleLogging = false });
        await _app.StartAsync();
        _client = new HttpClient { BaseAddress = new Uri(_app.Urls.First()) };
        _client.DefaultRequestHeaders.Add(RequestBoundary.TokenHeader, _token);
        foreach (var (source, csv) in new[] { ("roles", Csv.Roles(3)), ("users", Users) })
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

    private async Task<string[]> Lines(string path)
    {
        var response = await _client.GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal([0xEF, 0xBB, 0xBF], bytes[..3]); // UTF-8 with BOM
        return Encoding.UTF8.GetString(bytes[3..]).Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
    }

    [Fact]
    public async Task Availability_is_per_report_and_does_not_depend_on_the_SoD_module()
    {
        var page = JsonNode.Parse(await _client.GetStringAsync("/api/reports/availability"))!;
        // SoD is off in a fresh installation: SoD reports are not offered, the account and access reports are.
        Assert.False((bool)page["sod_enabled"]!);
        Assert.Equal(["review", "access"], page["pages"]!.AsArray().Select(p => (string)p!).ToArray());
        var reports = page["reports"]!.AsArray().ToDictionary(r => (string)r!["id"]!, r => r!);
        Assert.DoesNotContain("formal_review", reports.Keys);
        Assert.DoesNotContain("risk_matrix", reports.Keys);
        Assert.True((bool)reports["account_review"]["available"]!);
        Assert.True((bool)reports["compare_users"]["available"]!);
        Assert.False((bool)reports["position_changes"]["available"]!); // listed with its reason: no Employee Directory import
        Assert.Contains("Employee Directory", (string)reports["position_changes"]["reason"]!);
        Assert.Equal("username", (string)reports["account_review"]["columns"]![0]!["key"]!);
        Assert.True((bool)reports["account_review"]["columns"]![0]!["required"]!);
    }

    [Fact]
    public async Task Account_review_and_comparison_exports_keep_their_columns_and_format()
    {
        var review = await Lines("/api/account-review/export?include_completed=true");
        Assert.Equal("\"Username\",\"User group\",\"Full name\",\"SAP validity\",\"SAP lock status\",\"AD account status\",\"Directory match\",\"Findings\",\"License group classification\",\"Review state\",\"Reviewer\",\"Reviewed at\",\"Rationale\",\"Evidence version\",\"Reviewed evidence version\",\"Stale decision\"", review[0]);
        var list = JsonNode.Parse(await _client.GetStringAsync("/api/account-review?include_completed=true&limit=100"))!;
        Assert.Equal((int)list["total"]!, review.Length - 1); // the same population as the list
        Assert.StartsWith("\"SVC0001\",", review[1]);

        var compare = await Lines("/api/user-comparison/export?user_a=USER0001&user_b=USER0002&kind=roles&validity=active");
        Assert.Equal("\"Username\",\"User group\",\"Compared with\",\"Category\",\"Kind\",\"Identifier\",\"Side\",\"Assigned role\",\"Valid from\",\"Valid to\",\"Assignment status\",\"Catalogue match\",\"Validity view\",\"As of\"", compare[0]);
        Assert.Contains(compare, line => line.StartsWith("\"USER0002\",\"GRP_FIN\",\"USER0001\",\"b\",\"roles\",\"ZC:FI:ROLE_0002\",\"b\",", StringComparison.Ordinal));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/user-comparison/export?user_a=USER0001")).StatusCode);
    }

    [Fact]
    public async Task Columns_are_validated_ordered_and_previewed()
    {
        var chosen = await Lines("/api/account-review/export?include_completed=true&columns=review_state&columns=username&delimiter=semicolon");
        Assert.Equal("\"Review state\";\"Username\"", chosen[0]); // requested order, semicolon
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/account-review/export?columns=review_state")).StatusCode); // username is required
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/account-review/export?columns=username&columns=nope")).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/account-review/export?columns=username&columns=username")).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/account-review/export?delimiter=tab")).StatusCode);
        var preview = JsonNode.Parse(await _client.GetStringAsync("/api/account-review/export?include_completed=true&columns=username&preview=true"))!;
        Assert.Equal(3, (int)preview["total_rows"]!);
        Assert.Equal("Username", (string)preview["columns"]![0]!["label"]!);

        // The access exports keep their v1 output without report options and take the shared columns with them.
        var legacy = await Lines("/api/access/exports/release-roles?status=all");
        Assert.Equal("\"ROLE_NAME\";\"ROLE_DESCRIPTION\";\"RELEASE_AREA\";\"RELEASE_GROUP\";\"RELEASE_STRATEGY\";\"PR_PO\"", legacy[0]);
        var roles = await Lines("/api/access/exports/release-roles?status=all&columns=role_name&columns=document_type");
        Assert.Equal(["\"ROLE_NAME\";\"PR_PO\"", "\"ZO:MM:N:PR_REL_ST_G1_S1:ALL\";\"PR\""], roles);
        var assignments = await Lines("/api/access/exports/releases?status=all&columns=username&columns=role_name&columns=release_strategy");
        Assert.Equal(["\"USERNAME\";\"ROLE_NAME\";\"RELEASE_STRATEGY\"", "\"USER0002\";\"ZO:MM:N:PR_REL_ST_G1_S1:ALL\";\"S1\""], assignments);
        var directory = await Lines("/api/access/exports/users?columns=username&columns=role_name");
        Assert.Equal("\"USERNAME\";\"ROLE_NAME\"", directory[0]);
        Assert.Contains("\"USER0001\";\"ZC:FI:ROLE_0001\"", directory);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/access/exports/releases?columns=release_strategy")).StatusCode);
    }

    [Fact]
    public async Task Position_changes_need_the_directory_and_report_only_recorded_values()
    {
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await _client.GetAsync("/api/account-review/positions/export")).StatusCode); // status is required
        Assert.Equal(HttpStatusCode.Conflict, (await _client.GetAsync("/api/account-review/positions/export?position_status=all")).StatusCode);
        // The column definitions name the detection honestly: when a value was first seen in an import, not when the change happened.
        Assert.Contains(V1Reports.PositionColumns, c => c.Key == "detected_at" && c.Label == "First seen in an import");
        Assert.DoesNotContain(V1Reports.PositionColumns, c => c.Label.Contains("effective", StringComparison.OrdinalIgnoreCase) || c.Label.Contains("change date", StringComparison.OrdinalIgnoreCase));
    }
}
