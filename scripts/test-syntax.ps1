#Requires -Version 7.0

# Simple syntax validation test
Write-Host "Testing module loading..."

$sourceRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$coreModules = @(
    'Logger.ps1',
    'VectorMemoryBank.ps1', 
    'SemanticIndex.ps1'
)

foreach ($module in $coreModules) {
    $modulePath = Join-Path $sourceRoot "src\Core\$module"
    if (Test-Path $modulePath) {
        Write-Host "✅ Found: $module"
        try {
            # Test parsing without execution
            $content = Get-Content $modulePath -Raw
            [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null) | Out-Null
            Write-Host "   ✅ Syntax valid"
        } catch {
            Write-Host "   ❌ Syntax error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Missing: $module" -ForegroundColor Red
    }
}

Write-Host "✅ Module validation complete"
