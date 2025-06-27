#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise-Grade MCP Server with Agentic Orchestration
.DESCRIPTION
    - Autonomous orchestration and tool chaining
    - Intelligent entity extraction and normalization
    - Enterprise-grade security and compliance
    - Self-healing and adaptive capabilities
    - Comprehensive audit logging and monitoring
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.1.0-rc - Enterprise Agentic Architecture
    Compliance: GCC, SOC2, NIST Cybersecurity Framework
#>

param(
    [string]$LogLevel = "INFO",
    [string]$ConfigPath = $null,
    [switch]$EnableDiagnostics = $false
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import core modules in correct dependency order
$moduleRoot = Split-Path -Parent $PSCommandPath
$coreModules = @(
    'Logger.ps1',               # Base logging infrastructure
    'SemanticIndex.ps1',        # Semantic indexing classes (needed by VectorMemoryBank)
    'VectorMemoryBank.ps1',     # Vector memory system
    'ValidationEngine.ps1',     # Validation infrastructure
    'SecurityManager.ps1',      # Security infrastructure
    'ToolRegistry.ps1',         # Tool registration
    'ContextManager.ps1',       # Context management
    'ConfidenceEngine.ps1',     # Statistical confidence intervals
    'CodeExecutionEngine.ps1',  # Sandboxed code execution
    'HealthMonitor.ps1',       # Health monitoring
    'StateMachine.ps1',        # Table-driven state machines
    'InternalReasoningEngine.ps1', # Automated reasoning and correction
    'RuleBasedParser.ps1',     # Fallback regex/dictionary parser
    'EntityExtractor.ps1',      # Entity extraction
    'AIManager.ps1',            # Configurable AI provider management
    'WebSearchEngine.ps1',     # Contextual web search
    'OrchestrationEngine.ps1',  # Main orchestration engine
    'AsyncRequestProcessor.ps1' # Parallel request processing
)

foreach ($module in $coreModules) {
    $modulePath = Join-Path $moduleRoot "Core\$module"
    if (Test-Path $modulePath) {
        Write-Verbose "Loading module: $module"
        . $modulePath
        if (-not $?) {
            Write-Error "Failed to load module: $modulePath"
        }
    } else {
        Write-Error "Required module not found: $modulePath"
    }
}

# Load MCPServer class after all dependencies are loaded
$mcpServerClassPath = Join-Path $moduleRoot "Core\MCPServerClass.ps1"
if (Test-Path $mcpServerClassPath) {
    Write-Verbose "Loading MCPServer class"
    . $mcpServerClassPath
} else {
    Write-Error "MCPServer class file not found: $mcpServerClassPath"
}

# Global state
$script:orchestrationEngine = $null
$script:logger = $null
$script:performanceMonitor = $null
$script:isShuttingDown = $false

# Initialize the server
try {
    $config = @{
        LogLevel = $LogLevel
        ConfigPath = $ConfigPath
        EnableDiagnostics = $EnableDiagnostics
        ServerVersion = "2.1.0-rc"
    }
    
    $script:logger = [Logger]::new($LogLevel)
    $script:logger.Info("Starting Pierce County M365 MCP Server v2.1.0-rc")
    
    $script:orchestrationEngine = [OrchestrationEngine]::new($script:logger)
    $script:performanceMonitor = [PerformanceMonitor]::new($script:logger)
    
    $server = [MCPServer]::new($script:logger, $config)
    $server.Start()
}
catch {
    Write-Error "Failed to start MCP Server: $_"
    exit 1
}
function Initialize-Configuration {
    param(
        [string]$LogLevel,
        [string]$ConfigPath,
        [bool]$EnableDiagnostics
    )
    
    $config = @{
        LogLevel = $LogLevel
        ToolsDirectory = Join-Path $moduleRoot "tools"
        EnableDiagnostics = $EnableDiagnostics
        ServerVersion = "2.1.0-rc"
    }
    
    # Load configuration file if specified, otherwise try repo config
    if (-not $ConfigPath) {
        $repoConfig = Join-Path $moduleRoot '..' 'mcp.config.json'
        if (Test-Path $repoConfig) { $ConfigPath = $repoConfig }
    }
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        try {
            $fileConfig = Get-Content $ConfigPath | ConvertFrom-Json -AsHashtable
            foreach ($key in $fileConfig.Keys) {
                $config[$key] = $fileConfig[$key]
            }
        }
        catch {
            Write-Warning "Failed to load configuration file: $ConfigPath"
        }
    }
    
    return $config
}

function Start-MCPServer {
    try {
        # Initialize configuration
        $config = Initialize-Configuration -LogLevel $LogLevel -ConfigPath $ConfigPath -EnableDiagnostics $EnableDiagnostics
        
        # Initialize logger
        $logLevelEnum = [LogLevel]::Parse([LogLevel], $config.LogLevel, $true)
        $script:logger = [Logger]::new($logLevelEnum)
        
        # Create and start server
        $server = [MCPServer]::new($script:logger, $config)
        $script:orchestrationEngine = $server.OrchestrationEngine
        $script:performanceMonitor = $server.PerformanceMonitor
        
        # Start server
        $server.Start()
    }
    catch {
        if ($script:logger) {
            $script:logger.Fatal("Failed to start MCP Server", $_.Exception)
        } else {
            [Console]::Error.WriteLine("Fatal error: $($_.Exception.Message)")
        }
        exit 1
    }
}

# Handle script termination
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:isShuttingDown = $true
    if ($script:logger) {
        $script:logger.Info("PowerShell engine exiting")
    }
}

# Start the MCP server
Start-MCPServer
