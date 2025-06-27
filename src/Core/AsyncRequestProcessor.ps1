#Requires -Version 7.0
<#$
.SYNOPSIS
    Asynchronous request processor using a runspace pool
.DESCRIPTION
    Provides simple concurrency for MCP requests by executing
    OrchestrationEngine.ProcessRequest in parallel runspaces.
    This enables improved throughput when multiple requests
    are received concurrently.
.NOTES
    Added for async processing feature.
#>

using namespace System.Collections.Concurrent

class AsyncRequestProcessor {
    [RunspacePool] $RunspacePool
    [OrchestrationEngine] $Engine
    [Logger] $Logger
    [int] $MaxConcurrency
    hidden [ConcurrentDictionary[Guid, hashtable]] $Tasks

    AsyncRequestProcessor([OrchestrationEngine]$engine, [Logger]$logger, [int]$maxConcurrency = 4) {
        $this.Engine = $engine
        $this.Logger = $logger
        $this.MaxConcurrency = $maxConcurrency
        $this.Tasks = [ConcurrentDictionary[Guid, hashtable]]::new()
        $pool = [runspacefactory]::CreateRunspacePool(1, $maxConcurrency)
        $pool.Open()
        $this.RunspacePool = $pool
    }

    [Guid] SubmitRequest([OrchestrationRequest]$request) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $this.RunspacePool
        $script = {
            param($eng,$req)
            $eng.ProcessRequest($req)
        }
        $ps.AddScript($script).AddArgument($this.Engine).AddArgument($request) | Out-Null
        $jobId = [Guid]::NewGuid()
        $async = $ps.BeginInvoke()
        $taskInfo = @{ PowerShell = $ps; AsyncResult = $async }
        $this.Tasks[$jobId] = $taskInfo
        $this.Logger.Debug('Async request submitted', @{ JobId = $jobId; Request = $request.Input })
        return $jobId
    }

    [object] GetResult([Guid]$jobId) {
        $task = $null
        if ($this.Tasks.TryGetValue($jobId, [ref]$task)) {
            if ($task.AsyncResult.IsCompleted) {
                try {
                    $result = $task.PowerShell.EndInvoke($task.AsyncResult)
                    $this.Logger.Debug('Async request completed', @{ JobId = $jobId })
                } finally {
                    $task.PowerShell.Dispose()
                    $null = $this.Tasks.TryRemove($jobId, [ref]$null)
                }
                return $result
            }
        }
        return $null
    }

    [void] WaitAll() {
        foreach ($task in $this.Tasks.Values) {
            $task.AsyncResult.AsyncWaitHandle.WaitOne()
            $null = $task.PowerShell.EndInvoke($task.AsyncResult)
            $task.PowerShell.Dispose()
        }
        $this.Tasks.Clear()
    }

    [void] Dispose() {
        $this.WaitAll()
        $this.RunspacePool.Close()
        $this.RunspacePool.Dispose()
    }
}

Export-ModuleMember -Class AsyncRequestProcessor
