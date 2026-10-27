param([switch]$Playthrough, [int]$Difficulty=0)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$godot=Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw 'Godot 4.7.2 not found in the documented location.' }
Set-Location -LiteralPath $projectRoot
$log=Join-Path $projectRoot 'artifacts/test-latest.log'
if ($Playthrough) {
    & $godot --headless --path $projectRoot --fixed-fps 60 -- --autotest "--difficulty=$Difficulty" *> $log
} else {
    & $godot --headless --path $projectRoot -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit *> $log
}
$result=$LASTEXITCODE
$content=Get-Content -LiteralPath $log -Raw
Write-Output $content
if ($result -ne 0 -or $content -match 'SCRIPT ERROR:|ERROR:|Failing Tests\s+[1-9]') { exit 1 }
if ($Playthrough -and $content -notmatch 'AUTO_EXIT 0') { exit 1 }
if (-not $Playthrough -and $content -notmatch 'All tests passed!') { exit 1 }
exit 0
