#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Tool Registry and Management System
.DESCRIPTION
    Provides dynamic tool discovery, registration, and execution management
    for the Pierce County M365 MCP Server with enterprise-grade capabilities.
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

class ToolRegistry {
    hidden [Logger] $Logger
    hidden [ConcurrentDictionary[string, ToolDefinition]] $Tools
    hidden [ConcurrentDictionary[string, ToolModule]] $LoadedModules
    hidden [string] $ToolsDirectory
    hidden [ToolValidator] $Validator
    hidden [ToolMetrics] $Metrics
    
    ToolRegistry([Logger]$logger) {
        $this.Logger = $logger
        $this.Tools = [ConcurrentDictionary[string, ToolDefinition]]::new()
        $this.LoadedModules = [ConcurrentDictionary[string, ToolModule]]::new()
        $this.ToolsDirectory = Join-Path $PSScriptRoot "..\..\tools"
        $this.Validator = [ToolValidator]::new($logger)
        $this.Metrics = [ToolMetrics]::new()
        
        $this.InitializeRegistry()
    }
    
    [void] DiscoverTools() {
        $this.Logger.Info("Starting tool discovery", @{
            ToolsDirectory = $this.ToolsDirectory
        })
        
        try {
            # Ensure tools directory exists
            if (-not (Test-Path $this.ToolsDirectory)) {
                New-Item -Path $this.ToolsDirectory -ItemType Directory -Force | Out-Null
                $this.Logger.Warning("Tools directory created", @{
                    Path = $this.ToolsDirectory
                })
            }
            
            # Discover PowerShell tool modules
            $this.DiscoverPowerShellTools()
            
            # Discover JSON tool definitions
            $this.DiscoverJsonTools()
            
            # Validate all discovered tools
            $this.ValidateAllTools()
            
            # Generate tool documentation
            $this.GenerateToolDocumentation()
            
            $this.Logger.Info("Tool discovery completed", @{
                ToolCount = $this.Tools.Count
                LoadedModules = $this.LoadedModules.Count
            })
        }
        catch {
            $this.Logger.Error("Tool discovery failed", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [ToolDefinition] GetTool([string]$toolName) {
        $tool = $null
        if ($this.Tools.TryGetValue($toolName, [ref]$tool)) {
            return $tool
        }
        
        $this.Logger.Warning("Tool not found", @{
            ToolName = $toolName
            AvailableTools = @($this.Tools.Keys)
        })
        
        throw "Tool '$toolName' not found in registry"
    }
    
    [string[]] GetAvailableTools() {
        return @($this.Tools.Keys)
    }
    
    [ToolMetadata[]] GetToolMetadata() {
        $metadata = @()
        foreach ($tool in $this.Tools.Values) {
            $metadata += $tool.Metadata
        }
        return $metadata
    }
    
    [ToolExecutionResult] ExecuteTool([string]$toolName, [hashtable]$parameters, [OrchestrationSession]$session) {
        $startTime = Get-Date
        $result = [ToolExecutionResult]::new($toolName)
        
        try {
            $this.Logger.Debug("Executing tool", @{
                ToolName = $toolName
                ParameterCount = $parameters.Count
                SessionId = $session.SessionId
            })
            
            # Get tool definition
            $tool = $this.GetTool($toolName)
            
            # Validate parameters
            $paramValidation = $this.Validator.ValidateParameters($tool, $parameters)
            if (-not $paramValidation.IsValid) {
                $result.Status = [ToolExecutionStatus]::Failed
                $result.Error = "Parameter validation failed: $($paramValidation.Errors -join ', ')"
                return $result
            }
            
            # Update metrics
            $this.Metrics.RecordExecution($toolName, $startTime)
            
            # Execute tool based on type
            $executionResult = switch ($tool.Type) {
                [ToolType]::PowerShell { $this.ExecutePowerShellTool($tool, $parameters, $session) }
                [ToolType]::JsonDefinition { $this.ExecuteJsonTool($tool, $parameters, $session) }
                [ToolType]::Native { $this.ExecuteNativeTool($tool, $parameters, $session) }
                default { throw "Unsupported tool type: $($tool.Type)" }
            }
            
            $result.Result = $executionResult
            $result.Status = [ToolExecutionStatus]::Completed
            $result.Duration = (Get-Date) - $startTime
            
            # Record successful execution
            $this.Metrics.RecordSuccess($toolName, $result.Duration)
            
            $this.Logger.Info("Tool execution completed", @{
                ToolName = $toolName
                Duration = $result.Duration.TotalMilliseconds
                SessionId = $session.SessionId
            })
            
            return $result
        }
        catch {
            $result.Status = [ToolExecutionStatus]::Failed
            $result.Error = $_.Exception.Message
            $result.Duration = (Get-Date) - $startTime
            
            # Record failure
            $this.Metrics.RecordFailure($toolName, $_.Exception)
            
            $this.Logger.Error("Tool execution failed", @{
                ToolName = $toolName
                Error = $_.Exception.Message
                Duration = $result.Duration.TotalMilliseconds
                SessionId = $session.SessionId
            })
            
            return $result
        }
    }
    
    hidden [void] DiscoverPowerShellTools() {
        $psFiles = Get-ChildItem -Path $this.ToolsDirectory -Filter "*.ps1" -Recurse
        
        foreach ($file in $psFiles) {
            try {
                $this.Logger.Debug("Discovering PowerShell tool", @{
                    FilePath = $file.FullName
                })
                
                # Parse tool metadata from file
                $metadata = $this.ParsePowerShellToolMetadata($file.FullName)
                if ($metadata) {
                    $tool = [ToolDefinition]::new(
                        $metadata.Name,
                        [ToolType]::PowerShell,
                        $file.FullName,
                        $metadata
                    )
                    
                    $this.Tools.TryAdd($metadata.Name, $tool)
                    $this.Logger.Debug("PowerShell tool registered", @{
                        ToolName = $metadata.Name
                        FilePath = $file.FullName
                    })
                }
            }
            catch {
                $this.Logger.Warning("Failed to discover PowerShell tool", @{
                    FilePath = $file.FullName
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    hidden [void] DiscoverJsonTools() {
        $jsonFiles = Get-ChildItem -Path $this.ToolsDirectory -Filter "*.json" -Recurse
        
        foreach ($file in $jsonFiles) {
            try {
                $this.Logger.Debug("Discovering JSON tool", @{
                    FilePath = $file.FullName
                })
                
                $definition = Get-Content $file.FullName | ConvertFrom-Json
                $metadata = [ToolMetadata]::new()
                $metadata.Name = $definition.name
                $metadata.Description = $definition.description
                $metadata.Version = $definition.version
                $metadata.InputSchema = $definition.inputSchema
                $metadata.OutputSchema = $definition.outputSchema
                
                $tool = [ToolDefinition]::new(
                    $metadata.Name,
                    [ToolType]::JsonDefinition,
                    $file.FullName,
                    $metadata
                )
                
                $this.Tools.TryAdd($metadata.Name, $tool)
                $this.Logger.Debug("JSON tool registered", @{
                    ToolName = $metadata.Name
                    FilePath = $file.FullName
                })
            }
            catch {
                $this.Logger.Warning("Failed to discover JSON tool", @{
                    FilePath = $file.FullName
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    hidden [ToolMetadata] ParsePowerShellToolMetadata([string]$filePath) {
        $content = Get-Content $filePath -Raw
        
        # Extract metadata from comment-based help
        $metadata = [ToolMetadata]::new()
        
        # Extract synopsis
        if ($content -match '\.SYNOPSIS\s*\n\s*(.+?)(?=\n\s*\.|\n\s*#>|\Z)') {
            $metadata.Description = $matches[1].Trim()
        }
        
        # Extract tool name from filename or function
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        if ($content -match 'function\s+([A-Za-z0-9-_]+)') {
            $metadata.Name = $matches[1]
        } else {
            $metadata.Name = $fileName -replace '_mcp$', '' -replace '^mcp_', ''
        }
        
        # Extract version
        if ($content -match '\.VERSION\s*\n\s*(.+?)(?=\n\s*\.|\n\s*#>|\Z)') {
            $metadata.Version = $matches[1].Trim()
        } else {
            $metadata.Version = "1.0.0"
        }
        
        # Extract parameters for input schema
        $parameters = @{}
        $paramBlocks = [regex]::Matches($content, '\[Parameter\([^\]]*\)\]\s*\[([^\]]+)\]\s*\$([A-Za-z0-9_]+)')
        foreach ($match in $paramBlocks) {
            $paramType = $match.Groups[1].Value
            $paramName = $match.Groups[2].Value
            $parameters[$paramName] = @{
                type = $this.ConvertToJsonType($paramType)
                description = ""
            }
        }
        
        if ($parameters.Count -gt 0) {
            $metadata.InputSchema = @{
                type = "object"
                properties = $parameters
                required = @()
            }
        }
        
        # Extract output schema (simplified)
        $metadata.OutputSchema = @{
            type = "object"
            properties = @{
                status = @{ type = "string" }
                result = @{ type = "object" }
                error = @{ type = "string" }
            }
        }
        
        $metadata.FilePath = $filePath
        $metadata.Category = $this.DetermineToolCategory($metadata.Name, $content)
        $metadata.Tags = $this.ExtractToolTags($content)
        $metadata.IsAutonomous = $content -match '#\s*AUTONOMOUS\s*:\s*true'
        $metadata.RequiresApproval = $content -match '#\s*REQUIRES_APPROVAL\s*:\s*true'
        
        return $metadata
    }
    
    hidden [object] ExecutePowerShellTool([ToolDefinition]$tool, [hashtable]$parameters, [OrchestrationSession]$session) {
        # Load the PowerShell module if not already loaded
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($tool.Path)
        $module = $this.LoadedModules[$moduleName]
        
        if (-not $module) {
            $module = [ToolModule]::new($moduleName, $tool.Path)
            $this.LoadedModules.TryAdd($moduleName, $module)
        }
        
        # Prepare execution context
        $executionContext = @{
            Tool = $tool
            Parameters = $parameters
            Session = $session
            Logger = $this.Logger
        }
        
        # Execute the PowerShell script
        $scriptBlock = {
            param($context)
            
            # Import the script
            . $context.Tool.Path
            
            # Find the main function
            $functionName = $context.Tool.Metadata.Name
            $function = Get-Command $functionName -ErrorAction SilentlyContinue
            
            if ($function) {
                # Execute with parameters
                & $functionName @context.Parameters
            } else {
                # Execute script directly with parameters
                & $context.Tool.Path @context.Parameters
            }
        }
        
        # Execute in isolated runspace for security
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        
        try {
            $pipeline = $runspace.CreatePipeline()
            $pipeline.Commands.AddScript($scriptBlock)
            $pipeline.Commands[0].Parameters.Add("context", $executionContext)
            
            $result = $pipeline.Invoke()
            
            if ($pipeline.Error.Count -gt 0) {
                $errors = $pipeline.Error.ReadToEnd()
                throw "PowerShell execution errors: $($errors -join '; ')"
            }
            
            return $result
        }
        finally {
            $runspace.Close()
            $runspace.Dispose()
        }
    }
    
    hidden [object] ExecuteJsonTool([ToolDefinition]$tool, [hashtable]$parameters, [OrchestrationSession]$session) {
        # Load JSON tool definition
        $definition = Get-Content $tool.Path | ConvertFrom-Json
        
        # Execute based on execution type
        switch ($definition.executionType) {
            "powershell" {
                # Execute PowerShell command
                $command = $definition.command
                # Replace parameter placeholders
                foreach ($param in $parameters.GetEnumerator()) {
                    $command = $command -replace "\{\{$($param.Key)\}\}", $param.Value
                }
                
                return Invoke-Expression $command
            }
            "rest" {
                # Execute REST API call
                return $this.ExecuteRestCall($definition, $parameters)
            }
            "delegation" {
                # Delegate to another tool
                return $this.ExecuteTool($definition.delegateTo, $parameters, $session)
            }
            default {
                throw "Unsupported JSON tool execution type: $($definition.executionType)"
            }
        }
    }
    
    hidden [object] ExecuteNativeTool([ToolDefinition]$tool, [hashtable]$parameters, [OrchestrationSession]$session) {
        # Execute native executable or script
        $arguments = @()
        foreach ($param in $parameters.GetEnumerator()) {
            $arguments += "--$($param.Key)"
            $arguments += $param.Value
        }
        
        $process = Start-Process -FilePath $tool.Path -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput -RedirectStandardError
        
        if ($process.ExitCode -eq 0) {
            return @{
                status = "success"
                output = $process.StandardOutput.ReadToEnd()
            }
        } else {
            throw "Native tool execution failed: $($process.StandardError.ReadToEnd())"
        }
    }
    
    hidden [void] ValidateAllTools() {
        foreach ($tool in $this.Tools.Values) {
            try {
                $validation = $this.Validator.ValidateTool($tool)
                if (-not $validation.IsValid) {
                    $this.Logger.Warning("Tool validation failed", @{
                        ToolName = $tool.Metadata.Name
                        Errors = $validation.Errors
                    })
                }
            }
            catch {
                $this.Logger.Error("Tool validation error", @{
                    ToolName = $tool.Metadata.Name
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    hidden [void] GenerateToolDocumentation() {
        $docPath = Join-Path (Split-Path $this.ToolsDirectory -Parent) "docs\tools.md"
        $docDir = Split-Path $docPath -Parent
        
        if (-not (Test-Path $docDir)) {
            New-Item -Path $docDir -ItemType Directory -Force | Out-Null
        }
        
        $documentation = $this.BuildToolDocumentation()
        Set-Content -Path $docPath -Value $documentation -Encoding UTF8
        
        $this.Logger.Info("Tool documentation generated", @{
            DocumentationPath = $docPath
            ToolCount = $this.Tools.Count
        })
    }
    
    hidden [string] BuildToolDocumentation() {
        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine("# Pierce County M365 MCP Tools") | Out-Null
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("Auto-generated documentation for all available tools.") | Out-Null
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("## Tool Categories") | Out-Null
        $sb.AppendLine("") | Out-Null
        
        # Group tools by category
        $categories = $this.Tools.Values | Group-Object { $_.Metadata.Category }
        
        foreach ($category in $categories) {
            $sb.AppendLine("### $($category.Name)") | Out-Null
            $sb.AppendLine("") | Out-Null
            
            foreach ($tool in $category.Group) {
                $sb.AppendLine("#### $($tool.Metadata.Name)") | Out-Null
                $sb.AppendLine("") | Out-Null
                $sb.AppendLine("**Description:** $($tool.Metadata.Description)") | Out-Null
                $sb.AppendLine("") | Out-Null
                $sb.AppendLine("**Version:** $($tool.Metadata.Version)") | Out-Null
                $sb.AppendLine("") | Out-Null
                
                if ($tool.Metadata.Tags.Count -gt 0) {
                    $sb.AppendLine("**Tags:** $($tool.Metadata.Tags -join ', ')") | Out-Null
                    $sb.AppendLine("") | Out-Null
                }
                
                if ($tool.Metadata.IsAutonomous) {
                    $sb.AppendLine("**Autonomous:** Yes") | Out-Null
                } else {
                    $sb.AppendLine("**Autonomous:** No") | Out-Null
                }
                
                if ($tool.Metadata.RequiresApproval) {
                    $sb.AppendLine("**Requires Approval:** Yes") | Out-Null
                }
                
                $sb.AppendLine("") | Out-Null
                
                # Input schema
                if ($tool.Metadata.InputSchema) {
                    $sb.AppendLine("**Input Parameters:**") | Out-Null
                    $sb.AppendLine("") | Out-Null
                    $sb.AppendLine("```json") | Out-Null
                    $sb.AppendLine(($tool.Metadata.InputSchema | ConvertTo-Json -Depth 3)) | Out-Null
                    $sb.AppendLine("```") | Out-Null
                    $sb.AppendLine("") | Out-Null
                }
                
                $sb.AppendLine("---") | Out-Null
                $sb.AppendLine("") | Out-Null
            }
        }
        
        # Add metrics section
        $null = $sb.AppendLine('# Tool Metrics')
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
        $sb.AppendLine("") | Out-Null
        $sb.AppendLine("Total tools: $($this.Tools.Count)") | Out-Null
        $sb.AppendLine("") | Out-Null
        
        return $sb.ToString()
    }
    
    hidden [void] InitializeRegistry() {
        $this.Logger.Debug("Initializing tool registry", @{
            ToolsDirectory = $this.ToolsDirectory
        })
        
        # Create default tool directory structure
        $this.CreateDefaultDirectoryStructure()
    }
    
    hidden [void] CreateDefaultDirectoryStructure() {
        $directories = @(
            $this.ToolsDirectory,
            (Join-Path $this.ToolsDirectory "Core"),
            (Join-Path $this.ToolsDirectory "Exchange"),
            (Join-Path $this.ToolsDirectory "ActiveDirectory"),
            (Join-Path $this.ToolsDirectory "Graph"),
            (Join-Path $this.ToolsDirectory "Reporting"),
            (Join-Path $this.ToolsDirectory "Compliance"),
            (Join-Path $this.ToolsDirectory "Security")
        )
        
        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
        }
    }
    
    hidden [string] ConvertToJsonType([string]$psType) {
        switch -Regex ($psType) {
            'string' { return "string" }
            'int|int32|int64' { return "integer" }
            'bool|boolean' { return "boolean" }
            'double|decimal|float' { return "number" }
            'array|\[\]' { return "array" }
            'hashtable|pscustomobject' { return "object" }
            default { return "string" }
        }
    }
    
    hidden [string] DetermineToolCategory([string]$toolName, [string]$content) {
        # TODO: add 25 qdditional category keywords per category. Bonus point if REGEX can accomplish this.
        $categoryKeywords = @{
            'Core' = @('deprovision', 'provision', 'account', 'user')
            'Exchange' = @('mailbox', 'permission', 'calendar', 'exchange')
            'ActiveDirectory' = @('ad', 'directory', 'group', 'ou')
            'Graph' = @('graph', 'teams', 'sharepoint', 'onedrive')
            'Reporting' = @('report', 'analytics', 'metrics', 'audit')
            'Compliance' = @('compliance', 'retention', 'policy', 'legal')
            'Security' = @('security', 'threat', 'risk', 'access')
        }
        
        $lowerContent = $content.ToLower()
        $lowerToolName = $toolName.ToLower()
        
        foreach ($category in $categoryKeywords.GetEnumerator()) {
            foreach ($keyword in $category.Value) {
                if ($lowerContent.Contains($keyword) -or $lowerToolName.Contains($keyword)) {
                    return $category.Key
                }
            }
        }
        
        return 'Core'
    }
    
    hidden [string[]] ExtractToolTags([string]$content) {
        $tags = @()
        
        # Extract tags from comments
        $tagMatches = [regex]::Matches($content, '#\s*TAGS?\s*:\s*([^\r\n]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $tagMatches) {
            $tagLine = $match.Groups[1].Value
            $tags += $tagLine -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
        
        return $tags
    }
    
    hidden [object] ExecuteRestCall([object]$definition, [hashtable]$parameters) {
        $uri = $definition.endpoint
        $method = $definition.method
        $headers = @{}
        
        # Replace parameter placeholders in URI
        foreach ($param in $parameters.GetEnumerator()) {
            $uri = $uri -replace "\{\{$($param.Key)\}\}", $param.Value
        }
        
        # Add headers if specified
        if ($definition.headers) {
            foreach ($header in $definition.headers.PSObject.Properties) {
                $headers[$header.Name] = $header.Value
            }
        }
        
        # Prepare body
        $body = $null
        if ($definition.body -and $parameters.Count -gt 0) {
            $body = $parameters | ConvertTo-Json -Depth 3
            $headers['Content-Type'] = 'application/json'
        }
        
        # Execute REST call
        $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body
        return $response
    }
}

# Supporting classes and enums
enum ToolType {
    PowerShell
    JsonDefinition
    Native
    Rest
    Composite
}

class ToolDefinition {
    [string] $Name
    [ToolType] $Type
    [string] $Path
    [ToolMetadata] $Metadata
    [DateTime] $LastModified
    [bool] $IsValid
    
    ToolDefinition([string]$name, [ToolType]$type, [string]$path, [ToolMetadata]$metadata) {
        $this.Name = $name
        $this.Type = $type
        $this.Path = $path
        $this.Metadata = $metadata
        $this.LastModified = (Get-Item $path).LastWriteTime
        $this.IsValid = $true
    }
    
    [ToolExecutionResult] Execute([hashtable]$parameters) {
        # This is overridden by the registry
        throw "Direct tool execution not supported. Use ToolRegistry.ExecuteTool()"
    }
}

class ToolMetadata {
    [string] $Name
    [string] $Description
    [string] $Version
    [string] $Author
    [string] $Category
    [string[]] $Tags
    [hashtable] $InputSchema
    [hashtable] $OutputSchema
    [string] $FilePath
    [bool] $IsAutonomous
    [bool] $RequiresApproval
    [string[]] $Dependencies
    [DateTime] $CreatedDate
    [DateTime] $ModifiedDate
    
    ToolMetadata() {
        $this.Tags = @()
        $this.Dependencies = @()
        $this.IsAutonomous = $true
        $this.RequiresApproval = $false
        $this.CreatedDate = Get-Date
        $this.ModifiedDate = Get-Date
        $this.Version = "1.0.0"
        $this.Author = "Pierce County IT"
    }
}

class ToolModule {
    [string] $Name
    [string] $Path
    [bool] $IsLoaded
    [DateTime] $LoadedAt
    [object] $Module
    
    ToolModule([string]$name, [string]$path) {
        $this.Name = $name
        $this.Path = $path
        $this.IsLoaded = $false
    }
    
    [void] Load() {
        if (-not $this.IsLoaded) {
            $this.Module = Import-Module $this.Path -PassThru -Force
            $this.IsLoaded = $true
            $this.LoadedAt = Get-Date
        }
    }
    
    [void] Unload() {
        if ($this.IsLoaded -and $this.Module) {
            Remove-Module $this.Module -Force
            $this.IsLoaded = $false
            $this.Module = $null
        }
    }
}

class ToolValidator {
    hidden [Logger] $Logger
    
    ToolValidator([Logger]$logger) {
        $this.Logger = $logger
    }
    
    [ValidationResult] ValidateTool([ToolDefinition]$tool) {
        $result = [ValidationResult]::new()
        
        # Validate tool exists
        if (-not (Test-Path $tool.Path)) {
            $result.AddError("Tool file not found: $($tool.Path)")
        }
        
        # Validate metadata
        if ([string]::IsNullOrWhiteSpace($tool.Metadata.Name)) {
            $result.AddError("Tool name is required")
        }
        
        if ([string]::IsNullOrWhiteSpace($tool.Metadata.Description)) {
            $result.AddWarning("Tool description is missing")
        }
        
        # Validate input schema
        if ($tool.Metadata.InputSchema) {
            $schemaValidation = $this.ValidateJsonSchema($tool.Metadata.InputSchema)
            if (-not $schemaValidation.IsValid) {
                $result.AddError("Invalid input schema: $($schemaValidation.Errors -join ', ')")
            }
        }
        
        # Validate output schema
        if ($tool.Metadata.OutputSchema) {
            $schemaValidation = $this.ValidateJsonSchema($tool.Metadata.OutputSchema)
            if (-not $schemaValidation.IsValid) {
                $result.AddError("Invalid output schema: $($schemaValidation.Errors -join ', ')")
            }
        }
        
        return $result
    }
    
    [ValidationResult] ValidateParameters([ToolDefinition]$tool, [hashtable]$parameters) {
        $result = [ValidationResult]::new()
        
        if (-not $tool.Metadata.InputSchema) {
            # No schema to validate against
            return $result
        }
        
        $schema = $tool.Metadata.InputSchema
        
        # Check required parameters
        if ($schema.required) {
            foreach ($requiredParam in $schema.required) {
                if (-not $parameters.ContainsKey($requiredParam)) {
                    $result.AddError("Required parameter missing: $requiredParam")
                }
            }
        }
        
        # Validate parameter types
        if ($schema.properties) {
            foreach ($param in $parameters.GetEnumerator()) {
                $paramName = $param.Key
                $paramValue = $param.Value
                
                if ($schema.properties.ContainsKey($paramName)) {
                    $propertySchema = $schema.properties[$paramName]
                    $typeValidation = $this.ValidateParameterType($paramValue, $propertySchema)
                    if (-not $typeValidation) {
                        $result.AddError("Parameter '$paramName' has invalid type")
                    }
                }
            }
        }
        
        return $result
    }
    
    hidden [ValidationResult] ValidateJsonSchema([hashtable]$schema) {
        $result = [ValidationResult]::new()
        
        # Basic schema validation
        if (-not $schema.ContainsKey('type')) {
            $result.AddError("Schema must have a 'type' property")
        }
        
        $validTypes = @('object', 'array', 'string', 'number', 'integer', 'boolean', 'null')
        if ($schema.type -notin $validTypes) {
            $result.AddError("Invalid schema type: $($schema.type)")
        }
        
        return $result
    }
    
    hidden [bool] ValidateParameterType([object]$value, [hashtable]$propertySchema) {
        $expectedType = $propertySchema.type
        
        switch ($expectedType) {
            'string' { return $value -is [string] }
            'integer' { return $value -is [int] -or $value -is [int64] }
            'number' { return $value -is [int] -or $value -is [double] -or $value -is [decimal] }
            'boolean' { return $value -is [bool] }
            'array' { return $value -is [array] }
            'object' { return $value -is [hashtable] -or $value -is [PSCustomObject] }
            default { return $true }
        }
    }
}

class ToolMetrics {
    hidden [ConcurrentDictionary[string, ToolMetric]] $Metrics
    
    ToolMetrics() {
        $this.Metrics = [ConcurrentDictionary[string, ToolMetric]]::new()
    }
    
    [void] RecordExecution([string]$toolName, [DateTime]$startTime) {
        $metric = $this.GetOrCreateMetric($toolName)
        $metric.ExecutionCount++
        $metric.LastExecution = $startTime
    }
    
    [void] RecordSuccess([string]$toolName, [TimeSpan]$duration) {
        $metric = $this.GetOrCreateMetric($toolName)
        $metric.SuccessCount++
        $metric.TotalDuration = $metric.TotalDuration.Add($duration)
        $metric.AverageExecutionTime = [TimeSpan]::FromTicks($metric.TotalDuration.Ticks / $metric.SuccessCount)
    }
    
    [void] RecordFailure([string]$toolName, [Exception]$exception) {
        $metric = $this.GetOrCreateMetric($toolName)
        $metric.FailureCount++
        $metric.LastError = $exception.Message
        $metric.LastFailure = Get-Date
    }
    
    [ToolMetric] GetMetric([string]$toolName) {
        $metric = $null
        $this.Metrics.TryGetValue($toolName, [ref]$metric)
        return $metric
    }
    
    [ToolMetric[]] GetAllMetrics() {
        return @($this.Metrics.Values)
    }
    
    hidden [ToolMetric] GetOrCreateMetric([string]$toolName) {
        $metric = $null
        if (-not $this.Metrics.TryGetValue($toolName, [ref]$metric)) {
            $metric = [ToolMetric]::new($toolName)
            $this.Metrics.TryAdd($toolName, $metric)
        }
        return $metric
    }
}

class ToolMetric {
    [string] $ToolName
    [int] $ExecutionCount
    [int] $SuccessCount
    [int] $FailureCount
    [TimeSpan] $TotalDuration
    [TimeSpan] $AverageExecutionTime
    [DateTime] $LastExecution
    [DateTime] $LastFailure
    [string] $LastError
    [double] $SuccessRate
    
    ToolMetric([string]$toolName) {
        $this.ToolName = $toolName
        $this.ExecutionCount = 0
        $this.SuccessCount = 0
        $this.FailureCount = 0
        $this.TotalDuration = [TimeSpan]::Zero
        $this.AverageExecutionTime = [TimeSpan]::Zero
    }
    
    [void] UpdateSuccessRate() {
        if ($this.ExecutionCount -gt 0) {
            $this.SuccessRate = ($this.SuccessCount / $this.ExecutionCount) * 100
        } else {
            $this.SuccessRate = 0
        }
    }
}

Export-ModuleMember -Cmdlet * -Function * -Variable * -Alias *
