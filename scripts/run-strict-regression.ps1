param(
    [string]$EvidenceDirectory = "",
    [string]$GodotPath = ""
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$python = Get-Command python -ErrorAction SilentlyContinue
$prefix = @()
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    $prefix = @("-3")
}
if (-not $python) { throw "Python 3.10+ is required for the portable strict runner." }
$arguments = $prefix + @((Join-Path $PSScriptRoot "run-strict-regression.py"))
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $arguments += @("--godot", $GodotPath) }
if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) { $arguments += @("--evidence", $EvidenceDirectory) }
& $python.Source @arguments
exit $LASTEXITCODE
