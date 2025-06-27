#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Tool Registry for Pierce County MCP
.DESCRIPTION
    Discovers, validates and executes tools with robust error handling.
#>

using namespace System.Collections.Concurrent
using namespace System.Collections.Generic

enum ToolType {
    PowerShell
    Json
    Native
}

class ToolMetadata {
    [string] $Name
    [string] $Description
    [string] $Version
    [hashtable] $InputSchema
    [hashtable] $OutputSchema
    [string] $FilePath

    ToolMetadata() {
        $this.Version = '1.0.0'
    }
}

class ToolDefinition {
    [string] $Name
    [ToolType] $Type
    [string] $Path
    [ToolMetadata] $Metadata

    ToolDefinition([string]$name,[ToolType]$type,[string]$path,[ToolMetadata]$meta) {
        $this.Name=$name
        $this.Type=$type
        $this.Path=$path
        $this.Metadata=$meta
    }
}

class ToolMetric {
    [string] $ToolName
    [int] $Executions
    [int] $Failures
    [TimeSpan] $TotalDuration

    ToolMetric([string]$name) {
        $this.ToolName = $name
        $this.Executions = 0
        $this.Failures = 0
        $this.TotalDuration = [TimeSpan]::Zero
    }

    [void] Record([bool]$success,[TimeSpan]$duration) {
        $this.Executions++
        $this.TotalDuration = $this.TotalDuration.Add($duration)
        if(-not $success){ $this.Failures++ }
    }
}

class ToolMetrics {
    [ConcurrentDictionary[string,ToolMetric]] $Metrics
    ToolMetrics() { $this.Metrics = [ConcurrentDictionary[string,ToolMetric]]::new() }

    [void] Record([string]$name,[bool]$success,[TimeSpan]$duration) {
        $metric = $this.Metrics.GetOrAdd($name,[ToolMetric]::new($name))
        $metric.Record($success,$duration)
    }
}

class ToolValidator {
    [Logger] $Logger
    ToolValidator([Logger]$logger) { $this.Logger = $logger }

    [ValidationResult] ValidateTool([ToolDefinition]$tool) {
        $result = [ValidationResult]::new()
        if(-not (Test-Path $tool.Path)) { $result.AddError("Tool file not found: $($tool.Path)") }
        if(-not $tool.Metadata.Name) { $result.AddError('Tool name missing') }
        return $result
    }

    [ValidationResult] ValidateParameters([ToolDefinition]$tool,[hashtable]$params) {
        $result = [ValidationResult]::new()
        if(-not $tool.Metadata.InputSchema) { return $result }
        $schema = $tool.Metadata.InputSchema
        if($schema.required) {
            foreach($r in $schema.required) {
                if(-not $params.ContainsKey($r)) { $result.AddError("Missing parameter: $r") }
            }
        }
        return $result
    }
}

class ToolRegistry {
    [Logger] $Logger
    [string] $ToolsDirectory
    [ConcurrentDictionary[string,ToolDefinition]] $Tools
    [ToolValidator] $Validator
    [ToolMetrics] $Metrics

    ToolRegistry([Logger]$logger) {
        $this.Logger = $logger
        $this.ToolsDirectory = Join-Path $PSScriptRoot '..\\..\\tools'
        $this.Tools = [ConcurrentDictionary[string,ToolDefinition]]::new()
        $this.Validator = [ToolValidator]::new($logger)
        $this.Metrics = [ToolMetrics]::new()
        $this.EnsureDirectory()
    }

    hidden [void] EnsureDirectory() {
        if(-not (Test-Path $this.ToolsDirectory)) {
            New-Item -Path $this.ToolsDirectory -ItemType Directory -Force | Out-Null
            $this.Logger.Warning('Tools directory created', @{Path=$this.ToolsDirectory})
        }
    }

    [void] DiscoverTools() {
        try {
            $ps = Get-ChildItem -Path $this.ToolsDirectory -Recurse -Filter '*.ps1' -ErrorAction Stop
            foreach($f in $ps) { $this.RegisterPsTool($f.FullName) }
            $json = Get-ChildItem -Path $this.ToolsDirectory -Recurse -Filter '*.json' -ErrorAction Stop
            foreach($f in $json) { $this.RegisterJsonTool($f.FullName) }
            $this.Logger.Info('Tool discovery complete', @{Count=$this.Tools.Count})
        } catch {
            $this.Logger.Error('Discovery failed', @{Error=$_.Exception.Message})
            throw
        }
    }

    hidden [void] RegisterPsTool([string]$path) {
        try {
            $meta = $this.ParsePsMetadata($path)
            $tool = [ToolDefinition]::new($meta.Name,[ToolType]::PowerShell,$path,$meta)
            $this.Tools[$meta.Name] = $tool
        } catch {
            $this.Logger.Warning('Failed to register PS tool', @{Path=$path; Error=$_.Exception.Message})
        }
    }

    hidden [void] RegisterJsonTool([string]$path) {
        try {
            $d = Get-Content $path -Raw | ConvertFrom-Json
            $meta = [ToolMetadata]::new()
            $meta.Name = $d.name
            $meta.Description = $d.description
            $meta.Version = $d.version
            $meta.InputSchema = $d.inputSchema
            $meta.OutputSchema = $d.outputSchema
            $meta.FilePath = $path
            $tool = [ToolDefinition]::new($meta.Name,[ToolType]::Json,$path,$meta)
            $this.Tools[$meta.Name] = $tool
        } catch {
            $this.Logger.Warning('Failed to register JSON tool', @{Path=$path; Error=$_.Exception.Message})
        }
    }

    hidden [ToolMetadata] ParsePsMetadata([string]$path) {
        $content = Get-Content $path -Raw
        $meta = [ToolMetadata]::new()
        if($content -match 'function\s+([A-Za-z0-9_\\-]+)') { $meta.Name = $matches[1] } else { $meta.Name = [IO.Path]::GetFileNameWithoutExtension($path) }
        if($content -match '\.SYNOPSIS\s*\n\s*(.+?)\n') { $meta.Description = $matches[1].Trim() }
        if($content -match '\.VERSION\s*\n\s*(.+?)\n') { $meta.Version = $matches[1].Trim() }
        $meta.FilePath = $path
        return $meta
    }

    [ToolDefinition] GetTool([string]$name) {
        $tool = $null
        if($this.Tools.TryGetValue($name,[ref]$tool)) { return $tool }
        throw "Tool '$name' not found"
    }

    [string[]] GetAvailableTools() { return @($this.Tools.Keys) }

    [ToolExecutionResult] ExecuteTool([string]$name,[hashtable]$params,[OrchestrationSession]$session) {
        $start = Get-Date
        $result = [ToolExecutionResult]::new($name)
        try {
            $tool = $this.GetTool($name)
            $validation = $this.Validator.ValidateParameters($tool, $params)
            if (-not $validation.IsValid) {
                $result.Status = [ToolExecutionStatus]::Failed
                $result.Error  = "Parameter validation failed: $($validation.Errors -join ', ')"
                return $result
            }

            $output = switch ($tool.Type) {
                ([ToolType]::PowerShell) { $this.RunPsTool($tool, $params) }
                ([ToolType]::Json)       { $this.RunJsonTool($tool, $params) }
                ([ToolType]::Native)     { $this.RunNativeTool($tool, $params) }
                default { throw "Unsupported tool type" }
            }

            $result.Result = $output
            $result.Status = [ToolExecutionStatus]::Completed
            return $result
        } catch {
            $result.Status = [ToolExecutionStatus]::Failed
            $result.Error  = $_.Exception.Message
            throw
        } finally {
            $dur = (Get-Date) - $start
            $this.Metrics.Record($name, $result.Status -eq [ToolExecutionStatus]::Completed, $dur)
            $result.Duration = $dur
        }
    }

    hidden [object] RunPsTool([ToolDefinition]$tool,[hashtable]$params) {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        try {
            $pipeline = $rs.CreatePipeline()
            $block = {
                param($path,$fn,$args)
                . $path
                if(Get-Command $fn -ErrorAction SilentlyContinue) { & $fn @args } else { & $path @args }
            }
            $pipeline.Commands.AddScript($block)
            $pipeline.Commands[0].Parameters.Add('path',$tool.Path)
            $pipeline.Commands[0].Parameters.Add('fn',$tool.Metadata.Name)
            $pipeline.Commands[0].Parameters.Add('args',$params)
            $out = $pipeline.Invoke()
            if($pipeline.Error.Count -gt 0) { throw "PowerShell error: $($pipeline.Error.ReadToEnd() -join ';')" }
            return $out
        } finally {
            $rs.Close(); $rs.Dispose()
        }
    }

    hidden [object] RunJsonTool([ToolDefinition]$tool,[hashtable]$params) {
        $d = Get-Content $tool.Path -Raw | ConvertFrom-Json
        switch($d.executionType) {
            'powershell' {
                $cmd = $d.command
                foreach ($p in $params.GetEnumerator()) {
                    $token = "{{{0}}}" -f $p.Key
                    $cmd = $cmd -replace [Regex]::Escape($token), $p.Value
                }
                return Invoke-Expression $cmd
            }
            'rest' {
                return Invoke-RestMethod -Uri $d.endpoint -Method $d.method -Body ($params | ConvertTo-Json -Depth 3)
            }
            default { throw "Unsupported executionType: $($d.executionType)" }
        }
        return $null
    }
    hidden [object] RunNativeTool([ToolDefinition]$tool,[hashtable]$params) {
        $args = @()
        foreach($p in $params.GetEnumerator()) { $args += "--$($p.Key)"; $args += $p.Value }
        $proc = Start-Process -FilePath $tool.Path -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput -RedirectStandardError
        if($proc.ExitCode -ne 0) { throw "Native tool error: $($proc.StandardError.ReadToEnd())" }
        return $proc.StandardOutput.ReadToEnd()
    }
}

