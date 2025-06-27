#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Account Deprovisioning Tool - Agentic MCP Implementation
.DESCRIPTION
    Comprehensive account lifecycle management with autonomous orchestration,
    intelligent validation, and enterprise audit trails. Handles multi-account
    deprovisioning across Exchange Online, Microsoft Graph, and Active Directory.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Compatible: PowerShell 7.0+, MCP Protocol, Agentic Orchestration
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation

class AccountDeprovisioningTool {
    [string]$ToolName = "deprovision_account"
    [hashtable]$Config
    [Logger]$Logger
    [ValidationEngine]$Validator
    [SecurityManager]$Security

    AccountDeprovisioningTool([hashtable]$config, [Logger]$logger, [ValidationEngine]$validator, [SecurityManager]$security) {
        $this.Config = $config
        $this.Logger = $logger
        $this.Validator = $validator
        $this.Security = $security
    }

    [hashtable] GetSchema() {
        return @{
            name = $this.ToolName
            description = "Deprovision M365 accounts across Exchange, Graph, and Active Directory with comprehensive audit trails"
            inputSchema = @{
                type = "object"
                properties = @{
                    Accounts = @{
                        type = "array"
                        items = @{ type = "string" }
                        description = "Array of user principal names to deprovision"
                        minItems = 1
                        maxItems = 100
                    }
                    Account = @{
                        type = "string"
                        description = "Single user principal name to deprovision (alternative to Accounts array)"
                        pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                    }
                    Initiator = @{
                        type = "string"
                        description = "Identity of the requesting user or system"
                        default = "MCPAgent"
                    }
                    Reason = @{
                        type = "string"
                        description = "Business justification for deprovisioning"
                        default = "Automated deprovisioning"
                    }
                    TransferMailboxTo = @{
                        type = "string"
                        description = "Optional manager/delegate to transfer mailbox access"
                        pattern = "^[a-zA-Z0-9._%+-]+@piercecountywa\.gov$"
                    }
                    RetentionDays = @{
                        type = "integer"
                        description = "Days to retain account before final deletion"
                        minimum = 30
                        maximum = 365
                        default = 90
                    }
                }
                anyOf = @(
                    @{ required = @("Accounts") }
                    @{ required = @("Account") }
                )
            }
            outputSchema = @{
                type = "object"
                properties = @{
                    status = @{ type = "string"; enum = @("success", "partial", "failed") }
                    summary = @{
                        type = "object"
                        properties = @{
                            total = @{ type = "integer" }
                            successful = @{ type = "integer" }
                            failed = @{ type = "integer" }
                            warnings = @{ type = "integer" }
                        }
                    }
                    accounts = @{
                        type = "array"
                        items = @{
                            type = "object"
                            properties = @{
                                upn = @{ type = "string" }
                                status = @{ type = "string" }
                                actions = @{ type = "array" }
                                warnings = @{ type = "array" }
                                errors = @{ type = "array" }
                                executionTime = @{ type = "number" }
                                auditId = @{ type = "string" }
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
        $context = @{ Params = $params; Accounts = $null; Audit = $null; Results = @(); Response = $null }

        $states = @{
            Start = @{ Handler = {
                $context.Audit = @{
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    initiator = $context.Params.Initiator ?? "MCPAgent"
                    reason = $context.Params.Reason ?? "Automated deprovisioning"
                    complianceFlags = @()
                }
                $this.Logger.LogInfo("Account deprovisioning session started", @{ sessionId = $sessionId })
                $context.Accounts = $this.NormalizeAccountList($context.Params)
                return 'Validate'
            } }
            Validate = @{ Handler = {
                $val = $this.ValidateAccounts($context.Accounts)
                if ($val.HasCriticalErrors) { $context.Response = $this.BuildErrorResponse($val.Errors, $context.Audit); return $null }
                return 'Security'
            } }
            Security = @{ Handler = {
                $sec = $this.Security.ValidateDeprovisioningRequest($context.Accounts, $context.Audit.initiator)
                if (-not $sec.IsAuthorized) { $context.Response = $this.BuildSecurityErrorResponse($sec, $context.Audit); return $null }
                return 'Connect'
            } }
            Connect = @{ Handler = {
                $conn = $this.InitializeConnections()
                if (-not $conn.Success) { $context.Response = $this.BuildConnectionErrorResponse($conn, $context.Audit); return $null }
                return 'Process'
            } }
            Process = @{ Handler = {
                foreach ($acc in $context.Accounts) { $context.Results += $this.ProcessSingleAccount($acc, $context.Params, $sessionId) }
                $context.Response = $this.BuildSuccessResponse($context.Results, $context.Audit, $stopwatch.ElapsedMilliseconds)
                $this.Logger.LogInfo("Account deprovisioning session completed", @{ sessionId = $sessionId })
                return $null
            } }
        }

        try {
            $sm = [StateMachine]::new($states, 'Start', $this.Logger)
            $sm.Run($context)
        } catch {
            $this.Logger.LogError("Critical error in account deprovisioning", @{ sessionId = $sessionId; error = $_.Exception.Message })
            $context.Response = @{ status = 'failed'; error = 'Critical system error during deprovisioning'; sessionId = $sessionId; timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); auditTrail = $context.Audit }
        } finally {
            $stopwatch.Stop()
        }

        return $context.Response
    }

    [array] NormalizeAccountList([hashtable]$params) {
        $accounts = @()
        
        if ($params.ContainsKey('Accounts') -and $params.Accounts) {
            $accounts = $params.Accounts
        } elseif ($params.ContainsKey('Account') -and $params.Account) {
            $accounts = @($params.Account)
        }

        # Normalize email addresses to lowercase
        return $accounts | ForEach-Object { $_.ToLower().Trim() }
    }

    [hashtable] ValidateAccounts([array]$accounts) {
        $result = @{
            HasCriticalErrors = $false
            Errors = @()
            Warnings = @()
        }

        foreach ($account in $accounts) {
            # Validate Pierce County domain
            if ($account -notmatch '@piercecountywa\.gov$') {
                $result.Errors += "Invalid domain for account: $account. Must be @piercecountywa.gov"
                $result.HasCriticalErrors = $true
                continue
            }

            # Validate account format
            $validation = $this.Validator.ValidateUserPrincipalName($account)
            if (-not $validation.IsValid) {
                $result.Errors += "Invalid account format: $account. $($validation.ErrorMessage)"
                $result.HasCriticalErrors = $true
            }
        }

        return $result
    }

    [hashtable] ProcessSingleAccount([string]$account, [hashtable]$params, [string]$sessionId) {
        $accountStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $auditId = [Guid]::NewGuid().ToString()
        
        $accountResult = @{
            upn = $account
            status = "processing"
            actions = @()
            warnings = @()
            errors = @()
            executionTime = 0
            auditId = $auditId
        }

        try {
            $this.Logger.LogInfo("Processing account deprovisioning", @{
                account = $account
                sessionId = $sessionId
                auditId = $auditId
            })

            # Step 1: Disable Exchange mailbox and transfer permissions
            $exchangeResult = $this.ProcessExchangeDeprovisioning($account, $params, $auditId)
            $accountResult.actions += $exchangeResult.actions
            $accountResult.warnings += $exchangeResult.warnings
            if ($exchangeResult.errors) { $accountResult.errors += $exchangeResult.errors }

            # Step 2: Remove licenses and Microsoft Graph objects
            $graphResult = $this.ProcessGraphDeprovisioning($account, $auditId)
            $accountResult.actions += $graphResult.actions
            $accountResult.warnings += $graphResult.warnings
            if ($graphResult.errors) { $accountResult.errors += $graphResult.errors }

            # Step 3: Disable Active Directory account
            $adResult = $this.ProcessActiveDirectoryDeprovisioning($account, $auditId)
            $accountResult.actions += $adResult.actions
            $accountResult.warnings += $adResult.warnings
            if ($adResult.errors) { $accountResult.errors += $adResult.errors }

            # Determine final status
            if ($accountResult.errors.Count -eq 0) {
                $accountResult.status = "success"
            } elseif ($accountResult.actions.Count -gt 0) {
                $accountResult.status = "partial"
            } else {
                $accountResult.status = "failed"
            }

        } catch {
            $accountResult.status = "failed"
            $accountResult.errors += "Critical error processing account: $($_.Exception.Message)"
            
            $this.Logger.LogError("Account processing failed", @{
                account = $account
                sessionId = $sessionId
                auditId = $auditId
                error = $_.Exception.Message
            })
        } finally {
            $accountStopwatch.Stop()
            $accountResult.executionTime = $accountStopwatch.ElapsedMilliseconds
        }

        return $accountResult
    }

    [hashtable] ProcessExchangeDeprovisioning([string]$account, [hashtable]$params, [string]$auditId) {
        $result = @{
            actions = @()
            warnings = @()
            errors = @()
        }

        try {
            # Check if mailbox exists
            $mailbox = Get-Mailbox -Identity $account -ErrorAction SilentlyContinue
            if (-not $mailbox) {
                $result.warnings += "No Exchange mailbox found for $account"
                return $result
            }

            # Transfer mailbox permissions if specified
            if ($params.TransferMailboxTo) {
                try {
                    Add-MailboxPermission -Identity $account -User $params.TransferMailboxTo -AccessRights FullAccess -Confirm:$false
                    $result.actions += @{
                        step = "Transfer mailbox access"
                        target = $account
                        details = "Granted FullAccess to $($params.TransferMailboxTo)"
                        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                } catch {
                    $result.errors += "Failed to transfer mailbox access: $($_.Exception.Message)"
                }
            }

            # Convert to shared mailbox
            try {
                Set-Mailbox -Identity $account -Type Shared -Confirm:$false
                $result.actions += @{
                    step = "Convert to shared mailbox"
                    target = $account
                    details = "Mailbox converted to shared type"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
            } catch {
                $result.errors += "Failed to convert mailbox to shared: $($_.Exception.Message)"
            }

            # Hide from address lists
            try {
                Set-Mailbox -Identity $account -HiddenFromAddressListsEnabled $true -Confirm:$false
                $result.actions += @{
                    step = "Hide from address lists"
                    target = $account
                    details = "Mailbox hidden from GAL"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
            } catch {
                $result.errors += "Failed to hide mailbox from address lists: $($_.Exception.Message)"
            }

        } catch {
            $result.errors += "Exchange deprovisioning failed: $($_.Exception.Message)"
        }

        return $result
    }

    [hashtable] ProcessGraphDeprovisioning([string]$account, [string]$auditId) {
        $result = @{
            actions = @()
            warnings = @()
            errors = @()
        }

        try {
            # Get user from Microsoft Graph
            $user = Get-MgUser -Filter "userPrincipalName eq '$account'" -ErrorAction SilentlyContinue
            if (-not $user) {
                $result.warnings += "No Microsoft Graph user found for $account"
                return $result
            }

            # Remove all license assignments
            try {
                $licenses = Get-MgUserLicenseDetail -UserId $user.Id
                foreach ($license in $licenses) {
                    Set-MgUserLicense -UserId $user.Id -RemoveLicenses @($license.SkuId) -AddLicenses @()
                    $result.actions += @{
                        step = "Remove license"
                        target = $account
                        details = "Removed license: $($license.SkuPartNumber)"
                        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    }
                }
            } catch {
                $result.errors += "Failed to remove licenses: $($_.Exception.Message)"
            }

            # Block sign-in
            try {
                Update-MgUser -UserId $user.Id -AccountEnabled:$false
                $result.actions += @{
                    step = "Block sign-in"
                    target = $account
                    details = "Account disabled in Azure AD"
                    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
            } catch {
                $result.errors += "Failed to disable account: $($_.Exception.Message)"
            }

            # Remove from groups
            try {
                $memberOf = Get-MgUserMemberOf -UserId $user.Id
                foreach ($group in $memberOf) {
                    if ($group.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.group") {
                        Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id
                        $result.actions += @{
                            step = "Remove group membership"
                            target = $account
                            details = "Removed from group: $($group.AdditionalProperties.displayName)"
                            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    }
                }
            } catch {
                $result.warnings += "Some group memberships could not be removed: $($_.Exception.Message)"
            }

        } catch {
            $result.errors += "Microsoft Graph deprovisioning failed: $($_.Exception.Message)"
        }

        return $result
    }

    [hashtable] ProcessActiveDirectoryDeprovisioning([string]$account, [string]$auditId) {
        $result = @{
            actions = @()
            warnings = @()
            errors = @()
        }

        try {
            # Note: This would require AD PowerShell module in on-premises scenarios
            # For cloud-only tenants, this step may be skipped
            $result.warnings += "Active Directory processing skipped - cloud-only tenant"
            
        } catch {
            $result.errors += "Active Directory deprovisioning failed: $($_.Exception.Message)"
        }

        return $result
    }

    [hashtable] InitializeConnections() {
        try {
            # Import required modules
            Import-Module ExchangeOnlineManagement -Force
            Import-Module Microsoft.Graph.Users -Force
            Import-Module Microsoft.Graph.Groups -Force

            # Connect to Exchange Online (assumes modern auth)
            Connect-ExchangeOnline -ShowProgress:$false -ShowBanner:$false

            # Connect to Microsoft Graph
            Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.AccessAsUser.All" -NoWelcome

            return @{ Success = $true }
        } catch {
            return @{
                Success = $false
                Error = "Failed to initialize M365 connections: $($_.Exception.Message)"
            }
        }
    }

    [hashtable] BuildSuccessResponse([array]$results, [hashtable]$auditTrail, [int]$duration) {
        $summary = @{
            total = $results.Count
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
            summary = $summary
            accounts = $results
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
            error = "Connection initialization failed: $($connectionResult.Error)"
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
}

# Export the tool class for the registry
if ($MyInvocation.InvocationName -ne '.') {
    return [AccountDeprovisioningTool]
}
