[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildManifest,
    [Parameter(Mandatory = $true)][string]$ReleaseReport,
    [string]$EvidenceDirectory = 'docs/v2/evidence/v22'
)

# Run only after code is frozen, Build-V22.ps1 has exported it, and
# Verify-V2Release.ps1 has checked the extracted portable executable.
# This helper never launches an engine, re-exports, or removes old deliveries.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$utf8 = New-Object Text.UTF8Encoding($false)
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$gameName = -join ([char[]]@(0x4F4E, 0x7A7A, 0x5C0F, 0x961F))

function Resolve-OwnedPath([string]$Path, [switch]$AllowMissing) {
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $projectRoot $Path }
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package path must be inside this V2.2 workspace: $resolved"
    }
    # A lexical root check alone does not prevent a junction escaping the root.
    $cursor = $resolved
    while ($cursor.Length -ge $projectRoot.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in package path: $cursor" }
        }
        if ($cursor -eq $projectRoot) { break }
        $cursor = Split-Path -Parent $cursor
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $resolved)) { throw "Missing package input: $resolved" }
    return $resolved
}

function Read-Record([string]$Path) {
    $resolved = Resolve-OwnedPath $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Expected a JSON file: $resolved" }
    return ([IO.File]::ReadAllText($resolved) | ConvertFrom-Json)
}

function Assert-Hash([string]$Path, [string]$Expected) {
    if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { throw "Missing or invalid SHA256 for: $Path" }
    $resolved = Resolve-OwnedPath $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Expected a file: $resolved" }
    $actual = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "SHA256 does not match verified evidence: $resolved" }
    return $actual
}

# Keep these two functions aligned with Build-V22.ps1. Evidence is copied only
# by the explicit portable evidence path below, never through source traversal.
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

function Copy-PortableFile([string]$Source, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or ($Relative -split '[/\\]') -contains '..') { throw "Invalid package entry: $Relative" }
    $relativeEntry = $Relative.Replace('\', '/')
    if (-not $portableNames.Add($relativeEntry)) { throw "Duplicate portable entry: $relativeEntry" }
    $sourcePath = Resolve-OwnedPath $Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing portable file: $sourcePath" }
    $destination = Resolve-OwnedPath (Join-Path $outputRoot $relativeEntry) -AllowMissing
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destination
    $portableFiles.Add([pscustomobject]@{ path = $destination; relative = $relativeEntry })
}

function Write-Archive([string]$Destination, [object[]]$Files, [string]$Prefix) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
        $entries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in ($Files | Sort-Object relative)) {
            $entry = $Prefix + '/' + $file.relative.Replace('\', '/')
            if (-not $entries.Add($entry)) { throw "Duplicate archive entry: $entry" }
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.path, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $stream.Dispose()
    }
}

$projectText = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
if ($projectText -notmatch 'config/custom_user_dir_name="LowAltitudeSquadV22LivingWorld"' -or $projectText -notmatch 'run/main_scene="res://scenes/v2_main.tscn"') {
    throw 'Refusing to package a project that is not the isolated V2.2 application.'
}
$buildPath = Resolve-OwnedPath $BuildManifest
$releasePath = Resolve-OwnedPath $ReleaseReport
$evidenceRoot = Resolve-OwnedPath $EvidenceDirectory
if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { throw 'EvidenceDirectory must be a directory.' }
$build = Read-Record $buildPath
$release = Read-Record $releasePath
if ([IO.Path]::GetFullPath([string]$build.project_root) -ne $projectRoot) { throw 'Build manifest belongs to another workspace.' }
if ($release.ok -ne $true -or @($release.failures).Count -gt 0 -or [int]$release.checks -le 0) { throw 'The extracted release did not pass runtime verification.' }
if ([string]$release.engine -notmatch '^4\.7\.2(?:[.\-]|\s|$)') { throw 'The verified executable is not Godot 4.7.2.' }
# An older successful release report must not be reused with new combat media.
if ([string]$build.game_version -ne '2.2.0' -or [string]$release.game_version -ne '2.2.0') { throw 'Build and extracted release must both identify game version 2.2.0.' }
foreach ($field in @('schema', 'module_count', 'model_count', 'audio_count', 'family_count')) {
    $expected = @{ schema = 1; module_count = 5; model_count = 10; audio_count = 37; family_count = 13 }[$field]
    if ([int]$build.combat_payload.$field -ne $expected -or [int]$release.combat_payload.$field -ne $expected) { throw "Combat build/runtime contract is missing or incomplete: $field" }
}
foreach ($entry in @(@('model_manifest_sha256', 'assets/models/v22_combat/manifest.json'), @('audio_manifest_sha256', 'assets/audio/v22_combat/manifest.json'))) {
    $field = $entry[0]
    if ([string]$build.combat_payload.$field -ne [string]$release.combat_payload.$field) { throw "Extracted combat manifest differs from build: $field" }
    $null = Assert-Hash $entry[1] ([string]$release.combat_payload.$field)
}
if (@($build.combat_payload.source_files).Count -lt 60) { throw 'Combat editable-source snapshot is incomplete.' }
foreach ($record in $build.combat_payload.source_files) {
    if ([IO.Path]::IsPathRooted([string]$record.file) -or ([string]$record.file -split '[/\\]') -contains '..' -or -not (Test-AllowedPath ([string]$record.file))) { throw 'Invalid combat source snapshot entry.' }
    $null = Assert-Hash ([string]$record.file) ([string]$record.sha256)
}
$verifiedExe = Resolve-OwnedPath ([string]$release.executable)
$buildExe = Resolve-OwnedPath ([string]$build.executable)
if ($verifiedExe -eq $buildExe) { throw 'Verify the executable extracted from the initial portable ZIP, not just the export staging executable.' }
if ([string]$release.executable_sha256 -ne [string]$build.executable_sha256) { throw 'Release verifier and initial build observed different executables.' }
$verifiedHash = Assert-Hash $verifiedExe ([string]$release.executable_sha256)
$null = Assert-Hash $buildExe $verifiedHash
$null = Assert-Hash ([string]$build.portable_zip) ([string]$build.portable_sha256)
$null = Assert-Hash ([string]$build.source_zip) ([string]$build.source_sha256)

# Every output uses a fresh name. A failed invocation leaves its partial output
# available for diagnosis; it never removes, overwrites, or reuses an old stage.
$outputRoot = Resolve-OwnedPath ('build/V22LivingWorld-Final-' + $runId) -AllowMissing
$logRoot = Resolve-OwnedPath ('artifacts/v22/package-runs/' + $runId) -AllowMissing
$portableZip = Resolve-OwnedPath ('build/' + $gameName + 'V2.2-Windows-Final-' + $runId + '.zip') -AllowMissing
$sourceZip = Resolve-OwnedPath ('build/' + $gameName + 'V2.2-Source-Final-' + $runId + '.zip') -AllowMissing
foreach ($path in @($outputRoot, $logRoot, $portableZip, $sourceZip)) {
    if (Test-Path -LiteralPath $path) { throw "Final output already exists: $path" }
}
New-Item -ItemType Directory -Path $outputRoot | Out-Null
New-Item -ItemType Directory -Path $logRoot | Out-Null
$portableFiles = [Collections.Generic.List[object]]::new()
$portableNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Copy-PortableFile $verifiedExe ([IO.Path]::GetFileName($buildExe))
$exePath = Join-Path $outputRoot ([IO.Path]::GetFileName($buildExe))
$null = Assert-Hash $exePath $verifiedHash

# Same documentation, licenses, source roots and top-level whitelist as Build-V22.
foreach ($relative in @('README_V22.md', 'docs/v2/V22_PLAY_GUIDE.md', 'docs/v2/V22_VERIFICATION.md', 'docs/v2/V22_AUDIO.md', 'docs/v2/V22_ENVIRONMENT.md', 'docs/v2/V22_UI.md', 'docs/v2/V22_NIGHT.md', 'docs/v2/V22_COMBAT_DESIGN.md', 'docs/v2/V22_COMBAT_ART.md', 'docs/v2/V22_COMBAT_AUDIO.md', 'docs/v2/V22_ENCOUNTERS.md', 'assets/audio/v22_combat/CREDITS.txt', 'assets/models/v22_combat/LICENSE.txt', 'assets/audio/v22/CREDITS.txt', 'README_V2.md', 'THIRD_PARTY_NOTICES.md', 'docs/V2_ACCEPTANCE.md', 'docs/V2_MIGRATION.md', 'docs/V2_TRACEABILITY.md', 'docs/V2_PLAYTEST.md', 'docs/V2_ART_UPGRADE.md', 'docs/V2_AUDIO_UPGRADE.md', 'docs/V2_STREET_ASSETS.md', 'docs/V2_UI_UPGRADE.md', 'docs/V2_VISIBILITY_UPGRADE.md')) {
    Copy-PortableFile $relative $relative
}
foreach ($license in Get-SourceFiles (Join-Path $projectRoot 'assets/licenses')) { Copy-PortableFile $license.path $license.relative }
foreach ($relative in @('assets/fonts/OFL.txt', 'phone/vendor/qr_code/LICENSE.md', 'addons/gut/LICENSE.md', 'addons/gut/LICENSE')) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) { Copy-PortableFile $relative $relative }
}
# Deliberately non-recursive: only the curated JSON/PNG/Markdown review bundle.
foreach ($item in Get-ChildItem -LiteralPath $evidenceRoot -File) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Extension -notin @('.json', '.png', '.md')) { continue }
    Copy-PortableFile $item.FullName ('verification/' + $item.Name)
}
Copy-PortableFile $buildPath 'verification/packaging/initial_build_manifest.json'
Copy-PortableFile $releasePath 'verification/packaging/release_summary.json'

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
foreach ($record in $build.combat_payload.source_files) {
    if ([string]$record.file -notin $sourceNames) { throw "Required combat source is missing from the final source archive: $($record.file)" }
    $null = Assert-Hash ([string]$record.file) ([string]$record.sha256)
}

# Snapshot copied review files so the portable ZIP contains its own evidence index.
# The ZIP hashes live in the external manifest, avoiding a self-referential hash.
$payloadIndex = [ordered]@{
    package_id = $runId
    source_build_id = $build.build_id
    reused_executable_sha256 = $verifiedHash
    verifier_observed_executable_sha256 = $release.executable_sha256
    verified_executable_sha256_matches = $true
    release_checks = $release.checks
    game_version = '2.2.0'
    combat_payload = $release.combat_payload
    reexported = $false
    files = @($portableFiles.ToArray() | Sort-Object relative | ForEach-Object { [ordered]@{ file = $_.relative; bytes = (Get-Item -LiteralPath $_.path).Length; sha256 = (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash } })
}
$payloadPath = Join-Path $logRoot 'package_contents.json'
[IO.File]::WriteAllText($payloadPath, ($payloadIndex | ConvertTo-Json -Depth 10), $utf8)
Copy-PortableFile $payloadPath 'verification/packaging/package_contents.json'
Write-Archive $portableZip $portableFiles.ToArray() 'LowAltitudeSquadV22'
Write-Archive $sourceZip $sourceFiles.ToArray() 'LowAltitudeSquadV22-Source'
# Check again after archive creation in case the staged binary was altered.
$null = Assert-Hash $exePath $verifiedHash
$manifest = [ordered]@{
    build_id = $runId
    package_id = $runId
    source_build_id = $build.build_id
    utc = [DateTime]::UtcNow.ToString('o')
    project_root = $projectRoot
    game_version = '2.2.0'
    combat_payload = $build.combat_payload
    tests_skipped = [bool]$build.tests_skipped
    executable = $exePath
    executable_sha256 = $verifiedHash
    verifier_observed_executable = $verifiedExe
    verifier_observed_executable_sha256 = $release.executable_sha256
    verified_executable_sha256_matches = $true
    portable_zip = $portableZip
    portable_sha256 = (Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash
    source_zip = $sourceZip
    source_sha256 = (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash
    source_entries = @($sourceFiles.ToArray() | Sort-Object relative | ForEach-Object { $_.relative })
    portable_entries = @($portableFiles.ToArray() | Sort-Object relative | ForEach-Object { $_.relative })
    initial_build_manifest = $buildPath
    initial_build_manifest_sha256 = (Get-FileHash -LiteralPath $buildPath -Algorithm SHA256).Hash
    release_report = $releasePath
    release_report_sha256 = (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash
    release_checks = $release.checks
    engine = $release.engine
    evidence_directory = $evidenceRoot
    runtime_export_verified = $true
    reexported = $false
    source_recovery_verified_by_this_script = $false
    note = 'The packaged EXE is byte-identical to the extracted EXE observed by Verify-V2Release.ps1. Final documentation and curated evidence were repackaged from the frozen workspace. This helper did not run Godot, re-export, repeat runtime/GPU/device checks, or prove source recovery. Initial archives remain unchanged.'
}
$manifestPath = Join-Path $logRoot 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8)
Write-Host "Reused verified executable: $exePath"
Write-Host "Executable SHA256: $verifiedHash"
Write-Host "Final portable ZIP: $portableZip"
Write-Host "Final editable source ZIP: $sourceZip"
Write-Host "Final package manifest: $manifestPath"
