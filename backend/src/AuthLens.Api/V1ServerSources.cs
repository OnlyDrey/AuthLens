using System.Security.Cryptography;
using System.Text.Json.Nodes;
using AuthLens.Application;
using AuthLens.Domain.Imports;
using AuthLens.Domain.Roles;

namespace AuthLens.Api;

public static partial class V1DataSources
{
    private static void MapServerSources(RouteGroupBuilder api)
    {
        api.MapGet("/server/sources/{source}", async (string source, V1Settings store, HostSettings host, HttpContext http, CancellationToken ct) =>
        {
            http.Response.Headers.CacheControl = "no-store";
            if (!Names.ContainsKey(source)) return Detail(422, "Unknown source.");
            var settings = await store.GetAsync(ct);
            var path = (string?)settings[PathField[source]] ?? "";
            // Description never tests the filesystem or contacts a share.
            // authorization: none, managed, approved_root, exact, required (reauthorize: restored or revoked), invalid, not_applicable (Desktop).
            return Results.Ok(new { path, mode = (string?)settings["source_modes"]?[source], configured = path.Length > 0, host = Environment.MachineName,
                authorization = ServerSourcePolicy.Authorization(host, source, path), network = path.StartsWith(@"\\", StringComparison.Ordinal) });
        });
        // WP33 host file picker. Administration only (request boundary). Locations read no folder; a listing touches only an approved root.
        api.MapGet("/server/sources/browse", async (HttpContext http, HostSettings host, V1Settings store, string? path, string? q, bool? all, CancellationToken ct) =>
        {
            http.Response.Headers.CacheControl = "no-store";
            if (host.Mode != HostMode.Server) return Detail(404, "Host browsing is available on Server installations; Desktop uses the system file dialog.");
            if (string.IsNullOrWhiteSpace(path))
            {
                var settings = await store.GetAsync(ct);
                var configured = PathField.Values.Select(field => (string?)settings[field] ?? "");
                return Results.Ok(new { host = Environment.MachineName, locations = ServerSourceBrowser.Locations(host, configured) });
            }
            // Bounded: an unresponsive network location answers 503 after BrowseTimeout instead of holding the request (FILE-004). The enumeration
            // itself is read-only and ends with the operating system's own SMB timeout.
            try { return Results.Ok(await Task.Run(() => ServerSourceBrowser.Browse(host, path, q, all == true), ct).WaitAsync(ServerSourceBrowser.BrowseTimeout, ct)); }
            catch (TimeoutException) { return Results.Json(new { detail = $"The location did not answer within {ServerSourceBrowser.BrowseTimeout.TotalSeconds:0} seconds from the AuthLens server.", category = "network_unavailable" }, statusCode: 503); }
            catch (SourcePolicyException error) when (error.Failure == SourcePolicyFailure.Authorization)
            { return Results.Json(new { detail = "This folder is not approved for browsing. An administrator can approve it under Approved folders; nothing was read from it.", category = "not_approved" }, statusCode: 403); }
            catch (SourcePolicyException error) { return Results.Json(new { detail = error.Message, category = error.Failure == SourcePolicyFailure.UnsafePath ? "unsafe_path" : "invalid_path" }, statusCode: 400); }
            catch (UnauthorizedAccessException) { return Results.Json(new { detail = "The AuthLens service identity cannot list this folder. Grant it NTFS read (and, for a network folder, share) access; AuthLens never uses your browser sign-in for server files.", category = "access_denied" }, statusCode: 403); }
            catch (Exception error) when (error is DirectoryNotFoundException or FileNotFoundException) { return Results.Json(new { detail = "The folder does not exist or is not reachable from the AuthLens server.", category = "missing" }, statusCode: 404); }
            catch (Exception error) when (error is IOException or System.Net.Sockets.SocketException) { return Results.Json(new { detail = "The network location is unavailable from the AuthLens server.", category = "network_unavailable" }, statusCode: 503); }
        });
        api.MapGet("/server/sources/roots", (HttpContext http, HostSettings host) =>
        {
            http.Response.Headers.CacheControl = "no-store";
            if (host.Mode != HostMode.Server) return Detail(404, "Approved folders apply to Server installations.");
            try { return Results.Ok(new { approved = ServerSourceAuthorization.Roots(host), operator_roots = host.SourceRoots, max = ServerSourceAuthorization.MaxRoots }); }
            catch (SourcePolicyException) { return Detail(409, "The protected source authority could not be read; nothing is approved until the server operator reviews it."); }
        });
        api.MapPost("/server/sources/roots", async (HttpContext http, HostSettings host, CancellationToken ct) =>
        {
            var (body, invalid) = await V1Validation.ReadBody(http, ct);
            if (invalid is not null) return invalid;
            if (host.Mode != HostMode.Server || body?["path"] is not JsonValue pv || !pv.TryGetValue<string>(out var path)
                || body["approve_folder_access"] is not JsonValue flag || !flag.TryGetValue<bool>(out var approved) || !approved)
                return Detail(422, "Explicit approval of the folder is required.");
            try
            {
                var folder = ServerSourceAuthorization.ApproveRoot(host, path.Trim());
                http.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogInformation("Server source browse folder approved by {Actor}; no source data activated", Actors.Name(http));
                return Results.Ok(new { approved = true, path = folder, data_modified = false });
            }
            catch (SourceAuthorityUnavailableException error) { return Detail(409, error.Message); }
            catch (SourcePolicyException error) { return Detail(400, error.Failure == SourcePolicyFailure.UnsafePath ? "This folder cannot be approved: volume and share roots, the AuthLens installation and Windows, program or user-profile locations are excluded. Approve the specific export folder instead." : error.Message); }
            catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException) { return Detail(400, V1Refresh.Category(error).Message); }
        });
        api.MapDelete("/server/sources/roots", (HttpContext http, HostSettings host, string path) =>
        {
            if (host.Mode != HostMode.Server) return Detail(422, "Approved folders apply to Server installations.");
            try
            {
                var removed = ServerSourceAuthorization.RevokeRoot(host, path);
                http.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogInformation("Server source browse folder revoked by {Actor}; configurations and snapshots retained", Actors.Name(http));
                return Results.Ok(new { revoked = removed, data_modified = false });
            }
            catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException) { return Detail(400, V1Refresh.Category(error).Message); }
        });
        api.MapDelete("/server/sources/{source}/authorize", (string source, HttpContext http, HostSettings host) =>
        {
            if (host.Mode != HostMode.Server || !Names.ContainsKey(source)) return Detail(422, "Unknown server source.");
            try
            {
                var revoked = ServerSourceAuthorization.Revoke(host, source);
                http.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogInformation("Server source authority revoked for {Source} by {Actor}; configuration and snapshot retained", source, Actors.Name(http));
                return Results.Ok(new { revoked, data_modified = false });
            }
            catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException)
            { return Detail(400, V1Refresh.Category(error).Message); }
        });
        api.MapPost("/server/sources/{source}/authorize", async (string source, HttpContext http, HostSettings host, CancellationToken ct) =>
        {
            var (body, invalid) = await V1Validation.ReadBody(http, ct);
            if (invalid is not null) return invalid;
            if (host.Mode != HostMode.Server || !Names.ContainsKey(source) || body?["path"] is not JsonValue pv || !pv.TryGetValue<string>(out var path)
                || body["approve_host_access"] is not JsonValue flag || !flag.TryGetValue<bool>(out var approved) || !approved)
                return Detail(422, "Explicit approval of the exact server source is required.");
            try
            {
                ServerSourceAuthorization.Approve(host, source, path.Trim());
                http.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogInformation("Server source authority updated for {Source} by {Actor}; no source data activated", source, Actors.Name(http));
                return Results.Ok(new { authorized = true, data_modified = false });
            }
            catch (SourceAuthorityUnavailableException error) { return Detail(409, error.Message); }
            catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException)
            { return Detail(400, V1Refresh.Category(error).Message); }
        });
        api.MapPost("/server/sources/{source}/validate", async (string source, HttpContext http, HostSettings host, IServiceProvider services, CancellationToken ct) =>
        {
            var (body, invalid) = await V1Validation.ReadBody(http, ct);
            if (invalid is not null) return invalid;
            if (!Names.ContainsKey(source) || body?["path"] is not JsonValue pv || !pv.TryGetValue<string>(out var requested)
                || body["revision"] is not JsonValue rv || !rv.TryGetValue<int>(out var revision)) return Detail(422, "An absolute CSV source path and settings revision are required.");
            var temporary = "";
            try
            {
                var path = ServerSourcePolicy.Resolve(host, requested.Trim(), source);
                var settings = await services.GetRequiredService<V1Settings>().GetAsync(ct);
                if (revision != (int)settings["revision"]!) return Detail(409, "Settings changed. Reload before validating this source.");
                var profile = body["profile"] is JsonObject supplied ? source switch
                {
                    "roles" => Profile(supplied, AuthLens.Domain.Csv.CsvSpec.Roles.Fields),
                    "users" => Profile(supplied, AuthLens.Domain.Csv.CsvSpec.Users.Fields),
                    "sod" => Profile(supplied, AuthLens.Domain.Csv.CsvSpec.Sod.Fields),
                    _ => null,
                } : ActiveProfile(settings, source);
                if (profile is null) throw new DomainValidationException("The source import profile is invalid.");
                var directory = Path.Combine(host.DataDirectory, "uploads"); Directory.CreateDirectory(directory);
                temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".csv");
                File.Copy(path, temporary, false);
                string hash;
                using (var input = File.OpenRead(temporary)) hash = Convert.ToHexStringLower(await SHA256.HashDataAsync(input, ct));
                var (records, report) = Sources.Read(source, temporary, ct, profile);
                var rows = await Task.Run(() => records.ToList(), ct);
                if (rows.Count == 0) throw new EmptySourceException();
                ImportService.ValidateModel(source, rows, report.Warnings, await services.GetRequiredService<SnapshotService>().GetAsync(ct), Path.GetFileName(path), hash);
                services.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogInformation("Server source validation succeeded for {Source} by {Actor}", source, Actors.Name(http));
                return Results.Ok(new { status = "validated", records = rows.Count, sha256 = hash, revision = (int)settings["revision"]!, data_modified = false,
                    message = "Complete CSV validated under the running AuthLens process identity. No dataset was activated." });
            }
            catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException or DomainValidationException or AuthLens.Domain.Csv.CsvFormatException or System.Net.Sockets.SocketException or InvalidDataException)
            {
                var problem = V1Refresh.Category(error);
                services.GetRequiredService<ILoggerFactory>().CreateLogger("AuthLens.Sources").LogWarning("Server source validation failed for {Source}: {Category}", source, problem.Category);
                return Results.Json(new { detail = problem.Message, category = problem.Category, previous_preserved = true }, statusCode: 400);
            }
            finally { if (temporary.Length > 0) TryDelete(temporary); }
        });
    }
}
