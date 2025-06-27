#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Agentic Orchestration Engine for Pierce County M365 MCP Server
.DESCRIPTION
    Core orchestration engine that provides:
    - Intelligent request parsing and entity extraction
    - Autonomous tool chaining and workflow orchestration
    - Context persistence and memory management
    - Enterprise-grade security and compliance
    - Self-healing and adaptive capabilities
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0 - Enterprise Agentic Architecture
    Compliance: GCC, SOC2, NIST Cybersecurity Framework
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

class OrchestrationEngine {
    hidden [ConcurrentDictionary[string, object]] $Memory
    hidden [ConcurrentDictionary[string, object]] $Tools
    hidden [ConcurrentDictionary[string, object]] $ActiveSessions
    hidden [Logger] $Logger
    hidden [EntityExtractor] $EntityExtractor
    hidden [ValidationEngine] $ValidationEngine
    hidden [SecurityManager] $SecurityManager
    hidden [ToolRegistry] $ToolRegistry
    hidden [ContextManager] $ContextManager
    hidden [InternalReasoningEngine] $ReasoningEngine
    hidden [ConfidenceEngine] $ConfidenceEngine
    hidden [CodeExecutionEngine] $CodeExecutionEngine
    
    OrchestrationEngine([Logger]$logger) {
        $this.Memory = [ConcurrentDictionary[string, object]]::new()
        $this.Tools = [ConcurrentDictionary[string, object]]::new()
        $this.ActiveSessions = [ConcurrentDictionary[string, object]]::new()
        $this.Logger = $logger
        $this.EntityExtractor = [EntityExtractor]::new($logger)
        $this.ValidationEngine = [ValidationEngine]::new($logger)
        $this.SecurityManager = [SecurityManager]::new($logger)
        $this.ToolRegistry = [ToolRegistry]::new($logger)
        $this.ContextManager = [ContextManager]::new($logger)
        $this.CodeExecutionEngine = [CodeExecutionEngine]::new($logger)
        $this.ReasoningEngine = [InternalReasoningEngine]::new($logger, $this.ContextManager, $this.CodeExecutionEngine)
        $this.ConfidenceEngine = [ConfidenceEngine]::new($logger)
        
        $this.InitializeEngine()
    }
    
    hidden [void] InitializeEngine() {
        $this.Logger.Info("Initializing Enterprise Orchestration Engine")
        
        try {
            # Load organizational context and standards
            $this.LoadOrganizationalContext()
            
            # Initialize tool registry with auto-discovery
            $this.ToolRegistry.DiscoverTools()
            
            # Load persistent memory and context
            $this.ContextManager.LoadPersistedContext()
            
            # Initialize security policies
            $this.SecurityManager.LoadSecurityPolicies()
            
            $this.Logger.Info("Orchestration Engine initialized successfully")
        }
        catch {
            $this.Logger.Error("Failed to initialize Orchestration Engine: $_")
            throw
        }
    }
    
    [OrchestrationResult] ProcessRequest([OrchestrationRequest]$request) {
        $sessionId = [Guid]::NewGuid().ToString()
        $startTime = Get-Date
        
        try {
            $this.Logger.Info("Processing request", @{
                SessionId = $sessionId
                RequestType = $request.Type
                Initiator = $request.Initiator
            })
            
            # Create session context
            $session = [OrchestrationSession]::new($sessionId, $request.Initiator, $startTime)
            $this.ActiveSessions.TryAdd($sessionId, $session)
            
            # Parse and extract entities with intelligent correction
            $extractedEntities = $this.EntityExtractor.ExtractAndNormalize($request.Input, $session)
            $session.AddContext("ExtractedEntities", $extractedEntities)

            # Evaluate extraction confidence
            $scores = @()
            foreach ($list in @($extractedEntities.Users, $extractedEntities.Mailboxes, $extractedEntities.Groups, $extractedEntities.Actions)) {
                foreach ($e in $list) { $scores += $e.ConfidenceScore }
            }
            $avgScore = if ($scores.Count -gt 0) { ($scores | Measure-Object -Average).Average } else { 1 }
            $this.ConfidenceEngine.RegisterOutcome('EntityExtraction', $avgScore -ge 0.95)
            $metrics = $this.ConfidenceEngine.Evaluate('EntityExtraction', 0.95)
            $session.AddContext('EntityExtractionConfidence', $metrics)
            if (-not $metrics.IsHighConfidence) {
                $this.ReasoningEngine.Resolve(@{ Type='LowConfidence'; Stage='EntityExtraction'; Metrics=$metrics }, $session) | Out-Null
            }
            
            # Validate entities against Pierce County standards
            $validationResult = $this.ValidationEngine.ValidateEntities($extractedEntities, $session)
            if (-not $validationResult.IsValid) {
                $reasoning = $this.ReasoningEngine.Resolve(@{
                    Type = 'ValidationFailure'
                    ValidationResult = $validationResult
                    Request = $request
                }, $session)
                $session.AddContext('Reasoning', $reasoning)
                if (-not $reasoning.Resolved) {
                    return [OrchestrationResult]::Failure($sessionId, $validationResult.Errors)
                }
            }

            $this.ConfidenceEngine.RegisterOutcome('Validation', $validationResult.IsValid)
            $valMetrics = $this.ConfidenceEngine.Evaluate('Validation', 0.95)
            $session.AddContext('ValidationConfidence', $valMetrics)
            if (-not $valMetrics.IsHighConfidence) {
                $this.ReasoningEngine.Resolve(@{ Type='LowConfidence'; Stage='Validation'; Metrics=$valMetrics }, $session) | Out-Null
            }
            
            # Determine orchestration strategy
            $orchestrationPlan = $this.CreateOrchestrationPlan($extractedEntities, $session)
            $session.AddContext("OrchestrationPlan", $orchestrationPlan)
            
            # Execute autonomous orchestration
            $executionResult = $this.ExecuteOrchestration($orchestrationPlan, $session)

            $overallSuccess = ($executionResult.Results | Where-Object { $_.Status -eq [ToolExecutionStatus]::Failed }).Count -eq 0
            $this.ConfidenceEngine.RegisterOutcome('Workflow', $overallSuccess)
            $wfMetrics = $this.ConfidenceEngine.Evaluate('Workflow', 0.95)
            $session.AddContext('WorkflowConfidence', $wfMetrics)
            if (-not $wfMetrics.IsHighConfidence) {
                $this.ReasoningEngine.Resolve(@{ Type='LowConfidence'; Stage='Workflow'; Metrics=$wfMetrics }, $session) | Out-Null
            }
            
            # Update memory and context
            $this.UpdateMemoryFromSession($session)
            
            # Create comprehensive result
            $result = [OrchestrationResult]::Success($sessionId, $executionResult)
            $result.ExecutionTime = (Get-Date) - $startTime
            
            return $result
        }
        catch {
            $this.Logger.Error("Request processing failed", @{
                SessionId = $sessionId
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })

            $this.ReasoningEngine.Resolve(@{
                Type = 'ToolError'
                Error = $_.Exception.Message
            }, $session) | Out-Null

            return [OrchestrationResult]::Error($sessionId, $_.Exception.Message)
        }
        finally {
            # Cleanup session
            $this.ActiveSessions.TryRemove($sessionId, [ref]$null)
            
            # Persist context and memory updates
            $this.ContextManager.PersistContext()
        }
    }
    
    hidden [OrchestrationPlan] CreateOrchestrationPlan([EntityCollection]$entities, [OrchestrationSession]$session) {
        $plan = [OrchestrationPlan]::new()
        
        # Analyze intent and determine required tools
        $intent = $this.AnalyzeIntent($entities, $session)
        $plan.Intent = $intent
        
        # Get semantic suggestions from memory bank
        $semanticSuggestions = $this.ContextManager.GetSemanticSuggestions(
            $session.OriginalRequest, 
            $session.SessionId, 
            3
        )
        
        # Incorporate memory insights into planning
        if ($semanticSuggestions.Count -gt 0) {
            $session.AddContext("SemanticSuggestions", $semanticSuggestions)
            $this.Logger.Debug("Applied semantic suggestions to planning", @{
                SuggestionCount = $semanticSuggestions.Count
                SessionId = $session.SessionId
            })
        }
        
        # Map entities to tools with dependency resolution
        $toolChain = $this.ResolveToolChain($intent, $entities, $session)
        $plan.ToolChain = $toolChain
        
        # Add cross-cutting concerns (security, audit, validation)
        $plan.SecurityRequirements = $this.SecurityManager.DetermineRequirements($intent, $entities)
        $plan.AuditRequirements = $this.DetermineAuditRequirements($intent, $entities)
        
        $this.Logger.Debug("Orchestration plan created", @{
            Intent = $intent.Type
            ToolCount = $toolChain.Count
            SessionId = $session.SessionId
        })
        
        return $plan
    }
    
    hidden [OrchestrationResult] ExecuteOrchestration([OrchestrationPlan]$plan, [OrchestrationSession]$session) {
        $results = [List[ToolExecutionResult]]::new()
        $context = [Dictionary[string, object]]::new()
        
        foreach ($toolStep in $plan.ToolChain) {
            try {
                # Pre-execution security check
                $securityCheck = $this.SecurityManager.ValidateToolExecution($toolStep, $context, $session)
                if (-not $securityCheck.IsValid) {
                    throw "Security validation failed: $($securityCheck.Reason)"
                }
                
                # Execute tool with context injection
                $tool = $this.ToolRegistry.GetTool($toolStep.ToolName)
                $executionContext = $this.PrepareExecutionContext($toolStep, $context, $session)
                
                $this.Logger.Debug("Executing tool", @{
                    ToolName = $toolStep.ToolName
                    SessionId = $session.SessionId
                    StepIndex = $toolStep.Index
                })
                
                $toolResult = $tool.Execute($executionContext)
                $results.Add($toolResult)

                # Update context with results for next tool
                $this.UpdateContextFromResult($context, $toolResult)

                # Record execution confidence
                $this.ConfidenceEngine.RegisterOutcome('ToolExecution', $toolResult.Status -eq [ToolExecutionStatus]::Completed)
                $toolMetrics = $this.ConfidenceEngine.Evaluate('ToolExecution', 0.95)
                if (-not $toolMetrics.IsHighConfidence) {
                    $this.ReasoningEngine.Resolve(@{ Type='LowConfidence'; Stage='ToolExecution'; Metrics=$toolMetrics; Tool=$toolStep.ToolName }, $session) | Out-Null
                }
                
                # Check for early termination conditions
                if ($toolResult.Status -eq "Failed" -and $toolStep.IsCritical) {
                    $this.Logger.Warning("Critical tool failed, terminating orchestration", @{
                        ToolName = $toolStep.ToolName
                        Error = $toolResult.Error
                        SessionId = $session.SessionId
                    })
                    break
                }
            }
            catch {
                $this.Logger.Error("Tool execution failed", @{
                    ToolName = $toolStep.ToolName
                    Error = $_.Exception.Message
                    SessionId = $session.SessionId
                })
                
                # Attempt self-healing
                $healingResult = $this.AttemptSelfHealing($toolStep, $_, $session)
                if ($healingResult.Success) {
                    $results.Add($healingResult.Result)
                    $this.UpdateContextFromResult($context, $healingResult.Result)
                } else {
                    throw
                }
            }
        }
        
        return [OrchestrationResult]::new($results, $context)
    }
    
    hidden [void] UpdateMemoryFromSession([OrchestrationSession]$session) {
        try {
            # Store session memory using VectorMemoryBank
            $this.ContextManager.StoreMemoryFromSession($session)
            
            # Extract and store entity relationships
            if ($session.GetContext("ExtractedEntities")) {
                $entities = $session.GetContext("ExtractedEntities")
                $this.ContextManager.StoreEntityRelationships($entities, $session.SessionId)
            }
            
            # Store operational patterns for learning
            $this.AnalyzeAndStoreSessionPatterns($session)
            
            $this.Logger.Debug("Memory updated from session", @{
                SessionId = $session.SessionId
                EntityCount = $session.GetContext("ExtractedEntities")?.Count ?? 0
            })
        }
        catch {
            $this.Logger.Warning("Failed to update memory from session", @{
                SessionId = $session.SessionId
                Error = $_.Exception.Message
            })
        }
    }
    
    hidden [void] AnalyzeAndStoreSessionPatterns([OrchestrationSession]$session) {
        try {
            # Analyze session for operational patterns
            $patterns = @()
            
            # Time-based patterns
            $hour = $session.StartTime.Hour
            if ($hour -lt 8 -or $hour -gt 17) {
                $patterns += @{
                    Type = "OffHoursOperation"
                    Description = "Operation performed outside business hours"
                    Confidence = 0.9
                    Context = "TimePattern"
                }
            }
            
            # User behavior patterns
            $initiator = $session.Initiator
            if ($initiator -match "@piercecountywa\.gov$") {
                $patterns += @{
                    Type = "InternalUserOperation"
                    Description = "Operation initiated by internal user"
                    Confidence = 1.0
                    Context = "UserPattern"
                }
            }
            
            # Store patterns in memory
            foreach ($pattern in $patterns) {
                $this.ContextManager.VectorMemoryBank.StoreMemory(
                    "Pattern: $($pattern.Description)",
                    "SessionPattern",
                    $pattern,
                    $session.SessionId
                )
            }
        }
        catch {
            $this.Logger.Warning("Failed to analyze session patterns", @{
                SessionId = $session.SessionId
                Error = $_.Exception.Message
            })
        }
    }
    
    hidden [void] LoadOrganizationalContext() {
        # Load Pierce County specific configurations
        $orgContext = @{
            Domain = "piercecountywa.gov"
            TenantType = "GCC"
            NamingConventions = @{
                UserEmail = "^[a-z]+\.[a-z]+@piercecountywa\.gov$"
                SharedMailbox = "^[a-z0-9_-]+@piercecountywa\.gov$"
                ResourceMailbox = "^[a-z0-9_-]+@piercecountywa\.gov$"
            }
            ComplianceRequirements = @{
                AuditRetention = "7 years"
                SecurityClassification = "FOUO"
                DataResidency = "US"
            }
            BusinessRules = @{
                ManagerApprovalRequired = @("MailboxAccess", "GroupMembership")
                AutoApproved = @("CalendarPermissions")
                RestrictedOperations = @("AdminRoleAssignment", "ComplianceSearch")
            }
        }
        
        $this.Memory.TryAdd("OrganizationalContext", $orgContext)
    }
    
    hidden [SelfHealingResult] AttemptSelfHealing([ToolStep]$toolStep, [Exception]$error, [OrchestrationSession]$session) {
        $this.Logger.Info("Attempting self-healing", @{
            ToolName = $toolStep.ToolName
            ErrorType = $error.GetType().Name
            SessionId = $session.SessionId
        })
        
        # Implement adaptive error recovery strategies
        $healingStrategies = @(
            [RetryStrategy]::new(3, 1000),
            [FallbackStrategy]::new(),
            [ContextAdjustmentStrategy]::new(),
            [ToolSubstitutionStrategy]::new()
        )
        
        foreach ($strategy in $healingStrategies) {
            try {
                $result = $strategy.Attempt($toolStep, $error, $session, $this)
                if ($result.Success) {
                    $this.Logger.Info("Self-healing successful", @{
                        Strategy = $strategy.GetType().Name
                        ToolName = $toolStep.ToolName
                        SessionId = $session.SessionId
                    })
                    return $result
                }
            }
            catch {
                $this.Logger.Debug("Healing strategy failed", @{
                    Strategy = $strategy.GetType().Name
                    Error = $_.Exception.Message
                })
                continue
            }
        }
        
        return [SelfHealingResult]::Failure("All healing strategies exhausted")
    }
    
    [void] Dispose() {
        $this.Logger.Info("Disposing Orchestration Engine")
        
        # Persist final state
        $this.ContextManager.PersistContext()
        
        # Cleanup resources
        $this.ActiveSessions.Clear()
        $this.Tools.Clear()
        
        if ($this.Logger -is [IDisposable]) {
            $this.Logger.Dispose()
        }
    }
}

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

Export-ModuleMember -Cmdlet * -Function * -Variable * -Alias *
