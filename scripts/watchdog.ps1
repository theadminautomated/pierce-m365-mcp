#Requires -Version 7.0
param(
    [string]$ServerScript = (Join-Path $PSScriptRoot '..\src\MCPServer.ps1'),
    [int]$IntervalSec = 30
)

Write-Host "Starting MCP watchdog..." -ForegroundColor Cyan
while ($true) {
    $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ServerScript }
    if (-not $proc) {
        Write-Host "$(Get-Date -Format o) - MCP server not running. Launching..." -ForegroundColor Yellow
        Start-Process pwsh -ArgumentList "-NoLogo","-ExecutionPolicy","Bypass","-File",$ServerScript
    }
    Start-Sleep -Seconds $IntervalSec
}
