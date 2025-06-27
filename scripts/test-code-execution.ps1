#Requires -Version 7.0

Write-Host "Testing CodeExecutionEngine..." -ForegroundColor Cyan

$root = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$core = Join-Path $root 'src/Core'

$modules = @('Logger.ps1','CodeExecutionEngine.ps1')
foreach ($m in $modules) { . (Join-Path $core $m) }

$logger = [Logger]::new([LogLevel]::Info)
$engine = [CodeExecutionEngine]::new($logger)

# Dry run test
$result = $engine.Execute('PowerShell', 'Get-Date', @{}, 5, $true)
Write-Host "Dry Run Success: $($result.Success)" -ForegroundColor Green

# Execution test
$result2 = $engine.Execute('PowerShell', 'Get-Date', @{}, 5, $false)
Write-Host "Execution Output: $($result2.Output)" -ForegroundColor Green
