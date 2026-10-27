[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GodotPath = '',
    [string]$PythonPath = '',
    [string]$OutputRoot = '',
    [ValidatePattern('^2\.2-worldui-[a-z0-9][a-z0-9.-]*$')][string]$ReleaseTag = '2.2-worldui-r1',
    [ValidateRange(30,3600)][int]$TimeoutSeconds = 900,
    [switch]$SkipTests,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$projectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) { throw 'ProjectRoot must be the intended Godot source project.' }
$utf8 = New-Object Text.UTF8Encoding($false)
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
if (-not $OutputRoot) { $OutputRoot = Join-Path $projectRoot ('build/WorldUI/' + $ReleaseTag + '-' + $runId) }
$outputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
if (Test-Path -LiteralPath $outputRoot) { throw "OutputRoot must be a NEW directory; old packages are never overwritten: $outputRoot" }
if ($outputRoot -eq $projectRoot -or $projectRoot.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'OutputRoot cannot be the project or an ancestor.' }
$logRoot = Join-Path $outputRoot 'build-evidence'
$portableRoot = Join-Path $outputRoot 'Windows'
$exePath = Join-Path $portableRoot ('LowAltitudeSquad-WorldUI-' + $ReleaseTag + '.exe')

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
    $denied = @('.git', '.godot', '.tools', 'private', 'node_modules', 'build', 'delivery', 'deliveries', 'artifacts', 'evidence', '__pycache__', 'profiles', 'profile', 'qa_v2', 'qa_v22', 'qa', 'cache', '.pytest_cache', 'qa_fixtures', 'user_data', 'userdata', 'saves', 'savegames', 'migration_backups', '.venv', 'venv')
    foreach ($part in $parts) { if ($denied -contains $part.ToLowerInvariant()) { return $false } }
    $leaf = $parts[-1]
    # These exact source archives are required by the offline asset builders.
    $sourceArchives = @('assets/source/worldui/conveyor_kenney/kenney_conveyor-kit.zip', 'asset_sources/v2/audio/downloads/kenney_ui-audio.zip', 'asset_sources/v2/audio/downloads/kenney_impact-sounds.zip', 'asset_sources/v2/streets/third_party/kenney_car_kit.zip', 'asset_sources/v2/streets/third_party/kenney_commercial.zip', 'asset_sources/v2/streets/third_party/kenney_roads.zip')
    if ($sourceArchives -contains $relativePath) { return $true }
    if ($leaf -match '(?i)^(pilot\.json(?:\..*)?|profile_g\d+\.json|gut_.*\.json|\.env(?:\..*)?|test_result\.json)$') { return $false }
    if ($leaf -match '(?i)\.(log|tmp|bak|cache|db|zip|pck|exe|pyc|lnk|blend[0-9]+)$') { return $false }
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


function Assert-RequiredFile([string]$Relative) {
    $path = Join-Path $projectRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required WorldUI input missing: $Relative" }
    if (((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Required input is a link: $Relative" }
    return $path
}

function Get-WorldUIPayload {
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in @('README_WORLDUI.md','docs/v2/WORLDUI_VERIFICATION.md')) {
        $document = [IO.File]::ReadAllText((Assert-RequiredFile $relative))
        $exactTagPattern = '(?<![A-Za-z0-9.-])' + [regex]::Escape($ReleaseTag) + '(?![A-Za-z0-9.-])'
        if ($document -notmatch $exactTagPattern) { throw "Current document must explicitly identify the complete tag $ReleaseTag; do not rename an old verification report: $relative" }
    }
    foreach ($id in @('R1','R2','R3','R4')) {
        $layoutPath = 'data/worldui/' + $id + '.json'
        $layout = [IO.File]::ReadAllText((Assert-RequiredFile $layoutPath)) | ConvertFrom-Json
        if (@($layout.land).Count -eq 0 -or @($layout.roads).Count -eq 0) { throw "Empty authored geography: $id" }
        $null = $required.Add($layoutPath)
        $null = $required.Add('assets/world_ui/previews/' + $id + '.png')
    }
    foreach ($relative in @('scripts/v2/region_layout.gd','scripts/v2/worldui_builder.gd','assets/shaders/worldui_ground.gdshader','scripts_tools/worldui_author_layouts.py','scripts_tools/worldui_models.py','scripts_tools/worldui_acquire_conveyor.py','scripts_tools/apply_r3_maritime_layout.py','scripts_tools/qa_v2_continuous.gd','assets/models/worldui/manifest.json','assets/source/worldui/.gdignore','assets/source/worldui/conveyor_kenney/kenney_conveyor-kit.zip','assets/source/worldui/conveyor_kenney/License.txt','assets/source/worldui/conveyor_kenney/SOURCE.json','README_WORLDUI.md','docs/v2/WORLDUI_VERIFICATION.md','scripts_tools/Build-WorldUI.ps1','scripts_tools/Verify-WorldUIPackage.ps1','scripts_tools/verify_worldui_source.gd')) { $null = $required.Add($relative) }
    $models = [IO.File]::ReadAllText((Assert-RequiredFile 'assets/models/worldui/manifest.json')) | ConvertFrom-Json
    if (@($models.models).Count -lt 15) { throw 'WorldUI model manifest is incomplete.' }
    foreach ($file in $models.models) {
        if ([string]$file -notmatch '^[a-z0-9_]+\.glb$') { throw 'Unexpected WorldUI model filename.' }
        $null = $required.Add('assets/models/worldui/' + $file)
    }
    foreach ($directory in @('scripts/v2','assets/shaders','assets/models/worldui','assets/world_ui/previews','assets/source/worldui','references/worldui')) {
        $path = Join-Path $projectRoot $directory
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Required WorldUI directory missing: $directory" }
        foreach ($item in Get-SourceFiles $path) { $null = $required.Add($item.relative) }
    }
    $blends = @($required | Where-Object { $_ -like 'assets/source/worldui/*.blend' })
    if ($blends.Count -lt 15) { throw 'WorldUI editable Blender sources are incomplete.' }
    $references = @($required | Where-Object { $_ -like 'references/worldui/*.png' })
    if ($references.Count -lt 9) { throw 'WorldUI reference boards are incomplete.' }
    $origin = [IO.File]::ReadAllText((Assert-RequiredFile 'assets/source/worldui/conveyor_kenney/SOURCE.json')) | ConvertFrom-Json
    if ($origin.license -ne 'CC0-1.0' -or $origin.author -ne 'Kenney' -or (Get-FileHash -LiteralPath (Assert-RequiredFile 'assets/source/worldui/conveyor_kenney/kenney_conveyor-kit.zip') -Algorithm SHA256).Hash -ne $origin.sha256) { throw 'Kenney source license/original archive hash does not match SOURCE.json.' }
    $snapshots = foreach ($relative in ($required | Sort-Object)) {
        if (-not (Test-AllowedPath $relative)) { throw "WorldUI source excluded from source package: $relative" }
        $path = Assert-RequiredFile $relative
        [ordered]@{ file=$relative; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; bytes=(Get-Item -LiteralPath $path).Length }
    }
    return [ordered]@{ schema=1; release_tag=$ReleaseTag; region_count=4; model_count=@($models.models).Count; editable_blend_count=$blends.Count; reference_count=$references.Count; source_files=@($snapshots) }
}

function Get-CuratedEvidence {
    $root = Join-Path $projectRoot 'docs/v2/evidence/worldui'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
    if (((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Curated evidence cannot be a link.' }
    $allowed = @('.json','.jsonl','.png','.jpg','.jpeg','.md','.txt','.mp4','.webm','.gif','.wav','.ogg','.csv','.log')
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Curated evidence cannot contain linked files.' }
        if ($item.PSIsContainer) { continue }
        $relative = $item.FullName.Substring($root.Length+1).Replace('\','/')
        if ($relative -match '(?i)(^|/)(\.godot|\.git|profiles?|saves?|savegames|qa_v2|qa_v22|cache|user_data|userdata|migration_backups)(/|$)' -or $item.Name -match '(?i)^(profile_g\d+\.json|pilot\.json(?:\..*)?|\.env(?:\..*)?)$') { throw "Player/QA/cache material is not allowed in curated evidence: $relative" }
        if ($item.Extension.ToLowerInvariant() -notin $allowed) { throw "Unreviewed evidence extension: $relative" }
        [pscustomobject]@{ path=$item.FullName; relative=('docs/v2/evidence/worldui/'+$relative) }
    }
}

function Get-ReleaseSourceFiles {
    foreach ($directory in @('assets','asset_sources','data','docs','references','scenes','scripts','scripts_tools','tests','tests_v2','phone','addons')) {
        $path = Join-Path $projectRoot $directory
        if (Test-Path -LiteralPath $path -PathType Container) { Get-SourceFiles $path }
    }
    foreach ($name in @('project.godot','export_presets.cfg','toolchain.lock.json','README_WORLDUI.md','README_V22.md','README_V2.md','README.md','THIRD_PARTY_NOTICES.md','AGENTS.md','.gitignore','LICENSE','LICENSE.md')) {
        $path=Join-Path $projectRoot $name
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { [pscustomobject]@{path=$path;relative=$name} }
    }
    Get-CuratedEvidence
}

function Get-FileFreeze([object[]]$Files) {
    foreach ($file in ($Files | Sort-Object relative)) { [ordered]@{ file=$file.relative; sha256=(Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash; bytes=(Get-Item -LiteralPath $file.path).Length } }
}

function Assert-Freeze([object[]]$Freeze) {
    foreach ($item in $Freeze) {
        $path = Join-Path $projectRoot $item.file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.sha256) { throw "Source changed during release; use a new build after edits finish: $($item.file)" }
    }
}

function Copy-PortableFile([string]$Relative) {
    $source=Assert-RequiredFile $Relative
    $destination=Join-Path $portableRoot $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    return [pscustomobject]@{path=$destination;relative=$Relative}
}


try {
    $projectText=[IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
    if ($projectText -notmatch 'config/custom_user_dir_name="LowAltitudeSquadV22LivingWorld"' -or $projectText -notmatch 'run/main_scene="res://scenes/v2_main.tscn"') { throw 'Wrong project application identity.' }
    $toolchain=[IO.File]::ReadAllText((Assert-RequiredFile 'toolchain.lock.json')) | ConvertFrom-Json
    if ($toolchain.game_version -ne '2.2.0') { throw 'This proposal expects the preserved 2.2.0 base toolchain, with a separate WorldUI release tag.' }
    $presetText=[IO.File]::ReadAllText((Assert-RequiredFile 'export_presets.cfg'))
    $preset=[regex]::Match($presetText,'(?ms)^\[preset\.(\d+)\]\s*(.*?)(?=^\[|\z)')
    if (-not $preset.Success -or $preset.Groups[2].Value -notmatch 'name="Windows Desktop"' -or $preset.Groups[2].Value -notmatch '(?m)^export_filter="all_resources"' -or $presetText -notmatch 'binary_format/embed_pck=true') { throw 'Requires the Windows Desktop all_resources embedded-PCK preset.' }
    $include=[regex]::Match($preset.Groups[2].Value,'(?m)^include_filter="([^"]*)"').Groups[1].Value.Split(',')
    $exclude=[regex]::Match($preset.Groups[2].Value,'(?m)^exclude_filter="([^"]*)"').Groups[1].Value.Split(',')
    $runtimeFiles=@('data/v2/world_content.json','data/worldui/R1.json','data/worldui/R2.json','data/worldui/R3.json','data/worldui/R4.json','phone/index.html','phone/app.js','phone/style.css','assets/v2/audio/audio_manifest.json','assets/audio/v22/manifest.json','assets/audio/v22/CREDITS.txt','assets/models/v22_combat/manifest.json','assets/models/v22_combat/LICENSE.txt','assets/audio/v22_combat/manifest.json','assets/audio/v22_combat/CREDITS.txt')
    foreach ($relative in $runtimeFiles) {
        $null=Assert-RequiredFile $relative
        if (@($include | Where-Object {$_ -and $relative -like $_.Trim()}).Count -eq 0 -or @($exclude | Where-Object {$_ -and $relative -like $_.Trim()}).Count -gt 0) { throw "Runtime file not exported: $relative" }
    }
    if (@($exclude | Where-Object {'assets/source/worldui/research.blend' -like $_.Trim()}).Count -eq 0) { throw 'Add assets/source/* to export exclusions; editable source belongs in the Source ZIP.' }
    $worlduiPayload=Get-WorldUIPayload
    $combatPayload=Get-CombatPayload
    foreach ($record in @($worlduiPayload.source_files)+@($combatPayload.source_files)) {
        if ($record.file -notmatch '^(scripts/v2/|assets/shaders/|assets/models/worldui/|assets/world_ui/previews/|assets/models/v22_combat/|assets/audio/v22_combat/)') { continue }
        if (@($exclude | Where-Object {$_ -and $record.file -like $_.Trim()}).Count -gt 0) { throw "Runtime resource excluded: $($record.file)" }
    }
    $sourceFiles=@(Get-ReleaseSourceFiles)
    $names=@($sourceFiles | ForEach-Object {$_.relative})
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) { throw 'Source archive would contain duplicate paths.' }
    foreach ($record in @($worlduiPayload.source_files)+@($combatPayload.source_files)) { if ($record.file -notin $names) { throw "Required editable source missing from archive: $($record.file)" } }
    if ($ValidateOnly) {
        Write-Output ('WORLDUI_BUILD_PREFLIGHT '+([ordered]@{release_tag=$ReleaseTag;toolchain_game_version=$toolchain.game_version;source_entries=$sourceFiles.Count;worldui_required=$worlduiPayload.source_files.Count;output_root=$outputRoot;export_executed=$false;tests_executed=$false;status='PASS'} | ConvertTo-Json -Compress))
        exit 0
    }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $GodotPath=Resolve-Tool $GodotPath (Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe') 'godot.exe'
    $PythonPath=Resolve-Tool $PythonPath 'C:/Program Files/Python312/python.exe' 'python.exe'
    Invoke-BoundedProcess 'engine-version' $GodotPath @('--version') 30 '^4\.7\.2(?:\.|\s)'
    Invoke-BoundedProcess 'content-source-freshness' $PythonPath @('scripts_tools/validate_v2_content.py','--self-test') $TimeoutSeconds
    Invoke-BoundedProcess 'import' $GodotPath @('--headless','--path',$projectRoot,'--editor','--import','--quit') $TimeoutSeconds
    if (-not $SkipTests) {
        $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        Invoke-BoundedProcess 'tests' $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $projectRoot 'scripts_tools/Test-V2.ps1'),'-GodotPath',$GodotPath,'-PythonPath',$PythonPath,'-TimeoutSeconds',[string]$TimeoutSeconds,'-SkipContentValidation') ([math]::Min(86400,$TimeoutSeconds*24))
    }
    # Freeze AFTER importer/tests and BEFORE export; reject concurrent edits before packaging.
    $worlduiPayload=Get-WorldUIPayload
    $combatPayload=Get-CombatPayload
    $sourceFiles=@(Get-ReleaseSourceFiles)
    $freeze=@(Get-FileFreeze $sourceFiles)
    New-Item -ItemType Directory -Path $portableRoot | Out-Null
    Invoke-BoundedProcess 'export-windows' $GodotPath @('--headless','--path',$projectRoot,'--export-release','Windows Desktop',$exePath) $TimeoutSeconds
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf) -or (Get-Item -LiteralPath $exePath).Length -lt 1048576) { throw 'Export did not create a plausible executable.' }
    Assert-Freeze $freeze
    $portableFiles=[Collections.Generic.List[object]]::new()
    $portableFiles.Add([pscustomobject]@{path=$exePath;relative=[IO.Path]::GetFileName($exePath)})
    # Only current WorldUI guidance and verification describe this build. No old acceptance docs.
    foreach ($relative in @('README_WORLDUI.md','docs/v2/WORLDUI_VERIFICATION.md','THIRD_PARTY_NOTICES.md','assets/audio/v22/CREDITS.txt','assets/audio/v22_combat/CREDITS.txt','assets/models/v22_combat/LICENSE.txt','assets/source/worldui/conveyor_kenney/License.txt','assets/source/worldui/conveyor_kenney/SOURCE.json','assets/fonts/OFL.txt','phone/vendor/qr_code/LICENSE.md')) { $portableFiles.Add((Copy-PortableFile $relative)) }
    $portableFiles.Add((Copy-PortableFile 'docs/v2/WORLDUI_GALLERY.html'))
    foreach ($file in @(Get-SourceFiles (Join-Path $projectRoot 'assets/licenses'))+@(Get-SourceFiles (Join-Path $projectRoot 'references/worldui'))+@(Get-CuratedEvidence)) { $portableFiles.Add((Copy-PortableFile $file.relative)) }
    foreach ($relative in @('addons/gut/LICENSE','addons/gut/LICENSE.md')) { if (Test-Path -LiteralPath (Join-Path $projectRoot $relative)) { $portableFiles.Add((Copy-PortableFile $relative)) } }
    $identity=[ordered]@{schema=1;release_tag=$ReleaseTag;build_id=$runId;toolchain_game_version=$toolchain.game_version;artifact_family='WorldUI';utc=[DateTime]::UtcNow.ToString('o');executable=[IO.Path]::GetFileName($exePath);executable_sha256=(Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash;documentation='README_WORLDUI.md';verification='docs/v2/WORLDUI_VERIFICATION.md';reference_art_notice='references/worldui contains visual references, not gameplay screenshots';runtime_export_verified=$false;clean_source_reimport_verified=$false;human_playthrough_verified=$false;note='Packaging preserves supplied evidence; it does not independently prove GUI, device, performance or manual-play claims.'}
    $identityPath=Join-Path $logRoot 'WORLDUI_RELEASE.json'
    [IO.File]::WriteAllText($identityPath,($identity|ConvertTo-Json -Depth 8),$utf8)
    $freezePath=Join-Path $logRoot 'WORLDUI_SOURCE_FREEZE.json'
    [IO.File]::WriteAllText($freezePath,([ordered]@{release_tag=$ReleaseTag;build_id=$runId;files=$freeze}|ConvertTo-Json -Depth 8),$utf8)
    foreach ($file in @([pscustomobject]@{path=$identityPath;relative='WORLDUI_RELEASE.json'},[pscustomobject]@{path=$freezePath;relative='WORLDUI_SOURCE_FREEZE.json'})) { $portableFiles.Add($file);$sourceFiles+=$file }
    $portableZip=Join-Path $outputRoot ('WorldUI-'+$ReleaseTag+'-Windows-'+$runId+'.zip')
    $sourceZip=Join-Path $outputRoot ('WorldUI-'+$ReleaseTag+'-Source-'+$runId+'.zip')
    $portablePrefix='WorldUI-Windows-'+$ReleaseTag
    $sourcePrefix='WorldUI-Source-'+$ReleaseTag
    Write-Archive $portableZip $portableFiles.ToArray() $portablePrefix
    Write-Archive $sourceZip $sourceFiles $sourcePrefix
    Assert-Freeze $freeze
    $manifest=[ordered]@{schema=1;artifact_family='WorldUI';release_tag=$ReleaseTag;build_id=$runId;utc=[DateTime]::UtcNow.ToString('o');project_root=$projectRoot;toolchain_game_version=$toolchain.game_version;worldui_payload=$worlduiPayload;combat_payload=$combatPayload;tests_skipped=[bool]$SkipTests;executable=$exePath;executable_name=[IO.Path]::GetFileName($exePath);executable_sha256=$identity.executable_sha256;portable_zip=$portableZip;portable_sha256=(Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash;portable_prefix=$portablePrefix;source_zip=$sourceZip;source_sha256=(Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash;source_prefix=$sourcePrefix;source_freeze=$freeze;source_entries=@($sourceFiles|ForEach-Object{$_.relative});runtime_export_verified=$false;clean_source_reimport_verified=$false;note=$identity.note}
    [IO.File]::WriteAllText((Join-Path $logRoot 'manifest.json'),($manifest|ConvertTo-Json -Depth 10),$utf8)
    Write-Output ('WORLDUI_BUILD_COMPLETE '+([ordered]@{release_tag=$ReleaseTag;output_root=$outputRoot;manifest=(Join-Path $logRoot 'manifest.json');portable_zip=$portableZip;source_zip=$sourceZip}|ConvertTo-Json -Compress))
    if ($SkipTests) { Write-Warning 'Tests explicitly skipped; this package is not newly test-validated.' }
    exit 0
} catch {
    if (Test-Path -LiteralPath $logRoot -PathType Container) { [IO.File]::WriteAllText((Join-Path $logRoot 'build-error.txt'),$_.Exception.ToString(),$utf8) }
    Write-Error $_
    exit 1
}
