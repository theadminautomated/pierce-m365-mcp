#Requires -Version 7.0
<#
.SYNOPSIS
    Health monitoring and watchdog service for the MCP Server.
.DESCRIPTION
    Periodically collects health metrics and exposes a lightweight API
    for other components to query. Metrics include CPU, memory usage,
    and general process status. Results are logged and stored in a
    rolling history for troubleshooting and auditing.
#>

using namespace System.Collections.Concurrent

class HealthMonitor {
    [Logger] $Logger
    [System.Threading.Timer] $Timer
    [ConcurrentQueue[hashtable]] $History
    [TimeSpan] $Interval = [TimeSpan]::FromSeconds(30)

    HealthMonitor([Logger]$logger) {
        $this.Logger = $logger
        $this.History = [ConcurrentQueue[hashtable]]::new()
        $this.Start()
    }

    [void] Start() {
        $this.Timer = [System.Threading.Timer]::new({ param($state) $state.CheckHealth() }, $this, 0, $this.Interval.TotalMilliseconds)
    }

    [void] Stop() {
        if ($this.Timer) { $this.Timer.Dispose() }
    }

    [void] CheckHealth() {
        try {
            $status = @{ 
                timestamp = Get-Date
                memoryMB = [Math]::Round([System.GC]::GetTotalMemory($false) / 1MB, 2)
                cpuPercent = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
                process_running = $true
            }
            $this.History.Enqueue($status)
            $this.Logger.Debug('Health check', $status)
        } catch {
            $this.Logger.Warning('Health check failed', @{ error = $_.Exception.Message })
        }
    }

    [hashtable] GetLatestStatus() {
        $item = $null
        $this.History.TryPeek([ref]$item) | Out-Null
        return $item
    }

    [hashtable[]] GetHistory() {
        return $this.History.ToArray()
    }
}

