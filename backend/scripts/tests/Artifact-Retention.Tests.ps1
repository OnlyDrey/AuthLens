# WP34 (INST-119 to INST-121): installation artifact inventory and reviewed retention. Synthetic installation roots in TestDrive only; no service,
# registry or real installation is read or changed.
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    function script:New-RetentionSite {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 10))
        foreach ($dir in 'config', 'data\backups', 'keys\host', 'tls', 'deployment\runs', 'backups\predeploy', 'releases\.staging', 'app\setup') { New-Item -ItemType Directory -Force (Join-Path $root $dir) | Out-Null }
        $file = Join-Path $root 'config\deploy.json'
        [ordered]@{ Root = $root; ServiceName = 'AuthLensRetentionSynthetic'; AccessMode = 'Local'; ListenAddress = '127.0.0.1'; Port = 18799 } | ConvertTo-Json | Set-Content $file -Encoding UTF8
        $config = Read-AuthLensSettings $file
        $releases = @{}
        $day = 0
        foreach ($name in 'AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64', 'AuthLens-2.0.0-20261110-100000-bbbbbbb-win-x64', 'AuthLens-2.0.0-20261120-100000-ccccccc-win-x64', 'AuthLens-2.0.0-20261125-100000-ddddddd-win-x64') {
            $path = Join-Path $config.ReleasesRoot $name; New-Item -ItemType Directory -Force (Join-Path $path 'server') | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $path 'server\AuthLens.Api.exe'), (New-Object byte[] 1000))
            @{ build_timestamp_utc = ('2026-11-{0:00}T10:00:00Z' -f (1 + 8 * $day++)) } | ConvertTo-Json | Set-Content (Join-Path $path 'build-manifest.json')
            $releases[$name.Substring(31, 7)] = $path
        }
        New-Item -ItemType Directory -Force (Join-Path $config.ReleasesRoot '.staging\AuthLens-interrupted') | Out-Null
        foreach ($stage in @(@{ n = 'AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64'; s = 'completed'; d = -40 }, @{ n = 'AuthLens-2.0.0-20261120-100000-ccccccc-win-x64'; s = 'refused_or_failed'; d = -20 }, @{ n = 'AuthLens-2.0.0-20261125-100000-ddddddd-win-x64'; s = 'completed'; d = -1 })) {
            $path = Join-Path (Join-Path $root 'app\setup') $stage.n; New-Item -ItemType Directory -Force (Join-Path $path 'payload') | Out-Null
            @{ status = $stage.s } | ConvertTo-Json | Set-Content (Join-Path $path 'operation-result.json')
            (Get-Item $path).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays($stage.d)
        }
        foreach ($run in 1..4) {
            $path = Join-Path $config.WorkRoot ("runs\2026010{0}-100000-deploy-0000000{0}" -f $run); New-Item -ItemType Directory -Force $path | Out-Null
            Set-Content (Join-Path $path 'deploy.log') 'synthetic log'; (Get-Item $path).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-200)
        }
        foreach ($backup in 1..3) {
            $path = Join-Path $config.BackupRoot ("authlens-2026010{0}T100000Z-0000000{0}.slbak" -f $backup); [IO.File]::WriteAllBytes($path, (New-Object byte[] 5000))
            (Get-Item $path).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-10 + $backup)
        }
        Set-Content (Join-Path $config.BackupRoot 'authlens-x.slbak.partial') 'interrupted'
        Set-Content (Join-Path $root 'data\authlens.sqlite3') 'synthetic data'
        Set-Content (Join-Path $root 'data\backups\manual.slbak') 'in-app backup'
        Set-Content (Join-Path $root 'keys\host\host.key') 'synthetic key'
        Write-ALJournal $config ([pscustomobject]@{ phase = 'complete'; run = '20260104-100000-deploy-00000004'; from_release = $releases['ccccccc']; to_release = $releases['ddddddd']; commit = ('d' * 40); version = '2.0.0'
            backup = [pscustomobject]@{ file = (Join-Path $config.BackupRoot 'authlens-20260101T100000Z-00000001.slbak') }; history = @(); updated = '' })
        $script:Active = $releases['ddddddd']
        [pscustomobject]@{ Root = $root; Config = $config; Releases = $releases }
    }
}

Describe 'Installation artifact inventory (read-only preview)' {
    BeforeEach {
        $site = New-RetentionSite
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $script:Active }
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerFreeBytes { 1TB }
    }
    It 'preserves active, rollback, evidence, recent and required items and changes nothing' {
        $before = @(Get-ChildItem $site.Root -Recurse -Force | ForEach-Object { if ($_.PSIsContainer) { $_.FullName } else { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } })
        $inventory = Get-ALArtifactInventory $site.Config 1 2 2 90
        $item = @{}; foreach ($entry in $inventory.items) { $item[$entry.id] = $entry }
        $item['release:AuthLens-2.0.0-20261125-100000-ddddddd-win-x64'].reasons | Should -Contain 'active_release'
        $item['release:AuthLens-2.0.0-20261120-100000-ccccccc-win-x64'].reasons | Should -Contain 'rollback_dependency_from_release'
        $item['release:AuthLens-2.0.0-20261110-100000-bbbbbbb-win-x64'].reasons | Should -Contain 'retention_keep_previous_release'
        $item['release:AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64'].state | Should -Be 'eligible'
        $item['setup_stage:AuthLens-2.0.0-20261125-100000-ddddddd-win-x64'].reasons | Should -Contain 'setup_stage_of_preserved_release'
        $item['setup_stage:AuthLens-2.0.0-20261120-100000-ccccccc-win-x64'].reasons | Should -Contain 'setup_failure_evidence'
        $item['setup_stage:AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64'].state | Should -Be 'eligible'
        $item['deployment_run:20260104-100000-deploy-00000004'].reasons | Should -Contain 'deployment_journal_run'
        $item['deployment_run:20260101-100000-deploy-00000001'].state | Should -Be 'eligible'
        $item['predeploy_backup:authlens-20260101T100000Z-00000001.slbak'].reasons | Should -Contain 'deployment_journal_backup'
        $item['predeploy_backup:authlens-20260103T100000Z-00000003.slbak'].reasons | Should -Contain 'retention_keep_newest_backups'
        $item['failed_backup:authlens-x.slbak.partial'].state | Should -Be 'eligible'
        $item['failed_publication:AuthLens-interrupted'].state | Should -Be 'eligible'
        @($inventory.protected.category) | Should -Contain 'application_data_and_review_evidence'
        @($inventory.protected.category) | Should -Contain 'recovery_keys'
        @($inventory.items | Where-Object { $_.path -like (Join-Path $site.Root 'data*') -or $_.path -like (Join-Path $site.Root 'keys*') }).Count | Should -Be 0
        $inventory.cleanup_allowed | Should -BeTrue
        $inventory.selection_sha256 | Should -Match '^[0-9a-f]{64}$'
        @(Get-ChildItem $site.Root -Recurse -Force | ForEach-Object { if ($_.PSIsContainer) { $_.FullName } else { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } }) | Should -Be $before
    }
    It 'keeps everything while any deployment, repair or configuration change awaits recovery (<Marker>)' -ForEach @(@{ Marker = 'repair-pending.json' }, @{ Marker = 'configuration-pending.json' }, @{ Marker = 'journal' }) {
        if ($Marker -eq 'journal') { $journal = Read-ALJournal $site.Config; $journal.phase = 'switched'; Write-ALJournal $site.Config $journal } else { Set-Content (Join-Path $site.Config.WorkRoot $Marker) '{}' }
        $inventory = Get-ALArtifactInventory $site.Config
        $inventory.cleanup_allowed | Should -BeFalse
        @($inventory.items | Where-Object state -eq 'eligible').Count | Should -Be 0
        { Invoke-ALArtifactPrune $site.Config @('release') $inventory.selection_sha256 } | Should -Throw '*awaits recovery*'
    }
    It 'refuses retention below the safety minimums and unknown categories' {
        { Get-ALArtifactInventory $site.Config 0 } | Should -Throw '*Retention minimums*'
        { Get-ALArtifactInventory $site.Config 1 2 20 90 @('application_data') } | Should -Throw '*Unknown artifact category*'
    }
}

Describe 'Reviewed artifact cleanup (PruneArtifacts)' {
    BeforeEach {
        $site = New-RetentionSite
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $script:Active }
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerFreeBytes { 1TB }
    }
    It 'previews without mutation, refuses a stale selection and deletes exactly the reviewed selection' {
        $before = @(Get-ChildItem $site.Root -Recurse -Force | ForEach-Object FullName)
        { Invoke-ALArtifactPrune $site.Config @() } | Should -Throw '*explicit -ArtifactCategory*'
        $preview = Invoke-ALArtifactPrune $site.Config @('release', 'setup_stage') -DryRun
        $preview.preview | Should -BeTrue
        @($preview.would_delete.id) | Should -Be @('release:AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64', 'setup_stage:AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64')
        @(Get-ChildItem $site.Root -Recurse -Force | ForEach-Object FullName) | Should -Be $before
        { Invoke-ALArtifactPrune $site.Config @('release', 'setup_stage') ('0' * 64) } | Should -Throw '*differs from the reviewed preview*'
        @(Get-ChildItem $site.Root -Recurse -Force | ForEach-Object FullName) | Should -Be $before
        $result = Invoke-ALArtifactPrune $site.Config @('release', 'setup_stage') $preview.selection_sha256
        $result.pruned | Should -BeTrue
        $result.reclaimed_bytes | Should -Be $preview.would_reclaim_bytes
        Test-Path $site.Releases['aaaaaaa'] | Should -BeFalse
        foreach ($kept in 'bbbbbbb', 'ccccccc', 'ddddddd') { Test-Path $site.Releases[$kept] | Should -BeTrue }
        Test-Path (Join-Path $site.Root 'app\setup\AuthLens-2.0.0-20261120-100000-ccccccc-win-x64') | Should -BeTrue
        Test-Path (Join-Path $site.Root 'data\backups\manual.slbak') | Should -BeTrue
        Test-Path (Join-Path $site.Root 'keys\host\host.key') | Should -BeTrue
        $audit = @(Get-Content (Join-Path $site.Config.WorkRoot 'artifact-retention.jsonl') | ConvertFrom-Json)
        $audit.Count | Should -Be 1
        @($audit[0].deleted.id) | Should -Contain 'release:AuthLens-2.0.0-20261101-100000-aaaaaaa-win-x64'
    }
}

Describe 'Retention policy and upgrade boundaries (D-006, INST-121)' {
    It 'classifies ArtifactInventory as read-only and PruneArtifacts as simulated with approval' {
        foreach ($dry in $false, $true) { foreach ($yes in $false, $true) { (Get-ALActionPolicy 'ArtifactInventory' -DryRun:$dry -Yes:$yes).mode | Should -Be 'read_only' } }
        (Get-ALActionPolicy 'PruneArtifacts' -DryRun).mode | Should -Be 'simulate'
        (Get-ALActionPolicy 'PruneArtifacts' -DryRun -Yes).mode | Should -Be 'simulate'
        { Get-ALActionPolicy 'PruneArtifacts' } | Should -Throw '*repeat with -Yes*'
        (Get-ALActionPolicy 'PruneArtifacts' -Yes).approval_required | Should -BeTrue
    }
    It 'never deletes artifacts from Setup, upgrade, deployment or recovery paths' {
        $callers = foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '..') -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '\\tests\\' }) {
            if ((Get-Content -LiteralPath $file.FullName -Raw) -match 'Invoke-ALArtifactPrune\s') { $file.Name }
        }
        @($callers | Sort-Object -Unique) | Should -Be @('Deploy-AuthLens.ps1')
        $installer = Get-Content (Join-Path $PSScriptRoot '../deploy/AuthLens.Installer.ps1') -Raw
        $installer | Should -Not -Match 'Invoke-ALArtifactPrune'
        $manager = Get-Content (Join-Path $PSScriptRoot '../Service-Manager.ps1') -Raw
        $manager | Should -Not -Match "'-Action', 'PruneArtifacts'"
    }
}
