[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Manifest,
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$GodotPath = '',
    [ValidateRange(30,3600)][int]$TimeoutSeconds = 900,
    [switch]$ArchivesOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false)
$manifestPath=(Resolve-Path -LiteralPath $Manifest).Path
$build=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json
if ($build.artifact_family -ne 'WorldUI' -or $build.release_tag -notmatch '^2\.2-worldui-[a-z0-9][a-z0-9.-]*$') { throw 'Not a WorldUI build manifest.' }
$destinationRoot=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/')
if (Test-Path -LiteralPath $destinationRoot) { throw 'Use a new extraction directory; this verifier never deletes or replaces files.' }
if ($destinationRoot -eq [IO.Path]::GetPathRoot($destinationRoot)) { throw 'Cannot extract at a drive root.' }

function Join-SafePath([string]$Base,[string]$Relative) {
    $relativePath=$Relative.Replace('\','/')
    if ($relativePath.StartsWith('/') -or $relativePath.Contains(':') -or $relativePath.Contains([char]0) -or @($relativePath.Split('/')|Where-Object{$_ -eq '..' -or $_ -eq '.'}).Count -gt 0) { throw "Unsafe archive/source path: $Relative" }
    foreach($segment in $relativePath.Split('/')) {
        if(-not $segment -or $segment -ne $segment.TrimEnd(' ','.') -or $segment -match '(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0){throw "Invalid Windows path segment: $Relative"}
    }
    $basePath=[IO.Path]::GetFullPath($Base).TrimEnd('\','/')
    $result=[IO.Path]::GetFullPath((Join-Path $basePath $relativePath))
    if (-not $result.StartsWith($basePath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped extraction root: $Relative" }
    return $result
}

function Expand-SafeArchive([string]$Zip,[string]$Target,[string]$Prefix,[bool]$IsSource) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($entry in $archive.Entries) {
            $name=$entry.FullName.Replace('\','/')
            if (-not $name.StartsWith($Prefix+'/',[StringComparison]::Ordinal)) { throw "Unexpected ZIP prefix: $name" }
            if (-not $names.Add($name)) { throw "Duplicate ZIP entry: $name" }
            if (($entry.ExternalAttributes -shr 16 -band 0xF000) -eq 0xA000) { throw "ZIP symbolic links are not allowed: $name" }
            $relative=$name.Substring($Prefix.Length+1)
            if (-not $relative) { continue }
            if ($relative -match '(?i)(^|/)(\.godot|\.git|profiles?|saves?|savegames|qa_v2|qa_v22|cache|user_data|userdata|migration_backups)(/|$)' -or [IO.Path]::GetFileName($relative) -match '(?i)^(profile_g\d+\.json|pilot\.json(?:\..*)?|\.env(?:\..*)?)$') { throw "Player/QA/cache data found in ZIP: $name" }
            if ($IsSource -and $relative -match '(?i)(^|/)(build|artifacts|node_modules|\.tools|__pycache__)(/|$)') { throw "Generated build/cache in source archive: $name" }
            $output=Join-SafePath $Target $relative.TrimEnd('/')
            if ($name.EndsWith('/')) { [IO.Directory]::CreateDirectory($output)|Out-Null;continue }
            [IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null
            $input=$entry.Open()
            $file=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
            try { $input.CopyTo($file) } finally { $file.Dispose();$input.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function Invoke-SourceCheck([string]$Name,[string[]]$Arguments,[string]$Success='') {
    $quoted=foreach($argument in $Arguments) { if($argument.Contains('"')){throw 'Unsupported quote in process argument.'};'"'+($argument -replace '(\\+)$','$1$1')+'"' }
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$GodotPath
    $info.Arguments=$quoted -join ' '
    $info.WorkingDirectory=$sourceRoot
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=$utf8
    $info.StandardErrorEncoding=$utf8
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$info
    try {
        if(-not $process.Start()){throw "Cannot start $Name"}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $timeout=-not $process.WaitForExit($TimeoutSeconds*1000)
        if($timeout){$process.Kill()}
        $process.WaitForExit()
        $text=$stdout.GetAwaiter().GetResult()+"`n"+$stderr.GetAwaiter().GetResult()
        $code=$process.ExitCode
    } finally { $process.Dispose() }
    [IO.File]::WriteAllText((Join-Path $destinationRoot ($Name+'.log')),$text,$utf8)
    if($timeout -or $code -ne 0 -or $text -match 'SCRIPT ERROR:|(?m)^\s*ERROR:' -or ($Success -and $text -notmatch $Success)){throw "$Name failed; inspect its log in $destinationRoot"}
}

$portableZip=(Resolve-Path -LiteralPath $build.portable_zip).Path
$sourceZip=(Resolve-Path -LiteralPath $build.source_zip).Path
if((Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash -ne $build.portable_sha256 -or (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash -ne $build.source_sha256){throw 'Archive hashes differ from this build manifest.'}
$sourceRoot=Join-Path $destinationRoot 'source'
$windowsRoot=Join-Path $destinationRoot 'Windows'
New-Item -ItemType Directory -Path $sourceRoot,$windowsRoot | Out-Null
Expand-SafeArchive $sourceZip $sourceRoot $build.source_prefix $true
Expand-SafeArchive $portableZip $windowsRoot $build.portable_prefix $false
if(Test-Path -LiteralPath (Join-Path $sourceRoot '.godot')){throw 'Source archive contained imported cache.'}
foreach($record in $build.source_freeze){
    $file=Join-SafePath $sourceRoot $record.file
    if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $record.sha256){throw "Extracted source differs: $($record.file)"}
}
$executable=Join-SafePath $windowsRoot $build.executable_name
if((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $build.executable_sha256){throw 'Extracted Windows executable differs from the built executable.'}
foreach($directory in @($sourceRoot,$windowsRoot)){
    foreach($relative in @('README_WORLDUI.md','docs/v2/WORLDUI_VERIFICATION.md','WORLDUI_RELEASE.json','WORLDUI_SOURCE_FREEZE.json')){if(-not(Test-Path -LiteralPath (Join-SafePath $directory $relative) -PathType Leaf)){throw "Current release document missing: $relative"}}
    $identity=[IO.File]::ReadAllText((Join-Path $directory 'WORLDUI_RELEASE.json'))|ConvertFrom-Json
    if($identity.release_tag -ne $build.release_tag -or $identity.build_id -ne $build.build_id){throw 'Extracted identity belongs to a different release.'}
}
foreach($old in @('README_V22.md','docs/v2/V22_VERIFICATION.md','docs/V2_ACCEPTANCE.md')){if(Test-Path -LiteralPath (Join-Path $windowsRoot $old)){throw 'Old release acceptance docs must not represent the WorldUI Windows build.'}}
$reimported=$false
if(-not $ArchivesOnly){
    if(-not $GodotPath){$GodotPath=Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'}
    $GodotPath=(Resolve-Path -LiteralPath $GodotPath).Path
    Invoke-SourceCheck 'engine-version' @('--version') '^4\.7\.2(?:\.|\s)'
    # No pre-existing .godot was copied; this is a fresh offline reconstruction.
    Invoke-SourceCheck 'source-clean-import' @('--headless','--path',$sourceRoot,'--editor','--import','--quit')
    Invoke-SourceCheck 'source-resource-validation' @('--headless','--path',$sourceRoot,'--script','res://scripts_tools/verify_worldui_source.gd') 'WORLDUI_SOURCE_VERIFY.*"passed":true'
    $reimported=$true
}
$report=[ordered]@{schema=1;release_tag=$build.release_tag;build_id=$build.build_id;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;archives_hash_verified=$true;source_freeze_verified=$true;cache_present_before_import=$false;clean_source_reimport_verified=$reimported;source_root=$sourceRoot;extracted_executable=$executable;extracted_executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash;exported_gui_launched=$false;performance_verified=$false;physical_controller_verified=$false;player_profile_accessed=$false;scope='Independent archive extraction, hash checks, optional fresh headless editor import and resource loading. The gameplay main scene and exported EXE are not launched. GUI acceptance must use this exact extracted EXE separately.'}
[IO.File]::WriteAllText((Join-Path $destinationRoot 'worldui-package-verification.json'),($report|ConvertTo-Json -Depth 8),$utf8)
Write-Output ('WORLDUI_PACKAGE_VERIFIED '+($report|ConvertTo-Json -Compress))
