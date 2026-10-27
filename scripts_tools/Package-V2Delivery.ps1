[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildManifest,
    [Parameter(Mandatory = $true)][string]$ReleaseReport,
    [Parameter(Mandatory = $true)][string]$RestoredBuildManifest,
    [Parameter(Mandatory = $true)][string]$RestoredReleaseReport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$utf8 = New-Object Text.UTF8Encoding($false)

function Resolve-OwnedPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $root $Path }
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Delivery input must be inside this independent worktree: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) { throw "Missing delivery input: $resolved" }
    return $resolved
}

function Read-Record([string]$Path) {
    return ([IO.File]::ReadAllText((Resolve-OwnedPath $Path)) | ConvertFrom-Json)
}

function Assert-Hash([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath (Resolve-OwnedPath $Path) -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "Evidence hash mismatch: $Path" }
}

function Copy-DeliveryFile([string]$Source, [string]$Relative) {
    $sourcePath = Resolve-OwnedPath $Source
    $destination = Join-Path $delivery $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destination
}

$build = Read-Record $BuildManifest
$release = Read-Record $ReleaseReport
$restored = Read-Record $RestoredBuildManifest
$restoredRelease = Read-Record $RestoredReleaseReport
if ($build.tests_skipped -or $restored.tests_skipped) { throw 'Both builds must run the complete test suite.' }
if (-not $release.ok -or -not $restoredRelease.ok -or $release.failures.Count -or $restoredRelease.failures.Count) {
    throw 'Both actual release executables must pass their runtime checks.'
}
Assert-Hash $build.executable $build.executable_sha256
Assert-Hash $build.portable_zip $build.portable_sha256
Assert-Hash $build.source_zip $build.source_sha256
Assert-Hash $release.executable $build.executable_sha256
Assert-Hash $restoredRelease.executable $restored.executable_sha256
if ($release.executable_sha256 -ne $build.executable_sha256 -or $restoredRelease.executable_sha256 -ne $restored.executable_sha256) {
    throw 'Runtime evidence belongs to a different executable.'
}
$restoredRoot = Resolve-OwnedPath $restored.project_root
if ($restoredRoot -eq $root) { throw 'Source recovery must use a different directory.' }
foreach ($relative in $build.source_entries) {
    # Import metadata may be normalized by the engine; editable source must match.
    if ($relative -like '*.import') { continue }
    $source = Resolve-OwnedPath (Join-Path $root $relative)
    $copy = Resolve-OwnedPath (Join-Path $restoredRoot $relative)
    Assert-Hash $copy (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
}
$matrix = Read-Record 'artifacts/v2/render_verified/matrix_report.json'
$soak = Read-Record 'artifacts/v2/render_verified/soak_report.json'
if ($matrix.failures.Count -or $soak.failures.Count -or $soak.elapsed_wall_s -lt 1800) {
    throw 'The current GPU matrix and full 30-minute stability run are required.'
}
foreach ($report in @($matrix, $soak)) {
    foreach ($property in $report.source_snapshot.PSObject.Properties) {
        Assert-Hash ('scripts/v2/' + $property.Name + '.gd') ([string]$property.Value)
    }
    if ($report.content_sha256 -ne $release.content_sha256) { throw 'GPU and release content versions differ.' }
}
$branch = (git -C $root branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'codex/v2-independent-20261014') { throw 'Refusing to package an unrelated branch.' }
$changes = @(git -C $root status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0 -or $changes.Count) { throw 'Commit the final source and documentation before packaging.' }
$head = (git -C $root rev-parse HEAD).Trim()
$delivery = Join-Path $root ('delivery/V2Independent-' + $build.build_id)
if (Test-Path -LiteralPath $delivery) { throw "Delivery directory already exists: $delivery" }
New-Item -ItemType Directory -Path $delivery | Out-Null
Copy-DeliveryFile $build.portable_zip 'LowAltitudeSquadV2-Windows.zip'
Copy-DeliveryFile $build.source_zip 'LowAltitudeSquadV2-Source.zip'
foreach ($relative in @('README_V2.md', 'THIRD_PARTY_NOTICES.md', 'toolchain.lock.json', 'docs/V2_ACCEPTANCE.md', 'docs/V2_MIGRATION.md', 'docs/V2_TRACEABILITY.md', 'docs/V2_PLAYTEST.md', 'docs/V2_PROGRESS.md')) {
    Copy-DeliveryFile $relative $relative
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $delivery 'LowAltitudeSquadV2-Windows.zip'), $delivery)
$bundle = Join-Path $delivery 'LowAltitudeSquadV2-history.bundle'
git -C $root bundle create $bundle $branch
if ($LASTEXITCODE -ne 0) { throw 'Branch history bundle creation failed.' }
$previousErrorAction = $ErrorActionPreference
try {
    # Windows PowerShell can turn Git's informational stderr into error records.
    $ErrorActionPreference = 'Continue'
    $bundleVerification = @(git -C $root bundle verify $bundle 2>&1)
    $bundleExit = $LASTEXITCODE
} finally { $ErrorActionPreference = $previousErrorAction }
if ($bundleExit -ne 0) { throw 'Branch history bundle verification failed.' }
[IO.File]::WriteAllLines((Join-Path $delivery 'history-verification.txt'), [string[]]$bundleVerification, $utf8)

$evidenceZip = Join-Path $delivery 'LowAltitudeSquadV2-Evidence.zip'
$stream = [IO.File]::Open($evidenceZip, [IO.FileMode]::CreateNew)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
$evidenceEntries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Evidence([string]$Source, [string]$Relative) {
    $sourcePath = Resolve-OwnedPath $Source
    if (-not $evidenceEntries.Add($Relative)) { return }
    if (($Relative -split '[/\\]') -match '^(profiles?|private|saves|qa_v2|migration_backups|node_modules)$') { throw "Private path in evidence: $Relative" }
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourcePath, $Relative.Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
}
try {
    foreach ($folder in @('artifacts/v2', 'phone/evidence')) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $folder) -File -Recurse) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            Add-Evidence $file.FullName $file.FullName.Substring($root.Length + 1)
        }
    }
    Add-Evidence 'assets/v2/audio/test_result.json' 'audio/test_result.json'
    Add-Evidence $BuildManifest 'final/build_manifest.json'
    Add-Evidence $ReleaseReport 'final/release_summary.json'
    Add-Evidence $RestoredBuildManifest 'final/restored_build_manifest.json'
    Add-Evidence $RestoredReleaseReport 'final/restored_release_summary.json'
    foreach ($file in Get-ChildItem -LiteralPath (Split-Path -Parent (Resolve-OwnedPath $RestoredBuildManifest)) -File) {
        Add-Evidence $file.FullName ('source-restore/build/' + $file.Name)
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $restoredRoot 'artifacts/v2/test-runs') -File -Recurse) {
        Add-Evidence $file.FullName ('source-restore/' + $file.FullName.Substring($restoredRoot.Length + 1))
    }
    foreach ($relative in @('.tools/render-matrix-verified.log', '.tools/render-soak-verified.log', '.tools/build-restored-source-final.log', '.tools/build-final.log')) {
        if (Test-Path -LiteralPath (Join-Path $root $relative)) { Add-Evidence $relative ('logs/' + (Split-Path -Leaf $relative)) }
    }
} finally { $archive.Dispose(); $stream.Dispose() }

$hashes = foreach ($file in Get-ChildItem -LiteralPath $delivery -File -Recurse) {
    [ordered]@{ file = $file.FullName.Substring($delivery.Length + 1).Replace('\', '/'); bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
}
$manifest = [ordered]@{
    build_id = $build.build_id
    source_commit = $head
    branch = $branch
    frozen_v1 = '8e2eec6566a2fe45602ee0baa7dc4596f2d372c3'
    engine = $release.engine
    utc = [DateTime]::UtcNow.ToString('o')
    executable = 'LowAltitudeSquadV2/' + [IO.Path]::GetFileName($build.executable)
    release_checks = $release.checks
    restored_release_checks = $restoredRelease.checks
    source_recovery_compared = $true
    source_recovery_comparison_scope = 'All packaged editable source and assets, excluding engine-normalized .import metadata'
    gpu_runtime_pixel_failures = 0
    matrix_strict_performance_issues = @($matrix.performance_target_issues)
    soak_strict_performance_issues = @($soak.performance_target_issues)
    soak_seconds = $soak.elapsed_wall_s
    evidence_entries = $evidenceEntries.Count
    limitations = @('Android physical device not tested', 'iPhone physical testing deferred', 'Physical gamepad and novice/comfort/listening tests not performed', 'All medal deadlines not human-validated', 'Strict performance misses retained; see acceptance report')
    files = @($hashes)
}
[IO.File]::WriteAllText((Join-Path $delivery 'DELIVERY_MANIFEST.json'), ($manifest | ConvertTo-Json -Depth 10), $utf8)
Write-Host "Delivery: $delivery"
Write-Host "Current branch only: $head"
Write-Host "Runtime checks: $($release.checks) + restored $($restoredRelease.checks)"
