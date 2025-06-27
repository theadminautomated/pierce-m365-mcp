$baseDir = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path $baseDir 'Core'
$files = @(
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
    'PRSuggestionEngine.ps1',
    'OrchestrationEngine.ps1',
    'AsyncRequestProcessor.ps1',
    'MCPServerClass.ps1'
)
foreach ($file in $files) {
    $path = Join-Path $coreDir $file
    if (Test-Path $path) {
        . $path
    } else {
        Write-Warning "Module file missing: $path"
    }
}
Export-ModuleMember *
