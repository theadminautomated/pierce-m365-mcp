#Requires -Version 7.0

# Test MCP core modules one by one
Write-Host "🧪 Testing Core Modules..." -ForegroundColor Cyan

# Determine repository root dynamically so the script works in any environment
$repoRoot   = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$sourceRoot = Join-Path $repoRoot 'src'
$coreModules = @(
    'Logger.ps1',
    'OrchestrationTypes.ps1',
    'SemanticIndex.ps1',
    'VectorMemoryBank.ps1',
    'ValidationEngine.ps1',
    'SecurityManager.ps1',
    'ToolRegistry.ps1',
    'ContextManager.ps1',
    'ConfidenceEngine.ps1',
    'CodeExecutionEngine.ps1',
    'HealthMonitor.ps1',
    'StateMachine.ps1',
    'InternalReasoningEngine.ps1',
    'RuleBasedParser.ps1',
    'EntityExtractor.ps1',
    'AIManager.ps1',
    'WebSearchEngine.ps1',
    'OrchestrationEngine.ps1',
    'AsyncRequestProcessor.ps1'
)

foreach ($module in $coreModules) {
    $modulePath = Join-Path $sourceRoot "Core\$module"
    Write-Host "Testing: $module" -ForegroundColor Yellow
    
    try {
        . $modulePath
        Write-Host "✅ $module loaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "❌ $module failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        if ($_.Exception.InnerException) {
            Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
        break
    }
}

Write-Host "`n🎯 Testing Mcp.Core.psm1..." -ForegroundColor Cyan
Import-Module (Join-Path $sourceRoot 'Mcp.Core.psm1') -Force
Write-Host "✅ Mcp.Core.psm1 imported successfully" -ForegroundColor Green

Write-Host "✅ Module testing complete" -ForegroundColor Green
