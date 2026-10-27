param(
    [string]$ProjectRoot = '.',
    [string]$Python = 'C:/Program Files/Python312/python.exe',
    [switch]$AppendMissing
)
$ErrorActionPreference = 'Stop'
# Production only. No audio playback, engine, tests, saves or user input.
$taskRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ($taskRoot -ne (Resolve-Path -LiteralPath '.').Path) { throw 'Wrong project root' }
$taskCollector = Join-Path $taskRoot 'scripts/v3/content/dev88_presentation/collect_voice_lines.py'
& $Python -B -X utf8 $taskCollector
if ($LASTEXITCODE -ne 0) { throw 'Voice authoring manifest could not be produced' }
$taskManifest = Get-Content -LiteralPath (Join-Path $taskRoot 'data/v3/content/dev88_presentation/voice_lines.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskFinal = Join-Path $taskRoot 'assets/v3/content/dev88_presentation/voices'
$taskEstimate = [long]0
foreach ($taskLine in $taskManifest.clips) {
    if ($AppendMissing -and [System.IO.File]::Exists((Join-Path $taskFinal ($taskLine.cue_id + '.wav')))) { continue }
    $taskEstimate += [long]([Math]::Max(3.0, ([string]$taskLine.spoken_text).Length / 3.0 + 2.0) * 22050 * 2)
}
$taskEstimate += 2MB
$taskPolicyCode = @'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts_tools/v3'))
import dev
dev.POLICY.preflight('evidence', int(sys.argv[2]))
print(dev.POLICY.root)
'@
$taskManaged = (& $Python -B -X utf8 -c $taskPolicyCode $taskRoot ([string]$taskEstimate) | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($taskManaged)) { throw 'Storage policy refused voice authoring' }
$taskScratch = Join-Path $taskManaged 'authoring/dev88-presentation-voices'
[void][System.IO.Directory]::CreateDirectory($taskScratch)
[void][System.IO.Directory]::CreateDirectory($taskFinal)
Add-Type -AssemblyName System.Speech
$taskSynth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$taskFormat = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$taskProduced = 0
$taskReused = 0
$taskActualVoices = @{}
try {
    $taskSynth.Volume = 88
    foreach ($taskLine in $taskManifest.clips) {
        if ([string]$taskLine.cue_id -notmatch '^vo88_[a-f0-9]{16}$') { throw 'Unexpected owned audio filename' }
        $taskRequestedVoice = [string]$taskLine.voice
        $taskActualVoices[$taskRequestedVoice] = 1 + [int]$taskActualVoices[$taskRequestedVoice]
        $taskFinalWave = Join-Path $taskFinal ($taskLine.cue_id + '.wav')
        if ($AppendMissing -and [System.IO.File]::Exists($taskFinalWave)) {
            # Same owned content key encodes caption, character, voice and
            # rate. This is authoring continuation, not a file/quality test.
            $taskReused += 1
            continue
        }
        $taskSynth.SelectVoice($taskRequestedVoice)
        $taskSynth.Rate = [int]$taskLine.rate
        $taskWave = Join-Path $taskScratch ($taskLine.cue_id + '.wav')
        $taskSynth.SetOutputToWaveFile($taskWave, $taskFormat)
        $taskSynth.Speak([string]$taskLine.spoken_text)
        $taskSynth.SetOutputToNull()
        Copy-Item -LiteralPath $taskWave -Destination $taskFinalWave -Force
        $taskProduced += 1
    }
} finally {
    $taskSynth.SetOutputToNull()
    $taskSynth.Dispose()
}
$taskReceipt = [ordered]@{
    production = 'local offline synthetic speech authoring; no playback or game execution'
    clips_produced = $taskProduced
    prior_owned_content_keys_reused = $taskReused
    total_authored_clips = @($taskManifest.clips).Count
    actual_installed_voices = $taskActualVoices
    format = '22050 Hz / PCM 16 bit / mono'
    status = 'developed_not_playtested_not_human_mix_evaluated'
}
$taskReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskRoot 'data/v3/content/dev88_presentation/voice_production.json') -Encoding utf8
$taskReceipt | ConvertTo-Json -Depth 6 -Compress
