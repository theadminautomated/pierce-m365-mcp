#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Validation Engine for Pierce County M365 Operations
.DESCRIPTION
    Provides comprehensive validation, security checks, and compliance
    verification for all M365 operations with Pierce County standards.
#>

using namespace System.Collections.Generic
using namespace System.Text.RegularExpressions

class ValidationEngine {
    hidden [Logger] $Logger
    hidden [Dictionary[string, ValidationRule]] $Rules
    hidden [Dictionary[string, object]] $OrganizationalPolicies
    hidden [Dictionary[string, object]] $ComplianceRequirements
    
    ValidationEngine([Logger]$logger) {
        $this.Logger = $logger
        $this.Rules = [Dictionary[string, ValidationRule]]::new()
        $this.InitializeValidationRules()
        $this.LoadOrganizationalPolicies()
        $this.LoadComplianceRequirements()
    }
    
    [ValidationResult] ValidateEntities([EntityCollection]$entities, [OrchestrationSession]$session) {
        $this.Logger.Debug("Starting entity validation", @{
            SessionId = $session.SessionId
            EntityCount = ($entities.Users.Count + $entities.Mailboxes.Count + $entities.Groups.Count)
        })
        
        $result = [ValidationResult]::new()
        
        try {
            # Validate users
            foreach ($user in $entities.Users) {
                $userValidation = $this.ValidateUser($user, $session)
                $result.AddUserValidation($user.Email, $userValidation)
            }
            
            # Validate mailboxes
            foreach ($mailbox in $entities.Mailboxes) {
                $mailboxValidation = $this.ValidateMailbox($mailbox, $session)
                $result.AddMailboxValidation($mailbox.Email, $mailboxValidation)
            }
            
            # Validate groups
            foreach ($group in $entities.Groups) {
                $groupValidation = $this.ValidateGroup($group, $session)
                $result.AddGroupValidation($group.Name, $groupValidation)
            }
            
            # Validate actions
            foreach ($action in $entities.Actions) {
                $actionValidation = $this.ValidateAction($action, $entities, $session)
                $result.AddActionValidation($action.Type.ToString(), $actionValidation)
            }
            
            # Validate cross-entity relationships
            $relationshipValidation = $this.ValidateEntityRelationships($entities, $session)
            $result.AddRelationshipValidation($relationshipValidation)
            
            # Apply business rules
            $businessRuleValidation = $this.ValidateBusinessRules($entities, $session)
            $result.AddBusinessRuleValidation($businessRuleValidation)
            
            # Compliance checks
            $complianceValidation = $this.ValidateCompliance($entities, $session)
            $result.AddComplianceValidation($complianceValidation)
            
            $this.Logger.Info("Entity validation completed", @{
                SessionId = $session.SessionId
                IsValid = $result.IsValid
                ErrorCount = $result.Errors.Count
                WarningCount = $result.Warnings.Count
            })
            
            return $result
        }
        catch {
            $this.Logger.Error("Entity validation failed", @{
                Error = $_.Exception.Message
                SessionId = $session.SessionId
            })
            
            $result.AddError("Validation process failed: $($_.Exception.Message)")
            return $result
        }
    }
    
    hidden [EntityValidationResult] ValidateUser([UserEntity]$user, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("User", $user.Email)
        
        # Email format validation
        # TODO: Rare but valid email conventions: Admin accounts "sameAccountName_ADM@piercecountywa.gov - e.g., jtaylo7_adm@piercecountywa.gov"
        if (-not $this.Rules['UserEmailFormat'].Validate($user.Email)) {
            $validation.AddError("Invalid email format for Pierce County users")
        }
        
        # Domain validation
        if (-not $user.Email.EndsWith('@piercecountywa.gov')) {
            $validation.AddError("User email must be from piercecountywa.gov domain")
        }
        
        # Username format validation
        $localPart = $user.Email.Split('@')[0]
        if (-not ($localPart -match '^[a-z]+\.[a-z]+$')) {
            $validation.AddError("Email local part must follow firstname.lastname format")
        }
        
        # Display name validation
        if ($user.DisplayName -and -not $this.Rules['DisplayName'].Validate($user.DisplayName)) {
            $validation.AddWarning("Display name contains invalid characters")
        }
        
        # Department validation
        if ($user.Department -and -not $this.IsValidDepartment($user.Department)) {
            $validation.AddWarning("Department not found in organizational structure")
        }
        
        # Check for prohibited characters
        if ($user.Email -match '[A-Z]') {
            $validation.AddError("Email addresses must be lowercase")
        }
        
        # Length validation
        if ($user.Email.Length -gt 320) {
            $validation.AddError("Email address exceeds maximum length")
        }
        
        # Special character validation
        if ($localPart -match '[^a-z.]') {
            $validation.AddError("Email local part contains invalid characters")
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateMailbox([MailboxEntity]$mailbox, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("Mailbox", $mailbox.Email)
        
        # Email format validation
        if (-not $this.Rules['MailboxEmailFormat'].Validate($mailbox.Email)) {
            $validation.AddError("Invalid mailbox email format")
        }
        
        # Type-specific validation
        switch ($mailbox.Type) {
            [MailboxType]::Shared {
                if (-not $this.Rules['SharedMailboxNaming'].Validate($mailbox.Email)) {
                    $validation.AddError("Shared mailbox name does not follow naming conventions")
                }
            }
            [MailboxType]::Resource {
                if (-not $this.Rules['ResourceMailboxNaming'].Validate($mailbox.Email)) {
                    $validation.AddError("Resource mailbox name does not follow naming conventions")
                }
            }
            [MailboxType]::Equipment {
                if (-not ($mailbox.Email -match 'equipment|equip')) {
                    $validation.AddWarning("Equipment mailbox should include 'equipment' or 'equip' in name")
                }
            }
            [MailboxType]::Room {
                if (-not ($mailbox.Email -match 'room|conf|meeting')) {
                    $validation.AddWarning("Room mailbox should include room/conference indicator in name")
                }
            }
        }
        
        # Display name validation
        if ($mailbox.DisplayName -and $mailbox.DisplayName.Length -gt 256) {
            $validation.AddError("Mailbox display name exceeds maximum length")
        }
        
        # Alias validation
        if ($mailbox.Alias -and -not $this.Rules['MailboxAlias'].Validate($mailbox.Alias)) {
            $validation.AddError("Mailbox alias contains invalid characters")
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateGroup([GroupEntity]$group, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("Group", $group.Name)
        
        # Name validation
        if (-not $this.Rules['GroupName'].Validate($group.Name)) {
            $validation.AddError("Group name contains invalid characters or format")
        }
        
        # Email validation (if present)
        if ($group.Email -and -not $this.Rules['GroupEmail'].Validate($group.Email)) {
            $validation.AddError("Group email format is invalid")
        }
        
        # Type validation
        $validGroupTypes = @('Distribution', 'Security', 'Microsoft365', 'MailEnabledSecurity')
        if ($group.Type -and $group.Type -notin $validGroupTypes) {
            $validation.AddError("Invalid group type specified")
        }
        
        # Members validation
        foreach ($member in $group.Members) {
            if (-not $this.Rules['UserEmailFormat'].Validate($member)) {
                $validation.AddWarning("Invalid member email format: $member")
            }
        }
        
        # Owners validation
        foreach ($owner in $group.Owners) {
            if (-not $this.Rules['UserEmailFormat'].Validate($owner)) {
                $validation.AddError("Invalid owner email format: $owner")
            }
        }
        
        # Business rule: Groups must have at least one owner
        if ($group.Owners.Count -eq 0) {
            $validation.AddError("Groups must have at least one owner")
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateAction([ActionEntity]$action, [EntityCollection]$entities, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("Action", $action.Type.ToString())
        
        # Validate action has required context
        if ([string]::IsNullOrWhiteSpace($action.Context)) {
            $validation.AddWarning("Action lacks sufficient context")
        }
        
        # Validate action has related entities
        $hasRelatedEntities = $action.RelatedUsers.Count -gt 0 -or $action.RelatedPermissions.Count -gt 0
        if (-not $hasRelatedEntities) {
            $validation.AddError("Action must have related users or permissions")
        }
        
        # Type-specific validation
        switch ($action.Type) {
            [ActionType]::Grant {
                if ($action.RelatedPermissions.Count -eq 0) {
                    $validation.AddError("Grant action must specify permissions to grant")
                }
            }
            [ActionType]::Revoke {
                if ($action.RelatedPermissions.Count -eq 0) {
                    $validation.AddError("Revoke action must specify permissions to revoke")
                }
            }
            [ActionType]::Create {
                # Create actions should have naming requirements
                if ($entities.Mailboxes.Count -eq 0 -and $entities.Groups.Count -eq 0) {
                    $validation.AddError("Create action must specify what to create")
                }
            }
            [ActionType]::Deprovision {
                if ($action.RelatedUsers.Count -eq 0) {
                    $validation.AddError("Deprovision action must specify users to deprovision")
                }
                # Deprovision requires approval
                $action.RequiresApproval = $true
                $action.ApprovalReason = "User deprovisioning requires manager approval"
            }
        }
        
        # Security validation
        $privilegedActions = @([ActionType]::Create, [ActionType]::Deprovision, [ActionType]::Modify)
        if ($action.Type -in $privilegedActions) {
            $initiator = $session.Initiator
            if (-not $this.IsAuthorizedForPrivilegedAction($initiator, $action.Type)) {
                $validation.AddError("Initiator not authorized for privileged action: $($action.Type)")
            }
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateEntityRelationships([EntityCollection]$entities, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("Relationships", "Cross-Entity")
        
        # Validate user-action relationships
        foreach ($action in $entities.Actions) {
            foreach ($user in $action.RelatedUsers) {
                # Check if user exists in the entity collection
                $userExists = $entities.Users | Where-Object { $_.Email -eq $user.Email }
                if (-not $userExists) {
                    $validation.AddWarning("Action references user not in current context: $($user.Email)")
                }
            }
        }
        
        # Validate mailbox ownership
        # TODO: Do not consider mailbox ownership. Consider who the department of who is requesting access and the department of the accessed mailbox (via dept. ID). UNLESS the requester's extentionattribute1 value is 119.
        foreach ($mailbox in $entities.Mailboxes) {
            if ($mailbox.Owner) {
                $ownerExists = $entities.Users | Where-Object { $_.Email -eq $mailbox.Owner }
                if (-not $ownerExists) {
                    $validation.AddWarning("Mailbox owner not found in context: $($mailbox.Owner)")
                }
            }
        }
        
        # Validate group membership consistency
        foreach ($group in $entities.Groups) {
            # Check that all members are valid users
            foreach ($member in $group.Members) {
                if (-not $this.Rules['UserEmailFormat'].Validate($member)) {
                    $validation.AddError("Invalid group member email: $member")
                }
            }
            
            # Check that owners are also members (business rule)
            foreach ($owner in $group.Owners) {
                if ($owner -notin $group.Members) {
                    $validation.AddWarning("Group owner should also be a member: $owner")
                }
            }
        }
        
        # Validate permission-target relationships
        foreach ($permission in $entities.Permissions) {
            if ($permission.Target) {
                $targetExists = $entities.Mailboxes | Where-Object { $_.Email -eq $permission.Target }
                if (-not $targetExists) {
                    $validation.AddWarning("Permission target not found in context: $($permission.Target)")
                }
            }
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateBusinessRules([EntityCollection]$entities, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("BusinessRules", "Pierce County")
        
        # Rule: No external domain access
        foreach ($user in $entities.Users) {
            if (-not $user.Email.EndsWith('@piercecountywa.gov')) {
                $validation.AddError("External domain access not permitted: $($user.Email)")
            }
        }
        
        # Rule: Shared mailboxes require departmental ownership
        foreach ($mailbox in $entities.Mailboxes) {
            if ($mailbox.Type -eq [MailboxType]::Shared -and -not $mailbox.Owner) {
                $validation.AddError("Shared mailboxes must have a designated owner")
            }
        }
        
        # Rule: Resource mailboxes must follow location naming
        foreach ($mailbox in $entities.Mailboxes) {
            if ($mailbox.Type -eq [MailboxType]::Resource) {
                $localPart = $mailbox.Email.Split('@')[0]
                if (-not ($localPart -match '(room|conf|meeting|equipment)')) {
                    $validation.AddWarning("Resource mailbox should include location/type indicator")
                }
            }
        }
        
        # Rule: Administrative actions require business justification
        foreach ($action in $entities.Actions) {
            if ($action.Type -in @([ActionType]::Create, [ActionType]::Deprovision)) {
                if ([string]::IsNullOrWhiteSpace($action.Context)) {
                    $validation.AddError("Administrative actions require business justification")
                }
            }
        }
        
        # Rule: Distribution groups with >50 members require approval
        foreach ($group in $entities.Groups) {
            if ($group.Type -eq 'Distribution' -and $group.Members.Count -gt 50) {
                $validation.AddWarning("Large distribution groups require IT approval")
            }
        }
        
        # Rule: Calendar permissions follow organizational hierarchy
        foreach ($permission in $entities.Permissions) {
            if ($permission.Level -eq [PermissionLevel]::Calendar) {
                # In a real implementation, this would check organizational hierarchy
                $validation.AddInfo("Calendar permissions will be validated against organizational hierarchy")
            }
        }
        
        return $validation
    }
    
    hidden [EntityValidationResult] ValidateCompliance([EntityCollection]$entities, [OrchestrationSession]$session) {
        $validation = [EntityValidationResult]::new("Compliance", "GCC")
        
        # GCC Compliance checks
        foreach ($user in $entities.Users) {
            # Check data residency requirements
            if (-not $this.IsCompliantDataResidency($user.Email)) {
                $validation.AddError("User does not meet GCC data residency requirements")
            }
            
            # Check security classification
            if ($user.Title -and $this.RequiresSecurityClearance($user.Title)) {
                $validation.AddInfo("User position requires security clearance verification")
            }
        }
        
        # Audit requirements
        foreach ($action in $entities.Actions) {
            if ($action.Type -in @([ActionType]::Deprovision, [ActionType]::Create)) {
                $validation.AddInfo("Action requires comprehensive audit trail")
            }
        }
        
        # Data retention compliance
        foreach ($mailbox in $entities.Mailboxes) {
            if ($mailbox.Type -eq [MailboxType]::Shared) {
                $validation.AddInfo("Shared mailbox subject to 7-year retention policy")
            }
        }
        
        # FOUO (For Official Use Only) compliance
        $session.AddContext("ComplianceLevel", "FOUO")
        $validation.AddInfo("All operations classified as For Official Use Only")
        
        return $validation
    }
    
    hidden [void] InitializeValidationRules() {
        # User email format
        $this.Rules['UserEmailFormat'] = [ValidationRule]::new(
            'UserEmailFormat',
            '^[a-z]+\.[a-z]+@piercecountywa\.gov$',
            'User email must follow firstname.lastname@piercecountywa.gov format'
        )
        
        # Mailbox email format
        $this.Rules['MailboxEmailFormat'] = [ValidationRule]::new(
            'MailboxEmailFormat',
            '^[a-z0-9_-]+@piercecountywa\.gov$',
            'Mailbox email must contain only lowercase letters, numbers, underscores, and hyphens'
        )
        
        # Shared mailbox naming
        $this.Rules['SharedMailboxNaming'] = [ValidationRule]::new(
            'SharedMailboxNaming',
            '^[a-z0-9_-]+(shared|dept|div|team)?[a-z0-9_-]*@piercecountywa\.gov$',
            'Shared mailbox should include organizational identifier'
        )
        
        # Resource mailbox naming
        $this.Rules['ResourceMailboxNaming'] = [ValidationRule]::new(
            'ResourceMailboxNaming',
            '^[a-z0-9_-]+(room|cal|conf|meeting|equipment|resource)[a-z0-9_-]*@piercecountywa\.gov$',
            'Resource mailbox must include resource type indicator'
        )
        
        # Display name
        $this.Rules['DisplayName'] = [ValidationRule]::new(
            'DisplayName',
            '^[A-Za-z\s\-\.]+$',
            'Display name can only contain letters, spaces, hyphens, and periods'
        )
        
        # Group name
        $this.Rules['GroupName'] = [ValidationRule]::new(
            'GroupName',
            '^[A-Za-z0-9\s\-_\.]+$',
            'Group name can contain letters, numbers, spaces, hyphens, underscores, and periods'
        )
        
        # Group email
        $this.Rules['GroupEmail'] = [ValidationRule]::new(
            'GroupEmail',
            '^[a-z0-9_-]+@piercecountywa\.gov$',
            'Group email must follow Pierce County domain standards'
        )
        
        # Mailbox alias
        $this.Rules['MailboxAlias'] = [ValidationRule]::new(
            'MailboxAlias',
            '^[a-z0-9_-]+$',
            'Mailbox alias can only contain lowercase letters, numbers, underscores, and hyphens'
        )
    }
    
    hidden [void] LoadOrganizationalPolicies() {
        $this.OrganizationalPolicies = @{
            'MaxGroupSize' = 200
            'RequireApprovalThreshold' = 50
            'SharedMailboxOwnerRequired' = $true
            'ExternalDomainAllowed' = $false
            'AutoProvisioningEnabled' = $false
            'DefaultRetentionPeriod' = '7 years'
            'SecurityClearanceRequired' = @('Administrator', 'Security Officer', 'Compliance Manager')
            'PrivilegedRoles' = @('Global Administrator', 'Exchange Administrator', 'Security Administrator')
        }
    }
    
    hidden [void] LoadComplianceRequirements() {
        $this.ComplianceRequirements = @{
            'DataResidency' = 'United States'
            'EncryptionRequired' = $true
            'AuditRetention' = '7 years'
            'SecurityClassification' = 'FOUO'
            'ComplianceFrameworks' = @('SOC2', 'NIST', 'FISMA')
            'DataSubjectRights' = $true
            'BreachNotificationPeriod' = '72 hours'
        }
    }
    
    hidden [bool] IsValidDepartment([string]$department) {
        # This would typically query against the official department list
        $validDepartments = @(
            'Information Technology',
            'Human Resources',
            'Finance',
            'Public Works',
            'Parks and Recreation',
            'Planning and Public Works',
            'Sheriff',
            'Prosecutor',
            'Medical Examiner',
            'Emergency Management'
        )
        
        return $department -in $validDepartments
    }
    
    hidden [bool] IsAuthorizedForPrivilegedAction([string]$initiator, [ActionType]$actionType) {
        # This would typically check against AD groups or role assignments
        # For now, we'll check if the initiator is from IT or has admin in their email
        return $initiator -match 'admin|it\.' -or $initiator.Contains('@piercecountywa.gov')
    }
    
    hidden [bool] IsCompliantDataResidency([string]$email) {
        # All Pierce County emails are US-based by default
        return $email.EndsWith('@piercecountywa.gov')
    }
    
    hidden [bool] RequiresSecurityClearance([string]$title) {
        $clearanceRequiredTitles = $this.OrganizationalPolicies['SecurityClearanceRequired']
        return $clearanceRequiredTitles | Where-Object { $title -match $_ }
    }
}

class ValidationRule {
    [string] $Name
    [string] $Pattern
    [string] $Description
    [bool] $IsRegex
    
    ValidationRule([string]$name, [string]$pattern, [string]$description) {
        $this.Name = $name
        $this.Pattern = $pattern
        $this.Description = $description
        $this.IsRegex = $true
    }
    
    [bool] Validate([string]$value) {
        if ($this.IsRegex) {
            return $value -match $this.Pattern
        } else {
            return $value -eq $this.Pattern
        }
    }
}

class ValidationResult {
    [bool] $IsValid
    [List[EntityValidationResult]] $EntityResults
    [List[string]] $Errors
    [List[string]] $Warnings
    [List[string]] $Information
    [DateTime] $ValidationTime
    
    ValidationResult() {
        $this.EntityResults = [List[EntityValidationResult]]::new()
        $this.Errors = [List[string]]::new()
        $this.Warnings = [List[string]]::new()
        $this.Information = [List[string]]::new()
        $this.ValidationTime = Get-Date
        $this.IsValid = $true
    }
    
    [void] AddUserValidation([string]$email, [EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddMailboxValidation([string]$email, [EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddGroupValidation([string]$name, [EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddActionValidation([string]$action, [EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddRelationshipValidation([EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddBusinessRuleValidation([EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddComplianceValidation([EntityValidationResult]$result) {
        $this.EntityResults.Add($result)
        $this.ProcessEntityResult($result)
    }
    
    [void] AddError([string]$error) {
        $this.Errors.Add($error)
        $this.IsValid = $false
    }
    
    [void] AddWarning([string]$warning) {
        $this.Warnings.Add($warning)
    }
    
    [void] AddInformation([string]$info) {
        $this.Information.Add($info)
    }
    
    hidden [void] ProcessEntityResult([EntityValidationResult]$result) {
        $this.Errors.AddRange($result.Errors)
        $this.Warnings.AddRange($result.Warnings)
        $this.Information.AddRange($result.Information)
        
        if ($result.Errors.Count -gt 0) {
            $this.IsValid = $false
        }
    }
}

class EntityValidationResult {
    [string] $EntityType
    [string] $EntityId
    [List[string]] $Errors
    [List[string]] $Warnings
    [List[string]] $Information
    [bool] $IsValid
    
    EntityValidationResult([string]$entityType, [string]$entityId) {
        $this.EntityType = $entityType
        $this.EntityId = $entityId
        $this.Errors = [List[string]]::new()
        $this.Warnings = [List[string]]::new()
        $this.Information = [List[string]]::new()
        $this.IsValid = $true
    }
    
    [void] AddError([string]$error) {
        $this.Errors.Add($error)
        $this.IsValid = $false
    }
    
    [void] AddWarning([string]$warning) {
        $this.Warnings.Add($warning)
    }
    
    [void] AddInfo([string]$info) {
        $this.Information.Add($info)
    }
}

# Supporting Entity Classes
enum MailboxType {
    User = 0
    Shared = 1
    Resource = 2
    Equipment = 3
    Room = 4
    Distribution = 5
}

enum GroupType {
    Distribution = 0
    Security = 1
    Microsoft365 = 2
    Universal = 3
}

enum ActionType {
    Create = 0
    Update = 1
    Delete = 2
    Grant = 3
    Revoke = 4
    Provision = 5
    Deprovision = 6
}

enum PermissionLevel {
    None = 0
    Read = 1
    Write = 2
    FullAccess = 3
    Calendar = 4
    SendAs = 5
    SendOnBehalf = 6
}

class BaseEntity {
    [string] $Id
    [string] $Type
    [DateTime] $CreatedAt
    [hashtable] $Metadata
    
    BaseEntity([string]$type) {
        $this.Type = $type
        $this.CreatedAt = Get-Date
        $this.Metadata = @{}
    }
}

class UserEntity : BaseEntity {
    [string] $Email
    [string] $DisplayName
    [string] $Department
    [bool] $IsActive
    
    UserEntity([string]$email) : base("User") {
        $this.Email = $email
        $this.Id = $email
        $this.IsActive = $true
    }
}

class MailboxEntity : BaseEntity {
    [string] $Email
    [string] $DisplayName
    [MailboxType] $MailboxType
    [string] $Owner
    
    MailboxEntity([string]$email, [MailboxType]$type) : base("Mailbox") {
        $this.Email = $email
        $this.Id = $email
        $this.MailboxType = $type
    }
}

class GroupEntity : BaseEntity {
    [string] $Email
    [string] $DisplayName
    [GroupType] $GroupType
    [List[string]] $Members
    [List[string]] $Owners
    
    GroupEntity([string]$email, [GroupType]$type) : base("Group") {
        $this.Email = $email
        $this.Id = $email
        $this.GroupType = $type
        $this.Members = [List[string]]::new()
        $this.Owners = [List[string]]::new()
    }
}

class ActionEntity : BaseEntity {
    [ActionType] $ActionType
    [string] $Target
    [hashtable] $Parameters
    [string] $Reason
    
    ActionEntity([ActionType]$actionType, [string]$target) : base("Action") {
        $this.ActionType = $actionType
        $this.Target = $target
        $this.Id = [Guid]::NewGuid().ToString()
        $this.Parameters = @{}
    }
}

class EntityCollection {
    [List[UserEntity]] $Users
    [List[MailboxEntity]] $Mailboxes
    [List[GroupEntity]] $Groups
    [List[ActionEntity]] $Actions
    
    EntityCollection() {
        $this.Users = [List[UserEntity]]::new()
        $this.Mailboxes = [List[MailboxEntity]]::new()
        $this.Groups = [List[GroupEntity]]::new()
        $this.Actions = [List[ActionEntity]]::new()
    }
    
    [void] AddUser([UserEntity]$user) {
        $this.Users.Add($user)
    }
    
    [void] AddMailbox([MailboxEntity]$mailbox) {
        $this.Mailboxes.Add($mailbox)
    }
    
    [void] AddGroup([GroupEntity]$group) {
        $this.Groups.Add($group)
    }
    
    [void] AddAction([ActionEntity]$action) {
        $this.Actions.Add($action)
    }
    
    [BaseEntity[]] GetAllEntities() {
        $allEntities = [List[BaseEntity]]::new()
        $allEntities.AddRange($this.Users)
        $allEntities.AddRange($this.Mailboxes)
        $allEntities.AddRange($this.Groups)
        $allEntities.AddRange($this.Actions)
        return $allEntities.ToArray()
    }
}

class OrchestrationSession {
    [string] $SessionId
    [string] $Initiator
    [DateTime] $StartTime
    [string] $InputText
    [hashtable] $Context
    
    OrchestrationSession([string]$inputText, [string]$initiator) {
        $this.SessionId = [Guid]::NewGuid().ToString()
        $this.Initiator = $initiator
        $this.StartTime = Get-Date
        $this.InputText = $inputText
        $this.Context = @{}
    }
}
