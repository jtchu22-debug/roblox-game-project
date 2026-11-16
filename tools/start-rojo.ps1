<#
.SYNOPSIS
    Starts the Rojo live-sync development server for Starfall Ranch.
.DESCRIPTION
    Prefers the pinned repository binary at tools/bin/rojo.exe and falls back
    to `rojo` on PATH if installed via Rokit or Aftman.
#>
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PinnedRojo = Join-Path $PSScriptRoot "bin\rojo.exe"
$ProjectFile = Join-Path $RepoRoot "default.project.json"

if (Test-Path $PinnedRojo) {
    $RojoExe = $PinnedRojo
} elseif (Get-Command "rojo" -ErrorAction SilentlyContinue) {
    $RojoExe = "rojo"
} else {
    Write-Error "Rojo was not found at '$PinnedRojo' or on PATH. See docs/DEVELOPMENT_SETUP.md to install Rojo v7.4.4."
    exit 1
}

Write-Host "Starting Rojo sync server using: $RojoExe" -ForegroundColor Cyan
Write-Host "Project file: $ProjectFile" -ForegroundColor Gray
Write-Host "In Roblox Studio, open Plugins -> Rojo -> Connect (localhost:34872)." -ForegroundColor Green
Write-Host "Press Ctrl+C in this window to stop syncing." -ForegroundColor Yellow

Set-Location $RepoRoot
& $RojoExe serve $ProjectFile
