#Requires -Version 7.0
<%
.SYNOPSIS
    Pull Request Suggestion Engine for MCP Server
.DESCRIPTION
    Automatically packages code changes into a feature branch, runs tests and linting,
    and opens a pull request with detailed logs. Supports audit logging and
    notification to maintainers.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Compliance: GCC, SOC2, NIST
%>

using namespace System.IO

class PRSuggestionEngine {
    [string]$Repository
    [string]$BaseBranch
    [string]$NotificationEndpoint
    [string]$LogPath

    PRSuggestionEngine([string]$repository, [string]$baseBranch = 'main', [string]$notificationEndpoint = '', [string]$logPath = 'logs/pr-suggestions.log') {
        $this.Repository = $repository
        $this.BaseBranch = $baseBranch
        $this.NotificationEndpoint = $notificationEndpoint
        $this.LogPath = $logPath
    }

    [void]SuggestPullRequest([string]$changeDescription, [string[]]$testScripts) {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
        $branch = "pr-suggestion/$timestamp"

        Push-Location $this.Repository
        git checkout $this.BaseBranch | Out-Null
        git checkout -b $branch | Out-Null
        git add -A
        $files = git status --short
        $commitMsg = "feat: automated suggestion - $changeDescription"
        git commit -m $commitMsg | Out-Null

        $testLog = @()
        foreach ($script in $testScripts) {
            try {
                $output = & $script 2>&1
                $testLog += $output
            } catch {
                $testLog += $_.Exception.Message
            }
        }

        $logBody = $testLog -join "`n"
        $prBody = "### Change Description`n$changeDescription`n`n### Affected Files`n$files`n`n### Test Logs`n```
$logBody
```"

        gh pr create --base $this.BaseBranch --head $branch --title $changeDescription --body $prBody | Out-Null
        $prUrl = gh pr view --json url -q '.url'

        $logEntry = "[$(Get-Date -Format o)] Created PR $prUrl for branch $branch"
        $logEntry | Out-File -FilePath $this.LogPath -Append

        if ($this.NotificationEndpoint) {
            $payload = @{ text = "New PR Suggested: $prUrl - $changeDescription" } | ConvertTo-Json
            Invoke-RestMethod -Uri $this.NotificationEndpoint -Method Post -Body $payload -ContentType 'application/json'
        }
        Pop-Location
    }
}
