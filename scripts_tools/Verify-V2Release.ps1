[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [ValidateRange(10,300)][int]$TimeoutSeconds = 60,
    [switch]$WorldUISmoke
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$output = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath (Join-Path $output 'release_summary.json')) { throw 'Use a fresh evidence directory.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$case = 'release_' + [guid]::NewGuid().ToString('N')
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $exe
$info.WorkingDirectory = Split-Path -Parent $exe
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.Arguments = '-- --v2-qa=' + $case + ' --v2-verify-release "--evidence-dir=' + $output + '"'
if ($WorldUISmoke) { $info.Arguments += " --v2-verify-worldui-smoke" }
$process = New-Object Diagnostics.Process
$process.StartInfo = $info
try {
    if (-not $process.Start()) { throw 'Cannot start isolated release verification.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill() }
    $process.WaitForExit()
    $log = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
} finally { $process.Dispose() }
[IO.File]::WriteAllText((Join-Path $output 'runtime.log'), $log, (New-Object Text.UTF8Encoding($false)))
if ($timedOut -or $exitCode -ne 0 -or $log -match 'SCRIPT ERROR:|(?m)^\s*ERROR:') { throw "Release verification failed. Exit=$exitCode; timeout=$timedOut; evidence=$output" }
$reportPath = Join-Path $output 'release_summary.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Runtime did not produce verification evidence.' }
$report = [IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
if (-not $report.ok -or @($report.failures).Count -gt 0 -or [IO.Path]::GetFullPath($report.executable) -ne $exe) { throw 'Report failed or came from another executable.' }
if ($WorldUISmoke -and (-not $report.worldui_payload.executed -or -not $report.worldui_payload.formal_checkpoint_preserved -or @($report.worldui_payload.scenes).Count -ne 5)) { throw "Requested four-region automatic smoke was incomplete." }
$report | Add-Member -NotePropertyName executable_sha256 -NotePropertyValue (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$report | Add-Member -NotePropertyName qa_case -NotePropertyValue $case
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Write-Output "PASS extracted release: $($report.checks) checks; $reportPath"
