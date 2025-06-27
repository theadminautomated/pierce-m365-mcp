#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Security Manager for Pierce County M365 Operations
.DESCRIPTION
    Provides comprehensive security validation, threat detection, and 
    compliance enforcement for all M365 operations.
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

class SecurityManager {
    hidden [Logger] $Logger
    hidden [Dictionary[string, SecurityPolicy]] $Policies
    hidden [ConcurrentDictionary[string, SecurityContext]] $ActiveSessions
    hidden [ThreatDetector] $ThreatDetector
    hidden [ComplianceValidator] $ComplianceValidator
    
    SecurityManager([Logger]$logger) {
        $this.Logger = $logger
        $this.Policies = [Dictionary[string, SecurityPolicy]]::new()
        $this.ActiveSessions = [ConcurrentDictionary[string, SecurityContext]]::new()
        $this.ThreatDetector = [ThreatDetector]::new($logger)
        $this.ComplianceValidator = [ComplianceValidator]::new($logger)
        
        $this.LoadSecurityPolicies()
    }
    
    [SecurityValidationResult] ValidateToolExecution([ToolStep]$toolStep, [hashtable]$context, [OrchestrationSession]$session) {
        $this.Logger.Debug("Validating tool execution security", @{
            ToolName = $toolStep.ToolName
            SessionId = $session.SessionId
        })
        
        $result = [SecurityValidationResult]::new()
        
        try {
            # Get or create security context
            $securityContext = $this.GetOrCreateSecurityContext($session)
            
            # Validate against security policies
            $policyValidation = $this.ValidateAgainstPolicies($toolStep, $securityContext)
            $result.AddValidation($policyValidation)
            
            # Threat detection
            $threatAnalysis = $this.ThreatDetector.AnalyzeTool($toolStep, $context, $securityContext)
            $result.AddThreatAnalysis($threatAnalysis)
            
            # Compliance validation
            $complianceCheck = $this.ComplianceValidator.ValidateTool($toolStep, $securityContext)
            $result.AddComplianceValidation($complianceCheck)
            
            # Authorization check
            $authorizationResult = $this.ValidateAuthorization($toolStep, $securityContext)
            $result.AddAuthorizationResult($authorizationResult)
            
            # Update security metrics
            $this.UpdateSecurityMetrics($toolStep, $result, $securityContext)
            
            return $result
        }
        catch {
            $this.Logger.Error("Security validation failed", @{
                ToolName = $toolStep.ToolName
                Error = $_.Exception.Message
                SessionId = $session.SessionId
            })
            
            $result.IsValid = $false
            $result.Reason = "Security validation error: $($_.Exception.Message)"
            return $result
        }
    }
    
    [hashtable] DetermineRequirements([IntentType]$intent, [EntityCollection]$entities) {
        $requirements = @{
            RequiresElevation = $false
            RequiresApproval = $false
            RequiresMultiFactor = $false
            RequiresAudit = $true
            SecurityLevel = "Standard"
            DataClassification = "Internal"
        }
        
        # Determine requirements based on intent
        switch ($intent) {
            ([IntentType]::AccountDeprovisioning) {
                $requirements.RequiresElevation = $true
                $requirements.RequiresApproval = $true
                $requirements.RequiresMultiFactor = $true
                $requirements.SecurityLevel = "High"
                $requirements.DataClassification = "Confidential"
            }
            ([IntentType]::PermissionManagement) {
                $requirements.RequiresApproval = $true
                $requirements.SecurityLevel = "Medium"
            }
            ([IntentType]::ComplianceOperation) {
                $requirements.RequiresElevation = $true
                $requirements.RequiresAudit = $true
                $requirements.SecurityLevel = "High"
                $requirements.DataClassification = "Restricted"
            }
        }
        
        # Adjust based on entities
        foreach ($user in $entities.Users) {
            if ($user.Title -and $this.IsPrivilegedUser($user.Title)) {
                $requirements.RequiresMultiFactor = $true
                $requirements.SecurityLevel = "High"
            }
        }
        
        return $requirements
    }
    
    [void] LoadSecurityPolicies() {
        $this.Logger.Debug("Loading security policies")
        
        # Load Pierce County specific security policies
        # UserProvisioning policy
        $userProvPolicy = [SecurityPolicy]::new(
            'UserProvisioning',
            'Standard user provisioning operations',
            [SecurityLevel]::Medium,
            @('IT-Administrators', 'HR-Managers'),
            $true
        )
        $this.Policies.Add('UserProvisioning', $userProvPolicy)
        
        # AccountDeprovisioning policy
        $deprovPolicy = [SecurityPolicy]::new(
            'AccountDeprovisioning',
            'User account deprovisioning operations',
            [SecurityLevel]::High,
            @('IT-Administrators', 'Security-Officers'),
            $true
        )
        $this.Policies.Add('AccountDeprovisioning', $deprovPolicy)
        
        # PermissionGrant policy
        $permGrantPolicy = [SecurityPolicy]::new(
            'PermissionGrant',
            'Granting permissions to users',
            [SecurityLevel]::Medium,
            @('IT-Administrators', 'Department-Managers'),
            $true
        )
        $this.Policies.Add('PermissionGrant', $permGrantPolicy)
        
        # AdminOperations policy
        $adminOpsPolicy = [SecurityPolicy]::new(
            'AdminOperations',
            'Administrative operations requiring elevated access',
            [SecurityLevel]::Critical,
            @('Global-Administrators'),
            $true
        )
        $this.Policies.Add('AdminOperations', $adminOpsPolicy)
        
        # ComplianceAccess policy
        $compliancePolicy = [SecurityPolicy]::new(
            'ComplianceAccess',
            'Compliance and audit operations',
            [SecurityLevel]::High,
            @('Compliance-Officers', 'Legal-Team'),
            $true
        )
        $this.Policies.Add('ComplianceAccess', $compliancePolicy)
        
        $this.Logger.Info("Security policies loaded", @{
            PolicyCount = $this.Policies.Count
        })
    }
    
    hidden [SecurityContext] GetOrCreateSecurityContext([OrchestrationSession]$session) {
        $context = $null
        if (-not $this.ActiveSessions.TryGetValue($session.SessionId, [ref]$context)) {
            $context = [SecurityContext]::new($session.SessionId, $session.Initiator)
            $this.ActiveSessions.TryAdd($session.SessionId, $context)
        }
        return $context
    }
    
    hidden [PolicyValidationResult] ValidateAgainstPolicies([ToolStep]$toolStep, [SecurityContext]$securityContext) {
        $result = [PolicyValidationResult]::new()
        
        # Determine which policies apply to this tool
        $applicablePolicies = $this.GetApplicablePolicies($toolStep)
        
        foreach ($policy in $applicablePolicies) {
            $policyResult = $this.ValidateAgainstPolicy($toolStep, $policy, $securityContext)
            $result.AddPolicyResult($policy.Name, $policyResult)
        }
        
        return $result
    }
    
    hidden [SecurityPolicy[]] GetApplicablePolicies([ToolStep]$toolStep) {
        $applicablePolicies = @()
        
        # Map tools to policies based on tool name patterns
        $toolName = $toolStep.ToolName.ToLower()
        
        if ($toolName -match 'deprovision|deactivate|terminate') {
            $applicablePolicies += $this.Policies['AccountDeprovisioning']
        }
        
        if ($toolName -match 'permission|grant|access') {
            $applicablePolicies += $this.Policies['PermissionGrant']
        }
        
        if ($toolName -match 'admin|elevate|configure') {
            $applicablePolicies += $this.Policies['AdminOperations']
        }
        
        if ($toolName -match 'compliance|audit|legal') {
            $applicablePolicies += $this.Policies['ComplianceAccess']
        }
        
        # Default to user provisioning policy if no specific match
        if ($applicablePolicies.Count -eq 0) {
            $applicablePolicies += $this.Policies['UserProvisioning']
        }
        
        return $applicablePolicies
    }
    
    hidden [bool] ValidateAgainstPolicy([ToolStep]$toolStep, [SecurityPolicy]$policy, [SecurityContext]$securityContext) {
        # Check if user has required roles
        $hasRequiredRole = $false
        foreach ($requiredRole in $policy.RequiredRoles) {
            if ($this.UserHasRole($securityContext.Initiator, $requiredRole)) {
                $hasRequiredRole = $true
                break
            }
        }
        
        if (-not $hasRequiredRole) {
            $this.Logger.Warning("User lacks required role for policy", @{
                Policy = $policy.Name
                User = $securityContext.Initiator
                RequiredRoles = $policy.RequiredRoles
            })
            return $false
        }
        
        # Check security level requirements
        if ($securityContext.SecurityLevel -lt $policy.MinimumSecurityLevel) {
            $this.Logger.Warning("Security level insufficient for policy", @{
                Policy = $policy.Name
                CurrentLevel = $securityContext.SecurityLevel
                RequiredLevel = $policy.MinimumSecurityLevel
            })
            return $false
        }
        
        # Check if audit is required and enabled
        if ($policy.RequiresAudit -and -not $securityContext.AuditEnabled) {
            $this.Logger.Warning("Audit required but not enabled", @{
                Policy = $policy.Name
                User = $securityContext.Initiator
            })
            return $false
        }
        
        return $true
    }
    
    hidden [AuthorizationResult] ValidateAuthorization([ToolStep]$toolStep, [SecurityContext]$securityContext) {
        $result = [AuthorizationResult]::new()
        
        # Check basic authorization
        if (-not $this.IsUserAuthorized($securityContext.Initiator, $toolStep.ToolName)) {
            $result.IsAuthorized = $false
            $result.Reason = "User not authorized for tool: $($toolStep.ToolName)"
            return $result
        }
        
        # Check parameter-specific authorization
        foreach ($param in $toolStep.Parameters.GetEnumerator()) {
            if (-not $this.IsParameterAuthorized($securityContext.Initiator, $param.Key, $param.Value)) {
                $result.IsAuthorized = $false
                $result.Reason = "User not authorized for parameter: $($param.Key)"
                return $result
            }
        }
        
        # Check time-based restrictions
        if ($this.IsOutsideAllowedTime($securityContext.Initiator, $toolStep.ToolName)) {
            $result.IsAuthorized = $false
            $result.Reason = "Tool execution outside allowed time window"
            return $result
        }

        if (-not $this.ValidateMailboxAssignmentPolicy($toolStep, $securityContext.Initiator)) {
            $result.IsAuthorized = $false
            $result.Reason = 'Mailbox assignment policy violation'
            return $result
        }
        
        $result.IsAuthorized = $true
        $result.AuthorizedAt = Get-Date
        $result.AuthorizedBy = "SecurityManager"
        
        return $result
    }
    
    hidden [bool] UserHasRole([string]$user, [string]$role) {
        # In a real implementation, this would check AD group membership
        # For now, simulate based on email patterns
        $userLower = $user.ToLower()
        
        if ($role -eq 'IT-Administrators') { 
            return $userLower -match 'it\.|admin|tech' 
        }
        elseif ($role -eq 'HR-Managers') { 
            return $userLower -match 'hr\.|human' 
        }
        elseif ($role -eq 'Security-Officers') { 
            return $userLower -match 'security|compliance' 
        }
        elseif ($role -eq 'Global-Administrators') { 
            return $userLower -match 'admin' -and $userLower -match 'global|super' 
        }
        elseif ($role -eq 'Department-Managers') { 
            return $userLower -match 'manager|director|chief' 
        }
        elseif ($role -eq 'Compliance-Officers') { 
            return $userLower -match 'compliance|audit|legal' 
        }
        elseif ($role -eq 'Legal-Team') { 
            return $userLower -match 'legal|counsel|attorney' 
        }
        else {
            return $false
        }
    }
    
    hidden [bool] IsUserAuthorized([string]$user, [string]$toolName) {
        # Basic authorization check - all Pierce County users authorized for basic tools
        if (-not $user.EndsWith('@piercecountywa.gov')) {
            return $false
        }
        
        # Check for restricted tools
        $restrictedTools = @('admin_script', 'compliance_search', 'global_config')
        if ($toolName -in $restrictedTools) {
            return $this.UserHasRole($user, 'Global-Administrators')
        }
        
        return $true
    }
    
    hidden [bool] IsParameterAuthorized([string]$user, [string]$paramName, [object]$paramValue) {
        # Check for sensitive parameters
        $sensitiveParams = @('password', 'secret', 'token', 'key')
        if ($paramName.ToLower() -in $sensitiveParams) {
            return $this.UserHasRole($user, 'IT-Administrators')
        }
        
        # Check for external domain access
        if ($paramName -match 'email|domain' -and $paramValue -is [string] -and -not $paramValue.EndsWith('piercecountywa.gov')) {
            return $this.UserHasRole($user, 'Security-Officers')
        }
        
        return $true
    }
    
    hidden [bool] IsOutsideAllowedTime([string]$user, [string]$toolName) {
        # Check for time-restricted operations
        $now = Get-Date
        $hour = $now.Hour
        
        # Restrict admin operations to business hours (8 AM - 6 PM)
        if ($toolName -match 'admin|config|global' -and ($hour -lt 8 -or $hour -gt 18)) {
            # Unless user is a Global Admin
            return -not $this.UserHasRole($user, 'Global-Administrators')
        }
        
        # Restrict sensitive operations on weekends
        if (($now.DayOfWeek -eq [DayOfWeek]::Saturday -or $now.DayOfWeek -eq [DayOfWeek]::Sunday) -and
            $toolName -match 'deprovision|delete|remove') {
            return -not $this.UserHasRole($user, 'Security-Officers')
        }
        
        return $false
    }

    hidden [bool] ValidateMailboxAssignmentPolicy([ToolStep]$toolStep, [string]$initiator) {
        if ($toolStep.ToolName -ne 'add_mailbox_permissions') { return $true }

        $mailbox = $toolStep.Parameters['Mailbox']
        if (-not $mailbox) { return $true }

        try {
            $mailboxObj = Get-Mailbox -Identity $mailbox -ErrorAction Stop
            if ($mailboxObj.RecipientTypeDetails -eq 'UserMailbox') {
                $ea1 = $this.GetUserExtensionAttribute($initiator, 'extensionAttribute1')
                if ($ea1 -ne '119') { return $false }
            }
        } catch {
            return $false
        }

        return $true
    }

    hidden [string] GetUserExtensionAttribute([string]$user, [string]$attribute) {
        try {
            $adUser = Get-ADUser -Identity $user -Properties $attribute -ErrorAction Stop
            return $adUser.$attribute
        } catch {
            try {
                $mgUser = Get-MgUser -UserId $user -Property $attribute -ErrorAction Stop
                return $mgUser.AdditionalProperties[$attribute]
            } catch {
                return $null
            }
        }
    }
    
    hidden [bool] IsPrivilegedUser([string]$title) {
        $privilegedTitles = @(
            'Administrator', 'Manager', 'Director', 'Chief', 'Officer',
            'Supervisor', 'Lead', 'Senior', 'Principal'
        )
        
        foreach ($privilegedTitle in $privilegedTitles) {
            if ($title -match $privilegedTitle) {
                return $true
            }
        }
        
        return $false
    }
    
    hidden [void] UpdateSecurityMetrics([ToolStep]$toolStep, [SecurityValidationResult]$result, [SecurityContext]$securityContext) {
        # Update security metrics for monitoring and alerting
        $securityContext.IncrementValidationCount()
        
        if (-not $result.IsValid) {
            $securityContext.IncrementFailureCount()
            
            $this.Logger.Warning("Security validation failed", @{
                ToolName = $toolStep.ToolName
                User = $securityContext.Initiator
                Reason = $result.Reason
                ThreatLevel = $result.ThreatLevel
            })
        }
    }
}

# Supporting classes
enum SecurityLevel {
    Low = 1
    Medium = 2
    High = 3
    Critical = 4
}

enum ThreatLevel {
    None = 0
    Low = 1
    Medium = 2
    High = 3
    Critical = 4
}

class SecurityPolicy {
    [string] $Name
    [string] $Description
    [SecurityLevel] $MinimumSecurityLevel
    [string[]] $RequiredRoles
    [bool] $RequiresAudit
    [DateTime] $CreatedDate
    [DateTime] $LastModified
    
    SecurityPolicy([string]$name, [string]$description, [SecurityLevel]$securityLevel, [string[]]$requiredRoles, [bool]$requiresAudit) {
        $this.Name = $name
        $this.Description = $description
        $this.MinimumSecurityLevel = $securityLevel
        $this.RequiredRoles = $requiredRoles
        $this.RequiresAudit = $requiresAudit
        $this.CreatedDate = Get-Date
        $this.LastModified = Get-Date
    }
}

class SecurityContext {
    [string] $SessionId
    [string] $Initiator
    [SecurityLevel] $SecurityLevel
    [bool] $AuditEnabled
    [DateTime] $CreatedAt
    [int] $ValidationCount
    [int] $FailureCount
    [List[string]] $ViolationHistory
    
    SecurityContext([string]$sessionId, [string]$initiator) {
        $this.SessionId = $sessionId
        $this.Initiator = $initiator
        $this.SecurityLevel = [SecurityLevel]::Medium
        $this.AuditEnabled = $true
        $this.CreatedAt = Get-Date
        $this.ValidationCount = 0
        $this.FailureCount = 0
        $this.ViolationHistory = [List[string]]::new()
    }
    
    [void] IncrementValidationCount() {
        $this.ValidationCount++
    }
    
    [void] IncrementFailureCount() {
        $this.FailureCount++
    }
    
    [void] AddViolation([string]$violation) {
        $this.ViolationHistory.Add($violation)
    }
}

class SecurityValidationResult {
    [bool] $IsValid
    [string] $Reason
    [ThreatLevel] $ThreatLevel
    [PolicyValidationResult] $PolicyValidation
    [ThreatAnalysisResult] $ThreatAnalysis
    [ComplianceValidationResult] $ComplianceValidation
    [AuthorizationResult] $AuthorizationResult
    [DateTime] $ValidatedAt
    
    SecurityValidationResult() {
        $this.IsValid = $true
        $this.ThreatLevel = [ThreatLevel]::None
        $this.ValidatedAt = Get-Date
    }
    
    [void] AddValidation([PolicyValidationResult]$policyValidation) {
        $this.PolicyValidation = $policyValidation
        if (-not $policyValidation.IsValid) {
            $this.IsValid = $false
            $this.Reason = "Policy validation failed"
        }
    }
    
    [void] AddThreatAnalysis([ThreatAnalysisResult]$threatAnalysis) {
        $this.ThreatAnalysis = $threatAnalysis
        $this.ThreatLevel = $threatAnalysis.ThreatLevel
        
        if ($threatAnalysis.ThreatLevel -ge [ThreatLevel]::High) {
            $this.IsValid = $false
            $this.Reason = "High threat level detected"
        }
    }
    
    [void] AddComplianceValidation([ComplianceValidationResult]$complianceValidation) {
        $this.ComplianceValidation = $complianceValidation
        if (-not $complianceValidation.IsCompliant) {
            $this.IsValid = $false
            $this.Reason = "Compliance validation failed"
        }
    }
    
    [void] AddAuthorizationResult([AuthorizationResult]$authorizationResult) {
        $this.AuthorizationResult = $authorizationResult
        if (-not $authorizationResult.IsAuthorized) {
            $this.IsValid = $false
            $this.Reason = $authorizationResult.Reason
        }
    }
}

class PolicyValidationResult {
    [bool] $IsValid
    [Dictionary[string, bool]] $PolicyResults
    [List[string]] $Violations
    
    PolicyValidationResult() {
        $this.IsValid = $true
        $this.PolicyResults = [Dictionary[string, bool]]::new()
        $this.Violations = [List[string]]::new()
    }
    
    [void] AddPolicyResult([string]$policyName, [bool]$result) {
        $this.PolicyResults.Add($policyName, $result)
        if (-not $result) {
            $this.IsValid = $false
            $this.Violations.Add("Policy violation: $policyName")
        }
    }
}

class AuthorizationResult {
    [bool] $IsAuthorized
    [string] $Reason
    [DateTime] $AuthorizedAt
    [string] $AuthorizedBy
    
    AuthorizationResult() {
        $this.IsAuthorized = $false
    }
}

# Threat detection and compliance classes would be implemented similarly
class ThreatDetector {
    hidden [Logger] $Logger
    
    ThreatDetector([Logger]$logger) {
        $this.Logger = $logger
    }
    
    [ThreatAnalysisResult] AnalyzeTool([ToolStep]$toolStep, [hashtable]$context, [SecurityContext]$securityContext) {
        $result = [ThreatAnalysisResult]::new()
        
        # Simple threat analysis based on patterns
        $toolName = $toolStep.ToolName.ToLower()
        
        if ($toolName -match 'delete|remove|deprovision' -and $toolStep.Parameters.Count -gt 10) {
            $result.ThreatLevel = [ThreatLevel]::Medium
            $result.Indicators.Add("Bulk deletion operation detected")
        }
        
        if ($securityContext.FailureCount -gt 5) {
            $result.ThreatLevel = [ThreatLevel]::High
            $result.Indicators.Add("Multiple security failures detected")
        }
        
        return $result
    }
}

class ThreatAnalysisResult {
    [ThreatLevel] $ThreatLevel
    [List[string]] $Indicators
    [List[string]] $Recommendations
    
    ThreatAnalysisResult() {
        $this.ThreatLevel = [ThreatLevel]::None
        $this.Indicators = [List[string]]::new()
        $this.Recommendations = [List[string]]::new()
    }
}

class ComplianceValidator {
    hidden [Logger] $Logger
    
    ComplianceValidator([Logger]$logger) {
        $this.Logger = $logger
    }
    
    [ComplianceValidationResult] ValidateTool([ToolStep]$toolStep, [SecurityContext]$securityContext) {
        $result = [ComplianceValidationResult]::new()
        
        # GCC compliance checks
        $result.IsCompliant = $true
        $result.Framework = "GCC"
        
        # Check data residency
        if ($toolStep.Parameters.ContainsKey('ExternalEmail')) {
            $externalEmail = $toolStep.Parameters['ExternalEmail']
            if ($externalEmail -and -not $externalEmail.EndsWith('.gov')) {
                $result.IsCompliant = $false
                $result.Violations.Add("External email not from government domain")
            }
        }
        
        return $result
    }
}

class ComplianceValidationResult {
    [bool] $IsCompliant
    [string] $Framework
    [List[string]] $Violations
    [List[string]] $Requirements
    
    ComplianceValidationResult() {
        $this.IsCompliant = $true
        $this.Violations = [List[string]]::new()
        $this.Requirements = [List[string]]::new()
    }
}

# Supporting classes for SecurityManager
enum IntentType {
    UserProvisioning = 0
    AccountDeprovisioning = 1
    PermissionManagement = 2
    ComplianceOperation = 3
    DataAccess = 4
    SystemAdministration = 5
}

class ToolStep {
    [string] $Id
    [string] $ToolName
    [hashtable] $Parameters
    [string] $Description
    
    ToolStep([string]$toolName, [hashtable]$parameters) {
        $this.Id = [Guid]::NewGuid().ToString()
        $this.ToolName = $toolName
        $this.Parameters = $parameters ?? @{}
        $this.Description = "Execute $toolName"
    }
}
