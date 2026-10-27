param(
    [string]$ProjectRoot = '.',
    [string]$Python = 'C:/Program Files/Python312/python.exe'
)
$ErrorActionPreference = 'Stop'
$finalProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ($finalProject -ne (Resolve-Path -LiteralPath '.').Path) { throw 'Wrong project root' }
& $Python -B -X utf8 (Join-Path $finalProject 'scripts/v3/content/final_flow/prepare_final_voices.py')
if ($LASTEXITCODE -ne 0) { throw 'Final caption production failed' }
$finalManifest = Get-Content -LiteralPath (Join-Path $finalProject 'data/v3/content/final_flow/voice_production_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$finalEstimate = [long]2MB
foreach ($finalClip in $finalManifest.clips) { $finalEstimate += [long]([Math]::Max(3, ([string]$finalClip.text).Length / 2.7 + 2) * 22050 * 2) }
$finalPolicyCode = @'
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/'scripts_tools/v3'))
import dev
with dev.POLICY.lock():
 dev.POLICY.preflight('evidence',int(sys.argv[2]))
 print(dev.POLICY.root)
'@
$finalManaged = (& $Python -B -X utf8 -c $finalPolicyCode $finalProject ([string]$finalEstimate) | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($finalManaged)) { throw 'Storage budget refused final voice authoring' }
$finalScratch = Join-Path $finalManaged 'authoring/final-story-voices'
$finalAssets = Join-Path $finalProject 'assets/v3/content/final_flow/voices'
[void][System.IO.Directory]::CreateDirectory($finalScratch)
[void][System.IO.Directory]::CreateDirectory($finalAssets)
Add-Type -AssemblyName System.Speech
$finalSynth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$finalFormat = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$finalCount = 0
$finalBytes = [long]0
$finalUsedVoices = @{}
try {
    $finalSynth.Volume = 88
    foreach ($finalClip in $finalManifest.clips) {
        $finalName = [string]$finalClip.file
        if ($finalName -notmatch '^vofinal_[a-f0-9]{20}\.wav$') { throw 'Unexpected owned voice filename' }
        $finalDestination = Join-Path $finalAssets $finalName
        if ([System.IO.File]::Exists($finalDestination)) { throw 'Existing final voice preserved; do not regenerate without an explicit new content key' }
        $finalWave = Join-Path $finalScratch $finalName
        $finalSynth.SelectVoice([string]$finalClip.voice)
        $finalUsedVoices[[string]$finalClip.voice] = 1 + [int]$finalUsedVoices[[string]$finalClip.voice]
        $finalSynth.Rate = [int]$finalClip.rate
        $finalSynth.SetOutputToWaveFile($finalWave, $finalFormat)
        $finalSynth.Speak([string]$finalClip.text)
        $finalSynth.SetOutputToNull()
        $finalBytes += (Get-Item -LiteralPath $finalWave).Length
        Move-Item -LiteralPath $finalWave -Destination $finalDestination
        $finalCount += 1
    }
} finally {
    $finalSynth.SetOutputToNull()
    $finalSynth.Dispose()
}
$finalReceipt = [ordered]@{ production='offline speech authoring; no playback, game execution or tests'; files=$finalCount; bytes=$finalBytes; format='22050 Hz PCM16 mono'; voices=$finalUsedVoices; status='developed_not_listened' }
$finalReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $finalProject 'data/v3/content/final_flow/voice_production.json') -Encoding UTF8
$finalReceipt | ConvertTo-Json -Depth 4 -Compress
