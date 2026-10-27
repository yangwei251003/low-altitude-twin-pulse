param([switch]$Source)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if ($Source) {
    $enginePath=Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
    if (-not (Test-Path -LiteralPath $enginePath)) { throw 'Godot 4.7.2 is missing. See toolchain.lock.json.' }
    Start-Process -FilePath $enginePath -ArgumentList @('--path',('"'+$projectRoot+'"')) -WorkingDirectory $projectRoot
} else {
    $executable=Join-Path $projectRoot 'build/LowAltitude/低空小队.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw 'Export the Windows build with Export-Game.ps1 first.' }
    Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable)
}
