#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Mailbox Permissions Management Tool - Agentic MCP Implementation
.DESCRIPTION
    Comprehensive mailbox access control with autonomous orchestration,
    intelligent validation, and enterprise audit trails. Handles granular
    permission management for shared mailboxes, resource calendars, and user mailboxes.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.1.0-rc
    Compatible: PowerShell 7.0+, MCP Protocol, Agentic Orchestration
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation

class MailboxPermissionsTool {
    [string]$ToolName = "add_mailbox_permissions"
    [hashtable]$Config
    [Logger]$Logger
    [ValidationEngine]$Validator
    [SecurityManager]$Security

    MailboxPermissionsTool([hashtable]$config, [Logger]$logger, [ValidationEngine]$validator, [SecurityManager]$security) {
        $this.Config = $config
        $this.Logger = $logger
        $this.Validator = $validator
        $this.Security = $security
    }

    [hashtable] GetSchema() {
        return @{
            name = $this.ToolName
            description = "Add Full Access and Send As permissions to Exchange mailboxes with comprehensive audit trails"
            inputSchema = @{
                type = "object"
                properties = @{
                    Mailbox = @{
                        type = "string"
                        description = "Target mailbox identity (UPN, alias, or display name)"
                        pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                    }
                    Users = @{
                        type = "array"
                        items = @{ 
                            type = "string"
                            pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                        }
                        description = "Array of user principal names to grant permissions"
                        minItems = 1
                        maxItems = 50
                    }
                    Permissions = @{
                        type = "array"
                        items = @{
                            type = "string"
                            enum = @("FullAccess", "SendAs", "SendOnBehalf", "ReadPermission", "ChangePermission", "ChangeOwner")
                        }
                        description = "Specific permissions to grant"
                        default = @("FullAccess", "SendAs")
                    }
                    Initiator = @{
                        type = "string"
                        description = "Identity of the requesting user or system"
                        default = "MCPAgent"
                    }
                    Reason = @{
                        type = "string"
                        description = "Business justification for permission grant"
                        default = "Automated permission assignment"
                    }
                    AutoMapping = @{
                        type = "boolean"
                        description = "Enable auto-mapping for FullAccess permissions"
                        default = $true
                    }
                    InheritanceType = @{
                        type = "string"
                        enum = @("All", "Children", "Descendents", "SelfAndChildren", "None")
                        description = "Permission inheritance model"
                        default = "All"
                    }
                }
                required = @("Mailbox", "Users")
            }
            outputSchema = @{
                type = "object"
                properties = @{
                    status = @{ type = "string"; enum = @("success", "partial", "failed") }
                    mailbox = @{ type = "string" }
                    summary = @{
                        type = "object"
                        properties = @{
                            totalUsers = @{ type = "integer" }
                            successful = @{ type = "integer" }
                            failed = @{ type = "integer" }
                            warnings = @{ type = "integer" }
                        }
                    }
                    permissions = @{
                        type = "array"
                        items = @{
                            type = "object"
                            properties = @{
                                user = @{ type = "string" }
                                permissions = @{ type = "array" }
                                status = @{ type = "string" }
                                actions = @{ type = "array" }
                                warnings = @{ type = "array" }
                                errors = @{ type = "array" }
                                executionTime = @{ type = "number" }
                            }
                        }
                    }
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
        $context = @{ Params = $params; Results = @(); Audit = $null; Response = $null }

        $states = @{
            Start = @{ Handler = {
                $context.Audit = @{
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    initiator = $context.Params.Initiator ?? "MCPAgent"
                    reason = $context.Params.Reason ?? "Automated permission assignment"
                    complianceFlags = @()
                }
                $this.Logger.LogInfo("Mailbox permissions session started", @{ sessionId = $sessionId; mailbox = $context.Params.Mailbox })
                return 'Validate'
            } }
            Validate = @{ Handler = {
                $result = $this.ValidateInputs($context.Params)
                if ($result.HasErrors) { $context.Response = $this.BuildErrorResponse($result.Errors, $context.Audit); return $null }
                return 'Security'
            } }
            Security = @{ Handler = {
                $sec = $this.Security.ValidatePermissionRequest($context.Params.Mailbox, $context.Params.Users, $context.Audit.initiator)
                if (-not $sec.IsAuthorized) { $context.Response = $this.BuildSecurityErrorResponse($sec, $context.Audit); return $null }
                return 'Connect'
            } }
            Connect = @{ Handler = {
                $conn = $this.InitializeExchangeConnection()
                if (-not $conn.Success) { $context.Response = $this.BuildConnectionErrorResponse($conn, $context.Audit); return $null }
                return 'Verify'
            } }
            Verify = @{ Handler = {
                $val = $this.ValidateMailbox($context.Params.Mailbox)
                if (-not $val.IsValid) { $context.Response = $this.BuildMailboxErrorResponse($val, $context.Audit); return $null }
                return 'Assign'
            } }
            Assign = @{ Handler = {
                $perms = @($context.Params.Permissions ?? @("FullAccess", "SendAs"))
                foreach ($u in $context.Params.Users) {
                    $context.Results += $this.ProcessUserPermissions($context.Params.Mailbox, $u, $perms, $context.Params, $sessionId)
                }
                return 'Complete'
            } }
            Complete = @{ Handler = {
                $context.Response = $this.BuildSuccessResponse($context.Params.Mailbox, $context.Results, $context.Audit, $stopwatch.ElapsedMilliseconds)
                $this.Logger.LogInfo("Mailbox permissions session completed", @{ sessionId = $sessionId; mailbox = $context.Params.Mailbox })
                return $null
            } }
        }

        try {
            $sm = [StateMachine]::new($states, 'Start', $this.Logger)
            $sm.Run($context)
        } catch {
            $this.Logger.LogError("Critical error in mailbox permissions", @{ sessionId = $sessionId; mailbox = $context.Params.Mailbox; error = $_.Exception.Message })
            $context.Response = @{ status = 'failed'; error = 'Critical system error during permission assignment'; sessionId = $sessionId; timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); auditTrail = $context.Audit }
        } finally {
            $stopwatch.Stop()
        }

        return $context.Response
    }

    [hashtable] ValidateInputs([hashtable]$params) {
        $result = @{
            HasErrors = $false
            Errors = @()
            Warnings = @()
        }

        # Validate mailbox
        if (-not $params.Mailbox -or $params.Mailbox -notmatch '@piercecountywa\.gov$') {
            $result.Errors += "Invalid mailbox identity. Must be a valid @piercecountywa.gov address"
            $result.HasErrors = $true
        }

        # Validate users array
        if (-not $params.Users -or $params.Users.Count -eq 0) {
            $result.Errors += "Users array is required and cannot be empty"
            $result.HasErrors = $true
        } else {
            foreach ($user in $params.Users) {
                if ($user -notmatch '@piercecountywa\.gov$') {
                    $result.Errors += "Invalid user identity: $user. Must be a valid @piercecountywa.gov address"
                    $result.HasErrors = $true
                }
            }
        }

        # Validate permissions
        if ($params.Permissions) {
            $validPermissions = @("FullAccess", "SendAs", "SendOnBehalf", "ReadPermission", "ChangePermission", "ChangeOwner")
            foreach ($permission in $params.Permissions) {
                if ($permission -notin $validPermissions) {
                    $result.Errors += "Invalid permission: $permission. Must be one of: $($validPermissions -join ', ')"
                    $result.HasErrors = $true
                }
            }
        }

        return $result
    }

    [hashtable] ValidateMailbox([string]$mailboxIdentity) {
        try {
            $mailbox = Get-Mailbox -Identity $mailboxIdentity -ErrorAction Stop
            return @{
                IsValid = $true
                Mailbox = $mailbox
                Type = $mailbox.RecipientTypeDetails
            }
        } catch {
            return @{
                IsValid = $false
                Error = "Mailbox not found or access denied: $($_.Exception.Message)"
            }
        }
    }

    [hashtable] ProcessUserPermissions([string]$mailbox, [string]$user, [array]$permissions, [hashtable]$params, [string]$sessionId) {
        $userStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $userResult = @{
            user = $user
            permissions = $permissions
            status = "processing"
            actions = @()
            warnings = @()
            errors = @()
            executionTime = 0
        }

        try {
            $this.Logger.LogInfo("Processing user permissions", @{
                mailbox = $mailbox
                user = $user
                permissions = $permissions
                sessionId = $sessionId
            })

            # Verify user exists
            $userValidation = $this.ValidateUser($user)
            if (-not $userValidation.IsValid) {
                $userResult.errors += "User validation failed: $($userValidation.Error)"
                $userResult.status = "failed"
                return $userResult
            }

            # Process each permission type
            foreach ($permission in $permissions) {
                $permissionResult = $this.GrantSpecificPermission($mailbox, $user, $permission, $params)
                
                if ($permissionResult.Success) {
                    $userResult.actions += $permissionResult.Action
                } else {
                    if ($permissionResult.IsCritical) {
                        $userResult.errors += $permissionResult.Error
                    } else {
                        $userResult.warnings += $permissionResult.Error
                    }
                }
            }

            # Determine final status
            if ($userResult.errors.Count -eq 0) {
                $userResult.status = if ($userResult.warnings.Count -eq 0) { "success" } else { "partial" }
            } else {
                $userResult.status = "failed"
            }

        } catch {
            $userResult.status = "failed"
            $userResult.errors += "Critical error processing user permissions: $($_.Exception.Message)"
            
            $this.Logger.LogError("User permission processing failed", @{
                mailbox = $mailbox
                user = $user
                sessionId = $sessionId
                error = $_.Exception.Message
            })
        } finally {
            $userStopwatch.Stop()
            $userResult.executionTime = $userStopwatch.ElapsedMilliseconds
        }

        return $userResult
    }

    [hashtable] ValidateUser([string]$userIdentity) {
        try {
            $user = Get-Mailbox -Identity $userIdentity -ErrorAction Stop
            return @{
                IsValid = $true
                User = $user
            }
        } catch {
            try {
                # Try as a mail-enabled user
                $user = Get-MailUser -Identity $userIdentity -ErrorAction Stop
                return @{
                    IsValid = $true
                    User = $user
                }
            } catch {
                return @{
                    IsValid = $false
                    Error = "User not found or not mail-enabled: $($_.Exception.Message)"
                }
            }
        }
    }

    [hashtable] GrantSpecificPermission([string]$mailbox, [string]$user, [string]$permission, [hashtable]$params) {
        try {
            switch ($permission) {
                "FullAccess" {
                    $autoMapping = $params.AutoMapping ?? $true
                    $inheritanceType = $params.InheritanceType ?? "All"
                    
                    Add-MailboxPermission -Identity $mailbox -User $user -AccessRights FullAccess -InheritanceType $inheritanceType -AutoMapping:$autoMapping -Confirm:$false -ErrorAction Stop
                    
                    return @{
                        Success = $true
                        Action = @{
                            permission = "FullAccess"
                            target = $mailbox
                            user = $user
                            details = "AutoMapping: $autoMapping, Inheritance: $inheritanceType"
                            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    }
                }
                
                "SendAs" {
                    Add-RecipientPermission -Identity $mailbox -Trustee $user -AccessRights SendAs -Confirm:$false -ErrorAction Stop
                    
                    return @{
                        Success = $true
                        Action = @{
                            permission = "SendAs"
                            target = $mailbox
                            user = $user
                            details = "Send As permission granted"
                            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    }
                }
                
                "SendOnBehalf" {
                    $mailboxObj = Get-Mailbox -Identity $mailbox
                    $currentGrantees = $mailboxObj.GrantSendOnBehalfTo
                    $newGrantees = $currentGrantees + $user
                    
                    Set-Mailbox -Identity $mailbox -GrantSendOnBehalfTo $newGrantees -Confirm:$false -ErrorAction Stop
                    
                    return @{
                        Success = $true
                        Action = @{
                            permission = "SendOnBehalf"
                            target = $mailbox
                            user = $user
                            details = "Send On Behalf permission granted"
                            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    }
                }
                
                default {
                    return @{
                        Success = $false
                        IsCritical = $false
                        Error = "Unsupported permission type: $permission"
                    }
                }
            }
        } catch {
            return @{
                Success = $false
                IsCritical = $true
                Error = "Failed to grant $permission permission: $($_.Exception.Message)"
            }
        }
    }

    [hashtable] InitializeExchangeConnection() {
        try {
            Import-Module ExchangeOnlineManagement -Force
            
            # Check if already connected
            $sessions = Get-PSSession | Where-Object { $_.ComputerName -like "*outlook*" -and $_.State -eq "Opened" }
            if (-not $sessions) {
                Connect-ExchangeOnline -ShowProgress:$false -ShowBanner:$false
            }

            return @{ Success = $true }
        } catch {
            return @{
                Success = $false
                Error = "Failed to connect to Exchange Online: $($_.Exception.Message)"
            }
        }
    }

    [hashtable] BuildSuccessResponse([string]$mailbox, [array]$results, [hashtable]$auditTrail, [int]$duration) {
        $summary = @{
            totalUsers = $results.Count
            successful = ($results | Where-Object { $_.status -eq "success" }).Count
            failed = ($results | Where-Object { $_.status -eq "failed" }).Count
            warnings = ($results | Where-Object { $_.status -eq "partial" }).Count
        }

        $status = if ($summary.failed -eq 0) {
            if ($summary.warnings -eq 0) { "success" } else { "partial" }
        } else {
            "failed"
        }

        return @{
            status = $status
            mailbox = $mailbox
            summary = $summary
            permissions = $results
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
            error = "Exchange connection failed: $($connectionResult.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildMailboxErrorResponse([hashtable]$mailboxValidation, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Mailbox validation failed: $($mailboxValidation.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
}

# Export the tool class for the registry
if ($MyInvocation.InvocationName -ne '.') {
    return [MailboxPermissionsTool]
}
