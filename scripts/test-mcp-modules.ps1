#Requires -Version 7.0

# Test script to isolate MCP server startup issues
param(
    [switch]$Verbose = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Verbose) {
    $VerbosePreference = 'Continue'
}

try {
    Write-Host "Testing MCP Server Module Loading..."
    
    # Set path
    $moduleRoot = Split-Path -Parent $PSCommandPath
    $sourceRoot = Join-Path (Split-Path -Parent $moduleRoot) "src"
    
    Write-Host "Source root: $sourceRoot"
    
    # Test each core module individually
    $coreModules = @(
        'Logger.ps1',
        'VectorMemoryBank.ps1',
        'SemanticIndex.ps1',
        'OrchestrationEngine.ps1',
        'EntityExtractor.ps1',
        'ValidationEngine.ps1',
        'ToolRegistry.ps1',
        'SecurityManager.ps1',
        'ConfidenceEngine.ps1',
        'InternalReasoningEngine.ps1',
        'ContextManager.ps1'
    )
    
    foreach ($module in $coreModules) {
        $modulePath = Join-Path $sourceRoot "Core\$module"
        Write-Host "Testing: $module" -ForegroundColor Yellow
        
        if (-not (Test-Path $modulePath)) {
            Write-Host "  ❌ Module file not found: $modulePath" -ForegroundColor Red
            continue
        }
        
        try {
            # Test syntax
            $content = Get-Content $modulePath -Raw
            [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null) | Out-Null
            Write-Host "  ✅ Syntax valid" -ForegroundColor Green
            
            # Test loading
            . $modulePath
            Write-Host "  ✅ Loaded successfully" -ForegroundColor Green
            
        } catch {
            Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  📍 Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
            throw
        }
    }
    
    Write-Host "`n🎯 Testing Logger initialization..." -ForegroundColor Cyan
    $logger = [Logger]::new("INFO")
    Write-Host "✅ Logger created successfully" -ForegroundColor Green
    
    Write-Host "`n🎯 Testing PerformanceMonitor initialization..." -ForegroundColor Cyan
    $perfMonitor = [PerformanceMonitor]::new($logger)
    Write-Host "✅ PerformanceMonitor created successfully" -ForegroundColor Green
    
    Write-Host "`n🎯 Testing OrchestrationEngine initialization..." -ForegroundColor Cyan
    $orchEngine = [OrchestrationEngine]::new($logger)
    Write-Host "✅ OrchestrationEngine created successfully" -ForegroundColor Green
    
    Write-Host "`n🎉 All core modules loaded successfully!" -ForegroundColor Green -BackgroundColor DarkGreen
    
} catch {
    Write-Host "`n❌ Test failed!" -ForegroundColor Red -BackgroundColor DarkRed
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
