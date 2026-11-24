BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    $script:Scripts = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
    function script:New-SetupConfig([string]$Root) {
        foreach ($dir in (Join-Path $Root 'config'), (Join-Path $Root 'deployment')) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $file = Join-Path $Root 'config\deploy.json'
        # The keys Server Setup publishes (CreateServerDraft plus imported TLS paths); deliberately no RepositoryPath.
        [ordered]@{ Root = $Root; AccessMode = 'Local'; ListenAddress = '127.0.0.1'; Port = 18799; AllowedHosts = @('localhost', '127.0.0.1'); ProxyHosts = @(); TrustedProxies = @()
            CertificatePath = (Join-Path $Root 'tls\setup-1\server.pfx'); CertificatePasswordFile = (Join-Path $Root 'tls\setup-1\cert-password') } | ConvertTo-Json | Set-Content $file -Encoding UTF8
        $file
    }
}
# D-001 and the packaged-runtime audit: Setup-published configurations, the installed tool layout outside the repository, and repository
# deployments. Read-only: the child processes only run Status (service and listener queries), never a change.
Describe 'Installed deployment configuration compatibility (D-001)' {
    It 'accepts a Setup-published configuration without a repository and marks it packaged' {
        $config = Read-AuthLensSettings (New-SetupConfig (Join-Path $TestDrive 'setup'))
        $config.ExecutionContext | Should -Be 'packaged'
        $config.RepositoryPath | Should -Be ''
        $config.DataDirectory | Should -Be ([IO.Path]::Combine((Join-Path $TestDrive 'setup'), 'data'))
        (Read-AuthLensSettings (New-SetupConfig (Join-Path $TestDrive 'setup2')) -Packaged).RepositoryPath | Should -Be ''
    }
    It 'keeps repository deployments and their validation' {
        $file = Join-Path $TestDrive 'repo.json'
        @{ RepositoryPath = 'C:\src\authlens'; ListenAddress = '192.0.2.10'; Port = 18795 } | ConvertTo-Json | Set-Content $file
        $config = Read-AuthLensSettings $file
        $config.ExecutionContext | Should -Be 'repository'
        @{ RepositoryPath = 'relative\repo'; ListenAddress = '10.0.0.1'; Port = 1 } | ConvertTo-Json | Set-Content $file
        { Read-AuthLensSettings $file } | Should -Throw '*absolute path*'
    }
    It 'refuses only the actions that build from source on an installed Server' {
        $config = Read-AuthLensSettings (New-SetupConfig (Join-Path $TestDrive 'setup3'))
        { Resolve-ALCommit $config 'experiment/dotnet-backend' '' } | Should -Throw '*no RepositoryPath (an installed Server)*'
        { New-ALWorktree $config ('a' * 40) } | Should -Throw '*no RepositoryPath*'
    }
}

Describe 'Installed tool layout outside the repository' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    BeforeAll {
        # Recreate <Root>\app\setup\<package> exactly as build-installers.ps1 and the Server installer stage it, from the inventory in build-installers.ps1.
        $inventory = [regex]::Match((Get-Content (Join-Path $script:Scripts 'build-installers.ps1') -Raw), "foreach \(\`$relative in @\(([^)]*)\)").Groups[1].Value
        $script:Inventory = @([regex]::Matches($inventory, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $script:Install = Join-Path $TestDrive 'Root'
        $package = 'AuthLens-2.0.0-synthetic-win-x64'
        $script:Stage = Join-Path $script:Install "app\setup\$package"
        $script:Tools = Join-Path $script:Stage 'tools'
        $entries = foreach ($relative in $script:Inventory) {
            $target = Join-Path $script:Tools $relative
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:Scripts $relative) -Destination $target
            [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
        [IO.File]::WriteAllText((Join-Path $script:Tools 'installer-tools.json'), (@{ schema = 1; files = @($entries) } | ConvertTo-Json -Depth 5))
        $script:Payload = Join-Path $script:Stage "payload\$package"
        New-Item -ItemType Directory -Force $script:Payload | Out-Null
        Copy-Item (Join-Path $script:Scripts 'Service-Manager.ps1') $script:Payload
        $script:ConfigFile = New-SetupConfig $script:Install
    }
    It 'runs the installed Deploy-AuthLens Status on a Setup configuration from another working directory' {
        $inventory = $script:Inventory
        $inventory | Should -Contain 'deploy/Deploy-AuthLens.ps1'
        Push-Location ([IO.Path]::GetTempPath())
        try { $output = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $script:Tools 'deploy\Deploy-AuthLens.ps1') -Action Status -ConfigFile $script:ConfigFile 2>&1 | ForEach-Object { "$_" }) }
        finally { Pop-Location }
        $line = @($output | Where-Object { $_ -like 'AUTHLENS-RESULT: *' })[-1]
        $result = $line.Substring(17) | ConvertFrom-Json
        $result.exit | Should -Be 0
        $result.result.execution_context | Should -Be 'packaged'
        $result.result.access_mode | Should -Be 'Local'
        $result.result.configuration_change_pending | Should -BeFalse
        ($output -join "`n") | Should -Not -Match 'RepositoryPath'
    }
    It 'refuses a repository build from the installed tools with a clear message instead of a configuration error' {
        $output = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $script:Tools 'deploy\Deploy-AuthLens.ps1') -Action Deploy -ConfigFile $script:ConfigFile -DryRun 2>&1 | ForEach-Object { "$_" })
        $result = (@($output | Where-Object { $_ -like 'AUTHLENS-RESULT: *' })[-1]).Substring(17) | ConvertFrom-Json
        $result.exit | Should -Not -Be 0
        $result.result.error | Should -BeLike '*builds from a source repository*'
    }
    It 'has every installed tool dependency inside the staged tools, not in the repository' {
        foreach ($dependency in 'deploy\AuthLens.Paths.ps1', 'deploy\AuthLens.Acl.ps1', 'deploy\AuthLens.Installer.ps1', 'verify-release.ps1') { Test-Path (Join-Path $script:Tools $dependency) | Should -BeTrue }
        $module = Get-Content (Join-Path $script:Tools 'deploy\AuthLens.Deploy.psm1') -Raw
        $module | Should -Not -Match '\.\.\\\.\.\\|frontend\\|backend\\src'
    }
    It 'lets Service Manager find and verify the installed tools and refuses a changed tool' {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Payload 'Service-Manager.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in 'Get-AuthLensInstalledDeployTool', 'Get-AuthLensInstalledConfiguration', 'Get-AuthLensNetworkArguments') {
            . ([scriptblock]::Create($ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true).Extent.Text))
        }
        Get-AuthLensInstalledDeployTool $script:Payload | Should -Be (Join-Path $script:Tools 'deploy\Deploy-AuthLens.ps1')
        $installed = Get-AuthLensInstalledConfiguration $script:ConfigFile
        $installed.data_directory | Should -Be (Join-Path $script:Install 'data')
        $installed.service_name | Should -Be 'AuthLens'
        @(Get-AuthLensNetworkArguments $script:ConfigFile @{ Port = 18800; AllowedHosts = 'a.example.org, b.example.org'; TrustedProxies = '-' } $true) |
            Should -Be @('-Action', 'ChangeNetwork', '-ConfigFile', $script:ConfigFile, '-Port', '18800', '-AllowedHosts', 'a.example.org,b.example.org', '-TrustedProxies', '', '-DryRun')
        $module = Join-Path $script:Tools 'deploy\AuthLens.Deploy.psm1'
        $original = [IO.File]::ReadAllBytes($module)
        try {
            [IO.File]::AppendAllText($module, "`n# tampered")
            { Get-AuthLensInstalledDeployTool $script:Payload } | Should -Throw '*integrity verification failed*'
        } finally { [IO.File]::WriteAllBytes($module, $original) }
    }
}
