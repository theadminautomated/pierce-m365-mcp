#Requires -Version 7.0
<#
.SYNOPSIS
    MCP Server Class Definition
.DESCRIPTION
    Defines the main MCPServer class after all dependencies are loaded.
    This file must be loaded after all core modules are imported.
#>

# MCP Server class
class MCPServer {
    hidden [Logger] $Logger
    hidden [OrchestrationEngine] $OrchestrationEngine
    hidden [PerformanceMonitor] $PerformanceMonitor
    hidden [AsyncRequestProcessor] $AsyncProcessor
    hidden [AIManager] $AIManager
    hidden [hashtable] $Configuration
    hidden [string] $ServerVersion
    hidden [DateTime] $StartTime
    hidden [bool] $IsInitialized
    hidden [ServerMode] $Mode
    
    MCPServer([Logger]$logger, [hashtable]$config, [ServerMode]$mode) {
        $this.Logger = $logger
        $this.Configuration = $config
        $this.Mode = $mode
        $this.ServerVersion = "2.1.0-rc"
        $this.StartTime = Get-Date
        $this.IsInitialized = $false
        
        $this.Initialize()
    }
    
    hidden [void] Initialize() {
        try {
            $psVersion = (Get-Variable -Name PSVersionTable -ValueOnly).PSVersion.ToString()
            $this.Logger.Info("Initializing Pierce County M365 MCP Server", @{
                Version = $this.ServerVersion
                StartTime = $this.StartTime
                PowerShellVersion = $psVersion
                MachineName = $env:COMPUTERNAME
                UserContext = $env:USERNAME
            })
            
            # Initialize performance monitoring
            $this.PerformanceMonitor = [PerformanceMonitor]::new($this.Logger)
            $this.HealthMonitor = [HealthMonitor]::new($this.Logger)
            
            # Initialize AI manager based on server mode
            if ($this.Mode -ne [ServerMode]::JiraAutomationNoAI) {
                $this.AIManager = [AIManager]::new($this.Logger, $this.Configuration)
            }
            $this.OrchestrationEngine = [OrchestrationEngine]::new($this.Logger, $this.AIManager, $this.Mode)
            $this.AsyncProcessor = [AsyncRequestProcessor]::new($this.OrchestrationEngine, $this.Logger, 4)
            
            # Register enterprise tools
            $this.RegisterEnterpriseTools()
            
            # Validate configuration
            $this.ValidateConfiguration()
            
            # Perform startup diagnostics
            $this.RunStartupDiagnostics()
            
            $this.IsInitialized = $true
            
            $this.Logger.Info("MCP Server initialization completed", @{
                InitializationTime = ((Get-Date) - $this.StartTime).TotalMilliseconds
                AvailableTools = $this.OrchestrationEngine.ToolRegistry.GetAvailableTools().Count
            })
        }
        catch {
            $this.Logger.Fatal("MCP Server initialization failed", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] Start() {
        if (-not $this.IsInitialized) {
            throw "Server not initialized"
        }
        
        $this.Logger.Info("Starting MCP Server message loop")
        
        try {
            # Set up signal handling
            $this.SetupSignalHandling()
            
            # Main message processing loop
            while (-not $script:isShuttingDown) {
                try {
                    $this.ProcessNextMessage()
                }
                catch {
                    $this.Logger.Error("Message processing error", @{
                        Error = $_.Exception.Message
                        StackTrace = $_.ScriptStackTrace
                    })
                    
                    # Send error response
                    $this.SendErrorResponse($_.Exception.Message)
                }
            }
        }
        catch {
            $this.Logger.Fatal("MCP Server crashed", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
        finally {
            $this.Shutdown()
        }
    }
    
    hidden [void] SetupSignalHandling() {
        # Register signal handlers for graceful shutdown
        Register-ObjectEvent -InputObject ([System.Console]) -EventName CancelKeyPress -Action {
            $script:isShuttingDown = $true
            if ($script:logger) {
                $script:logger.Info("Received shutdown signal (Ctrl+C)")
            }
        }
    }
    
    hidden [void] ProcessNextMessage() {
        # Read JSON-RPC message from stdin
        $inputLine = [Console]::ReadLine()
        
        if ([string]::IsNullOrEmpty($inputLine)) {
            return
        }
        
        try {
            $request = $inputLine | ConvertFrom-Json -AsHashtable
            $response = $this.HandleRequest($request)
            
            if ($response) {
                $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
                [Console]::WriteLine($responseJson)
                [Console]::Out.Flush()
            }
        }
        catch {
            $this.Logger.Error("Failed to process message", @{
                Input = $inputLine
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            
            $this.SendErrorResponse("Invalid JSON-RPC message")
        }
    }
    
    hidden [hashtable] HandleRequest([hashtable]$request) {
        $this.PerformanceMonitor.StartOperation("MessageProcessing")
        $success = $true
        
        try {
            # Log incoming request (sanitized)
            $this.Logger.Debug("Processing MCP request", @{
                Method = $request.method
                Id = $request.id
                HasParams = $request.ContainsKey('params')
            })
            
            switch ($request.method) {
                "initialize" { return $this.HandleInitialize($request) }
                "initialized" { return $this.HandleInitialized($request) }
                "tools/list" { return $this.HandleToolsList($request) }
                "tools/call" { return $this.HandleToolsCall($request) }
                "tools/callAsync" { return $this.HandleToolsCallAsync($request) }
                "tools/result" { return $this.HandleToolsResult($request) }
                "resources/list" { return $this.HandleResourcesList($request) }
                "resources/read" { return $this.HandleResourcesRead($request) }
                "logging/setLevel" { return $this.HandleLoggingSetLevel($request) }
                "prompts/list" { return $this.HandlePromptsList($request) }
                "prompts/get" { return $this.HandlePromptsGet($request) }
                "code/execute" { return $this.HandleCodeExecute($request) }
                default {
                    $this.Logger.Warning("Unknown method requested", @{
                        Method = $request.method
                        Id = $request.id
                    })
                    
                    return @{
                        jsonrpc = "2.0"
                        id = $request.id
                        error = @{
                            code = -32601
                            message = "Method not found: $($request.method)"
                        }
                    }
                }
            }

            return $null
        }
        catch {
            $this.Logger.Error("Request handling failed", @{
                Method = $request.method
                Id = $request.id
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            $success = $false
            
            return @{
                jsonrpc = "2.0"
                id = $request.id
                error = @{
                    code = -32603
                    message = "Internal error: $($_.Exception.Message)"
                }
            }
        }
        finally {
            $this.PerformanceMonitor.EndOperation("MessageProcessing", $success)
        }
    }
    
    hidden [hashtable] HandleInitialize([hashtable]$request) {
        $this.Logger.Info("MCP client initializing", @{
            ClientInfo = $request.params.clientInfo
            Capabilities = $request.params.capabilities
        })
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                protocolVersion = "2024-11-05"
                capabilities = @{
                    tools = @{
                        listChanged = $false
                    }
                    resources = @{
                        subscribe = $false
                        listChanged = $false
                    }
                    prompts = @{
                        listChanged = $false
                    }
                    logging = @{}
                }
                serverInfo = @{
                    name = "Pierce County M365 MCP Server"
                    version = $this.ServerVersion
                }
            }
        }
    }
    
    hidden [hashtable] HandleInitialized([hashtable]$request) {
        $this.Logger.Info("MCP client initialized successfully")
        return $null  # No response required for initialized
    }
    
    hidden [hashtable] HandleToolsList([hashtable]$request) {
        $tools = $this.OrchestrationEngine.ToolRegistry.GetAvailableTools()
        
        $toolSchemas = @()
        foreach ($tool in $tools) {
            $toolSchemas += @{
                name = $tool.ToolName
                description = $tool.Description
                inputSchema = $tool.GetInputSchema()
            }
        }
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                tools = $toolSchemas
            }
        }
    }
    
    hidden [hashtable] HandleToolsCall([hashtable]$request) {
        $toolName = $request.params.name
        $arguments = $request.params.arguments
        
        try {
            # Create orchestration request
            $orchRequest = $this.CreateOrchestrationRequest($toolName, $arguments)
            
            # Execute through orchestration engine
            $result = $this.OrchestrationEngine.ProcessRequest($orchRequest)
            
            # Convert result to MCP format
            return @{
                jsonrpc = "2.0"
                id = $request.id
                result = @{
                    content = @(
                        @{
                            type = "text"
                            text = $result.Response
                        }
                    )
                    isError = $result.Success -eq $false
                }
            }
        }
        catch {
            $this.Logger.Error("Tool execution failed", @{
                ToolName = $toolName
                Arguments = $arguments
                Error = $_.Exception.Message
            })
            
            return @{
                jsonrpc = "2.0"
                id = $request.id
                error = @{
                    code = -32603
                    message = "Tool execution failed: $($_.Exception.Message)"
                }
            }
        }
    }

    hidden [hashtable] HandleToolsCallAsync([hashtable]$request) {
        $toolName = $request.params.name
        $arguments = $request.params.arguments

        try {
            $orchRequest = $this.CreateOrchestrationRequest($toolName, $arguments)
            $jobId = $this.AsyncProcessor.SubmitRequest($orchRequest)

            return @{
                jsonrpc = "2.0"
                id = $request.id
                result = @{ jobId = $jobId }
            }
        } catch {
            $this.Logger.Error("Async tool execution failed", @{
                ToolName = $toolName
                Arguments = $arguments
                Error = $_.Exception.Message
            })
            return @{
                jsonrpc = "2.0"
                id = $request.id
                error = @{ code = -32603; message = "Async tool execution failed: $($_.Exception.Message)" }
            }
        }
    }

    hidden [hashtable] HandleToolsResult([hashtable]$request) {
        $jobId = [Guid]$request.params.jobId
        $result = $this.AsyncProcessor.GetResult($jobId)

        if ($null -eq $result) {
            return @{ jsonrpc = "2.0"; id = $request.id; result = @{ status = 'Running' } }
        } else {
            return @{ jsonrpc = "2.0"; id = $request.id; result = @{ status = 'Completed'; output = $result } }
        }
    }
    
    hidden [hashtable] HandlePromptsList([hashtable]$request) {
        $prompts = @(
            @{
                name = "enterprise_analysis"
                description = "Analyze enterprise M365 configuration and provide recommendations"
                arguments = @(
                    @{
                        name = "scope"
                        description = "Analysis scope (users, mailboxes, groups, security)"
                        required = $true
                    }
                )
            },
            @{
                name = "compliance_report"
                description = "Generate compliance report for specified timeframe"
                arguments = @(
                    @{
                        name = "timeframe"
                        description = "Report timeframe (daily, weekly, monthly)"
                        required = $true
                    }
                )
            }
        )
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                prompts = $prompts
            }
        }
    }
    
    hidden [hashtable] HandlePromptsGet([hashtable]$request) {
        $promptName = $request.params.name
        $arguments = $request.params.arguments
        $prompt = ""
        
        switch ($promptName) {
            "enterprise_analysis" {
                $scope = $arguments.scope
                $prompt = "Analyze the Pierce County M365 $scope configuration and provide detailed recommendations for optimization, security improvements, and compliance alignment."
            }
            "compliance_report" {
                $timeframe = $arguments.timeframe
                $prompt = "Generate a comprehensive compliance report for Pierce County M365 tenant covering the $timeframe period, including security events, policy violations, and remediation recommendations."
            }
            default {
                return @{
                    jsonrpc = "2.0"
                    id = $request.id
                    error = @{
                        code = -32602
                        message = "Unknown prompt: $promptName"
                    }
                }
            }
        }
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                description = "Enterprise M365 analysis prompt"
                messages = @(
                    @{
                        role = "user"
                        content = @{
                            type = "text"
                            text = $prompt
                        }
                    }
                )
            }
        }
    }
    
    hidden [hashtable] HandleResourcesList([hashtable]$request) {
        $resources = @(
            @{
                uri = "pierce://docs/governance"
                name = "Pierce County M365 Governance Documentation"
                description = "Comprehensive governance documentation for Pierce County M365 environment"
                mimeType = "text/markdown"
            },
            @{
                uri = "pierce://metrics/performance"
                name = "Performance Metrics"
                description = "Real-time performance metrics and monitoring data"
                mimeType = "application/json"
            },
            @{
                uri = "pierce://audit/logs"
                name = "Audit Logs"
                description = "Recent audit log entries and security events"
                mimeType = "application/json"
            }
        )
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                resources = $resources
            }
        }
    }
    
    hidden [hashtable] HandleResourcesRead([hashtable]$request) {
        $uri = $request.params.uri
        $content = ""
        
        switch -Regex ($uri) {
            "pierce://docs/governance" {
                $content = $this.GetGovernanceDocumentation()
            }
            "pierce://metrics/performance" {
                $content = $this.GetPerformanceMetrics() | ConvertTo-Json -Depth 3
            }
            "pierce://audit/logs" {
                $content = $this.GetAuditLogs() | ConvertTo-Json -Depth 3
            }
            default {
                return @{
                    jsonrpc = "2.0"
                    id = $request.id
                    error = @{
                        code = -32602
                        message = "Unknown resource URI: $uri"
                    }
                }
            }
        }
        
        return @{
            jsonrpc = "2.0"
            id = $request.id
            result = @{
                contents = @(
                    @{
                        uri = $uri
                        mimeType = if ($uri -match "docs") { "text/markdown" } else { "application/json" }
                        text = $content
                    }
                )
            }
        }
    }
    
    hidden [hashtable] HandleLoggingSetLevel([hashtable]$request) {
        $level = $request.params.level
        
        try {
            $logLevel = [LogLevel]::Parse([LogLevel], $level, $true)
            $this.Logger.MinimumLevel = $logLevel
            
            $this.Logger.Info("Log level changed", @{
                NewLevel = $level
                RequestId = $request.id
            })
            
            return @{
                jsonrpc = "2.0"
                id = $request.id
                result = @{}
            }
        }
        catch {
            return @{
                jsonrpc = "2.0"
                id = $request.id
                error = @{
                    code = -32602
                    message = "Invalid log level: $level"
                }
            }
        }
    }

    hidden [hashtable] HandleCodeExecute([hashtable]$request) {
        $lang = $request.params.language ?? 'PowerShell'
        $code = $request.params.code
        $params = $request.params.parameters
        $dry = [bool]($request.params.dryRun)
        $timeout = $request.params.timeoutSeconds ?? 10

        try {
            $execResult = $this.OrchestrationEngine.CodeExecutionEngine.Execute($lang, $code, $params, $timeout, $dry)
            return @{
                jsonrpc = '2.0'
                id = $request.id
                result = $execResult.ToHashtable()
            }
        } catch {
            $this.Logger.Error('Code execution request failed', $_)
            return @{
                jsonrpc = '2.0'
                id = $request.id
                error = @{
                    code = -32603
                    message = $_.Exception.Message
                }
            }
        }
    }
    
    hidden [OrchestrationRequest] CreateOrchestrationRequest([string]$toolName, [hashtable]$arguments) {
        # Convert MCP tool call to orchestration request
        $inputText = "Execute tool '$toolName'"
        
        if ($arguments.Count -gt 0) {
            $argText = ($arguments.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "
            $inputText += " with parameters: $argText"
        }
        
        $request = [OrchestrationRequest]::new($inputText, "MCP-Client")
        $request.Type = "ToolExecution"
        $request.Metadata = @{
            ToolName = $toolName
            Arguments = $arguments
            Source = "MCP"
        }
        
        return $request
    }
    
    hidden [void] SendErrorResponse([string]$message) {
        $errorResponse = @{
            jsonrpc = "2.0"
            id = $null
            error = @{
                code = -32700
                message = $message
            }
        } | ConvertTo-Json -Depth 3 -Compress
        
        [Console]::WriteLine($errorResponse)
        [Console]::Out.Flush()
    }
    
    hidden [void] ValidateConfiguration() {
        $this.Logger.Debug("Validating server configuration")
        
        # Validate required configuration sections
        $requiredSections = @('Logging', 'Security', 'Performance', 'Tools')
        foreach ($section in $requiredSections) {
            if (-not $this.Configuration.ContainsKey($section)) {
                $this.Logger.Warning("Missing configuration section", @{ Section = $section })
            }
        }
        
        # Validate security settings
        if ($this.Configuration.ContainsKey('Security')) {
            $securityConfig = $this.Configuration.Security
            if (-not $securityConfig.ContainsKey('AllowedDomains')) {
                $this.Logger.Warning("Security configuration missing AllowedDomains")
            }
        }
        
        $this.Logger.Info("Configuration validation completed")
    }
    
    hidden [void] RunStartupDiagnostics() {
        $this.Logger.Info("Running startup diagnostics")
        
        try {
            # Test PowerShell version
            $psVersion = (Get-Variable -Name PSVersionTable -ValueOnly).PSVersion
            if ($psVersion.Major -lt 7) {
                $this.Logger.Warning("PowerShell version below 7.0", @{
                    CurrentVersion = $psVersion.ToString()
                    RecommendedVersion = "7.0+"
                })
            }
            
            # Test module availability
            $requiredModules = @('Microsoft.Graph', 'ExchangeOnlineManagement')
            foreach ($module in $requiredModules) {
                $moduleInfo = Get-Module -Name $module -ListAvailable
                if ($moduleInfo) {
                    $this.Logger.Debug("Required module available", @{
                        Module = $module
                        Version = $moduleInfo[0].Version.ToString()
                    })
                } else {
                    $this.Logger.Warning("Required module not found", @{
                        Module = $module
                    })
                }
            }
            
            # Test network connectivity
            $testUrls = @('https://graph.microsoft.com', 'https://outlook.office365.com')
            foreach ($url in $testUrls) {
                try {
                    $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 5 -UseBasicParsing
                    $this.Logger.Debug("Network connectivity test passed", @{
                        Url = $url
                        StatusCode = $response.StatusCode
                    })
                }
                catch {
                    $this.Logger.Warning("Network connectivity test failed", @{
                        Url = $url
                        Error = $_.Exception.Message
                    })
                }
            }
            
            $this.Logger.Info("Startup diagnostics completed")
        }
        catch {
            $this.Logger.Error("Startup diagnostics failed", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
        }
    }
    
    hidden [string] GetGovernanceDocumentation() {
        return @"
# Pierce County M365 Governance Documentation

## Overview
This documentation covers the governance framework for Pierce County's Microsoft 365 environment.

## Security Policies
- Multi-factor authentication required for all users
- Conditional access policies enforced
- Data loss prevention policies active

## Compliance Standards
- SOC 2 Type II compliance
- NIST Cybersecurity Framework alignment
- GCC (Government Community Cloud) requirements

## User Management
- Standardized naming conventions
- Role-based access control
- Regular access reviews

## Data Protection
- Information protection labels
- Retention policies
- Backup and recovery procedures

Last Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
    }
    
    hidden [hashtable] GetPerformanceMetrics() {
        # This would return actual performance metrics
        return @{
            timestamp = Get-Date
            server = @{
                uptime = ((Get-Date) - $this.StartTime).TotalMinutes
                memory_usage = [System.GC]::GetTotalMemory($false) / 1MB
                cpu_usage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
            }
            operations = @{
                total_requests = $this.PerformanceMonitor.GetTotalOperations()
                average_response_time = $this.PerformanceMonitor.GetAverageResponseTime()
                error_rate = $this.PerformanceMonitor.GetErrorRate()
            }
            health = $this.HealthMonitor.GetLatestStatus()
        }
    }
    
    hidden [hashtable] GetAuditLogs() {
        # This would return recent audit log entries
        return @{
            timestamp = Get-Date
            entries = @(
                @{
                    timestamp = Get-Date
                    level = "INFO"
                    action = "Server started"
                    details = @{
                        version = $this.ServerVersion
                        user = $env:USERNAME
                        machine = $env:COMPUTERNAME
                    }
                }
            )
        }
    }
    
    hidden [void] RegisterEnterpriseTools() {
        try {
            $this.Logger.Info("Registering enterprise tools from modular structure")
            
            # Account management tools
            $accountsPath = Join-Path $PSScriptRoot "Tools\Accounts"
            if (Test-Path $accountsPath) {
                $this.RegisterToolsFromDirectory($accountsPath, "Accounts")
            }
            
            # Mailbox management tools
            $mailboxesPath = Join-Path $PSScriptRoot "Tools\Mailboxes"
            if (Test-Path $mailboxesPath) {
                $this.RegisterToolsFromDirectory($mailboxesPath, "Mailboxes")
            }
            
            # Group management tools
            $groupsPath = Join-Path $PSScriptRoot "Tools\Groups"
            if (Test-Path $groupsPath) {
                $this.RegisterToolsFromDirectory($groupsPath, "Groups")
            }
            
            # Resource management tools
            $resourcesPath = Join-Path $PSScriptRoot "Tools\Resources"
            if (Test-Path $resourcesPath) {
                $this.RegisterToolsFromDirectory($resourcesPath, "Resources")
            }
            
            # Administrative tools
            $adminPath = Join-Path $PSScriptRoot "Tools\Administration"
            if (Test-Path $adminPath) {
                $this.RegisterToolsFromDirectory($adminPath, "Administration")
            }
            
            $this.Logger.Info("Enterprise tool registration completed")
            
        } catch {
            $this.Logger.Error("Failed to register enterprise tools", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    hidden [void] RegisterToolsFromDirectory([string]$directoryPath, [string]$category) {
        $toolFiles = Get-ChildItem -Path $directoryPath -Filter "*.ps1" -File
        
        foreach ($toolFile in $toolFiles) {
            try {
                $this.Logger.Debug("Registering tool from file", @{
                    File = $toolFile.FullName
                    Category = $category
                })
                
                # Load the tool class
                $toolClass = . $toolFile.FullName
                
                if ($toolClass -and $toolClass.BaseType -eq [Object]) {
                    # Instantiate the tool
                    $toolInstance = $toolClass::new(
                        $this.Configuration,
                        $this.Logger,
                        $this.OrchestrationEngine.Validator,
                        $this.OrchestrationEngine.Security
                    )
                    
                    # Register with orchestration engine
                    $this.OrchestrationEngine.RegisterTool($toolInstance, $category)
                    
                    $this.Logger.Info("Registered enterprise tool", @{
                        ToolName = $toolInstance.ToolName
                        Category = $category
                        File = $toolFile.Name
                    })
                }
                
            } catch {
                $this.Logger.Warning("Failed to register tool from file", @{
                    File = $toolFile.FullName
                    Category = $category
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    [void] Shutdown() {
        $this.Logger.Info("MCP Server shutting down")
        
        try {
            # Dispose orchestration engine
            if ($this.OrchestrationEngine) {
                $this.OrchestrationEngine.Dispose()
            }

            if ($this.AsyncProcessor) {
                $this.AsyncProcessor.Dispose()
            }

            # Dispose performance monitor
            if ($this.PerformanceMonitor) {
                $this.PerformanceMonitor.Dispose()
            }

            if ($this.HealthMonitor) {
                $this.HealthMonitor.Stop()
            }

            $shutdownTime = Get-Date
            $uptime = $shutdownTime - $this.StartTime
            
            $this.Logger.Info("MCP Server shutdown completed", @{
                ShutdownTime = $shutdownTime
                TotalUptime = $uptime.ToString()
            })
            
            # Dispose logger last
            $this.Logger.Dispose()
        }
        catch {
            [Console]::Error.WriteLine("Shutdown error: $($_.Exception.Message)")
        }
    }
}
