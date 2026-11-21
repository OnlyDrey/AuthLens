# Data & CSV

1. [CSV Schemas](CSV_SCHEMAS.md): exact fields, limits, encodings and source-specific presets.
2. [Import & Refresh](IMPORT_AND_REFRESH.md): Static/Dynamic modes, validation, full replacement, snapshots and recovery.
3. [Employee Directory](EMPLOYEE_DIRECTORY.md): identity/manager matching and independent feature dependencies.
4. [Data Health](DATA_HEALTH.md): source availability, findings, coverage denominators and drilldowns.
5. [SAP area classification](CLASSIFICATION.md) and [SAP Modules](SAP_MODULES.md): explicit CSV evidence and visual preferences.

6. [SoD matrix source](SOD_MATRIX.md): verified activity slots, supported policy and durable source lifecycle.

[Configuration](../architecture/README.md) owns local storage/preferences;
[deployment security](../deployment/SERVER_NETWORK_ACCESS.md) owns hosted filesystem/access rules.
Use only [synthetic examples](../../examples/README.md) in repository fixtures.

Durable storage is described in [Storage and revisions](../architecture/DATABASE_DESIGN.md).
SQLite is the system of record, including settings and immutable review history. Do not delete it as cache cleanup.
See [backup/restore](../operations/BACKUP_AND_RECOVERY.md) and
[retention](../operations/BACKUP_AND_RECOVERY.md#retention-retention-tab) before deleting or replacing data.
