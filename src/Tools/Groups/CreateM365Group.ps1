#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Microsoft 365 Group Creation Tool - Agentic MCP Implementation
.DESCRIPTION
    Comprehensive M365 group provisioning with autonomous orchestration,
    intelligent validation, and enterprise audit trails. Handles complete
    group lifecycle including creation, membership, and configuration.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Compatible: PowerShell 7.0+, MCP Protocol, Agentic Orchestration
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation

class M365GroupTool {
    [string]$ToolName = "new_m365_group"
    [hashtable]$Config
    [Logger]$Logger
    [ValidationEngine]$Validator
    [SecurityManager]$Security

    M365GroupTool([hashtable]$config, [Logger]$logger, [ValidationEngine]$validator, [SecurityManager]$security) {
        $this.Config = $config
        $this.Logger = $logger
        $this.Validator = $validator
        $this.Security = $security
    }

    [hashtable] GetSchema() {
        return @{
            name = $this.ToolName
            description = "Create new Microsoft 365 group with specified owners and members with comprehensive audit trails"
            inputSchema = @{
                type = "object"
                properties = @{
                    DisplayName = @{
                        type = "string"
                        description = "Display name for the M365 group"
                        minLength = 1
                        maxLength = 64
                    }
                    MailNickname = @{
                        type = "string"
                        description = "Mail nickname/alias for the group (will auto-generate if not provided)"
                        pattern = "^[a-zA-Z0-9._-]+$"
                    }
                    Description = @{
                        type = "string"
                        description = "Description of the group's purpose"
                        maxLength = 1024
                    }
                    Owners = @{
                        type = "array"
                        items = @{ 
                            type = "string"
                            pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                        }
                        description = "Array of group owners (required)"
                        minItems = 1
                        maxItems = 10
                    }
                    Members = @{
                        type = "array"
                        items = @{ 
                            type = "string"
                            pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                        }
                        description = "Array of initial group members"
                        default = @()
                    }
                    Privacy = @{
                        type = "string"
                        enum = @("Public", "Private")
                        description = "Group privacy setting"
                        default = "Private"
                    }
                    GroupType = @{
                        type = "string"
                        enum = @("Unified", "Security", "Distribution")
                        description = "Type of M365 group to create"
                        default = "Unified"
                    }
                    Department = @{
                        type = "string"
                        description = "Department or division for organizational classification"
                    }
                    Initiator = @{
                        type = "string"
                        description = "Identity of the requesting user or system"
                        default = "MCPAgent"
                    }
                    Reason = @{
                        type = "string"
                        description = "Business justification for group creation"
                        default = "Automated M365 group creation"
                    }
                }
                required = @("DisplayName", "Owners")
            }
            outputSchema = @{
                type = "object"
                properties = @{
                    status = @{ type = "string"; enum = @("success", "partial", "failed") }
                    group = @{
                        type = "object"
                        properties = @{
                            displayName = @{ type = "string" }
                            mailNickname = @{ type = "string" }
                            emailAddress = @{ type = "string" }
                            groupId = @{ type = "string" }
                            privacy = @{ type = "string" }
                            created = @{ type = "string" }
                        }
                    }
                    membership = @{
                        type = "object"
                        properties = @{
                            owners = @{ type = "array" }
                            members = @{ type = "array" }
                            totalOwners = @{ type = "integer" }
                            totalMembers = @{ type = "integer" }
                        }
                    }
                    actions = @{ type = "array" }
                    warnings = @{ type = "array" }
                    errors = @{ type = "array" }
                    auditTrail = @{
                        type = "object"
                        properties = @{
                            sessionId = @{ type = "string" }
                            timestamp = @{ type = "string" }
                            initiator = @{ type = "string" }
                            reason = @{ type = "string" }
                            complianceFlags = @{ type = "array" }
                        }
                    }
                }
            }
        }
    }

    [hashtable] Execute([hashtable]$params) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $sessionId = [Guid]::NewGuid().ToString()
        
        try {
            # Initialize audit trail
            $auditTrail = @{
                sessionId = $sessionId
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                initiator = $params.Initiator ?? "MCPAgent"
                reason = $params.Reason ?? "Automated M365 group creation"
                complianceFlags = @()
            }

            $this.Logger.LogInfo("M365 group creation session started", @{
                sessionId = $sessionId
                displayName = $params.DisplayName
                owners = $params.Owners
                initiator = $auditTrail.initiator
            })

            # Generate mail nickname if not provided
            if (-not $params.MailNickname) {
                $params.MailNickname = $this.GenerateMailNickname($params.DisplayName, $params.Department)
            }

            # Validate inputs
            $validationResult = $this.ValidateInputs($params)
            if ($validationResult.HasErrors) {
                return $this.BuildErrorResponse($validationResult.Errors, $auditTrail)
            }

            # Security validation
            $securityValidation = $this.Security.ValidateGroupCreationRequest($params.DisplayName, $params.Owners, $auditTrail.initiator)
            if (-not $securityValidation.IsAuthorized) {
                return $this.BuildSecurityErrorResponse($securityValidation, $auditTrail)
            }

            # Initialize Graph connection
            $connectionResult = $this.InitializeGraphConnection()
            if (-not $connectionResult.Success) {
                return $this.BuildConnectionErrorResponse($connectionResult, $auditTrail)
            }

            # Create M365 group
            $groupResult = $this.CreateM365Group($params, $sessionId)
            if (-not $groupResult.Success) {
                return $this.BuildGroupCreationErrorResponse($groupResult, $auditTrail)
            }

            # Configure membership
            $membershipResult = $this.ConfigureGroupMembership($groupResult.Group, $params, $sessionId)

            # Build comprehensive response
            $response = $this.BuildSuccessResponse($groupResult, $membershipResult, $auditTrail, $stopwatch.ElapsedMilliseconds)
            
            $this.Logger.LogInfo("M365 group creation completed", @{
                sessionId = $sessionId
                groupId = $groupResult.Group.Id
                emailAddress = $groupResult.Group.Mail
                duration = $stopwatch.ElapsedMilliseconds
                status = $response.status
            })

            return $response

        } catch {
            $this.Logger.LogError("Critical error in M365 group creation", @{
                sessionId = $sessionId
                error = $_.Exception.Message
                stackTrace = $_.ScriptStackTrace
            })

            return @{
                status = "failed"
                error = "Critical system error during group creation"
                sessionId = $sessionId
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                auditTrail = $auditTrail
            }
        } finally {
            $stopwatch.Stop()
        }
    }

    [string] GenerateMailNickname([string]$displayName, [string]$department) {
        # Generate mail nickname based on display name and department
        $nickname = $displayName.ToLower() -replace '[^a-z0-9]', ''
        
        if ($department) {
            $deptPrefix = $department.ToLower() -replace '[^a-z0-9]', '' | 
                          ForEach-Object { $_.Substring(0, [Math]::Min(4, $_.Length)) }
            $nickname = "$deptPrefix$nickname"
        }
        
        # Ensure nickname meets requirements
        if ($nickname.Length -gt 64) {
            $nickname = $nickname.Substring(0, 64)
        }
        
        # Ensure it doesn't start with number
        if ($nickname -match '^[0-9]') {
            $nickname = "g$nickname"
        }
        
        return $nickname
    }

    [hashtable] ValidateInputs([hashtable]$params) {
        $result = @{
            HasErrors = $false
            Errors = @()
            Warnings = @()
        }

        # Validate display name
        if (-not $params.DisplayName -or $params.DisplayName.Trim().Length -eq 0) {
            $result.Errors += "DisplayName is required and cannot be empty"
            $result.HasErrors = $true
        }

        # Validate owners
        if (-not $params.Owners -or $params.Owners.Count -eq 0) {
            $result.Errors += "At least one owner is required"
            $result.HasErrors = $true
        } else {
            foreach ($owner in $params.Owners) {
                if ($owner -notmatch '@piercecountywa\.gov$') {
                    $result.Errors += "Invalid owner email: $owner. Must be @piercecountywa.gov"
                    $result.HasErrors = $true
                }
            }
        }

        # Validate members
        if ($params.Members) {
            foreach ($member in $params.Members) {
                if ($member -notmatch '@piercecountywa\.gov$') {
                    $result.Errors += "Invalid member email: $member. Must be @piercecountywa.gov"
                    $result.HasErrors = $true
                }
            }
        }

        # Validate mail nickname
        if ($params.MailNickname -and $params.MailNickname -notmatch '^[a-zA-Z0-9._-]+$') {
            $result.Errors += "Invalid MailNickname. Must contain only letters, numbers, periods, underscores, and hyphens"
            $result.HasErrors = $true
        }

        return $result
    }

    [hashtable] CreateM365Group([hashtable]$params, [string]$sessionId) {
        try {
            $this.Logger.LogInfo("Creating M365 group", @{
                displayName = $params.DisplayName
                mailNickname = $params.MailNickname
                privacy = $params.Privacy
                sessionId = $sessionId
            })

            # Check if group already exists
            $existingGroup = Get-MgGroup -Filter "mailNickname eq '$($params.MailNickname)'" -ErrorAction SilentlyContinue
            if ($existingGroup) {
                return @{
                    Success = $false
                    Error = "Group already exists with mail nickname: $($params.MailNickname)"
                    IsCritical = $true
                }
            }

            # Prepare group parameters
            $groupParams = @{
                DisplayName = $params.DisplayName
                MailNickname = $params.MailNickname
                MailEnabled = $true
                SecurityEnabled = $false
                GroupTypes = @("Unified")
                Visibility = $params.Privacy ?? "Private"
            }

            if ($params.Description) {
                $groupParams.Description = $params.Description
            }

            # Create the group
            $newGroup = New-MgGroup @groupParams

            # Additional configuration if department specified
            if ($params.Department) {
                Update-MgGroup -GroupId $newGroup.Id -Department $params.Department
            }

            return @{
                Success = $true
                Group = @{
                    DisplayName = $newGroup.DisplayName
                    MailNickname = $newGroup.MailNickname
                    EmailAddress = $newGroup.Mail
                    GroupId = $newGroup.Id
                    Privacy = $newGroup.Visibility
                    Created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    Id = $newGroup.Id
                }
                Actions = @(
                    @{
                        step = "Create M365 group"
                        target = $newGroup.DisplayName
                        details = "Group created with ID: $($newGroup.Id)"
                        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                )
            }

        } catch {
            return @{
                Success = $false
                Error = "Failed to create M365 group: $($_.Exception.Message)"
                IsCritical = $true
            }
        }
    }

    [hashtable] ConfigureGroupMembership([hashtable]$group, [hashtable]$params, [string]$sessionId) {
        $membershipResults = @{
            Owners = @()
            Members = @()
            Actions = @()
            Warnings = @()
            Errors = @()
        }

        # Add owners
        foreach ($owner in $params.Owners) {
            try {
                # Get user object
                $user = Get-MgUser -Filter "userPrincipalName eq '$owner'" -ErrorAction Stop
                
                # Add as owner
                $ownerRef = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($user.Id)"
                }
                New-MgGroupOwnerByRef -GroupId $group.Id -BodyParameter $ownerRef

                # Also add as member
                New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter $ownerRef

                $membershipResults.Owners += @{
                    user = $owner
                    userId = $user.Id
                    status = "success"
                    result = "Added as owner and member"
                }

                $membershipResults.Actions += @{
                    step = "Add group owner"
                    target = $group.DisplayName
                    user = $owner
                    details = "User added as owner and member"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }

            } catch {
                $membershipResults.Owners += @{
                    user = $owner
                    userId = $null
                    status = "failed"
                    result = "Failed to add as owner: $($_.Exception.Message)"
                }

                $membershipResults.Errors += "Failed to add owner $owner`: $($_.Exception.Message)"

                $this.Logger.LogWarning("Failed to add group owner", @{
                    group = $group.DisplayName
                    owner = $owner
                    error = $_.Exception.Message
                    sessionId = $sessionId
                })
            }
        }

        # Add additional members (excluding owners)
        $additionalMembers = $params.Members | Where-Object { $_ -notin $params.Owners }
        foreach ($member in $additionalMembers) {
            try {
                # Get user object
                $user = Get-MgUser -Filter "userPrincipalName eq '$member'" -ErrorAction Stop
                
                # Add as member
                $memberRef = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($user.Id)"
                }
                New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter $memberRef

                $membershipResults.Members += @{
                    user = $member
                    userId = $user.Id
                    status = "success"
                    result = "Added as member"
                }

                $membershipResults.Actions += @{
                    step = "Add group member"
                    target = $group.DisplayName
                    user = $member
                    details = "User added as member"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }

            } catch {
                $membershipResults.Members += @{
                    user = $member
                    userId = $null
                    status = "failed"
                    result = "Failed to add as member: $($_.Exception.Message)"
                }

                $membershipResults.Errors += "Failed to add member $member`: $($_.Exception.Message)"

                $this.Logger.LogWarning("Failed to add group member", @{
                    group = $group.DisplayName
                    member = $member
                    error = $_.Exception.Message
                    sessionId = $sessionId
                })
            }
        }

        return $membershipResults
    }

    [hashtable] InitializeGraphConnection() {
        try {
            Import-Module Microsoft.Graph.Groups -Force
            Import-Module Microsoft.Graph.Users -Force
            
            # Check if already connected
            $context = Get-MgContext -ErrorAction SilentlyContinue
            if (-not $context) {
                Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All", "Directory.ReadWrite.All" -NoWelcome
            }

            return @{ Success = $true }
        } catch {
            return @{
                Success = $false
                Error = "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
            }
        }
    }

    [hashtable] BuildSuccessResponse([hashtable]$groupResult, [hashtable]$membershipResult, [hashtable]$auditTrail, [int]$duration) {
        $allActions = @()
        $allActions += $groupResult.Actions
        $allActions += $membershipResult.Actions

        $membership = @{
            owners = $membershipResult.Owners
            members = $membershipResult.Members
            totalOwners = ($membershipResult.Owners | Where-Object { $_.status -eq "success" }).Count
            totalMembers = ($membershipResult.Members | Where-Object { $_.status -eq "success" }).Count
        }

        $status = if ($membershipResult.Errors.Count -eq 0) {
            "success"
        } elseif ($groupResult.Success -and $membership.totalOwners -gt 0) {
            "partial"
        } else {
            "failed"
        }

        return @{
            status = $status
            group = $groupResult.Group
            membership = $membership
            actions = $allActions
            warnings = $membershipResult.Warnings
            errors = $membershipResult.Errors
            auditTrail = $auditTrail
            executionTime = $duration
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildErrorResponse([array]$errors, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            errors = $errors
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildSecurityErrorResponse([hashtable]$securityValidation, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Security validation failed: $($securityValidation.Reason)"
            securityFlags = $securityValidation.Flags
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildConnectionErrorResponse([hashtable]$connectionResult, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Microsoft Graph connection failed: $($connectionResult.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildGroupCreationErrorResponse([hashtable]$groupResult, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Group creation failed: $($groupResult.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
}

# Export the tool class for the registry
if ($MyInvocation.InvocationName -ne '.') {
    return [M365GroupTool]
}
