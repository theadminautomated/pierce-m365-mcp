#Requires -Version 7.0

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# Supporting classes and enums
enum IntentType {
    AccountProvisioning
    AccountDeprovisioning
    PermissionManagement
    GroupManagement
    ResourceManagement
    ComplianceOperation
    ReportingAnalytics
    SystemMaintenance
}

enum ToolExecutionStatus {
    Pending
    Running
    Completed
    Failed
    Skipped
    Retrying
}

class OrchestrationRequest {
    [string] $Type
    [string] $Input
    [string] $Initiator
    [datetime] $Timestamp
    [hashtable] $Metadata

    OrchestrationRequest([string]$input, [string]$initiator) {
        $this.Input = $input
        $this.Initiator = $initiator
        $this.Timestamp = Get-Date
        $this.Metadata = @{}
    }
}

class OrchestrationResult {
    [string] $SessionId
    [bool] $Success
    [string] $Status
    [object[]] $Results
    [string[]] $Errors
    [timespan] $ExecutionTime
    [hashtable] $Metadata

    static [OrchestrationResult] Success([string]$sessionId, [object]$result) {
        $or = [OrchestrationResult]::new()
        $or.SessionId = $sessionId
        $or.Success = $true
        $or.Status = "Success"
        $or.Results = @($result)
        $or.Errors = @()
        $or.Metadata = @{}
        return $or
    }

    static [OrchestrationResult] Failure([string]$sessionId, [string[]]$errors) {
        $or = [OrchestrationResult]::new()
        $or.SessionId = $sessionId
        $or.Success = $false
        $or.Status = "Failed"
        $or.Results = @()
        $or.Errors = $errors
        $or.Metadata = @{}
        return $or
    }

    static [OrchestrationResult] Error([string]$sessionId, [string]$error) {
        $or = [OrchestrationResult]::new()
        $or.SessionId = $sessionId
        $or.Success = $false
        $or.Status = "Error"
        $or.Results = @()
        $or.Errors = @($error)
        $or.Metadata = @{}
        return $or
    }
}

class OrchestrationSession {
    [string] $SessionId
    [string] $Initiator
    [datetime] $StartTime
    [ConcurrentDictionary[string, object]] $Context
    [List[string]] $AuditTrail

    OrchestrationSession([string]$sessionId, [string]$initiator, [datetime]$startTime) {
        $this.SessionId = $sessionId
        $this.Initiator = $initiator
        $this.StartTime = $startTime
        $this.Context = [ConcurrentDictionary[string, object]]::new()
        $this.AuditTrail = [List[string]]::new()
    }

    [void] AddContext([string]$key, [object]$value) {
        $this.Context.TryAdd($key, $value)
        $this.AuditTrail.Add("Context added: $key")
    }

    [object] GetContext([string]$key) {
        $value = $null
        $this.Context.TryGetValue($key, [ref]$value)
        return $value
    }
}

class OrchestrationPlan {
    [IntentType] $Intent
    [List[ToolStep]] $ToolChain
    [hashtable] $SecurityRequirements
    [hashtable] $AuditRequirements
    [datetime] $CreatedAt

    OrchestrationPlan() {
        $this.ToolChain = [List[ToolStep]]::new()
        $this.SecurityRequirements = @{}
        $this.AuditRequirements = @{}
        $this.CreatedAt = Get-Date
    }
}

class ToolStep {
    [int] $Index
    [string] $ToolName
    [hashtable] $Parameters
    [bool] $IsCritical
    [string[]] $Dependencies
    [hashtable] $ExecutionContext

    ToolStep([string]$toolName, [hashtable]$parameters) {
        $this.ToolName = $toolName
        $this.Parameters = $parameters
        $this.IsCritical = $true
        $this.Dependencies = @()
        $this.ExecutionContext = @{}
    }
}

class ToolExecutionResult {
    [string] $ToolName
    [ToolExecutionStatus] $Status
    [object] $Result
    [string] $Error
    [timespan] $Duration
    [hashtable] $Metadata

    ToolExecutionResult([string]$toolName) {
        $this.ToolName = $toolName
        $this.Status = [ToolExecutionStatus]::Pending
        $this.Metadata = @{}
    }
}

class SelfHealingResult {
    [bool] $Success
    [ToolExecutionResult] $Result
    [string] $Reason
    [string] $Strategy

    static [SelfHealingResult] Success([ToolExecutionResult]$result, [string]$strategy) {
        $shr = [SelfHealingResult]::new()
        $shr.Success = $true
        $shr.Result = $result
        $shr.Strategy = $strategy
        return $shr
    }

    static [SelfHealingResult] Failure([string]$reason) {
        $shr = [SelfHealingResult]::new()
        $shr.Success = $false
        $shr.Reason = $reason
        return $shr
    }
}
