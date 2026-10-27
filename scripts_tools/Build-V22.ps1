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
$outputRoot = Join-Path $projectRoot 'build/V22LivingWorld'
$exePath = Join-Path $outputRoot ($gameName + 'V2.2.exe')

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

function Get-CombatPayload {
    $modules = @('damage_model', 'enemy_brain', 'enemy_actor', 'encounter_director', 'combat_feedback')
    $modelIds = @('enemy_scout', 'enemy_harasser', 'enemy_suppressor', 'enemy_support', 'weapon_pulse', 'weapon_burst', 'weapon_lance', 'wreck_core', 'wreck_rotor', 'wreck_panel')
    $families = @('shot_light', 'shot_heavy', 'near_pass', 'impact_metal', 'impact_ground', 'impact_water', 'shield', 'component', 'destroyed', 'wreck', 'approach', 'warning', 'critical')
    $modelManifest = 'assets/models/v22_combat/manifest.json'
    $audioManifest = 'assets/audio/v22_combat/manifest.json'
    $models = [IO.File]::ReadAllText((Join-Path $projectRoot $modelManifest)) | ConvertFrom-Json
    $audio = [IO.File]::ReadAllText((Join-Path $projectRoot $audioManifest)) | ConvertFrom-Json
    if (@($models.models).Count -ne 10 -or @($audio.files).Count -ne 37 -or $audio.schema -ne 1) { throw 'Combat manifests require 10 models and 37 schema-1 audio files.' }
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $modules) { $null = $required.Add('scripts/v2/' + $name + '.gd') }
    $null = $required.Add('assets/shaders/v22_combat/visible_body_rim.gdshader')
    # Freeze all shared runtime sources too: existing flight/session/import
    # helpers are part of this release just as much as the five new modules.
    foreach ($directory in @('scripts/v2', 'assets/shaders')) {
        foreach ($item in (Get-ChildItem -LiteralPath (Join-Path $projectRoot $directory) -Recurse -File)) {
            if ($item.Extension -in @('.gd', '.gdshader', '.gdshaderinc')) {
                $null = $required.Add($item.FullName.Substring($projectRoot.Length + 1).Replace('\', '/'))
            }
        }
    }
    foreach ($relative in @('project.godot', 'export_presets.cfg', 'scripts/visuals.gd')) { $null = $required.Add($relative) }
    foreach ($relative in @($modelManifest, $audioManifest, 'assets/models/v22_combat/LICENSE.txt', 'assets/audio/v22_combat/CREDITS.txt', 'assets/source_models/v22_combat/LICENSE.txt', 'assets/source_audio/v22_combat/Kenney-License.txt', 'assets/source_audio/v22_combat/sources.json', 'scripts_tools/v22_combat_audio_build.py', 'scripts_tools/build_v22_combat_assets.py', 'assets/source_models/v22_combat/.gdignore', 'assets/source_audio/v22_combat/.gdignore')) { $null = $required.Add($relative) }
    $seenModels = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $models.models) {
        if ($item.id -notin $modelIds -or -not $seenModels.Add([string]$item.id) -or $item.scene -ne ('res://assets/models/v22_combat/' + $item.id + '.glb') -or $item.source -ne ('assets/source_models/v22_combat/' + $item.id + '.blend') -or $item.license -ne 'CC0-1.0') { throw "Invalid combat model record: $($item.id)" }
        $relative = ([string]$item.scene).Substring(6)
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash -ne $item.sha256) { throw "Combat GLB differs from its manifest: $relative" }
        $null = $required.Add($relative)
        $null = $required.Add([string]$item.source)
    }
    $seenAudio = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $audio.files) {
        if ($item.family -notin $families -or $item.file -ne ($item.id + '.wav') -or $item.id -notmatch '^[a-z_]+_[0-9]{2}$' -or -not $seenAudio.Add([string]$item.id) -or $item.channels -ne 1 -or $item.sample_rate -ne 48000 -or $item.loop -ne $false -or $item.seconds -le 0) { throw "Invalid combat audio record: $($item.id)" }
        $relative = 'assets/audio/v22_combat/' + $item.file
        $path = Join-Path $projectRoot $relative
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.sha256 -or (Get-Item -LiteralPath $path).Length -ne $item.bytes) { throw "Combat WAV differs from its manifest: $relative" }
        $null = $required.Add($relative)
        $importPath = $path + '.import'
        if (-not (Test-Path -LiteralPath $importPath -PathType Leaf) -or [IO.File]::ReadAllText($importPath) -notmatch '(?m)^compress/mode=0\s*$') { throw "Short combat audio must explicitly retain PCM import: $relative" }
        $null = $required.Add($relative + '.import')
    }
    foreach ($family in $families) {
        $expected = if ($family -in @('warning', 'critical')) { 2 } else { 3 }
        if (@($audio.files | Where-Object { $_.family -eq $family }).Count -ne $expected) { throw "Missing combat variations: $family" }
    }
    # Python writes native Windows newlines; JSON preserves the logical LF text.
    # Normalize CRLF only; wording, whitespace and the final newline still match.
    if ([IO.File]::ReadAllText((Join-Path $projectRoot 'assets/audio/v22_combat/CREDITS.txt')).Replace("`r`n", "`n") -cne ([string]$audio.credits_text).Replace("`r`n", "`n")) { throw 'Combat credits differ from the runtime manifest.' }
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot 'scripts_tools/v22_combat_audio_build.py') -Algorithm SHA256).Hash -ne $audio.generator_sha256) { throw 'Combat audio generator differs from the recorded editable source.' }
    $sources = [IO.File]::ReadAllText((Join-Path $projectRoot 'assets/source_audio/v22_combat/sources.json')) | ConvertFrom-Json
    $null = $required.Add([string]$sources.original_archive)
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $sources.original_archive) -Algorithm SHA256).Hash -ne $sources.archive_sha256) { throw 'Combat source archive hash differs.' }
    foreach ($property in $sources.selected_files.PSObject.Properties) {
        $record = $property.Value
        if ([string]$record.file -notmatch '^originals/[a-zA-Z0-9_]+\.ogg$') { throw 'Unexpected combat source path.' }
        $relative = 'assets/source_audio/v22_combat/' + $record.file
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash -ne $record.sha256) { throw "Combat original source hash differs: $relative" }
        $null = $required.Add($relative)
    }
    $snapshots = foreach ($relative in ($required | Sort-Object)) {
        if (-not (Test-AllowedPath $relative)) { throw "Combat editable source excluded from source package: $relative" }
        [ordered]@{ file = $relative; sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash }
    }
    return [ordered]@{ schema = 1; module_count = $modules.Count; model_count = $seenModels.Count; audio_count = $seenAudio.Count; family_count = $families.Count; model_manifest_sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot $modelManifest) -Algorithm SHA256).Hash; audio_manifest_sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot $audioManifest) -Algorithm SHA256).Hash; source_files = @($snapshots) }
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
    if ($projectText -notmatch 'config/custom_user_dir_name="LowAltitudeSquadV22LivingWorld"' -or $projectText -notmatch 'run/main_scene="res://scenes/v2_main.tscn"') { throw 'Refusing to build a project that is not the isolated V2.2 application.' }
    $GodotPath = Resolve-Tool $GodotPath (Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe') 'godot.exe'
    $PythonPath = Resolve-Tool $PythonPath (Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe') 'python.exe'
    Invoke-BoundedProcess 'engine-version' $GodotPath @('--version') 30 '^4\.7\.2(?:\.|\s)'
    Invoke-BoundedProcess 'content-source-freshness' $PythonPath @('scripts_tools/validate_v2_content.py', '--self-test') $TimeoutSeconds
    $presetText = [IO.File]::ReadAllText((Join-Path $projectRoot 'export_presets.cfg'))
    $preset = [regex]::Match($presetText, '(?ms)^\[preset\.(\d+)\]\s*(.*?)(?=^\[|\z)')
    if (-not $preset.Success -or $preset.Groups[2].Value -notmatch 'name="Windows Desktop"') { throw 'The first export preset must be Windows Desktop.' }
    $include = [regex]::Match($preset.Groups[2].Value, '(?m)^include_filter="([^"]*)"').Groups[1].Value.Split(',')
    $exclude = [regex]::Match($preset.Groups[2].Value, '(?m)^exclude_filter="([^"]*)"').Groups[1].Value.Split(',')
    $runtimeFiles = @('data/v2/world_content.json', 'phone/index.html', 'phone/app.js', 'phone/style.css', 'assets/v2/audio/audio_manifest.json', 'assets/audio/v22/manifest.json', 'assets/audio/v22/CREDITS.txt', 'assets/models/v22_combat/manifest.json', 'assets/models/v22_combat/LICENSE.txt', 'assets/audio/v22_combat/manifest.json', 'assets/audio/v22_combat/CREDITS.txt')
    foreach ($relative in $runtimeFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) { throw "Runtime file missing: $relative" }
        if (@($include | Where-Object { $_ -and $relative -like $_.Trim() }).Count -eq 0 -or @($exclude | Where-Object { $_ -and $relative -like $_.Trim() }).Count -gt 0) { throw "Non-resource runtime file is not included by the export preset: $relative" }
    }
    if ($presetText -notmatch 'binary_format/embed_pck=true') { throw 'The portable single-executable package requires an embedded PCK.' }
    $combatPayload = Get-CombatPayload
    if ($preset.Groups[2].Value -notmatch '(?m)^export_filter="all_resources"') { throw 'The combat release requires the all-resources export preset.' }
    foreach ($record in $combatPayload.source_files) {
        $relative = [string]$record.file
        if ($relative -notmatch '^(scripts/v2/|assets/models/v22_combat/|assets/audio/v22_combat/)') { continue }
        if (@($exclude | Where-Object { $_ -and $relative -like $_.Trim() }).Count -gt 0) { throw "Combat runtime resource excluded by export preset: $relative" }
    }
    $toolchain = [IO.File]::ReadAllText((Join-Path $projectRoot 'toolchain.lock.json')) | ConvertFrom-Json
    if ($toolchain.game_version -ne '2.2.0') { throw 'The release toolchain must identify game version 2.2.0.' }
    Invoke-BoundedProcess 'import' $GodotPath @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit') $TimeoutSeconds
    if (-not $SkipTests) {
        $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        Invoke-BoundedProcess 'tests' $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Test-V2.ps1'), '-GodotPath', $GodotPath, '-PythonPath', $PythonPath, '-TimeoutSeconds', [string]$TimeoutSeconds, '-SkipContentValidation') ([math]::Min(86400, $TimeoutSeconds * 24))
    }
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    Invoke-BoundedProcess 'export-windows' $GodotPath @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', $exePath) $TimeoutSeconds
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf) -or (Get-Item -LiteralPath $exePath).Length -lt 1048576) { throw 'Export did not produce a plausible executable.' }
    $portableFiles = [Collections.Generic.List[object]]::new()
    $portableFiles.Add([pscustomobject]@{ path = $exePath; relative = [IO.Path]::GetFileName($exePath) })
    foreach ($relative in @('README_V22.md', 'docs/v2/V22_PLAY_GUIDE.md', 'docs/v2/V22_VERIFICATION.md', 'docs/v2/V22_AUDIO.md', 'docs/v2/V22_ENVIRONMENT.md', 'docs/v2/V22_UI.md', 'docs/v2/V22_NIGHT.md', 'docs/v2/V22_COMBAT_DESIGN.md', 'docs/v2/V22_COMBAT_ART.md', 'docs/v2/V22_COMBAT_AUDIO.md', 'docs/v2/V22_ENCOUNTERS.md', 'assets/audio/v22_combat/CREDITS.txt', 'assets/models/v22_combat/LICENSE.txt', 'assets/audio/v22/CREDITS.txt', 'README_V2.md', 'THIRD_PARTY_NOTICES.md', 'docs/V2_ACCEPTANCE.md', 'docs/V2_MIGRATION.md', 'docs/V2_TRACEABILITY.md', 'docs/V2_PLAYTEST.md', 'docs/V2_ART_UPGRADE.md', 'docs/V2_AUDIO_UPGRADE.md', 'docs/V2_STREET_ASSETS.md', 'docs/V2_UI_UPGRADE.md', 'docs/V2_VISIBILITY_UPGRADE.md')) {
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
    # Only the explicit V2.2 review bundle, never a player's saves or general logs.
    $evidenceRoot = Join-Path $projectRoot 'docs/v2/evidence/v22'
    if (Test-Path -LiteralPath $evidenceRoot -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $evidenceRoot -File) {
            if ($item.Extension -notin @('.json','.png','.md')) { continue }
            $relative = 'verification/' + $item.Name
            $destination = Join-Path $outputRoot $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
            $portableFiles.Add([pscustomobject]@{ path = $destination; relative = $relative })
        }
    }
    $sourceFiles = [Collections.Generic.List[object]]::new()
    foreach ($directory in @('assets', 'asset_sources', 'data', 'docs', 'scenes', 'scripts', 'scripts_tools', 'tests', 'tests_v2', 'phone', 'addons')) {
        $path = Join-Path $projectRoot $directory
        if (Test-Path -LiteralPath $path -PathType Container) { foreach ($item in Get-SourceFiles $path) { $sourceFiles.Add($item) } }
    }
    foreach ($name in @('project.godot', 'export_presets.cfg', 'toolchain.lock.json', 'README_V22.md', 'README_V2.md', 'README.md', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md', '.gitignore', 'LICENSE', 'LICENSE.md')) {
        $path = Join-Path $projectRoot $name
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { $sourceFiles.Add([pscustomobject]@{ path = $path; relative = $name }) }
    }
    $sourceNames = @($sourceFiles.ToArray() | ForEach-Object { $_.relative })
    foreach ($record in $combatPayload.source_files) {
        if ($record.file -notin $sourceNames) { throw "Required combat source is missing from the source archive: $($record.file)" }
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $record.file) -Algorithm SHA256).Hash -ne $record.sha256) { throw "Combat input changed during build: $($record.file)" }
    }
    $portableZip = Join-Path $projectRoot ('build/' + $gameName + 'V2.2-Windows-' + $runId + '.zip')
    $sourceZip = Join-Path $projectRoot ('build/' + $gameName + 'V2.2-Source-' + $runId + '.zip')
    Write-Archive $portableZip $portableFiles.ToArray() 'LowAltitudeSquadV22'
    Write-Archive $sourceZip $sourceFiles.ToArray() 'LowAltitudeSquadV22-Source'
    $manifest = [ordered]@{ build_id = $runId; utc = [DateTime]::UtcNow.ToString('o'); project_root = $projectRoot; game_version = '2.2.0'; combat_payload = $combatPayload; tests_skipped = [bool]$SkipTests; executable = $exePath; executable_sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash; portable_zip = $portableZip; portable_sha256 = (Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash; source_zip = $sourceZip; source_sha256 = (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash; source_entries = @($sourceFiles.ToArray() | ForEach-Object { $_.relative }); runtime_export_verified = $false; note = 'Packaging is not exported-game runtime, GPU, manual play, Android, or 30-minute stability evidence.' }
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
