# Functional and deployment acceptance

Use [current status](STATUS.md) to distinguish implemented functionality, focused automated verification and remaining native acceptance.
The [2.0.0 work-package tracker](WORK_PACKAGES.md) lists the remediation packages (WP1 to WP34 and QA items), their test evidence and the Windows backlog. The [2.0.0 VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md) is the ordered operator procedure for a release candidate on a disposable Windows VM; results go into the [acceptance tracker](ACCEPTANCE_TRACKER.md).

## Functional acceptance

Use synthetic/reserved-domain data in isolated storage. Cover Dashboard/navigation, roles, users/comparison, Directory mappings, filters/packages,
Account Review/history, SoD matrices/decisions/evidence/periods, Data Health and Settings. Read-only checks precede reversible write checks.
Create and verify an encrypted backup before controlled writes; preserve immutable business evidence and keep scheduled refresh disabled until sources are reviewed.

## Mobile and keyboard acceptance

Check 360, 375, 390, 768, 800, 1024, 1280, 1440 and 1600 px in light/dark themes. Include drawers, dropdowns, focus restoration, Escape, touch targets,
forms, dialogs, filter state, table column controls and exports. Page content must not scroll horizontally; complex tables intentionally scroll inside
named keyboard-accessible regions. Keep essential data/actions and DOM order intact. Capture representative screenshots with synthetic data.

## Deployment and recovery acceptance

Verify package identity/checksums, Desktop loopback isolation or Server HTTPS/authentication/service identity, database integrity/foreign keys,
accounts/permissions, evidence hashes, restart persistence, encrypted restore into a separate clean environment and a tested rollback plan.
External access requires authenticated end-to-end testing from outside the local network. A proxy authentication gate does not prove backend reachability.

## Execution policy

Follow the [progressive validation policy](../development/README.md). Run direct tests first, then affected specifications and direct dependents.
Do not widen a failing run before diagnosing the error, logs, trace and original reproduction. Do not weaken assertions or increase timeouts to hide failures.
Full backend/browser regression is an explicit checkpoint. CI runs only on push to `main`; see [CI](../development/CI.md).
