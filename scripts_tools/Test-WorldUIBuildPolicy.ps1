[CmdletBinding()]
param([string]$ProposalRoot='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $ProposalRoot){$ProposalRoot=Split-Path -Parent $MyInvocation.MyCommand.Path}
$checks=0
$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Label){$script:checks++;if(-not $Value){$script:failures.Add($Label)}}
foreach($filename in @('Build-WorldUI.ps1','Verify-WorldUIPackage.ps1')){
    $path=Join-Path $ProposalRoot $filename
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) ($filename+' parses in this PowerShell runtime')
    foreach($error in $errors){Write-Output $error.Message}
    foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
        # Load only helper definitions. Never execute either script's build/import body.
        . ([scriptblock]::Create($function.Extent.Text))
    }
}
foreach($path in @('data/worldui/R1.json','assets/source/worldui/research.blend','assets/source/worldui/conveyor_kenney/kenney_conveyor-kit.zip','assets/source/worldui/conveyor_kenney/License.txt','references/worldui/00_direction_comparison.png','scripts_tools/qa_v2_continuous.gd','assets/world_ui/previews/R4.png')){Check (Test-AllowedPath $path) ('Source policy preserves '+$path)}
foreach($path in @('.godot/imported/test.ctex','assets/.git/config','profiles/default/profile_g0.json','qa_v22/route/file.json','qa_v2/session/file.json','cache/object.bin','assets/image.cache','Thumbs.db','build/old.exe','artifacts/qa/result.json','assets/source/worldui/research.blend1','assets/source/worldui/unknown.zip','secret/.env','userdata/settings.json','logs/raw.log')){Check (-not(Test-AllowedPath $path)) ('Source policy rejects '+$path)}
$safeBase=Join-Path $ProposalRoot 'path-policy-only'
foreach($path in @('../escape.txt','folder/../../escape.txt','C:/escape.txt','/escape.txt','safe/../escape.txt','file.txt:alternate','folder/.. /escape.txt','NUL.txt','folder./escape.txt')){
    $rejected=$false
    try{$null=Join-SafePath $safeBase $path}catch{$rejected=$true}
    Check $rejected ('Extraction rejects '+$path)
}
$safe=Join-SafePath $safeBase 'data/worldui/R1.json'
Check ($safe.StartsWith([IO.Path]::GetFullPath($safeBase)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'Ordinary extraction stays within destination'
$text=[IO.File]::ReadAllText((Join-Path $ProposalRoot 'Build-WorldUI.ps1'))
Check ($text.Contains("'data/worldui/R1.json','data/worldui/R2.json','data/worldui/R3.json','data/worldui/R4.json'")) 'All four JSON layouts require export inclusion'
Check ($text.Contains("'scripts_tools/apply_r3_maritime_layout.py'")) 'Maritime helper is a required frozen source'
Check ($text.Contains("'assets/shaders/worldui_ground.gdshader'")) 'Ground shader is a required frozen source'
Check ($text.Contains("'README_WORLDUI.md','docs/v2/WORLDUI_VERIFICATION.md','THIRD_PARTY_NOTICES.md'")) 'Windows docs are current WorldUI documents plus legal notices'
Check (-not($text.Contains("Copy-PortableFile 'README_V22.md'"))) 'Old README is not copied into Windows package'
Check ($text.Contains("'WorldUI-Windows-'+`$ReleaseTag") -and $text.Contains("'WorldUI-Source-'+`$ReleaseTag")) 'Both ZIP roots carry WorldUI identity'
Check ($text.Contains("[IO.FileMode]::CreateNew") -and $text.Contains('OutputRoot must be a NEW directory')) 'Existing deliveries are never overwritten'
Check ($text.Contains('Assert-Freeze $freeze')) 'All packaged sources are checked for concurrent edits'
$report=[ordered]@{checks=$checks;failures=@($failures);passed=($failures.Count -eq 0);scope='PowerShell parsing, package policy and path-boundary checks only; no export, import, GUI, archive creation or user-profile access.'}
$report|ConvertTo-Json -Depth 5
if($failures.Count -gt 0){exit 1}
