# Versioning and build identity

The product is **AuthLens**. The current version is `2.0.0-alpha.1`; `backend/product-version.json` is its authoritative source.
Frontend package metadata mirrors that value. Builds do not increment the product version.

## Canonical identities

| Item | Identity |
| --- | --- |
| Windows service | `AuthLens`, account `NT SERVICE\AuthLens` |
| Server executable | `AuthLens.Api.exe` |
| Desktop executable | `AuthLens.exe` |
| Server installation root | `C:\ProgramData\AuthLens` |
| Application database | `authlens.sqlite3` |
| Desktop data root | `%LOCALAPPDATA%\AuthLens` |
| Configuration variables | `AUTHLENS_*` |
| Deployment module | `AuthLens.Deploy`, functions `*-AL*` |
| Desktop installer | `AuthLens-<version>-Setup.exe` |
| Server installer | `AuthLens-Server-<version>-Setup.exe` |
| Branding sources | [assets/branding](../../assets/branding/) |

## Version, channel and build

Product versions use `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-alpha.N`, `-beta.N`, `-rc.N`. The pre-release number starts at 1.
The Windows file version is `MAJOR.MINOR.PATCH.N`, with 0 as its last component for a stable version.
The current assembly version is `2.0.0.0` and file version `2.0.0.1`.

Build identity is separate: source commit, UTC build timestamp, platform and SHA-256 checksums are recorded by the release scripts in
`build-manifest.json` and `SHA256SUMS`. A release build records whether the working tree was dirty. Versioned release directories are never overwritten.

The CLI `--version`, `/product-version.json`, application information, Desktop About and release manifest expose build/product identity.
The host serves its own runtime identity; frontend assets carry the product metadata embedded when they were built.

## Release policy

Build and verify packages using the [deployment guide](../deployment/DESKTOP_SERVER_DEPLOYMENT.md). A source push does not publish packages.
CI runs only on push to `main`; development validation is local. Tags, releases, merges and deployment require explicit authorization.
Native installer, Desktop, service, restart, TLS, backup/restore and rollback acceptance are tracked separately in [current status](../validation/STATUS.md).
