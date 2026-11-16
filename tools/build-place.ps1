<#
.SYNOPSIS
    Builds an isolated Roblox Studio place file (build.rbxlx) from default.project.json.
.DESCRIPTION
    Useful for smoke-testing Rojo project structure or opening a clean place file
    directly in Roblox Studio. Note: build.rbxlx is gitignored.
#>
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PinnedRojo = Join-Path $PSScriptRoot "bin\rojo.exe"
$ProjectFile = Join-Path $RepoRoot "default.project.json"
$OutputPlace = Join-Path $RepoRoot "build.rbxlx"

if (Test-Path $PinnedRojo) {
    $RojoExe = $PinnedRojo
} elseif (Get-Command "rojo" -ErrorAction SilentlyContinue) {
    $RojoExe = "rojo"
} else {
    Write-Error "Rojo was not found at '$PinnedRojo' or on PATH. See docs/DEVELOPMENT_SETUP.md to install Rojo v7.4.4."
    exit 1
}

Set-Location $RepoRoot
& $RojoExe build $ProjectFile -o $OutputPlace
if ($LASTEXITCODE -eq 0) {
    Write-Host "Built place file successfully: $OutputPlace" -ForegroundColor Green
} else {
    Write-Error "Rojo build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
