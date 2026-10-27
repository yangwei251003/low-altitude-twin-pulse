param(
    [string]$ProjectRoot = '.',
    [string]$Python = 'C:/Program Files/Python312/python.exe'
)
$ErrorActionPreference = 'Stop'
# Authoring only: no engine, playback, game session, input or save operation.
# Editable text remains in radio_lines.json. The voice is an obvious temporary
# synthetic radio narrator and does not impersonate a performer.
$taskRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$expected = (Resolve-Path -LiteralPath '.').Path
if ($taskRoot -ne $expected) { throw 'Wrong real project root' }
$taskManifestPath = Join-Path $taskRoot 'data/v3/content/presentation_next/radio_lines.json'
$taskLines = Get-Content -LiteralPath $taskManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$taskBudgetCode = @'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts_tools' / 'v3'))
import dev
dev.POLICY.preflight('evidence', 8 * 1024 * 1024)
print(dev.POLICY.root)
'@
$taskManagedRoot = (& $Python -B -c $taskBudgetCode $taskRoot | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($taskManagedRoot)) { throw 'Managed storage policy refused authoring output' }
$taskScratch = Join-Path $taskManagedRoot 'authoring/presentation-next-radio'
$taskFinal = Join-Path $taskRoot 'assets/v3/content/presentation_next/voices'
[void][System.IO.Directory]::CreateDirectory($taskScratch)
[void][System.IO.Directory]::CreateDirectory($taskFinal)
Add-Type -AssemblyName System.Speech
$taskSynth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$taskFormat = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(
    [int]$taskLines.sample_rate,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono
)
try {
    $taskSynth.SelectVoice([string]$taskLines.generator_voice)
    $taskSynth.Rate = 0
    $taskSynth.Volume = 88
    foreach ($taskLine in $taskLines.lines) {
        if ([string]$taskLine.id -notmatch '^radio_[a-z0-9_]+$') { throw 'Unsafe line filename' }
        $taskWave = Join-Path $taskScratch ($taskLine.id + '.wav')
        $taskSynth.SetOutputToWaveFile($taskWave, $taskFormat)
        $taskSynth.Speak([string]$taskLine.text)
        $taskSynth.SetOutputToNull()
        Copy-Item -LiteralPath $taskWave -Destination (Join-Path $taskFinal ($taskLine.id + '.wav')) -Force
    }
} finally {
    $taskSynth.SetOutputToNull()
    $taskSynth.Dispose()
}
Write-Output ('Produced ' + @($taskLines.lines).Count + ' temporary synthetic radio WAVs; no audio playback or game execution.')
