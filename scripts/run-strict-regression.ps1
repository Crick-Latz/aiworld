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
    @{ Name = "p1_6_cognition"; Script = "res://test/p1_6_cognition.gd"; Expected = 27 },
    @{ Name = "p1_7_ecology"; Script = "res://test/p1_7_ecology.gd"; Expected = 10 },
    @{ Name = "p2_institution"; Script = "res://test/p2_institution.gd"; Expected = 44 },
    @{ Name = "narrative_ir"; Script = "res://test/narrative_ir.gd"; Expected = 24 },
    @{ Name = "p3_narrative"; Script = "res://test/p3_narrative.gd"; Expected = 78 },
    @{ Name = "p4_threads"; Script = "res://test/p4_threads.gd"; Expected = 17 },
    @{ Name = "p5_spatial"; Script = "res://test/p5_spatial.gd"; Expected = 15 },
    @{ Name = "p4_3_thread_renderer"; Script = "res://test/p4_3_thread_renderer.gd"; Expected = 15 },
    @{ Name = "p6_world_knowledge"; Script = "res://test/p6_world_knowledge.gd"; Expected = 15 },
    @{ Name = "p6_1_runtime_agency_shadow"; Script = "res://test/p6_1_runtime_agency_shadow.gd"; Expected = 15 },
    @{ Name = "p6_2_agency_action_bridge"; Script = "res://test/p6_2_agency_action_bridge.gd"; Expected = 33 },
    @{ Name = "p6_3_items"; Script = "res://test/p6_3_items.gd"; Expected = 45 },
    @{ Name = "p6_3b_plan_steps"; Script = "res://test/p6_3b_plan_steps.gd"; Expected = 23 },
    @{ Name = "p6_3b_execution"; Script = "res://test/p6_3b_execution.gd"; Expected = 28 },
    @{ Name = "intention_revalidation"; Script = "res://test/intention_revalidation.gd"; Expected = 14 }
    @{ Name = "intention_utility"; Script = "res://test/intention_utility.gd"; Expected = 6 }
    @{ Name = "execution_receipt"; Script = "res://test/execution_receipt.gd"; Expected = 6 }
    @{ Name = "action_travel"; Script = "res://test/action_travel_lifecycle.gd"; Expected = 11 }
    @{ Name = "resource_target_revalidation"; Script = "res://test/resource_target_revalidation.gd"; Expected = 15 }
)

$failures = [Collections.Generic.List[string]]::new()
$totalPassed = 0

function Invoke-GodotGate {
    param([string]$Name, [string[]]$Arguments, [int]$Expected = -1)
    $logPath = Join-Path $resolvedEvidence "$Name.log"
    # p3_narrative 的故障注入用例会故意向 stderr 打 "ERROR: Parse JSON failed"（引擎 JSON 解析报错）。
    # $ErrorActionPreference=Stop 会把 stderr 记录升级为终止性错误——调用期间降为 Continue。
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $godot @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $text = ($output | Out-String)
    if ($exitCode -ne 0) { $failures.Add("$Name exit=$exitCode") }
    if ($text -match "(?m)^FAIL ") { $failures.Add("$Name contains FAIL") }
    if ($text -match "SCRIPT ERROR") { $failures.Add("$Name contains SCRIPT ERROR") }
    # 已知噪声：p3 故意喂坏 JSON 触发的引擎解析报错（非引擎故障）
    $engineErrors = ($output | Where-Object { $_ -match "^ERROR:" -and $_ -notmatch "Parse JSON failed" })
    if ($engineErrors.Count -gt 0) { $failures.Add("$Name contains engine ERROR") }
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
