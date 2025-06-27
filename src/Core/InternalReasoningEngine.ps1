#Requires -Version 7.0
<#
.SYNOPSIS
    Internal Reasoning Engine for Pierce County MCP Server
.DESCRIPTION
    Provides automatic reasoning and resolution for ambiguous input, validation failures,
    and unexpected errors. Aggregates context from the current session, vector memory,
    and tool output to determine corrective actions.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Compliance: GCC, SOC2, NIST
#>

using namespace System.Collections.Generic

class ReasoningResult {
    [bool]$Resolved
    [string]$Resolution
    [object]$UpdatedRequest
    [List[string]]$Actions

    ReasoningResult() {
        $this.Resolved = $false
        $this.Actions  = [List[string]]::new()
    }
}

class InternalReasoningEngine {
    hidden [Logger] $Logger
    hidden [ContextManager] $ContextManager
    hidden [int] $MaxIterations = 5

    InternalReasoningEngine([Logger]$logger, [ContextManager]$contextManager) {
        $this.Logger = $logger
        $this.ContextManager = $contextManager
    }

    [ReasoningResult] Resolve([hashtable]$issue, [OrchestrationSession]$session) {
        $result = [ReasoningResult]::new()
        try {
            $this.Logger.Info("Internal reasoning triggered", @{ SessionId = $session.SessionId; IssueType = $issue.Type })
            $context = $this.GetContextSnapshot($session)
            switch ($issue.Type) {
                'ValidationFailure' { $result = $this.ResolveValidationFailure($issue, $context, $session) }
                'ToolError'       { $result = $this.ResolveToolError($issue, $context, $session) }
                default           { $result.Resolution = 'Unknown issue type' }
            }
            $metadata = @{ Type = $issue.Type; Session = $session.SessionId }
            $this.ContextManager.VectorMemoryBank.StoreMemory(
                "Reasoning result: $($result.Resolution)",
                'InternalReasoning',
                $metadata,
                $session.SessionId
            ) | Out-Null
        } catch {
            $this.Logger.Error('Internal reasoning failure', $_)
            $result.Resolution = $_.Exception.Message
        }
        return $result
    }

    hidden [hashtable] GetContextSnapshot([OrchestrationSession]$session) {
        $conversation = $this.ContextManager.VectorMemoryBank.GetConversationContext($session.SessionId)
        return @{ Session = $session.Context; History = $conversation }
    }

    hidden [ReasoningResult] ResolveValidationFailure([hashtable]$issue, [hashtable]$context, [OrchestrationSession]$session) {
        $result = [ReasoningResult]::new()
        $errors = $issue.ValidationResult.Errors
        if ($errors.Count -eq 0 -and $issue.ValidationResult.Warnings.Count -gt 0) {
            $result.Resolved = $true
            $result.Resolution = 'Validation warnings acknowledged'
        } else {
            $result.Resolution = 'Unable to auto-resolve validation errors'
        }
        $result.Actions.Add("Validation errors: $($errors -join '; ')")
        return $result
    }

    hidden [ReasoningResult] ResolveToolError([hashtable]$issue, [hashtable]$context, [OrchestrationSession]$session) {
        $result = [ReasoningResult]::new()
        $result.Resolution = 'Tool execution error analyzed'
        $result.Actions.Add("Error: $($issue.Error)")
        return $result
    }
}

Export-ModuleMember -Class InternalReasoningEngine, ReasoningResult
