#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Logging and Monitoring Framework
.DESCRIPTION
    Provides comprehensive logging, monitoring, and telemetry capabilities
    for the Pierce County M365 MCP Server with enterprise-grade features.
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.IO

enum LogLevel {
    Trace = 0
    Debug = 1
    Info = 2
    Warning = 3
    Error = 4
    Fatal = 5
}

class Logger {
    hidden [LogLevel] $MinimumLevel
    hidden [List[LogTargetBase]] $Targets
    hidden [ConcurrentQueue[LogEntry]] $LogQueue
    hidden [System.Threading.Timer] $FlushTimer
    hidden [bool] $IsDisposed
    hidden [LogFormatter] $Formatter
    hidden [LogMetrics] $Metrics
    
    Logger([LogLevel]$minimumLevel = [LogLevel]::Info) {
        $this.MinimumLevel = $minimumLevel
        $this.Targets = [List[LogTargetBase]]::new()
        $this.LogQueue = [ConcurrentQueue[LogEntry]]::new()
        $this.IsDisposed = $false
        $this.Formatter = [LogFormatter]::new()
        $this.Metrics = [LogMetrics]::new()
        
        $this.InitializeDefaultTargets()
        $this.StartFlushTimer()
    }
    
    [void] Trace([string]$message) {
        $this.Log([LogLevel]::Trace, $message, $null, $null)
    }
    
    [void] Trace([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Trace, $message, $context, $null)
    }
    
    [void] Debug([string]$message) {
        $this.Log([LogLevel]::Debug, $message, $null, $null)
    }
    
    [void] Debug([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Debug, $message, $context, $null)
    }
    
    [void] Info([string]$message) {
        $this.Log([LogLevel]::Info, $message, $null, $null)
    }
    
    [void] Info([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Info, $message, $context, $null)
    }
    
    [void] Warning([string]$message) {
        $this.Log([LogLevel]::Warning, $message, $null, $null)
    }
    
    [void] Warning([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Warning, $message, $context, $null)
    }
    
    [void] Error([string]$message) {
        $this.Log([LogLevel]::Error, $message, $null, $null)
    }
    
    [void] Error([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Error, $message, $context, $null)
    }
    
    [void] Error([string]$message, [Exception]$exception) {
        $this.Log([LogLevel]::Error, $message, $null, $exception)
    }
    
    [void] Error([string]$message, [hashtable]$context, [Exception]$exception) {
        $this.Log([LogLevel]::Error, $message, $context, $exception)
    }
    
    [void] Fatal([string]$message) {
        $this.Log([LogLevel]::Fatal, $message, $null, $null)
    }
    
    [void] Fatal([string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Fatal, $message, $context, $null)
    }
    
    [void] Fatal([string]$message, [Exception]$exception) {
        $this.Log([LogLevel]::Fatal, $message, $null, $exception)
    }
    
    [void] AddTarget([LogTargetBase]$target) {
        $this.Targets.Add($target)
    }
    
    [void] RemoveTarget([LogTargetBase]$target) {
        $this.Targets.Remove($target)
    }
    
    [LogMetrics] GetMetrics() {
        return $this.Metrics
    }
    
    hidden [void] Log([LogLevel]$level, [string]$message, [hashtable]$context, [Exception]$exception) {
        if ($this.IsDisposed -or $level -lt $this.MinimumLevel) {
            return
        }
        
        try {
            $entry = [LogEntry]::new($level, $message, $context, $exception)
            $this.LogQueue.Enqueue($entry)
            $this.Metrics.RecordLogEntry($level)
            
            # For fatal errors, flush immediately
            if ($level -eq [LogLevel]::Fatal) {
                $this.FlushLogs()
            }
        }
        catch {
            # Avoid infinite recursion on logging errors
            [Console]::Error.WriteLine("Logging error: $($_.Exception.Message)")
        }
    }
    
    hidden [void] InitializeDefaultTargets() {
        # Console target for error output
        $consoleTarget = [ConsoleLogTarget]::new([LogLevel]::Warning)
        $this.AddTarget($consoleTarget)
        
        # File target for all logs
        $logDir = Join-Path $env:TEMP "PierceCountyMCP\Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $logFile = Join-Path $logDir "mcp-server-$(Get-Date -Format 'yyyy-MM-dd').log"
        $fileTarget = [FileLogTarget]::new($logFile, [LogLevel]::Debug)
        $this.AddTarget($fileTarget)
        
        # Event log target for Windows events
        if ($global:PSVersionTable.Platform -eq "Win32NT" -or $env:OS -eq "Windows_NT") {
            try {
                $eventTarget = [EventLogTarget]::new("Pierce County MCP", [LogLevel]::Warning)
                $this.AddTarget($eventTarget)
            }
            catch {
                # Event log registration might fail in non-admin contexts
                [Console]::Error.WriteLine("Failed to initialize event log target: $($_.Exception.Message)")
            }
        }
        
        # Structured log target for SIEM integration
        $structuredLogFile = Join-Path $logDir "mcp-structured-$(Get-Date -Format 'yyyy-MM-dd').json"
        $structuredTarget = [StructuredLogTarget]::new($structuredLogFile, [LogLevel]::Info)
        $this.AddTarget($structuredTarget)
    }
    
    hidden [void] StartFlushTimer() {
        # Flush logs every 5 seconds
        $this.FlushTimer = [System.Threading.Timer]::new(
            { param($state) $state.FlushLogs() },
            $this,
            5000,
            5000
        )
    }
    
    hidden [void] FlushLogs() {
        $entries = @()
        $entry = $null
        
        # Dequeue all pending entries
        while ($this.LogQueue.TryDequeue([ref]$entry)) {
            $entries += $entry
        }
        
        if ($entries.Count -eq 0) {
            return
        }
        
        # Send to all targets
        foreach ($target in $this.Targets) {
            try {
                foreach ($entry in $entries) {
                    if ($entry.Level -ge $target.MinimumLevel) {
                        $target.Write($entry, $this.Formatter)
                    }
                }
                $target.Flush()
            }
            catch {
                [Console]::Error.WriteLine("Log target error: $($_.Exception.Message)")
            }
        }
    }
    
    [void] Dispose() {
        if ($this.IsDisposed) {
            return
        }
        
        $this.IsDisposed = $true
        
        # Flush remaining logs
        $this.FlushLogs()
        
        # Dispose timer
        if ($this.FlushTimer) {
            $this.FlushTimer.Dispose()
        }
        
        # Dispose targets
        foreach ($target in $this.Targets) {
            if ($target -is [IDisposable]) {
                $target.Dispose()
            }
        }
        
        $this.Targets.Clear()
    }
}

class LogEntry {
    [DateTime] $Timestamp
    [LogLevel] $Level
    [string] $Message
    [hashtable] $Context
    [Exception] $Exception
    [string] $ThreadId
    [string] $ProcessId
    [string] $MachineName
    [string] $UserName
    
    LogEntry([LogLevel]$level, [string]$message, [hashtable]$context, [Exception]$exception) {
        $this.Timestamp = Get-Date
        $this.Level = $level
        $this.Message = $message
        $this.Context = $context ?? @{}
        $this.Exception = $exception
        $this.ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId.ToString()
        $this.ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id.ToString()
        $this.MachineName = $env:COMPUTERNAME
        $this.UserName = $env:USERNAME
    }
    
    [hashtable] ToHashtable() {
        $hash = @{
            Timestamp = $this.Timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            Level = $this.Level.ToString()
            Message = $this.Message
            ThreadId = $this.ThreadId
            ProcessId = $this.ProcessId
            MachineName = $this.MachineName
            UserName = $this.UserName
        }
        
        if ($this.Context.Count -gt 0) {
            $hash['Context'] = $this.Context
        }
        
        if ($this.Exception) {
            $hash['Exception'] = @{
                Type = $this.Exception.GetType().Name
                Message = $this.Exception.Message
                StackTrace = $this.Exception.StackTrace
            }
        }
        
        return $hash
    }
}

class LogFormatter {
    [string] FormatEntry([LogEntry]$entry) {
        $timestamp = $entry.Timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff')
        $level = $entry.Level.ToString().ToUpper().PadRight(7)
        $thread = "[$($entry.ThreadId)]"
        
        $message = "[$timestamp] $level $thread $($entry.Message)"
        
        if ($entry.Context.Count -gt 0) {
            $contextJson = $entry.Context | ConvertTo-Json -Compress -Depth 3
            $message += " | Context: $contextJson"
        }
        
        if ($entry.Exception) {
            $message += " | Exception: $($entry.Exception.GetType().Name): $($entry.Exception.Message)"
            if ($entry.Exception.StackTrace) {
                $message += "`n$($entry.Exception.StackTrace)"
            }
        }
        
        return $message
    }
    
    [string] FormatStructured([LogEntry]$entry) {
        return $entry.ToHashtable() | ConvertTo-Json -Compress -Depth 5
    }
}

# Base class for log targets
class LogTargetBase {
    [LogLevel] $MinimumLevel
    
    LogTargetBase([LogLevel]$minimumLevel) {
        $this.MinimumLevel = $minimumLevel
    }
    
    [void] Write([LogEntry]$entry, [LogFormatter]$formatter) {
        throw "Write method must be implemented by derived class"
    }
    
    [void] Flush() {
        # Default implementation - override if needed
    }
}

class ConsoleLogTarget : LogTargetBase {
    
    ConsoleLogTarget([LogLevel]$minimumLevel) : base($minimumLevel) {
    }
    
    [void] Write([LogEntry]$entry, [LogFormatter]$formatter) {
        $message = $formatter.FormatEntry($entry)
        
        switch ($entry.Level) {
            ([LogLevel]::Error) { [Console]::Error.WriteLine($message) }
            ([LogLevel]::Fatal) { [Console]::Error.WriteLine($message) }
            default { [Console]::Error.WriteLine($message) }
        }
    }
    
    [void] Flush() {
        # Console auto-flushes
    }
}

class FileLogTarget : LogTargetBase {
    [string] $FilePath
    hidden [System.IO.StreamWriter] $Writer
    hidden [object] $Lock
    
    FileLogTarget([string]$filePath, [LogLevel]$minimumLevel) : base($minimumLevel) {
        $this.FilePath = $filePath
        $this.Lock = [object]::new()
        
        # Ensure directory exists
        $directory = [System.IO.Path]::GetDirectoryName($filePath)
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Initialize writer with UTF8 encoding and auto-flush
        $this.Writer = [System.IO.StreamWriter]::new($filePath, $true, [System.Text.Encoding]::UTF8)
        $this.Writer.AutoFlush = $false
    }
    
    [void] Write([LogEntry]$entry, [LogFormatter]$formatter) {
        $message = $formatter.FormatEntry($entry)
        
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.Writer.WriteLine($message)
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [void] Flush() {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.Writer.Flush()
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [void] Dispose() {
        if ($this.Writer) {
            $this.Writer.Dispose()
        }
    }
}

class StructuredLogTarget : LogTargetBase {
    [string] $FilePath
    hidden [System.IO.StreamWriter] $Writer
    hidden [object] $Lock
    
    StructuredLogTarget([string]$filePath, [LogLevel]$minimumLevel) : base($minimumLevel) {
        $this.FilePath = $filePath
        $this.Lock = [object]::new()
        
        # Ensure directory exists
        $directory = [System.IO.Path]::GetDirectoryName($filePath)
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        $this.Writer = [System.IO.StreamWriter]::new($filePath, $true, [System.Text.Encoding]::UTF8)
        $this.Writer.AutoFlush = $false
    }
    
    [void] Write([LogEntry]$entry, [LogFormatter]$formatter) {
        $message = $formatter.FormatStructured($entry)
        
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.Writer.WriteLine($message)
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [void] Flush() {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.Writer.Flush()
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [void] Dispose() {
        if ($this.Writer) {
            $this.Writer.Dispose()
        }
    }
}

class EventLogTarget : LogTargetBase {
    [string] $Source
    [string] $LogName
    
    EventLogTarget([string]$source, [LogLevel]$minimumLevel) : base($minimumLevel) {
        $this.Source = $source
        $this.LogName = "Application"
        
        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            try {
                [System.Diagnostics.EventLog]::CreateEventSource($source, $this.LogName)
            }
            catch {
                # Might not have permissions - use default source
                $this.Source = "Application"
            }
        }
    }
    
    [void] Write([LogEntry]$entry, [LogFormatter]$formatter) {
        $message = $formatter.FormatEntry($entry)
        $eventType = $this.GetEventType($entry.Level)
        $eventId = $this.GetEventId($entry.Level)
        
        try {
            [System.Diagnostics.EventLog]::WriteEntry($this.Source, $message, $eventType, $eventId)
        }
        catch {
            # Silently fail to avoid recursion
        }
    }
    
    [void] Flush() {
        # Event log auto-flushes
    }
    
    hidden [System.Diagnostics.EventLogEntryType] GetEventType([LogLevel]$level) {
        switch ($level) {
            ([LogLevel]::Error) { 
                return [System.Diagnostics.EventLogEntryType]::Error 
            }
            ([LogLevel]::Fatal) { 
                return [System.Diagnostics.EventLogEntryType]::Error 
            }
            ([LogLevel]::Warning) { 
                return [System.Diagnostics.EventLogEntryType]::Warning 
            }
            default { 
                return [System.Diagnostics.EventLogEntryType]::Information 
            }
        }
        # This should never be reached, but satisfy parser
        return [System.Diagnostics.EventLogEntryType]::Information
    }
    
    hidden [int] GetEventId([LogLevel]$level) {
        return [int]$level + 1000
    }
}

class LogMetrics {
    hidden [ConcurrentDictionary[LogLevel, int]] $Counts
    [DateTime] $StartTime
    [DateTime] $LastLogTime
    
    LogMetrics() {
        $this.Counts = [ConcurrentDictionary[LogLevel, int]]::new()
        $this.StartTime = Get-Date
        $this.LastLogTime = Get-Date
        
        # Initialize counters
        foreach ($level in [Enum]::GetValues([LogLevel])) {
            $this.Counts.TryAdd($level, 0)
        }
    }
    
    [void] RecordLogEntry([LogLevel]$level) {
        $this.Counts.AddOrUpdate($level, 1, { param($key, $value) $value + 1 })
        $this.LastLogTime = Get-Date
    }
    
    [int] GetCount([LogLevel]$level) {
        $count = 0
        $this.Counts.TryGetValue($level, [ref]$count)
        return $count
    }
    
    [int] GetTotalCount() {
        $total = 0
        foreach ($count in $this.Counts.Values) {
            $total += $count
        }
        return $total
    }
    
    [hashtable] GetSummary() {
        return @{
            StartTime = $this.StartTime
            LastLogTime = $this.LastLogTime
            Uptime = (Get-Date) - $this.StartTime
            TotalLogs = $this.GetTotalCount()
            LogCounts = @{
                Trace = $this.GetCount([LogLevel]::Trace)
                Debug = $this.GetCount([LogLevel]::Debug)
                Info = $this.GetCount([LogLevel]::Info)
                Warning = $this.GetCount([LogLevel]::Warning)
                Error = $this.GetCount([LogLevel]::Error)
                Fatal = $this.GetCount([LogLevel]::Fatal)
            }
        }
    }
}

# Performance monitoring classes
class PerformanceMonitor {
    hidden [ConcurrentDictionary[string, PerformanceCounter]] $Counters
    hidden [Logger] $Logger
    hidden [System.Threading.Timer] $CollectionTimer
    hidden [long] $TotalOperations
    hidden [long] $ErrorCount
    hidden [TimeSpan] $AggregateDuration
    hidden [object] $AggregateLock
    
    PerformanceMonitor([Logger]$logger) {
        $this.Logger = $logger
        $this.TotalOperations = 0
        $this.ErrorCount = 0
        $this.AggregateDuration = [TimeSpan]::Zero
        $this.AggregateLock = [object]::new()
        $this.Counters = [ConcurrentDictionary[string, PerformanceCounter]]::new()
        $this.InitializeCounters()
        $this.StartCollection()
    }
    
    [void] StartOperation([string]$operationName) {
        $counter = $this.GetOrCreateCounter($operationName)
        $counter.Start()
    }
    
    [void] EndOperation([string]$operationName, [bool]$success = $true) {
        $counter = $this.GetOrCreateCounter($operationName)
        $duration = $counter.End()
        [System.Threading.Monitor]::Enter($this.AggregateLock)
        try {
            $this.TotalOperations++
            $this.AggregateDuration = $this.AggregateDuration.Add($duration)
            if (-not $success) { $this.ErrorCount++ }
        } finally {
            [System.Threading.Monitor]::Exit($this.AggregateLock)
        }
    }
    
    [PerformanceCounter] GetCounter([string]$operationName) {
        $counter = $null
        $this.Counters.TryGetValue($operationName, [ref]$counter)
        return $counter
    }
    
    hidden [PerformanceCounter] GetOrCreateCounter([string]$operationName) {
        $counter = $null
        if (-not $this.Counters.TryGetValue($operationName, [ref]$counter)) {
            $counter = [PerformanceCounter]::new($operationName)
            $this.Counters.TryAdd($operationName, $counter)
        }
        return $counter
    }
    
    hidden [void] InitializeCounters() {
        # Initialize standard counters
        $standardOperations = @(
            'request_processing',
            'tool_execution',
            'entity_extraction',
            'validation',
            'orchestration'
        )
        
        foreach ($operation in $standardOperations) {
            $this.GetOrCreateCounter($operation)
        }
    }
    
    hidden [void] StartCollection() {
        # Collect performance metrics every 30 seconds
        $this.CollectionTimer = [System.Threading.Timer]::new(
            { param($state) $state.CollectMetrics() },

            $this,
            30000,
            30000
        )
    }
    
    [long] GetTotalOperations() {
        return $this.TotalOperations
    }

    [double] GetAverageResponseTime() {
        if ($this.TotalOperations -eq 0) { return 0 }
        return ($this.AggregateDuration.TotalMilliseconds / $this.TotalOperations)
    }

    [double] GetErrorRate() {
        if ($this.TotalOperations -eq 0) { return 0 }
        return [math]::Round($this.ErrorCount / [double]$this.TotalOperations, 4)
    }

    
    [void] Dispose() {
        if ($this.CollectionTimer) {
            $this.CollectionTimer.Dispose()
        }
    }
}

class PerformanceCounter {
    [string] $Name
    [int] $ExecutionCount
    [TimeSpan] $TotalDuration
    [TimeSpan] $MinDuration
    [TimeSpan] $MaxDuration
    [TimeSpan] $AverageDuration
    [DateTime] $LastExecution
    hidden [DateTime] $CurrentStart
    hidden [object] $Lock
    
    PerformanceCounter([string]$name) {
        $this.Name = $name
        $this.ExecutionCount = 0
        $this.TotalDuration = [TimeSpan]::Zero
        $this.MinDuration = [TimeSpan]::MaxValue
        $this.MaxDuration = [TimeSpan]::Zero
        $this.AverageDuration = [TimeSpan]::Zero
        $this.Lock = [object]::new()
    }
    
    [void] Start() {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.CurrentStart = Get-Date
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [TimeSpan] End() {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if ($this.CurrentStart -eq [DateTime]::MinValue) {
                return [TimeSpan]::Zero
            }
            
            $duration = (Get-Date) - $this.CurrentStart
            $this.ExecutionCount++
            $this.TotalDuration = $this.TotalDuration.Add($duration)
            $this.LastExecution = Get-Date
            
            if ($duration -lt $this.MinDuration) {
                $this.MinDuration = $duration
            }
            
            if ($duration -gt $this.MaxDuration) {
                $this.MaxDuration = $duration
            }
            
            $this.AverageDuration = [TimeSpan]::FromTicks($this.TotalDuration.Ticks / $this.ExecutionCount)
            $this.CurrentStart = [DateTime]::MinValue
            return $duration
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [hashtable] GetMetrics() {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            return @{
                ExecutionCount = $this.ExecutionCount
                TotalDurationMs = $this.TotalDuration.TotalMilliseconds
                MinDurationMs = if ($this.MinDuration -eq [TimeSpan]::MaxValue) { 0 } else { $this.MinDuration.TotalMilliseconds }
                MaxDurationMs = $this.MaxDuration.TotalMilliseconds
                AverageDurationMs = $this.AverageDuration.TotalMilliseconds
                LastExecution = $this.LastExecution
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
}
