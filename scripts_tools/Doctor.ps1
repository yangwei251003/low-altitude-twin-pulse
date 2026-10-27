param([string]$GodotPath=(Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'))
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$failures=0
function Check-File([string]$Label,[string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Write-Output "PASS $Label" }
    else { Write-Output "MISSING $Label : $Path"; $script:failures++ }
}
Check-File 'Godot 4.7.2' $GodotPath
if (Test-Path -LiteralPath $GodotPath) {
    $version=& $GodotPath --version
    Write-Output "Engine: $version"
    if ($version -notmatch '^4\.7\.2\.stable') { $failures++; Write-Output 'MISMATCH: this project is locked to Godot 4.7.2 standard.' }
}
Check-File 'Windows release template' (Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe')
Check-File 'GUT 9.7.1' (Join-Path $projectRoot 'addons/gut/gut_cmdln.gd')
Check-File 'Chinese font' (Join-Path $projectRoot 'assets/fonts/NotoSansSC-Medium.ttf')
Check-File 'Player model' (Join-Path $projectRoot 'assets/models/player.glb')
Check-File 'Main scene' (Join-Path $projectRoot 'scenes/main.tscn')
Write-Output 'Read-only check. It does not install or modify tools.'
exit ([int]($failures -gt 0))
