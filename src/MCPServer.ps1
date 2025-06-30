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
    [switch]$EnableDiagnostics = $false,
    [ValidateSet('Admin','JiraAutomation','JiraAutomationNoAI')]
    [string]$Mode = 'Admin'
)

if ($env:MCP_MODE) {
    $validModes = @('Admin', 'JiraAutomation', 'JiraAutomationNoAI')
    $trimmedMode = $env:MCP_MODE.Trim()
    if ($validModes -contains $trimmedMode) {
        $Mode = $trimmedMode
    } else {
        Write-Warning "Invalid MCP_MODE value: '$env:MCP_MODE'. Falling back to default Mode: '$Mode'."
    }
}

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import core modules in correct dependency order
$moduleRoot = Split-Path -Parent $PSCommandPath
$coreModules = @(
    'Logger.ps1',               # Base logging infrastructure
    'OrchestrationTypes.ps1',   # Shared orchestration classes
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

function Initialize-Configuration {
    param(
        [string]$LogLevel,
        [string]$ConfigPath,
        [bool]$EnableDiagnostics,
        [string]$Mode
    )
    
    $config = @{
        LogLevel = $LogLevel
        ToolsDirectory = Join-Path $moduleRoot "tools"
        EnableDiagnostics = $EnableDiagnostics
        ServerVersion = "2.1.0-rc"
        Mode = $Mode
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

    if (-not $config.ContainsKey('AIProviders')) {
        $config.AIProviders = @()
    }

    Validate-Configuration -Config $config

    return $config
}

function Validate-Configuration {
    param([hashtable]$Config)

    if (-not $Config.AIProviders -or $Config.AIProviders.Count -eq 0) {
        throw "Configuration must include at least one AI provider"
    }

    $default = $Config.DefaultAIProvider
    if ($default) {
        $names = $Config.AIProviders | ForEach-Object { $_.Name }
        if ($names -notcontains $default) {
            throw "DefaultAIProvider '$default' not found in AIProviders list"
        }
    }

    if (-not $Config.ContainsKey('Mode')) { throw "Server mode not specified" }
}

function Start-MCPServer {
    try {
        # Initialize configuration
        $config = Initialize-Configuration -LogLevel $LogLevel -ConfigPath $ConfigPath -EnableDiagnostics $EnableDiagnostics -Mode $Mode
        
        # Initialize logger
        $logLevelEnum = [LogLevel]::Parse([LogLevel], $config.LogLevel, $true)
        $script:logger = [Logger]::new($logLevelEnum)
        
        # Create and start server
        try {
            $serverMode = [System.Enum]::Parse([ServerMode], $config.Mode, $true)
        } catch {
            throw "Invalid server mode: $($config.Mode)"
        }
        $server = [MCPServer]::new($script:logger, $config, $serverMode)
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
