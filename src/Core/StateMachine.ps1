#Requires -Version 7.0
<#
.SYNOPSIS
    Generic table-driven state machine for deterministic workflows
.DESCRIPTION
    Provides explicit state transitions, validation, and error handling for
    auditability. Used by MCP tools to manage multi-step processes.
#>

class StateMachine {
    [string]$CurrentState
    [hashtable]$States
    [Logger]$Logger

    StateMachine([hashtable]$states, [string]$initialState, [Logger]$logger) {
        $this.States = $states
        $this.CurrentState = $initialState
        $this.Logger = $logger
    }

    [void] Run([hashtable]$context) {
        while ($true) {
            if (-not $this.States.ContainsKey($this.CurrentState)) {
                throw "Undefined state: $($this.CurrentState)"
            }
            $state = $this.States[$this.CurrentState]
            $handler = $state.Handler
            $next = & $handler $context
            $this.Logger.Debug("State transition", @{ State=$this.CurrentState; Next=$next })
            if (-not $next) { break }
            $this.CurrentState = $next
        }
    }
}

Export-ModuleMember -Cmdlet * -Function * -Variable * -Alias *
