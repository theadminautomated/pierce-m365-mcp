#Requires -Version 7.0
<#!
.SYNOPSIS
    Lightweight Web Search Engine
.DESCRIPTION
    Provides basic web search capabilities using publicly accessible
    search endpoints (e.g. DuckDuckGo HTML results). Designed for
    use by the Confidence Engine when confidence drops below
    threshold. Not intended for direct user invocation.
.NOTES
    Prototype implementation. Parsing logic is simplified and should
    be reviewed before production use.
#>

using namespace System.Collections.Generic

class WebSearchResult {
    [string]$Title
    [string]$Url
    [string]$Snippet
}

class WebSearchEngine {
    hidden [Logger] $Logger
    [int]$RateLimitSeconds = 5
    [DateTime]$LastQueryTime = [DateTime]::MinValue

    WebSearchEngine([Logger]$logger) {
        $this.Logger = $logger
    }

    [List[WebSearchResult]] Search([string]$query, [int]$maxResults) {
        if ($maxResults -le 0) { $maxResults = 5 }
        $this.EnforceRateLimit()
        $encoded = [System.Web.HttpUtility]::UrlEncode($query)
        $url = "https://duckduckgo.com/html/?q=$encoded"
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Method Get -ErrorAction Stop
            $results = $this.ParseResults($response.Content, $maxResults)
            $this.LastQueryTime = Get-Date
            return $results
        } catch {
            $this.Logger.Error('Web search failed', $_)
            return [List[WebSearchResult]]::new()
        }
    }

    hidden [void] EnforceRateLimit() {
        $diff = (Get-Date) - $this.LastQueryTime
        if ($diff.TotalSeconds -lt $this.RateLimitSeconds) {
            Start-Sleep -Seconds ($this.RateLimitSeconds - [int]$diff.TotalSeconds)
        }
    }

    hidden [List[WebSearchResult]] ParseResults([string]$html, [int]$maxResults) {
        $results = [List[WebSearchResult]]::new()
        $pattern = '<a rel="nofollow" class="result__a" href="(?<url>.*?)".*?>(?<title>.*?)</a>.*?<a class="result__snippet".*?>(?<snippet>.*?)</a>'
        $matches = [regex]::Matches($html, $pattern, 'Singleline')
        foreach ($match in $matches) {
            $r = [WebSearchResult]::new()
            $r.Url = $match.Groups['url'].Value
            $r.Title = ([regex]::Replace($match.Groups['title'].Value, '<.*?>', ''))
            $r.Snippet = ([regex]::Replace($match.Groups['snippet'].Value, '<.*?>', ''))
            $results.Add($r)
            if ($results.Count -ge $maxResults) { break }
        }
        return $results
    }
}

Export-ModuleMember -Class WebSearchEngine, WebSearchResult
