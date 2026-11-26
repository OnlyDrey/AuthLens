# AuthLens – Claude Code

@AGENTS.md

## Project documentation

- Build and test (`backend/`): `docs/development/README.md`; deployment: `docs/deployment/README.md`
- Release status and open native checks: `docs/validation/STATUS.md`, `docs/validation/ACCEPTANCE_TRACKER.md`, `docs/deployment/WINDOWS_DEPLOYMENT.md#acceptance-checklist-windows-pending`
- SAP Lens 1 and its v1 documentation are archived outside the repository; the guides under `docs/` replace them

## Working rules

Follow the shared instructions in AGENTS.md; they are authoritative and are not repeated here.

- Before implementation, inspect `git status` and safely fast-forward `experiment/dotnet-backend` from `origin/experiment/dotnet-backend`.
- Preserve local changes and existing functionality.
- Follow Progressive test validation (AGENTS.md): Level 1 direct tests after each change, Level 2 affected files, broad profiles only at checkpoints. Do not run full regression without explicit authorization.
- Windows builds: root `build.ps1` only, output root `C:\AuthLens` (standard: `.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)`, optional `-ZipPackage`);
  artifacts in `C:\AuthLens\{Build,Installer,Acceptance}\<version>\<build-id>` and `C:\AuthLens\Packages`; installed Server root
  `C:\ProgramData\AuthLens`. Rules in AGENTS.md (Commands); no other output roots without approval.
- Commit and push completed phases to `origin/experiment/dotnet-backend`.
- Never force-push, modify `main`, dispatch workflows or publish releases without authorization. CI runs only on push to `main` (see AGENTS.md, GitHub Actions CI policy); pushes to `experiment/dotnet-backend` or `work` do not trigger it, so validate locally.
