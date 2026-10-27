$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$godot=Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$output=Join-Path $projectRoot 'build/LowAltitude'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Set-Location -LiteralPath $projectRoot
& $godot --headless --path $projectRoot --export-release 'Windows Desktop' (Join-Path $output '低空小队.exe') *> (Join-Path $projectRoot 'artifacts/export.log')
if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath (Join-Path $projectRoot 'artifacts/export.log') -Tail 40; exit 1 }
$exportLog=Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'artifacts/export.log')
if ($exportLog -match 'SCRIPT ERROR:|ERROR:') { Write-Output $exportLog; exit 1 }
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $output '游玩说明.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $output
$licenseOutput=Join-Path $output 'licenses'
New-Item -ItemType Directory -Path $licenseOutput -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'assets/licenses') -File | Copy-Item -Destination $licenseOutput -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/fonts/OFL.txt') -Destination (Join-Path $output 'licenses/NotoSansSC-OFL.txt')
Get-Item -LiteralPath (Join-Path $output '低空小队.exe') | Select-Object FullName,Length,LastWriteTime
