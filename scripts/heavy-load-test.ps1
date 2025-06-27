#Requires -Version 7.0
param(
    [int]$Threads = 10,
    [int]$RequestsPerThread = 50,
    [string]$ServerScript = (Join-Path $PSScriptRoot '..\src\MCPServer.ps1')
)

Write-Host "Simulating heavy load..." -ForegroundColor Cyan
$jobs = for ($i=0; $i -lt $Threads; $i++) {
    Start-Job -ScriptBlock {
        param($cnt,$srv)
        for ($j=0; $j -lt $cnt; $j++) {
            try {
                pwsh -NoLogo -File $srv -Command '{}' | Out-Null
            } catch {}
        }
    } -ArgumentList $RequestsPerThread,$ServerScript
}

$jobs | Wait-Job | Receive-Job | Out-Null
Write-Host "Load test completed." -ForegroundColor Green
