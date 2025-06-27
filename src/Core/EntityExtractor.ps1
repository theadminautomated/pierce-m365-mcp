#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Entity Extraction and Normalization Engine
.DESCRIPTION
    Provides intelligent parsing, correction, and normalization of user inputs
    for Pierce County M365 operations with autonomous entity recognition.
#>

using namespace System.Collections.Generic
using namespace System.Text.RegularExpressions

class EntityExtractor {
    hidden [Logger] $Logger
    hidden [Dictionary[string, Regex]] $Patterns
    hidden [Dictionary[string, string[]]] $Synonyms
    hidden [Dictionary[string, string]] $Corrections
    hidden [Dictionary[string, object]] $OrganizationalContext
    
    EntityExtractor([Logger]$logger) {
        $this.Logger = $logger
        $this.InitializePatterns()
        $this.InitializeSynonyms()
        $this.InitializeCorrections()
        $this.LoadOrganizationalContext()
    }
    
    [EntityCollection] ExtractAndNormalize([string]$input, [OrchestrationSession]$session) {
        $this.Logger.Debug("Starting entity extraction", @{
            InputLength = $input.Length
            SessionId = $session.SessionId
        })
        
        try {
            # Pre-process input (clean, normalize, spell-check)
            $normalizedInput = $this.PreprocessInput($input)
            
            # Extract entities using multiple strategies
            $entities = [EntityCollection]::new()
            
            # Extract users/accounts
            $users = $this.ExtractUsers($normalizedInput)
            $entities.AddUsers($users)
            
            # Extract mailboxes
            $mailboxes = $this.ExtractMailboxes($normalizedInput)
            $entities.AddMailboxes($mailboxes)
            
            # Extract groups
            $groups = $this.ExtractGroups($normalizedInput)
            $entities.AddGroups($groups)
            
            # Extract actions/operations
            $actions = $this.ExtractActions($normalizedInput)
            $entities.AddActions($actions)
            
            # Extract permissions
            $permissions = $this.ExtractPermissions($normalizedInput)
            $entities.AddPermissions($permissions)
            
            # Extract departments/organizational units
            $departments = $this.ExtractDepartments($normalizedInput)
            $entities.AddDepartments($departments)
            
            # Extract temporal references
            $timeReferences = $this.ExtractTimeReferences($normalizedInput)
            $entities.AddTimeReferences($timeReferences)
            
            # Post-process: validate, correct, and enrich entities
            $this.ValidateAndEnrichEntities($entities, $session)
            
            $this.Logger.Info("Entity extraction completed", @{
                UserCount = $entities.Users.Count
                MailboxCount = $entities.Mailboxes.Count
                GroupCount = $entities.Groups.Count
                ActionCount = $entities.Actions.Count
                SessionId = $session.SessionId
            })
            
            return $entities
        }
        catch {
            $this.Logger.Error("Entity extraction failed", @{
                Error = $_.Exception.Message
                SessionId = $session.SessionId
                Input = $input
            })
            throw
        }
    }
    
    hidden [string] PreprocessInput([string]$input) {
        # Remove extra whitespace and normalize line endings
        $cleaned = [Regex]::Replace($input.Trim(), '\s+', ' ')
        
        # Apply spelling corrections for common Pierce County terms
        foreach ($correction in $this.Corrections.GetEnumerator()) {
            $cleaned = $cleaned -replace $correction.Key, $correction.Value
        }
        
        # Normalize case for email addresses
        $cleaned = [Regex]::Replace($cleaned, '([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', 
            { param($match) $match.Value.ToLower() })
        
        return $cleaned
    }
    
    hidden [List[UserEntity]] ExtractUsers([string]$input) {
        $users = [List[UserEntity]]::new()
        
        # Extract email addresses
        $emailMatches = $this.Patterns['Email'].Matches($input)
        foreach ($match in $emailMatches) {
            $email = $match.Value.ToLower()
            if ($this.IsValidPierceCountyEmail($email)) {
                $user = [UserEntity]::new($email)
                $user.DisplayName = $this.InferDisplayNameFromEmail($email)
                $users.Add($user)
            }
        }
        
        # Extract name patterns and attempt email inference
        $nameMatches = $this.Patterns['FullName'].Matches($input)
        foreach ($match in $nameMatches) {
            $fullName = $match.Value
            $inferredEmail = $this.InferEmailFromName($fullName)
            if ($inferredEmail -and -not ($users | Where-Object { $_.Email -eq $inferredEmail })) {
                $user = [UserEntity]::new($inferredEmail)
                $user.DisplayName = $fullName
                $user.IsInferred = $true
                $users.Add($user)
            }
        }
        
        # Extract username patterns
        $usernameMatches = $this.Patterns['Username'].Matches($input)
        foreach ($match in $usernameMatches) {
            $username = $match.Value.ToLower()
            $email = "$username@piercecountywa.gov"
            if (-not ($users | Where-Object { $_.Email -eq $email })) {
                $user = [UserEntity]::new($email)
                $user.Username = $username
                $users.Add($user)
            }
        }
        
        return $users
    }
    
    hidden [List[MailboxEntity]] ExtractMailboxes([string]$input) {
        $mailboxes = [List[MailboxEntity]]::new()
        
        # Extract shared mailbox patterns
        $sharedMatches = $this.Patterns['SharedMailbox'].Matches($input)
        foreach ($match in $sharedMatches) {
            $email = $match.Value.ToLower()
            $mailbox = [MailboxEntity]::new($email, [MailboxType]::Shared)
            $mailbox.DisplayName = $this.InferMailboxDisplayName($email)
            $mailboxes.Add($mailbox)
        }
        
        # Extract resource mailbox patterns
        $resourceMatches = $this.Patterns['ResourceMailbox'].Matches($input)
        foreach ($match in $resourceMatches) {
            $email = $match.Value.ToLower()
            $mailbox = [MailboxEntity]::new($email, [MailboxType]::Resource)
            $mailbox.DisplayName = $this.InferMailboxDisplayName($email)
            $mailboxes.Add($mailbox)
        }
        
        # Infer mailbox types from context keywords
        $mailboxKeywords = @{
            'calendar' = [MailboxType]::Resource
            'room' = [MailboxType]::Resource
            'equipment' = [MailboxType]::Resource
            'shared' = [MailboxType]::Shared
            'department' = [MailboxType]::Shared
            'division' = [MailboxType]::Shared
        }
        
        foreach ($keyword in $mailboxKeywords.GetEnumerator()) {
            if ($input -match "\b$($keyword.Key)\b") {
                # Look for nearby email patterns
                $contextWindow = 50
                $keywordIndex = $input.IndexOf($keyword.Key)
                $start = [Math]::Max(0, $keywordIndex - $contextWindow)
                $end = [Math]::Min($input.Length, $keywordIndex + $contextWindow)
                $context = $input.Substring($start, $end - $start)
                
                $contextEmails = $this.Patterns['Email'].Matches($context)
                foreach ($match in $contextEmails) {
                    $email = $match.Value.ToLower()
                    if ($this.IsValidPierceCountyEmail($email) -and -not ($mailboxes | Where-Object { $_.Email -eq $email })) {
                        $mailbox = [MailboxEntity]::new($email, $keyword.Value)
                        $mailbox.IsInferred = $true
                        $mailboxes.Add($mailbox)
                    }
                }
            }
        }
        
        return $mailboxes
    }
    
    hidden [List[ActionEntity]] ExtractActions([string]$input) {
        $actions = [List[ActionEntity]]::new()
        
        # Define action patterns with synonyms
        $actionMappings = @{
            'grant|give|add|assign|provide|allow' = [ActionType]::Grant
            'revoke|remove|delete|deny|take away|disable' = [ActionType]::Revoke
            'create|make|establish|set up|provision' = [ActionType]::Create
            'deprovision|deactivate|terminate|offboard' = [ActionType]::Deprovision
            'modify|change|update|edit|alter' = [ActionType]::Modify
            'review|check|audit|examine|analyze' = [ActionType]::Review
        }
        
        foreach ($mapping in $actionMappings.GetEnumerator()) {
            $pattern = "(?i)\b($($mapping.Key))\b"
            $matches = [Regex]::Matches($input, $pattern)
            foreach ($match in $matches) {
                $action = [ActionEntity]::new($mapping.Value)
                $action.OriginalText = $match.Value
                $action.Context = $this.ExtractActionContext($input, $match.Index)
                $actions.Add($action)
            }
        }
        
        return $actions
    }
    
    hidden [List[PermissionEntity]] ExtractPermissions([string]$input) {
        $permissions = [List[PermissionEntity]]::new()
        
        # Define permission patterns
        $permissionPatterns = @{
            'full access|full control|owner' = [PermissionLevel]::FullAccess
            'send as|send on behalf' = [PermissionLevel]::SendAs
            'read|view|reviewer' = [PermissionLevel]::Read
            'editor|edit|modify' = [PermissionLevel]::Edit
            'author|contribute' = [PermissionLevel]::Author
            'calendar permissions?' = [PermissionLevel]::Calendar
        }
        
        foreach ($pattern in $permissionPatterns.GetEnumerator()) {
            $regex = "(?i)\b$($pattern.Key)\b"
            $matches = [Regex]::Matches($input, $regex)
            foreach ($match in $matches) {
                $permission = [PermissionEntity]::new($pattern.Value)
                $permission.OriginalText = $match.Value
                $permissions.Add($permission)
            }
        }
        
        return $permissions
    }
    
    hidden [List[DepartmentEntity]] ExtractDepartments([string]$input) {
        $departments = [List[DepartmentEntity]]::new()
        
        # Load known Pierce County departments
        $knownDepartments = $this.OrganizationalContext['Departments']
        
        foreach ($dept in $knownDepartments) {
            $deptPatterns = @(
                $dept.Name,
                $dept.ShortName,
                $dept.Aliases
            ) | Where-Object { $_ }
            
            foreach ($pattern in $deptPatterns) {
                if ($input -match "(?i)\b$([Regex]::Escape($pattern))\b") {
                    $department = [DepartmentEntity]::new($dept.Name)
                    $department.ShortName = $dept.ShortName
                    $department.DepartmentId = $dept.Id
                    $departments.Add($department)
                    break
                }
            }
        }
        
        return $departments
    }
    
    hidden [List[TimeEntity]] ExtractTimeReferences([string]$input) {
        $timeReferences = [List[TimeEntity]]::new()
        
        # Extract relative time references
        $relativePatterns = @{
            'immediately|now|asap|right away' = 0
            'today' = 0
            'tomorrow' = 1
            'next week' = 7
            'in (\d+) days?' = '$1'
            'end of month' = 30
        }
        
        foreach ($pattern in $relativePatterns.GetEnumerator()) {
            if ($input -match "(?i)\b$($pattern.Key)\b") {
                $timeRef = [TimeEntity]::new()
                $timeRef.OriginalText = $matches[0]
                $timeRef.RelativeDays = [int]$pattern.Value
                $timeRef.TargetDate = (Get-Date).AddDays($timeRef.RelativeDays)
                $timeReferences.Add($timeRef)
            }
        }
        
        # Extract absolute dates
        $datePatterns = @(
            '\b\d{1,2}/\d{1,2}/\d{4}\b',
            '\b\d{4}-\d{2}-\d{2}\b',
            '\b[A-Za-z]+ \d{1,2},? \d{4}\b'
        )
        
        foreach ($pattern in $datePatterns) {
            $matches = [Regex]::Matches($input, $pattern)
            foreach ($match in $matches) {
                try {
                    $date = [DateTime]::Parse($match.Value)
                    $timeRef = [TimeEntity]::new()
                    $timeRef.OriginalText = $match.Value
                    $timeRef.TargetDate = $date
                    $timeRef.RelativeDays = ($date - (Get-Date)).Days
                    $timeReferences.Add($timeRef)
                }
                catch {
                    # Invalid date format, skip
                    continue
                }
            }
        }
        
        return $timeReferences
    }
    
    hidden [void] ValidateAndEnrichEntities([EntityCollection]$entities, [OrchestrationSession]$session) {
        # Validate email formats and domains
        foreach ($user in $entities.Users) {
            if (-not $this.IsValidPierceCountyEmail($user.Email)) {
                $user.HasValidationErrors = $true
                $user.ValidationErrors.Add("Invalid Pierce County email format")
            }
        }
        
        # Enrich entities with organizational data
        $this.EnrichWithOrganizationalData($entities)
        
        # Cross-reference entities for consistency
        $this.CrossReferenceEntities($entities)
        
        # Apply business rules and context
        $this.ApplyBusinessRules($entities, $session)
    }
    
    hidden [void] InitializePatterns() {
        $this.Patterns = [Dictionary[string, Regex]]::new()
        $this.Patterns['Email'] = [Regex]::new('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', 'IgnoreCase')
        $this.Patterns['SharedMailbox'] = [Regex]::new('[a-z0-9_-]+@piercecountywa\.gov', 'IgnoreCase')
        $this.Patterns['ResourceMailbox'] = [Regex]::new('[a-z0-9_-]+(room|cal|equipment|resource)[a-z0-9_-]*@piercecountywa\.gov', 'IgnoreCase')
        $this.Patterns['FullName'] = [Regex]::new('\b[A-Z][a-z]+ [A-Z][a-z]+(?:\s[A-Z][a-z]+)*\b')
        $this.Patterns['Username'] = [Regex]::new('\b[a-z]+\.[a-z]+\b')
        $this.Patterns['PhoneNumber'] = [Regex]::new('\b\d{3}[-.]?\d{3}[-.]?\d{4}\b')
        $this.Patterns['Department'] = [Regex]::new('\b(department|division|office|bureau|unit)\s+of\s+[A-Za-z\s]+', 'IgnoreCase')
    }
    
    hidden [void] InitializeSynonyms() {
        # TODO: Make synonym list MUCH more robust and comprehensive
        $this.Synonyms = [Dictionary[string, string[]]]::new()
        $this.Synonyms['Access'] = @('permission', 'rights', 'privileges', 'access')
        $this.Synonyms['Remove'] = @('delete', 'revoke', 'take away', 'remove', 'disable')
        $this.Synonyms['Add'] = @('grant', 'give', 'assign', 'add', 'provide')
        $this.Synonyms['User'] = @('user', 'person', 'employee', 'staff', 'individual')
        $this.Synonyms['Group'] = @('group', 'team', 'distribution list', 'security group')
        $this.Synonyms['Mailbox'] = @('mailbox', 'email', 'inbox', 'mail')
    }
    
    hidden [void] InitializeCorrections() {
        # TODO: Make corrections list MUCH more robust and comprehensive
        $this.Corrections = [Dictionary[string,string]]::new()
        $this.Corrections['\bpierce\s*county\b'] = 'Pierce County'
        $this.Corrections['\bm365\b'] = 'Microsoft 365'
        $this.Corrections['\bexchange\b'] = 'Exchange Online'
        $this.Corrections['\bad\b'] = 'Active Directory'
        $this.Corrections['\bshare\s*point\b'] = 'SharePoint'
        $this.Corrections['\bteams\b'] = 'Microsoft Teams'
    }
    
    hidden [void] LoadOrganizationalContext() {
        # This would typically load from a configuration file or database
        $this.OrganizationalContext = [Dictionary[string, object]]::new()
        $departments = [List[object]]::new()
        $departments.Add(@{ Name = 'Information Technology'; ShortName = 'IT'; Id = 'IT001'; Aliases = @('IT', 'Technology') })
        $departments.Add(@{ Name = 'Human Resources'; ShortName = 'HR'; Id = 'HR001'; Aliases = @('HR', 'Personnel') })
        $departments.Add(@{ Name = 'Finance'; ShortName = 'FIN'; Id = 'FIN001'; Aliases = @('Finance', 'Accounting') })
        $departments.Add(@{ Name = 'Public Works'; ShortName = 'PW'; Id = 'PW001'; Aliases = @('Public Works', 'Engineering') })
        $this.OrganizationalContext['Departments'] = $departments
    }
    
    hidden [bool] IsValidPierceCountyEmail([string]$email) {
        return $email -match '^[a-z0-9._%+-]+@piercecountywa\.gov$'
    }
    
    hidden [string] InferDisplayNameFromEmail([string]$email) {
        $localPart = $email.Split('@')[0]
        $parts = $localPart.Split('.')
        return ($parts | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join ' '
    }
    
    hidden [string] InferEmailFromName([string]$fullName) {
        $parts = $fullName.Split(' ')
        if ($parts.Count -ge 2) {
            $firstName = $parts[0].ToLower()
            $lastName = $parts[-1].ToLower()
            return "$firstName.$lastName@piercecountywa.gov"
        }
        return $null
    }
    
    hidden [string] InferMailboxDisplayName([string]$email) {
        $localPart = $email.Split('@')[0]
        # Remove common prefixes/suffixes
        $cleaned = $localPart -replace '^(shared|resource|cal|room|equipment)', '' -replace '(cal|room|equipment)$', ''
        $parts = $cleaned.Split('_', '-')
        return ($parts | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join ' '
    }
    
    hidden [string] ExtractActionContext([string]$input, [int]$actionIndex) {
        $contextWindow = 30
        $start = [Math]::Max(0, $actionIndex - $contextWindow)
        $end = [Math]::Min($input.Length, $actionIndex + $contextWindow)
        return $input.Substring($start, $end - $start)
    }
    
    hidden [void] EnrichWithOrganizationalData([EntityCollection]$entities) {
        # Enrich user entities with department information
        foreach ($user in $entities.Users) {
            # In a real implementation, this would query AD or HR systems
            # For now, we'll infer from email patterns
            $localPart = $user.Email.Split('@')[0]
            if ($localPart -match '^([a-z]+)\.') {
                $potentialDept = $matches[1]
                $matchingDept = $this.OrganizationalContext['Departments'] | 
                    Where-Object { $_.ShortName.ToLower() -eq $potentialDept -or $_.Aliases -contains $potentialDept }
                if ($matchingDept) {
                    $user.Department = $matchingDept.Name
                    $user.DepartmentId = $matchingDept.Id
                }
            }
        }
    }
    
    hidden [void] CrossReferenceEntities([EntityCollection]$entities) {
        # Link related entities based on patterns and context
        foreach ($action in $entities.Actions) {
            # Find related users and permissions in the same context
            $contextWords = $action.Context.Split(' ')
            
            foreach ($user in $entities.Users) {
                if ($action.Context -match [Regex]::Escape($user.Email) -or 
                    $action.Context -match [Regex]::Escape($user.DisplayName)) {
                    $action.RelatedUsers.Add($user)
                }
            }
            
            foreach ($permission in $entities.Permissions) {
                if ($action.Context -match [Regex]::Escape($permission.OriginalText)) {
                    $action.RelatedPermissions.Add($permission)
                }
            }
        }
    }
    
    hidden [void] ApplyBusinessRules([EntityCollection]$entities, [OrchestrationSession]$session) {
        # Apply Pierce County specific business rules
        
        # Rule: Admin operations require explicit approval
        foreach ($action in $entities.Actions) {
            if ($action.Type -in @([ActionType]::Create, [ActionType]::Deprovision) -and
                $action.RelatedUsers.Count -gt 0) {
                $action.RequiresApproval = $true
                $action.ApprovalReason = "Administrative operation requires manager approval"
            }
        }
        
        # Rule: External domain emails are flagged
        foreach ($user in $entities.Users) {
            if (-not $user.Email.EndsWith('@piercecountywa.gov')) {
                $user.HasValidationErrors = $true
                $user.ValidationErrors.Add("External domain not permitted")
            }
        }
        
        # Rule: Resource mailboxes have special naming requirements
        foreach ($mailbox in $entities.Mailboxes) {
            if ($mailbox.Type -eq [MailboxType]::Resource -and
                -not ($mailbox.Email -match '(room|cal|equipment|resource)')) {
                $mailbox.HasValidationErrors = $true
                $mailbox.ValidationErrors.Add("Resource mailbox should include type indicator")
            }
        }
    }
}

# Supporting entity classes
enum ActionType {
    Grant
    Revoke
    Create
    Deprovision
    Modify
    Review
}

enum PermissionLevel {
    FullAccess
    SendAs
    Read
    Edit
    Author
    Calendar
}

enum MailboxType {
    User
    Shared
    Resource
    Equipment
    Room
}

class EntityCollection {
    [List[UserEntity]] $Users
    [List[MailboxEntity]] $Mailboxes
    [List[GroupEntity]] $Groups
    [List[ActionEntity]] $Actions
    [List[PermissionEntity]] $Permissions
    [List[DepartmentEntity]] $Departments
    [List[TimeEntity]] $TimeReferences
    
    EntityCollection() {
        $this.Users = [List[UserEntity]]::new()
        $this.Mailboxes = [List[MailboxEntity]]::new()
        $this.Groups = [List[GroupEntity]]::new()
        $this.Actions = [List[ActionEntity]]::new()
        $this.Permissions = [List[PermissionEntity]]::new()
        $this.Departments = [List[DepartmentEntity]]::new()
        $this.TimeReferences = [List[TimeEntity]]::new()
    }
    
    [void] AddUsers([List[UserEntity]]$users) {
        foreach ($user in $users) {
            if (-not ($this.Users | Where-Object { $_.Email -eq $user.Email })) {
                $this.Users.Add($user)
            }
        }
    }
    
    [void] AddMailboxes([List[MailboxEntity]]$mailboxes) {
        foreach ($mailbox in $mailboxes) {
            if (-not ($this.Mailboxes | Where-Object { $_.Email -eq $mailbox.Email })) {
                $this.Mailboxes.Add($mailbox)
            }
        }
    }
    
    [void] AddGroups([List[GroupEntity]]$groups) { $this.Groups.AddRange($groups) }
    [void] AddActions([List[ActionEntity]]$actions) { $this.Actions.AddRange($actions) }
    [void] AddPermissions([List[PermissionEntity]]$permissions) { $this.Permissions.AddRange($permissions) }
    [void] AddDepartments([List[DepartmentEntity]]$departments) { $this.Departments.AddRange($departments) }
    [void] AddTimeReferences([List[TimeEntity]]$timeReferences) { $this.TimeReferences.AddRange($timeReferences) }
}

class BaseEntity {
    [bool] $IsInferred
    [bool] $HasValidationErrors
    [List[string]] $ValidationErrors
    [double] $ConfidenceScore
    [hashtable] $Metadata
    
    BaseEntity() {
        $this.IsInferred = $false
        $this.HasValidationErrors = $false
        $this.ValidationErrors = [List[string]]::new()
        $this.ConfidenceScore = 1.0
        $this.Metadata = @{}
    }
}

class UserEntity : BaseEntity {
    [string] $Email
    [string] $DisplayName
    [string] $Username
    [string] $Department
    [string] $DepartmentId
    [string] $Title
    [string] $Manager
    
    UserEntity([string]$email) : base() {
        $this.Email = $email
    }
}

class MailboxEntity : BaseEntity {
    [string] $Email
    [string] $DisplayName
    [MailboxType] $Type
    [string] $Alias
    [string] $Owner
    
    MailboxEntity([string]$email, [MailboxType]$type) : base() {
        $this.Email = $email
        $this.Type = $type
    }
}

class GroupEntity : BaseEntity {
    [string] $Name
    [string] $Email
    [string] $Type
    [string] $Description
    [List[string]] $Members
    [List[string]] $Owners
    
    GroupEntity([string]$name) : base() {
        $this.Name = $name
        $this.Members = [List[string]]::new()
        $this.Owners = [List[string]]::new()
    }
}

class ActionEntity : BaseEntity {
    [ActionType] $Type
    [string] $OriginalText
    [string] $Context
    [bool] $RequiresApproval
    [string] $ApprovalReason
    [List[UserEntity]] $RelatedUsers
    [List[PermissionEntity]] $RelatedPermissions
    
    ActionEntity([ActionType]$type) : base() {
        $this.Type = $type
        $this.RequiresApproval = $false
        $this.RelatedUsers = [List[UserEntity]]::new()
        $this.RelatedPermissions = [List[PermissionEntity]]::new()
    }
}

class PermissionEntity : BaseEntity {
    [PermissionLevel] $Level
    [string] $OriginalText
    [string] $Scope
    [string] $Target
    
    PermissionEntity([PermissionLevel]$level) : base() {
        $this.Level = $level
    }
}

class DepartmentEntity : BaseEntity {
    [string] $Name
    [string] $ShortName
    [string] $DepartmentId
    [string] $Manager
    [List[string]] $Aliases
    
    DepartmentEntity([string]$name) : base() {
        $this.Name = $name
        $this.Aliases = [List[string]]::new()
    }
}

class TimeEntity : BaseEntity {
    [string] $OriginalText
    [DateTime] $TargetDate
    [int] $RelativeDays
    [bool] $IsUrgent
    
    TimeEntity() : base() {
        $this.IsUrgent = $false
    }
}

