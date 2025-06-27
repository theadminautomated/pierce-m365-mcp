#Requires -Version 7.0
<#!
.SYNOPSIS
    Confidence Interval Engine for MCP Server
.DESCRIPTION
    Provides dynamic confidence interval calculations for all MCP operations using Wilson score interval.
    Stores success metrics per action type and determines if confidence falls below threshold.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.1.0-rc
#>

using namespace System.Collections.Concurrent

class StatsRecord {
    [int]$Success
    [int]$Total
    StatsRecord() { $this.Success = 0; $this.Total = 0 }
}

class ConfidenceMetrics {
    [string]$ActionType
    [double]$Mean
    [double]$LowerBound
    [double]$UpperBound
    [int]$SampleSize
    [double]$ConfidenceLevel
    [string]$Method
    [bool]$IsHighConfidence
    [hashtable]$Metadata

    ConfidenceMetrics() { $this.Method = 'Wilson'; $this.Metadata = @{} }
}

class ConfidenceEngine {
    hidden [ConcurrentDictionary[string, StatsRecord]] $Stats
    hidden [Logger] $Logger
    hidden [double] $DefaultLevel = 0.95

    ConfidenceEngine([Logger]$logger) {
        $this.Stats = [ConcurrentDictionary[string, StatsRecord]]::new()
        $this.Logger = $logger
    }

    [void] RegisterOutcome([string]$actionType, [bool]$success) {
        $record = $null
        if (-not $this.Stats.TryGetValue($actionType, [ref]$record)) {
            $record = [StatsRecord]::new()
            $this.Stats.TryAdd($actionType, $record) | Out-Null
        }
        if ($success) { $record.Success++ }
        $record.Total++
    }

    [ConfidenceMetrics] Evaluate([string]$actionType, [double]$confidenceLevel) {
        if (-not $confidenceLevel) { $confidenceLevel = $this.DefaultLevel }
        $z = 1.96
        $metrics = [ConfidenceMetrics]::new()
        $metrics.ActionType = $actionType
        $metrics.ConfidenceLevel = $confidenceLevel
        $record = $null
        if (-not $this.Stats.TryGetValue($actionType, [ref]$record)) {
            $metrics.Mean = 1
            $metrics.LowerBound = 1
            $metrics.UpperBound = 1
            $metrics.SampleSize = 0
            $metrics.IsHighConfidence = $true
            return $metrics
        }
        $n = [double]$record.Total
        $p = if ($n -eq 0) { 1 } else { [double]$record.Success / $n }
        $denom = 1 + ($z*$z)/$n
        $center = ($p + ($z*$z)/(2*$n)) / $denom
        $margin = ($z * [Math]::Sqrt(($p*(1-$p) + ($z*$z)/(4*$n)) / $n)) / $denom
        $metrics.Mean = $p
        $metrics.LowerBound = [Math]::Max(0, $center - $margin)
        $metrics.UpperBound = [Math]::Min(1, $center + $margin)
        $metrics.SampleSize = [int]$n
        $metrics.IsHighConfidence = $metrics.LowerBound -ge $confidenceLevel
        return $metrics
    }
}

Export-ModuleMember -Class ConfidenceEngine, ConfidenceMetrics
