param(
    [string]$EvidenceDirectory = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = Join-Path $repoRoot "game"
$godot = Join-Path $repoRoot "tools\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot console executable not found: $godot"
}

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $EvidenceDirectory = Join-Path $repoRoot ".tmp\fg-r1-$stamp"
}
$resolvedRepo = [IO.Path]::GetFullPath($repoRoot)
$resolvedEvidence = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not $resolvedEvidence.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Evidence directory must stay inside repository: $resolvedEvidence"
}
New-Item -ItemType Directory -Force -Path $resolvedEvidence | Out-Null

$suites = @(
    @{ Name = "run_all"; Script = "res://test/run_all.gd"; Expected = 199 },
    @{ Name = "player_physics"; Script = "res://test/player_physics.gd"; Expected = 28 },
    @{ Name = "camera_rotation"; Script = "res://test/camera_rotation.gd"; Expected = 10; FixedFps = 60 },
    @{ Name = "observer_sim"; Script = "res://test/observer_sim.gd"; Expected = 13 },
    @{ Name = "story_causal"; Script = "res://test/story_causal.gd"; Expected = 15 },
    @{ Name = "story_dynamic"; Script = "res://test/story_dynamic.gd"; Expected = 11 },
    @{ Name = "story_save"; Script = "res://test/story_save.gd"; Expected = 6 },
    @{ Name = "ai_mock"; Script = "res://test/ai_mock.gd"; Expected = 10 },
    @{ Name = "island_sim"; Script = "res://test/island_sim.gd"; Expected = 8 },
    @{ Name = "p0_cognition"; Script = "res://test/p0_cognition.gd"; Expected = 9 },
    @{ Name = "p1_social"; Script = "res://test/p1_social.gd"; Expected = 33 },
    @{ Name = "p1_5_cognition"; Script = "res://test/p1_5_cognition.gd"; Expected = 24 },
    @{ Name = "p1_6_cognition"; Script = "res://test/p1_6_cognition.gd"; Expected = 35 },
    @{ Name = "p1_7_ecology"; Script = "res://test/p1_7_ecology.gd"; Expected = 10 },
    @{ Name = "p2_institution"; Script = "res://test/p2_institution.gd"; Expected = 44 },
    @{ Name = "narrative_ir"; Script = "res://test/narrative_ir.gd"; Expected = 24 },
    @{ Name = "p3_narrative"; Script = "res://test/p3_narrative.gd"; Expected = 27 }
)

$failures = [Collections.Generic.List[string]]::new()
$totalPassed = 0

function Invoke-GodotGate {
    param([string]$Name, [string[]]$Arguments, [int]$Expected = -1)
    $logPath = Join-Path $resolvedEvidence "$Name.log"
    $output = & $godot @Arguments 2>&1 | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String)
    if ($exitCode -ne 0) { $failures.Add("$Name exit=$exitCode") }
    if ($text -match "(?m)^FAIL ") { $failures.Add("$Name contains FAIL") }
    if ($text -match "SCRIPT ERROR") { $failures.Add("$Name contains SCRIPT ERROR") }
    if ($text -match "(?m)^ERROR:") { $failures.Add("$Name contains engine ERROR") }
    if ($Expected -ge 0) {
        $match = [regex]::Match($text, "SUMMARY pass=(\d+) fail=(\d+)")
        if (-not $match.Success) {
            $failures.Add("$Name missing SUMMARY")
        } else {
            $actualPass = [int]$match.Groups[1].Value
            $actualFail = [int]$match.Groups[2].Value
            if ($actualPass -ne $Expected -or $actualFail -ne 0) {
                $failures.Add("$Name expected=$Expected/0 actual=$actualPass/$actualFail")
            }
            $script:totalPassed += $actualPass
        }
    }
    Write-Host ("{0,-20} exit={1} expected={2}" -f $Name, $exitCode, $Expected)
}

Invoke-GodotGate -Name "editor_import" -Arguments @("--headless", "--path", $gameRoot, "--editor", "--quit")
foreach ($suite in $suites) {
    $suiteArguments = @("--headless")
    if ($suite.ContainsKey("FixedFps")) {
        $suiteArguments += @("--fixed-fps", [string]$suite.FixedFps)
    }
    $suiteArguments += @("--path", $gameRoot, "--script", $suite.Script)
    Invoke-GodotGate -Name $suite.Name -Arguments $suiteArguments -Expected $suite.Expected
}

$boundaryLog = Join-Path $resolvedEvidence "module_boundaries.log"
$boundaryOutput = & node (Join-Path $repoRoot "scripts\check-module-boundaries.mjs") 2>&1 | Tee-Object -FilePath $boundaryLog
$boundaryExit = $LASTEXITCODE
if ($boundaryExit -ne 0) { $failures.Add("module_boundaries exit=$boundaryExit") }
Write-Host ("{0,-20} exit={1}" -f "module_boundaries", $boundaryExit)

if ($failures.Count -gt 0) {
    Write-Host "STRICT_REGRESSION FAIL evidence=$resolvedEvidence"
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host "STRICT_REGRESSION PASS suites=$($suites.Count) assertions=$totalPassed evidence=$resolvedEvidence"
exit 0
