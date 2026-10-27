[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$PythonPath = '',
    [ValidateRange(10, 3600)][int]$TimeoutSeconds = 300,
    [switch]$SkipContentValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$utf8 = New-Object Text.UTF8Encoding($false)
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$logRoot = Join-Path $projectRoot ('artifacts/v2/test-runs/' + $runId)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Resolve-Tool([string]$Provided, [string]$Fallback, [string]$Command) {
    if ($Provided) { $candidate = $Provided }
    elseif (Test-Path -LiteralPath $Fallback -PathType Leaf) { $candidate = $Fallback }
    else { $candidate = (Get-Command $Command -ErrorAction Stop).Source }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing tool: $resolved" }
    return $resolved
}

function Quote-NativeArgument([string]$Value) {
    if ($Value.Contains('"')) { throw 'Double quotes are not supported inside an argument.' }
    return '"' + ($Value -replace '(\\+)$', '$1$1') + '"'
}

function Read-TestSummaries([string]$Output) {
    $summaries = [Collections.Generic.List[object]]::new()
    $problems = [Collections.Generic.List[string]]::new()
    $buffer = ''
    foreach ($line in ($Output -split "`n")) {
        $candidate = $line.Trim()
        if ($candidate -match '(?:_SUMMARY|_RESULT|_REPORT)\s+(\{.*\})\s*$') { $candidate = $Matches[1] }
        if ($buffer) { $buffer += "`n" + $candidate }
        elseif ($candidate.StartsWith('{')) { $buffer = $candidate }
        else { continue }
        try { $summary = $buffer | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        $buffer = ''
        $names = @($summary.PSObject.Properties | ForEach-Object { $_.Name })
        if (@($names | Where-Object { $_ -in @('failed', 'failures', 'errors', 'passed', 'ok', 'status') }).Count -eq 0) { continue }
        $summaries.Add($summary)
        foreach ($field in @('failed', 'failures', 'errors')) {
            if ($field -notin $names) { continue }
            $value = $summary.$field
            if ($null -eq $value) { continue }
            if ($value -is [array]) { if ($value.Count -gt 0) { $problems.Add("$field is nonempty") } }
            elseif ($value -is [bool]) { if ($value) { $problems.Add("$field is true") } }
            elseif ($value -is [string]) { if ($value -ne '' -and $value -ne '0') { $problems.Add("$field is nonempty") } }
            elseif ($value -is [ValueType]) { if ([double]$value -ne 0) { $problems.Add("$field is nonzero") } }
            else { $problems.Add("$field has an unexpected object value") }
        }
        foreach ($field in @('ok', 'passed')) { if ($field -in $names -and $summary.$field -is [bool] -and -not $summary.$field) { $problems.Add("$field is false") } }
        if ('status' -in $names -and [string]$summary.status -match '^(FAIL|FAILED|ERROR)$') { $problems.Add('status reports failure') }
    }
    if ($buffer) { $problems.Add('Malformed or incomplete JSON summary') }
    return [pscustomobject]@{ found = $summaries.Count; valid = ($problems.Count -eq 0); problems = @($problems.ToArray()) }
}

function Invoke-BoundedProcess([string]$Name, [string]$File, [string[]]$Arguments, [int]$Limit, [string]$SuccessPattern = '', [bool]$RequireSummary = $false) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = (($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        if (-not $process.Start()) { throw "Cannot start $Name" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Limit * 1000)) {
            $timedOut = $true
            $process.Kill()
        }
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
    } finally {
        $watch.Stop()
        $process.Dispose()
    }
    $log = Join-Path $logRoot ($Name + '.log')
    [IO.File]::WriteAllText($log, $output, $utf8)
    $scriptError = $output -match 'SCRIPT ERROR:|(?m)^\s*ERROR:|Traceback \(most recent call last\):'
    $markerFound = -not $SuccessPattern -or $output -match $SuccessPattern
    $summaryState = Read-TestSummaries $output
    $summaryOk = $summaryState.valid -and (-not $RequireSummary -or $summaryState.found -gt 0)
    $ok = -not $timedOut -and $code -eq 0 -and -not $scriptError -and $markerFound -and $summaryOk
    Write-Host (('{0} {1} ({2:n1}s) {3}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Name, $watch.Elapsed.TotalSeconds, $log))
    if (-not $ok) { Write-Host (($output -split "`n" | Select-Object -Last 16) -join "`n") }
    return [pscustomobject]@{ name = $Name; ok = $ok; exit_code = $code; timed_out = $timedOut; script_error = $scriptError; success_marker = $markerFound; summaries = $summaryState.found; summary_errors = $summaryState.problems; seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3); log = $log }
}

try {
    $GodotPath = Resolve-Tool $GodotPath (Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe') 'godot.exe'
    $results = [Collections.Generic.List[object]]::new()
    $version = Invoke-BoundedProcess 'engine-version' $GodotPath @('--version') 30 '^4\.7\.2(?:\.|\s)'
    $results.Add($version)
    if (-not $version.ok) { throw 'Godot 4.7.2 is required.' }
    if (-not $SkipContentValidation) {
        $PythonPath = Resolve-Tool $PythonPath (Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe') 'python.exe'
        $validation = Invoke-BoundedProcess 'content-source-freshness' $PythonPath @('scripts_tools/validate_v2_content.py', '--self-test') $TimeoutSeconds
        $results.Add($validation)
        if (-not $validation.ok) { throw 'Runtime content differs from the authoritative source, or validation failed.' }
    }
    $successJson = '"(?:failed)"\s*:\s*0|"(?:ok|passed)"\s*:\s*true|"status"\s*:\s*"PASS"'
    $testScripts = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests_v2') -File -Filter 'test_*.gd' | Sort-Object Name)
    if ($testScripts.Count -eq 0) { throw 'No V2 standalone tests found.' }
    $combatTests = @('test_combat.gd', 'test_v22_damage.gd', 'test_v22_enemy_brain.gd', 'test_v22_feedback.gd')
    foreach ($required in $combatTests) {
        if ($required -notin $testScripts.Name) { throw "Required combat regression is missing: $required" }
    }
    foreach ($test in $testScripts) {
        if ([IO.File]::ReadAllText($test.FullName) -notmatch '(?m)^extends SceneTree\s*$') { throw "Not a standalone SceneTree test: $($test.Name)" }
        $script = 'tests_v2/' + $test.Name
        if ($test.BaseName -eq 'test_flight') {
            foreach ($fps in @(30, 60, 120)) {
                $results.Add((Invoke-BoundedProcess ($test.BaseName + '-' + $fps) $GodotPath @('--headless', '--path', $projectRoot, '--fixed-fps', [string]$fps, '--script', $script, '--', "--render-fps=$fps") $TimeoutSeconds $successJson $true))
            }
        } elseif ($test.BaseName -eq 'test_session') {
            $qaCase = 'session_' + $runId
            $summaryCopy = Join-Path $logRoot 'session_summary.json'
            $sessionResult = Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', "--v2-qa=$qaCase", "--session-summary-output=$summaryCopy") $TimeoutSeconds $successJson $true
            $sessionResult | Add-Member -NotePropertyName summary_copy -NotePropertyValue $summaryCopy
            if (-not (Test-Path -LiteralPath $summaryCopy -PathType Leaf)) {
                $sessionResult.ok = $false
                $sessionResult.summary_errors += 'Session summary copy is missing'
            } else {
                $copied = [IO.File]::ReadAllText($summaryCopy) | ConvertFrom-Json
                if ($copied.qa_case -ne $qaCase -or -not $copied.ok -or @($copied.failures).Count -gt 0) {
                    $sessionResult.ok = $false
                    $sessionResult.summary_errors += 'Session summary case or result does not match this run'
                }
            }
            $results.Add($sessionResult)
        } elseif ($test.BaseName -eq 'test_worldui_restoration') {
            $restorationRoot = Join-Path $env:TEMP ('worldui-restoration-' + $runId)
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--restoration-root=' + $restorationRoot)) $TimeoutSeconds $successJson $true))
        } elseif ($test.BaseName -eq 'test_worldui_profile_isolation') {
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--v2-qa=catalog_isolation_' + $runId)) $TimeoutSeconds $successJson $true))
        } elseif ($test.BaseName -eq 'test_worldui_loaded_corridors') {
            $loadedRoot = Join-Path $env:TEMP ('worldui-loaded-' + $runId)
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--fixed-fps', '60', '--script', $script, '--', ('--loaded-output=' + $loadedRoot)) ([math]::Max(390,$TimeoutSeconds)) $successJson $true))
        } elseif ($test.BaseName -eq 'test_worldui_status') {
            $statusRoot = Join-Path $env:TEMP ('worldui-status-' + $runId)
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--status-root=' + $statusRoot)) $TimeoutSeconds $successJson $true))
        } elseif ($test.BaseName -eq 'test_worldui_retry') {
            $retryRoot = Join-Path $env:TEMP ('worldui-retry-' + $runId)
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--retry-root=' + $retryRoot)) $TimeoutSeconds $successJson $true))
        } elseif ($test.BaseName -eq 'test_worldui_ui_smoke') {
            $smokeRoot = Join-Path $env:TEMP ('worldui-ui-smoke-' + $runId)
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--ui-smoke-root=' + $smokeRoot)) $TimeoutSeconds $successJson $true))
        } elseif ($test.BaseName -in @('test_v22_lobby_tour','test_v22_night','test_v22_practice')) {
            $casePrefix = @{test_v22_lobby_tour='lobby_tour_';test_v22_night='night_';test_v22_practice='practice_'}[$test.BaseName]
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script, '--', ('--v2-qa=' + $casePrefix + $runId)) $TimeoutSeconds $successJson $true))
        } else {
            $results.Add((Invoke-BoundedProcess $test.BaseName $GodotPath @('--headless', '--path', $projectRoot, '--script', $script) $TimeoutSeconds $successJson $true))
        }
    }
    # Contract-only mode: deliberately no --capture, no audio recording or
    # claim about actual output/human listening from a Dummy headless driver.
    $combatAudioScript = 'scripts_tools/v22_combat_audio_probe.gd'
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $combatAudioScript) -PathType Leaf)) { throw 'Required combat audio contract probe is missing.' }
    $results.Add((Invoke-BoundedProcess 'v22-combat-audio-contract' $GodotPath @('--headless', '--path', $projectRoot, '--script', $combatAudioScript) $TimeoutSeconds 'V22_COMBAT_AUDIO_RESULT.*"passed"\s*:\s*true' $true))
    $gutScript = Join-Path $projectRoot 'addons/gut/gut_cmdln.gd'
    if (-not (Test-Path -LiteralPath $gutScript -PathType Leaf)) { throw 'Pinned GUT dependency is missing; no online installation is attempted.' }
    $results.Add((Invoke-BoundedProcess 'gut-v1-regression' $GodotPath @('--headless', '--path', $projectRoot, '-s', 'addons/gut/gut_cmdln.gd', '-gdir=res://tests', '-gexit') $TimeoutSeconds 'All tests passed!'))
    $failed = @($results | Where-Object { -not $_.ok }).Count
    $summary = [ordered]@{ suite = 'V2-offline-test-runner'; run_id = $runId; utc = [DateTime]::UtcNow.ToString('o'); engine = $GodotPath; passed = ($failed -eq 0); failed = $failed; content_validation_skipped = [bool]$SkipContentValidation; required_combat_tests = @($combatTests) + @('v22-combat-audio-contract'); media_capture_executed = $false; tests = @($results.ToArray()); scope = 'Automated headless tests only, including combat audio resource/voice/occlusion contracts. No actual audio-output capture, human listening, GPU, physical controller, phone hardware, manual play, or timing-feasibility claim.' }
    [IO.File]::WriteAllText((Join-Path $logRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 10), $utf8)
    Write-Host "Summary: $logRoot/summary.json"
    if ($failed -gt 0) { exit 1 }
    exit 0
} catch {
    [IO.File]::WriteAllText((Join-Path $logRoot 'runner-error.txt'), $_.Exception.ToString(), $utf8)
    Write-Error $_
    exit 1
}
