#Requires -Version 7.0
<#
.SYNOPSIS
    Rule-based fallback parser for entity extraction
.DESCRIPTION
    Provides deterministic regex and lookup table parsing when
    AI-driven extraction yields low confidence or fails.
#>

using namespace System.Collections.Generic
using namespace System.Text.RegularExpressions

class RuleBasedParser {
    [Logger]$Logger

    RuleBasedParser([Logger]$logger) {
        $this.Logger = $logger
    }

    [Hashtable] Parse([string]$input) {
        $result = @{ Users = @(); Mailboxes = @(); Groups = @() }
        try {
            $emailRegex = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
            foreach ($match in [Regex]::Matches($input, $emailRegex)) {
                $email = $match.Value.ToLower()
                if ($email -match '@piercecountywa\.gov$') {
                    $result.Users += $email
                }
            }

            $groupRegex = '\\b(?:DL|GRP)-[A-Z0-9_-]+'
            foreach ($match in [Regex]::Matches($input, $groupRegex)) {
                $result.Groups += $match.Value
            }

            $mailRegex = '[a-z0-9._%+-]+@piercecountywa\.gov'
            foreach ($match in [Regex]::Matches($input, $mailRegex)) {
                $result.Mailboxes += $match.Value.ToLower()
            }
        } catch {
            $this.Logger.Warning('Rule-based parsing error', @{ Error = $_.Exception.Message })
        }
        return $result
    }
}

