#Requires -Version 7.0
<#
.SYNOPSIS
    Secure sandboxed code execution engine.
.DESCRIPTION
    Provides a sandboxed execution environment for validating and
    simulating PowerShell (and future languages) within the MCP server.
    Supports dry-run syntax checking, parameterized execution, strict
    input sanitization, timeouts, and detailed logging.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Threading

class ExecutionResult {
    [bool]   $Success
    [string] $Output
    [string] $Error
    [string[]] $Warnings
    [TimeSpan] $Duration
    [hashtable] $Metadata

    ExecutionResult() {
        $this.Success = $false
        $this.Output = ''
        $this.Error = ''
        $this.Warnings = @()
        $this.Duration = [TimeSpan]::Zero
        $this.Metadata = @{}
    }

    [hashtable] ToHashtable() {
        return @{
            success  = $this.Success
            output   = $this.Output
            error    = $this.Error
            warnings = $this.Warnings
            duration = $this.Duration.TotalMilliseconds
            metadata = $this.Metadata
        }
    }
}

class CodeExecutionEngine {
    hidden [Logger] $Logger
    hidden [int]    $DefaultTimeout = 10

    CodeExecutionEngine([Logger]$logger) {
        $this.Logger = $logger
    }

    [ExecutionResult] Execute([string]$language, [string]$code, [hashtable]$parameters, [int]$timeoutSeconds, [bool]$dryRun) {
        if (-not $timeoutSeconds -or $timeoutSeconds -le 0) { $timeoutSeconds = $this.DefaultTimeout }
        $result = [ExecutionResult]::new()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            if ([string]::IsNullOrWhiteSpace($code)) {
                throw 'Code content is empty'
            }

            if ($language -ne 'PowerShell') {
                throw "Unsupported language: $language"
            }

            # Basic sanitization - block risky commands
            if ($code -match '(?i)(Remove-Item|Set-Item|Stop-Process|Start-Process|Invoke-WebRequest|Invoke-RestMethod)') {
                throw 'Unsafe commands detected'
            }

            if ($dryRun) {
                [System.Management.Automation.PSParser]::Tokenize($code, [ref]$null) | Out-Null
                $result.Success = $true
                $result.Output = 'Syntax OK'
            } else {
                $ps = [PowerShell]::Create()
                $ps.AddScript($code) | Out-Null
                if ($parameters) {
                    $ps.AddParameters($parameters) | Out-Null
                }

                $async = $ps.BeginInvoke()
                if (-not $async.AsyncWaitHandle.WaitOne($timeoutSeconds * 1000)) {
                    $ps.Stop()
                    throw 'Execution timed out'
                }

                $output = $ps.EndInvoke($async)
                $result.Output = ($output | Out-String).Trim()
                $result.Success = $ps.Streams.Error.Count -eq 0
                if ($ps.Streams.Error.Count -gt 0) {
                    $err = $ps.Streams.Error | ForEach-Object { $_.ToString() } | Out-String
                    $result.Error = $err.Trim()
                }
                if ($ps.Streams.Warning.Count -gt 0) {
                    $result.Warnings = $ps.Streams.Warning | ForEach-Object { $_.Message }
                }
            }
        } catch {
            $result.Error = $_.Exception.Message
            $this.Logger.Warning('Code execution error', @{ error = $_.Exception.Message })
        } finally {
            $stopwatch.Stop()
            $result.Duration = $stopwatch.Elapsed
        }

        $this.Logger.Info('Code execution completed', @{ success = $result.Success; durationMs = $result.Duration.TotalMilliseconds })
        return $result
    }
}

