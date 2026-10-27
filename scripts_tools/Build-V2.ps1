[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$PythonPath = '',
    [ValidateRange(30, 3600)][int]$TimeoutSeconds = 900,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$utf8 = New-Object Text.UTF8Encoding($false)
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$logRoot = Join-Path $projectRoot ('artifacts/v2/build-runs/' + $runId)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$gameName = -join ([char[]]@(0x4F4E, 0x7A7A, 0x5C0F, 0x961F))
$outputRoot = Join-Path $projectRoot 'build/V2Independent'
$exePath = Join-Path $outputRoot ($gameName + 'V2.exe')

function Resolve-Tool([string]$Provided, [string]$Fallback, [string]$Command) {
    if ($Provided) { $candidate = $Provided }
    elseif (Test-Path -LiteralPath $Fallback -PathType Leaf) { $candidate = $Fallback }
    else { $candidate = (Get-Command $Command -ErrorAction Stop).Source }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing tool: $resolved" }
    return $resolved
}

function Invoke-BoundedProcess([string]$Name, [string]$File, [string[]]$Arguments, [int]$Limit, [string]$SuccessPattern = '') {
    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Contains('"')) { throw 'Double quotes are not supported inside an argument.' }
        '"' + ($argument -replace '(\\+)$', '$1$1') + '"'
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $quoted -join ' '
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "Cannot start $Name" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Limit * 1000)
        if ($timedOut) { $process.Kill() }
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
    } finally { $process.Dispose() }
    $log = Join-Path $logRoot ($Name + '.log')
    [IO.File]::WriteAllText($log, $output, $utf8)
    if ($timedOut -or $code -ne 0 -or $output -match 'SCRIPT ERROR:|(?m)^\s*ERROR:|Traceback \(most recent call last\):' -or ($SuccessPattern -and $output -notmatch $SuccessPattern)) {
        throw "$Name failed or timed out. Exit=$code. Log=$log"
    }
    Write-Host "PASS $Name : $log"
}

function Test-AllowedPath([string]$Relative) {
    $relativePath = $Relative.Replace('\', '/')
    $parts = $relativePath.Split('/')
    $denied = @('.git', '.godot', '.tools', 'private', 'node_modules', 'build', 'delivery', 'deliveries', 'artifacts', 'evidence', '__pycache__', 'profiles', 'profile', 'qa_v2', 'qa', 'user_data', 'userdata', 'saves', 'savegames', 'migration_backups', '.venv', 'venv')
    foreach ($part in $parts) { if ($denied -contains $part.ToLowerInvariant()) { return $false } }
    $leaf = $parts[-1]
    # These exact source archives are required by the offline asset builders.
    $sourceArchives = @('asset_sources/v2/audio/downloads/kenney_ui-audio.zip', 'asset_sources/v2/audio/downloads/kenney_impact-sounds.zip', 'asset_sources/v2/streets/third_party/kenney_car_kit.zip', 'asset_sources/v2/streets/third_party/kenney_commercial.zip', 'asset_sources/v2/streets/third_party/kenney_roads.zip')
    if ($sourceArchives -contains $relativePath) { return $true }
    if ($leaf -match '(?i)^(pilot\.json(?:\..*)?|profile_g\d+\.json|gut_.*\.json|\.env(?:\..*)?|test_result\.json)$') { return $false }
    if ($leaf -match '(?i)\.(log|tmp|bak|zip|pck|exe|pyc|lnk|blend[0-9]+)$') { return $false }
    return $true
}

function Get-SourceFiles([string]$Directory) {
    $rootItem = Get-Item -LiteralPath $Directory -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $relative = $item.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        if (-not (Test-AllowedPath $relative)) { continue }
        if ($item.PSIsContainer) { Get-SourceFiles $item.FullName }
        else { [pscustomobject]@{ path = $item.FullName; relative = $relative } }
    }
}

function Write-Archive([string]$Destination, [object[]]$Files, [string]$Prefix) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
    try {
        foreach ($file in $Files) {
            $entry = $Prefix + '/' + $file.relative.Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.path, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose(); $stream.Dispose() }
}

try {
    $projectText = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
    if ($projectText -notmatch 'config/custom_user_dir_name="LowAltitudeSquadV2Independent20261014"' -or $projectText -notmatch 'run/main_scene="res://scenes/v2_main.tscn"') { throw 'Refusing to build a project that is not the isolated V2 application.' }
    $GodotPath = Resolve-Tool $GodotPath (Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe') 'godot.exe'
    $PythonPath = Resolve-Tool $PythonPath (Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe') 'python.exe'
    Invoke-BoundedProcess 'engine-version' $GodotPath @('--version') 30 '^4\.7\.2(?:\.|\s)'
    Invoke-BoundedProcess 'content-source-freshness' $PythonPath @('scripts_tools/validate_v2_content.py', '--self-test') $TimeoutSeconds
    $presetText = [IO.File]::ReadAllText((Join-Path $projectRoot 'export_presets.cfg'))
    $preset = [regex]::Match($presetText, '(?ms)^\[preset\.(\d+)\]\s*(.*?)(?=^\[|\z)')
    if (-not $preset.Success -or $preset.Groups[2].Value -notmatch 'name="Windows Desktop"') { throw 'The first export preset must be Windows Desktop.' }
    $include = [regex]::Match($preset.Groups[2].Value, '(?m)^include_filter="([^"]*)"').Groups[1].Value.Split(',')
    $exclude = [regex]::Match($preset.Groups[2].Value, '(?m)^exclude_filter="([^"]*)"').Groups[1].Value.Split(',')
    $runtimeFiles = @('data/v2/world_content.json', 'phone/index.html', 'phone/app.js', 'phone/style.css', 'assets/v2/audio/audio_manifest.json')
    foreach ($relative in $runtimeFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) { throw "Runtime file missing: $relative" }
        if (@($include | Where-Object { $_ -and $relative -like $_.Trim() }).Count -eq 0 -or @($exclude | Where-Object { $_ -and $relative -like $_.Trim() }).Count -gt 0) { throw "Non-resource runtime file is not included by the export preset: $relative" }
    }
    if ($presetText -notmatch 'binary_format/embed_pck=true') { throw 'The portable single-executable package requires an embedded PCK.' }
    Invoke-BoundedProcess 'import' $GodotPath @('--headless', '--path', $projectRoot, '--editor', '--import') $TimeoutSeconds
    if (-not $SkipTests) {
        $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        Invoke-BoundedProcess 'tests' $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Test-V2.ps1'), '-GodotPath', $GodotPath, '-PythonPath', $PythonPath, '-TimeoutSeconds', [string]$TimeoutSeconds, '-SkipContentValidation') ([math]::Min(86400, $TimeoutSeconds * 24))
    }
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    Invoke-BoundedProcess 'export-windows' $GodotPath @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', $exePath) $TimeoutSeconds
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf) -or (Get-Item -LiteralPath $exePath).Length -lt 1048576) { throw 'Export did not produce a plausible executable.' }
    $portableFiles = [Collections.Generic.List[object]]::new()
    $portableFiles.Add([pscustomobject]@{ path = $exePath; relative = [IO.Path]::GetFileName($exePath) })
    foreach ($relative in @('README_V2.md', 'THIRD_PARTY_NOTICES.md', 'docs/V2_ACCEPTANCE.md', 'docs/V2_MIGRATION.md', 'docs/V2_TRACEABILITY.md', 'docs/V2_PLAYTEST.md', 'docs/V2_ART_UPGRADE.md', 'docs/V2_AUDIO_UPGRADE.md', 'docs/V2_STREET_ASSETS.md', 'docs/V2_UI_UPGRADE.md', 'docs/V2_VISIBILITY_UPGRADE.md')) {
        $source = Join-Path $projectRoot $relative
        $destination = Join-Path $outputRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $portableFiles.Add([pscustomobject]@{ path = $destination; relative = $relative })
    }
    foreach ($license in Get-SourceFiles (Join-Path $projectRoot 'assets/licenses')) {
        $destination = Join-Path $outputRoot $license.relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $license.path -Destination $destination -Force
        $portableFiles.Add([pscustomobject]@{ path = $destination; relative = $license.relative })
    }
    foreach ($relative in @('assets/fonts/OFL.txt', 'phone/vendor/qr_code/LICENSE.md', 'addons/gut/LICENSE.md', 'addons/gut/LICENSE')) {
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $destination = Join-Path $outputRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $portableFiles.Add([pscustomobject]@{ path = $destination; relative = $relative })
    }
    $sourceFiles = [Collections.Generic.List[object]]::new()
    foreach ($directory in @('assets', 'asset_sources', 'data', 'docs', 'scenes', 'scripts', 'scripts_tools', 'tests', 'tests_v2', 'phone', 'addons')) {
        $path = Join-Path $projectRoot $directory
        if (Test-Path -LiteralPath $path -PathType Container) { foreach ($item in Get-SourceFiles $path) { $sourceFiles.Add($item) } }
    }
    foreach ($name in @('project.godot', 'export_presets.cfg', 'toolchain.lock.json', 'README_V2.md', 'README.md', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md', '.gitignore', 'LICENSE', 'LICENSE.md')) {
        $path = Join-Path $projectRoot $name
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { $sourceFiles.Add([pscustomobject]@{ path = $path; relative = $name }) }
    }
    $portableZip = Join-Path $projectRoot ('build/' + $gameName + 'V2-Windows-' + $runId + '.zip')
    $sourceZip = Join-Path $projectRoot ('build/' + $gameName + 'V2-Source-' + $runId + '.zip')
    Write-Archive $portableZip $portableFiles.ToArray() 'LowAltitudeSquadV2'
    Write-Archive $sourceZip $sourceFiles.ToArray() 'LowAltitudeSquadV2-Source'
    $manifest = [ordered]@{ build_id = $runId; utc = [DateTime]::UtcNow.ToString('o'); project_root = $projectRoot; tests_skipped = [bool]$SkipTests; executable = $exePath; executable_sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash; portable_zip = $portableZip; portable_sha256 = (Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash; source_zip = $sourceZip; source_sha256 = (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash; source_entries = @($sourceFiles.ToArray() | ForEach-Object { $_.relative }); runtime_export_verified = $false; note = 'Packaging is not exported-game runtime, GPU, manual play, Android, or 30-minute stability evidence.' }
    [IO.File]::WriteAllText((Join-Path $logRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8), $utf8)
    Write-Host "Executable: $exePath"
    Write-Host "Portable ZIP: $portableZip"
    Write-Host "Editable source ZIP: $sourceZip"
    Write-Host "Build evidence: $logRoot/manifest.json"
    if ($SkipTests) { Write-Warning 'Tests were explicitly skipped; this build is not test-validated.' }
    exit 0
} catch {
    [IO.File]::WriteAllText((Join-Path $logRoot 'build-error.txt'), $_.Exception.ToString(), $utf8)
    Write-Error $_
    exit 1
}
