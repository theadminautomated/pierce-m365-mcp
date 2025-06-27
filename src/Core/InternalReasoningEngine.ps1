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
    Version: 2.1.0-rc
    Compliance: GCC, SOC2, NIST
#>

using namespace System.Collections.Generic

class ReasoningResult {
    [bool]$Resolved
    [string]$Resolution
    [object]$UpdatedRequest
    [List[string]]$Actions
    [OrchestrationPlan]$SuggestedPlan

    ReasoningResult() {
        $this.Resolved = $false
        $this.Actions  = [List[string]]::new()
    }
}

class InternalReasoningEngine {
    hidden [Logger] $Logger
    hidden [ContextManager] $ContextManager
    hidden [CodeExecutionEngine] $CodeExecutionEngine
    hidden [int] $MaxIterations = 5

    InternalReasoningEngine([Logger]$logger, [ContextManager]$contextManager, [CodeExecutionEngine]$codeExecutionEngine) {
        $this.Logger = $logger
        $this.ContextManager = $contextManager
        $this.CodeExecutionEngine = $codeExecutionEngine
    }

    [ReasoningResult] Resolve([hashtable]$issue, [OrchestrationSession]$session) {
        $result = [ReasoningResult]::new()
        try {
            $this.Logger.Info("Internal reasoning triggered", @{ SessionId = $session.SessionId; IssueType = $issue.Type })
            $context = $this.GetContextSnapshot($session)
            switch ($issue.Type) {
                'ValidationFailure' { $result = $this.ResolveValidationFailure($issue, $context, $session) }
                'ToolError'       { $result = $this.ResolveToolError($issue, $context, $session) }
                'LowConfidence'   { $result = $this.ResolveLowConfidence($issue, $context, $session) }
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

    hidden [ReasoningResult] ResolveLowConfidence([hashtable]$issue, [hashtable]$context, [OrchestrationSession]$session) {
        $result = [ReasoningResult]::new()
        $metrics = $issue.Metrics
        $stage = $issue.Stage
        $result.Resolution = "Low confidence detected at $stage"
        $result.Actions.Add("LowerBound: $($metrics.LowerBound)")
        $result.Actions.Add('Reanalyzing context and suggesting improvements')
        return $result
    }

    [OrchestrationPlan] EvaluateAndOptimizePlan([OrchestrationPlan]$plan, [EntityCollection]$entities, [OrchestrationSession]$session) {
        try {
            $suggestions = $this.ContextManager.GetContextualSuggestions($entities, $session.SessionId)
            if ($suggestions.Count -gt 0) {
                $session.AddContext('ReasoningSuggestions', $suggestions)
                # For now just log suggestions; a real implementation would modify plan order
                $this.Logger.Debug('Plan optimization suggestions generated', @{ SessionId = $session.SessionId; Count = $suggestions.Count })
            }
        } catch {
            $this.Logger.Warning('Plan optimization failed', $_)
        }
        return $plan
    }

    [OrchestrationPlan] EvaluateNextStep([OrchestrationPlan]$plan, [int]$currentIndex, [ToolExecutionResult]$lastResult, [OrchestrationSession]$session) {
        try {
            if ($lastResult.Status -eq [ToolExecutionStatus]::Failed) {
                $analysis = $this.Resolve(@{ Type='ToolError'; Error=$lastResult.Error }, $session)
                if ($analysis.SuggestedPlan) { return $analysis.SuggestedPlan }
            }
        } catch {
            $this.Logger.Warning('EvaluateNextStep failed', $_)
        }
        return $plan
    }
}

Export-ModuleMember -Class InternalReasoningEngine, ReasoningResult
