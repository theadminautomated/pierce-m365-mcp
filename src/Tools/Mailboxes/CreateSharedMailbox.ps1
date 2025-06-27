#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Shared Mailbox Creation Tool - Agentic MCP Implementation
.DESCRIPTION
    Comprehensive shared mailbox provisioning with autonomous orchestration,
    intelligent validation, and enterprise audit trails. Handles complete
    mailbox lifecycle including creation, permissions, and configuration.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Compatible: PowerShell 7.0+, MCP Protocol, Agentic Orchestration
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation

class SharedMailboxTool {
    [string]$ToolName = "new_shared_mailbox"
    [hashtable]$Config
    [Logger]$Logger
    [ValidationEngine]$Validator
    [SecurityManager]$Security

    SharedMailboxTool([hashtable]$config, [Logger]$logger, [ValidationEngine]$validator, [SecurityManager]$security) {
        $this.Config = $config
        $this.Logger = $logger
        $this.Validator = $validator
        $this.Security = $security
    }

    [hashtable] GetSchema() {
        return @{
            name = $this.ToolName
            description = "Create new shared mailbox with permissions for specified users and comprehensive audit trails"
            inputSchema = @{
                type = "object"
                properties = @{
                    DisplayName = @{
                        type = "string"
                        description = "Display name for the shared mailbox"
                        minLength = 1
                        maxLength = 64
                    }
                    PrimarySmtpAddress = @{
                        type = "string"
                        description = "Primary SMTP address for the shared mailbox"
                        pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                    }
                    Owner = @{
                        type = "string"
                        description = "Primary owner/manager of the shared mailbox"
                        pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                    }
                    Users = @{
                        type = "array"
                        items = @{ 
                            type = "string"
                            pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                        }
                        description = "Array of users to grant access to the shared mailbox"
                        default = @()
                    }
                    Department = @{
                        type = "string"
                        description = "Department or division for organizational classification"
                    }
                    Purpose = @{
                        type = "string"
                        description = "Business purpose or function of the shared mailbox"
                    }
                    Initiator = @{
                        type = "string"
                        description = "Identity of the requesting user or system"
                        default = "MCPAgent"
                    }
                    Reason = @{
                        type = "string"
                        description = "Business justification for mailbox creation"
                        default = "Automated shared mailbox creation"
                    }
                    AutoMapping = @{
                        type = "boolean"
                        description = "Enable auto-mapping for users with FullAccess"
                        default = $true
                    }
                    SendAsPermissions = @{
                        type = "boolean"
                        description = "Grant SendAs permissions to specified users"
                        default = $true
                    }
                }
                required = @("DisplayName", "Owner")
            }
            outputSchema = @{
                type = "object"
                properties = @{
                    status = @{ type = "string"; enum = @("success", "partial", "failed") }
                    mailbox = @{
                        type = "object"
                        properties = @{
                            displayName = @{ type = "string" }
                            primarySmtpAddress = @{ type = "string" }
                            alias = @{ type = "string" }
                            guid = @{ type = "string" }
                            created = @{ type = "string" }
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
                                result = @{ type = "string" }
                            }
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
        $context = @{ Params = $params; Mailbox = $null; Audit = $null; Response = $null }

        $states = @{
            Start = @{ Handler = {
                $context.Audit = @{
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    initiator = $context.Params.Initiator ?? "MCPAgent"
                    reason = $context.Params.Reason ?? "Automated shared mailbox creation"
                    complianceFlags = @()
                }
                $this.Logger.LogInfo("Shared mailbox creation session started", @{ sessionId = $sessionId; displayName = $context.Params.DisplayName })
                if (-not $context.Params.PrimarySmtpAddress) { $context.Params.PrimarySmtpAddress = $this.GenerateSmtpAddress($context.Params.DisplayName, $context.Params.Department) }
                return 'Validate'
            } }
            Validate = @{ Handler = {
                $val = $this.ValidateInputs($context.Params)
                if ($val.HasErrors) { $context.Response = $this.BuildErrorResponse($val.Errors, $context.Audit); return $null }
                return 'Security'
            } }
            Security = @{ Handler = {
                $sec = $this.Security.ValidateMailboxCreationRequest($context.Params.PrimarySmtpAddress, $context.Params.Owner, $context.Audit.initiator)
                if (-not $sec.IsAuthorized) { $context.Response = $this.BuildSecurityErrorResponse($sec, $context.Audit); return $null }
                return 'Connect'
            } }
            Connect = @{ Handler = {
                $conn = $this.InitializeExchangeConnection()
                if (-not $conn.Success) { $context.Response = $this.BuildConnectionErrorResponse($conn, $context.Audit); return $null }
                return 'Create'
            } }
            Create = @{ Handler = {
                $mail = $this.CreateSharedMailbox($context.Params, $sessionId)
                if (-not $mail.Success) { $context.Response = $this.BuildMailboxCreationErrorResponse($mail, $context.Audit); return $null }
                $context.Mailbox = $mail.Mailbox
                return 'Permissions'
            } }
            Permissions = @{ Handler = {
                $perms = $this.ConfigureMailboxPermissions($context.Mailbox, $context.Params, $sessionId)
                $context.Response = $this.BuildSuccessResponse($context.Mailbox, $perms, $context.Audit, $stopwatch.ElapsedMilliseconds)
                $this.Logger.LogInfo("Shared mailbox creation completed", @{ sessionId = $sessionId; mailbox = $context.Mailbox.PrimarySmtpAddress })
                return $null
            } }
        }

        try {
            $sm = [StateMachine]::new($states, 'Start', $this.Logger)
            $sm.Run($context)
        } catch {
            $this.Logger.LogError("Critical error in shared mailbox creation", @{ sessionId = $sessionId; error = $_.Exception.Message })
            $context.Response = @{ status = 'failed'; error = 'Critical system error during mailbox creation'; sessionId = $sessionId; timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); auditTrail = $context.Audit }
        } finally {
            $stopwatch.Stop()
        }

        return $context.Response
    }

    [string] GenerateSmtpAddress([string]$displayName, [string]$department) {
        # Generate SMTP address based on display name and department
        $alias = $displayName.ToLower() -replace '[^a-z0-9]', ''
        
        if ($department) {
            $deptPrefix = $department.ToLower() -replace '[^a-z0-9]', '' | 
                          ForEach-Object { $_.Substring(0, [Math]::Min(4, $_.Length)) }
            $alias = "$deptPrefix$alias"
        }
        
        # Ensure alias is not too long
        if ($alias.Length -gt 20) {
            $alias = $alias.Substring(0, 20)
        }
        
        return "$alias@piercecountywa.gov"
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

        # Validate owner
        if (-not $params.Owner -or $params.Owner -notmatch '@piercecountywa\.gov$') {
            $result.Errors += "Owner must be a valid @piercecountywa.gov email address"
            $result.HasErrors = $true
        }

        # Validate primary SMTP address
        if ($params.PrimarySmtpAddress -and $params.PrimarySmtpAddress -notmatch '@piercecountywa\.gov$') {
            $result.Errors += "PrimarySmtpAddress must be a valid @piercecountywa.gov email address"
            $result.HasErrors = $true
        }

        # Validate users array
        if ($params.Users) {
            foreach ($user in $params.Users) {
                if ($user -notmatch '@piercecountywa\.gov$') {
                    $result.Errors += "Invalid user email: $user. Must be @piercecountywa.gov"
                    $result.HasErrors = $true
                }
            }
        }

        return $result
    }

    [hashtable] CreateSharedMailbox([hashtable]$params, [string]$sessionId) {
        try {
            $this.Logger.LogInfo("Creating shared mailbox", @{
                displayName = $params.DisplayName
                primarySmtpAddress = $params.PrimarySmtpAddress
                sessionId = $sessionId
            })

            # Check if mailbox already exists
            $existingMailbox = Get-Mailbox -Identity $params.PrimarySmtpAddress -ErrorAction SilentlyContinue
            if ($existingMailbox) {
                return @{
                    Success = $false
                    Error = "Mailbox already exists with address: $($params.PrimarySmtpAddress)"
                    IsCritical = $true
                }
            }

            # Create the shared mailbox
            $newMailbox = New-Mailbox -Name $params.DisplayName -DisplayName $params.DisplayName -PrimarySmtpAddress $params.PrimarySmtpAddress -Shared -Confirm:$false

            # Additional configuration
            if ($params.Department) {
                Set-Mailbox -Identity $newMailbox.Identity -Department $params.Department -Confirm:$false
            }

            if ($params.Purpose) {
                Set-Mailbox -Identity $newMailbox.Identity -Office $params.Purpose -Confirm:$false
            }

            return @{
                Success = $true
                Mailbox = @{
                    DisplayName = $newMailbox.DisplayName
                    PrimarySmtpAddress = $newMailbox.PrimarySmtpAddress
                    Alias = $newMailbox.Alias
                    Guid = $newMailbox.Guid.ToString()
                    Identity = $newMailbox.Identity
                    Created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
                Actions = @(
                    @{
                        step = "Create shared mailbox"
                        target = $newMailbox.PrimarySmtpAddress
                        details = "Mailbox created successfully"
                        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                )
            }

        } catch {
            return @{
                Success = $false
                Error = "Failed to create shared mailbox: $($_.Exception.Message)"
                IsCritical = $true
            }
        }
    }

    [hashtable] ConfigureMailboxPermissions([hashtable]$mailbox, [hashtable]$params, [string]$sessionId) {
        $permissionResults = @{
            Permissions = @()
            Actions = @()
            Warnings = @()
            Errors = @()
        }

        # Always grant owner full permissions
        $allUsers = @($params.Owner)
        if ($params.Users) {
            $allUsers += $params.Users | Where-Object { $_ -ne $params.Owner }
        }

        foreach ($user in $allUsers) {
            $userPermissionResult = @{
                user = $user
                permissions = @()
                status = "processing"
                result = ""
            }

            try {
                # Grant FullAccess permission
                $autoMapping = if ($user -eq $params.Owner) { $true } else { $params.AutoMapping ?? $true }
                Add-MailboxPermission -Identity $mailbox.Identity -User $user -AccessRights FullAccess -AutoMapping:$autoMapping -Confirm:$false

                $userPermissionResult.permissions += "FullAccess"
                $permissionResults.Actions += @{
                    step = "Grant FullAccess"
                    target = $mailbox.PrimarySmtpAddress
                    user = $user
                    details = "AutoMapping: $autoMapping"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }

                # Grant SendAs permission if requested
                if ($params.SendAsPermissions) {
                    Add-RecipientPermission -Identity $mailbox.Identity -Trustee $user -AccessRights SendAs -Confirm:$false
                    $userPermissionResult.permissions += "SendAs"
                    $permissionResults.Actions += @{
                        step = "Grant SendAs"
                        target = $mailbox.PrimarySmtpAddress
                        user = $user
                        details = "Send As permission granted"
                        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                }

                $userPermissionResult.status = "success"
                $userPermissionResult.result = "Permissions granted successfully"

            } catch {
                $userPermissionResult.status = "failed"
                $userPermissionResult.result = "Failed to grant permissions: $($_.Exception.Message)"
                $permissionResults.Errors += "Permission grant failed for $user`: $($_.Exception.Message)"

                $this.Logger.LogWarning("Failed to grant permissions", @{
                    mailbox = $mailbox.PrimarySmtpAddress
                    user = $user
                    error = $_.Exception.Message
                    sessionId = $sessionId
                })
            }

            $permissionResults.Permissions += $userPermissionResult
        }

        return $permissionResults
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

    [hashtable] BuildSuccessResponse([hashtable]$mailboxResult, [hashtable]$permissionsResult, [hashtable]$auditTrail, [int]$duration) {
        $allActions = @()
        $allActions += $mailboxResult.Actions
        $allActions += $permissionsResult.Actions

        $status = if ($permissionsResult.Errors.Count -eq 0) {
            "success"
        } elseif ($mailboxResult.Success -and $permissionsResult.Permissions.Count -gt 0) {
            "partial"
        } else {
            "failed"
        }

        return @{
            status = $status
            mailbox = $mailboxResult.Mailbox
            permissions = $permissionsResult.Permissions
            actions = $allActions
            warnings = $permissionsResult.Warnings
            errors = $permissionsResult.Errors
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

    [hashtable] BuildMailboxCreationErrorResponse([hashtable]$mailboxResult, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Mailbox creation failed: $($mailboxResult.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
}

# Export the tool class for the registry
if ($MyInvocation.InvocationName -ne '.') {
    return [SharedMailboxTool]
}
