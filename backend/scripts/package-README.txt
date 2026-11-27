AuthLens {{VERSION}} - deployment package (build {{BUILD_ID}}, source commit {{SHA}}, package revision {{REVISION}})
=============================================================================================================

This folder is self-contained: it needs neither the development repository nor the build machine's Build or Installer folders.

  AuthLens-{{VERSION}}-Server-Setup.exe    Server (Windows service AuthLens), run elevated
  AuthLens-{{VERSION}}-Desktop-Setup.exe   Desktop (per user), run as the user
  Expand-AuthLensPackage.ps1          verifies and extracts this package; re-verifies an extracted folder
  SHA256SUMS.txt                      SHA-256 of every file in this package except itself
  installer-manifest.json             release identity and Setup program hashes
  package-manifest.json               package identity and revision (separate from the build identity)
  Tools\                              installation, verification and recovery helpers (Tools\installer-tools.json)

1. Copy the ZIP to C:\AuthLens on the target machine. If the build report gives the ZIP's SHA-256, compare it:
     (Get-FileHash C:\AuthLens\<package>.zip -Algorithm SHA256).Hash
2. Recommended: verify and extract with the package's own script (read it out of the ZIP first, see the deployment guide). It validates
   every archive entry, never overwrites C:\AuthLens\AuthLens-{{VERSION}}-{{BUILD_ID}}, extracts into a temporary .x-* folder, checks every
   SHA-256 and the release identity, and only then renames the folder into place:
     powershell -NoProfile -ExecutionPolicy Bypass -File <Expand-AuthLensPackage.ps1> -Package C:\AuthLens\<package>.zip -Destination C:\AuthLens [-ExpectedSha256 <hash>]
   Alternative: Windows "Extract All" into the new folder C:\AuthLens\AuthLens-{{VERSION}}-{{BUILD_ID}}, then verify it (step 3).
3. Verify the extracted folder at any time (a folder that exists is not proof of a complete extraction):
     powershell -NoProfile -ExecutionPolicy Bypass -File C:\AuthLens\AuthLens-{{VERSION}}-{{BUILD_ID}}\Expand-AuthLensPackage.ps1 -VerifyOnly -ExtractedDirectory C:\AuthLens\AuthLens-{{VERSION}}-{{BUILD_ID}}
4. Server: run AuthLens-{{VERSION}}-Server-Setup.exe from an elevated session (silent upgrade: /CONFIGFILE=<deploy.json> /OPERATION=Upgrade).
   Desktop: run AuthLens-{{VERSION}}-Desktop-Setup.exe as the user.
5. Independent recovery before an upgrade: Tools\recovery\New-AuthLensRecoveryBundle.ps1 (or Service Manager: Backup and recovery keys >
   Create a recovery bundle). A verified bundle proves the backup opens with the copied key; it is not a restore rehearsal
   (Tools\recovery\Test-AuthLensRestoreRehearsal.ps1, isolated, never touches the installation).

Integrity is not authenticity: SHA256SUMS.txt proves the files match each other's recorded digests; only a ZIP SHA-256 from a trusted build
report detects a replaced package, and no checksum proves who published it. The Setup programs are signed only when the release report says
so; check them with Get-AuthenticodeSignature. Full guide: docs/deployment/WINDOWS_DEPLOYMENT.md (Production package transfer).
