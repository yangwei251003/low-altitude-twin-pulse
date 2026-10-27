param([ValidateRange(0,2)][int]$Map=0,[switch]$Menu)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$enginePath=Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$log=Join-Path $projectRoot 'artifacts/capture-latest.log'
$probeOption=if ($Menu) {'--menu'} else {"--map=$Map"}
& $enginePath --path $projectRoot -s scripts_tools/render_probe.gd -- $probeOption *> $log
$result=$LASTEXITCODE
$content=Get-Content -Raw -LiteralPath $log
Write-Output $content
if ($result -ne 0 -or $content -match 'SCRIPT ERROR:|ERROR:' -or $content -notmatch 'RENDER_OK|RENDER_PROBE_OK') { exit 1 }
Write-Output 'Actual GPU images: artifacts/screenshots. This probe freezes actors and is not a gameplay or performance test.'
exit 0
