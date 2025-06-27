#Requires -Version 7.0
<#
.SYNOPSIS
    Semantic Index Engine for Vector Memory Bank
.DESCRIPTION
    Provides semantic embedding generation and similarity search capabilities
    using lightweight, open-source algorithms for enterprise memory systems.
.NOTES
    Implementation uses TF-IDF with cosine similarity as a free alternative
    to expensive commercial embedding APIs.
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Numerics
using namespace System.Text.RegularExpressions

class SemanticIndex {
    hidden [Logger] $Logger
    hidden [ConcurrentDictionary[string, double[]]] $VectorIndex
    hidden [ConcurrentDictionary[string, string]] $ContentMap
    hidden [Dictionary[string, double]] $TermFrequency
    hidden [Dictionary[string, int]] $DocumentFrequency
    hidden [int] $TotalDocuments
    hidden [List[string]] $Vocabulary
    hidden [int] $VectorDimensions
    hidden [bool] $IsInitialized
    
    SemanticIndex([Logger]$logger) {
        $this.Logger = $logger
        $this.VectorIndex = [ConcurrentDictionary[string, double[]]]::new()
        $this.ContentMap = [ConcurrentDictionary[string, string]]::new()
        $this.TermFrequency = [Dictionary[string, double]]::new()
        $this.DocumentFrequency = [Dictionary[string, int]]::new()
        $this.TotalDocuments = 0
        $this.Vocabulary = [List[string]]::new()
        $this.VectorDimensions = 384
        $this.IsInitialized = $false
    }
    
    [void] Initialize() {
        try {
            # Initialize with common M365/organizational terms
            $this.BuildBaseVocabulary()
            $this.IsInitialized = $true
            
            $this.Logger.Info("Semantic Index initialized", @{
                VectorDimensions = $this.VectorDimensions
                BaseVocabularySize = $this.Vocabulary.Count
            })
        } catch {
            $this.Logger.Error("Failed to initialize Semantic Index", @{
                Error = $_.Exception.Message
            })
            throw
        }
    }
    
    [double[]] GenerateEmbedding([string]$text) {
        if (-not $this.IsInitialized) {
            throw "Semantic Index not initialized"
        }
        
        try {
            # Preprocess text
            $tokens = $this.TokenizeText($text)
            $termCounts = $this.CountTerms($tokens)
            
            # Generate TF-IDF vector
            $vector = $this.GenerateTFIDFVector($termCounts, $tokens.Count)
            
            # Normalize vector
            $normalizedVector = $this.NormalizeVector($vector)
            
            return $normalizedVector
            
        } catch {
            $this.Logger.Error("Failed to generate embedding", @{
                Text = $text.Substring(0, [Math]::Min(100, $text.Length))
                Error = $_.Exception.Message
            })
            
            # Return zero vector on error
            return @(0.0) * $this.VectorDimensions
        }
    }
    
    [void] AddVector([string]$id, [double[]]$vector, [string]$content) {
        try {
            $this.VectorIndex.TryAdd($id, $vector)
            $this.ContentMap.TryAdd($id, $content)
            
            # Update vocabulary and statistics
            $tokens = $this.TokenizeText($content)
            $this.UpdateVocabularyStatistics($tokens)
            $this.TotalDocuments++
            
            $this.Logger.Debug("Vector added to index", @{
                Id = $id
                VectorLength = $vector.Length
                ContentLength = $content.Length
            })
            
        } catch {
            $this.Logger.Error("Failed to add vector to index", @{
                Id = $id
                Error = $_.Exception.Message
            })
        }
    }
    
    [void] RemoveVector([string]$id) {
        try {
            $removed = $this.VectorIndex.TryRemove($id, [ref]$null)
            $this.ContentMap.TryRemove($id, [ref]$null)
            
            if ($removed) {
                $this.TotalDocuments = [Math]::Max(0, $this.TotalDocuments - 1)
                
                $this.Logger.Debug("Vector removed from index", @{
                    Id = $id
                    RemainingVectors = $this.VectorIndex.Count
                })
            }
        } catch {
            $this.Logger.Error("Failed to remove vector from index", @{
                Id = $id
                Error = $_.Exception.Message
            })
        }
    }
    
    [List[SemanticSearchResult]] Search([double[]]$queryVector, [int]$maxResults) {
        $results = [List[SemanticSearchResult]]::new()
        
        try {
            # Calculate similarities with all vectors
            $similarities = [List[VectorSimilarity]]::new()
            
            foreach ($kvp in $this.VectorIndex) {
                $similarity = $this.CalculateCosineSimilarity($queryVector, $kvp.Value)
                
                if ($similarity -gt 0.1) {  # Filter very low similarities
                    $similarities.Add([VectorSimilarity]@{
                        Id = $kvp.Key
                        Similarity = $similarity
                    })
                }
            }
            
            # Sort by similarity and take top results
            $topSimilarities = $similarities | 
                Sort-Object Similarity -Descending | 
                Select-Object -First $maxResults
            
            foreach ($sim in $topSimilarities) {
                $results.Add([SemanticSearchResult]@{
                    Id = $sim.Id
                    Similarity = $sim.Similarity
                    Content = $this.ContentMap[$sim.Id]
                })
            }
            
            $this.Logger.Debug("Semantic search completed", @{
                QueryVectorLength = $queryVector.Length
                TotalVectors = $this.VectorIndex.Count
                ResultCount = $results.Count
                TopSimilarity = if ($results.Count -gt 0) { $results[0].Similarity } else { 0 }
            })
            
        } catch {
            $this.Logger.Error("Semantic search failed", @{
                Error = $_.Exception.Message
                QueryVectorLength = $queryVector.Length
            })
        }
        
        return $results
    }
    
    [List[string]] FindSimilarContent([string]$content, [double]$threshold = 0.8, [int]$maxResults = 5) {
        $similarContent = [List[string]]::new()
        
        try {
            $queryVector = $this.GenerateEmbedding($content)
            $searchResults = $this.Search($queryVector, $maxResults * 2)
            
            foreach ($result in $searchResults) {
                if ($result.Similarity -gt $threshold -and $result.Content -ne $content) {
                    $similarContent.Add($result.Content)
                    if ($similarContent.Count -ge $maxResults) {
                        break
                    }
                }
            }
            
        } catch {
            $this.Logger.Error("Failed to find similar content", @{
                Content = $content.Substring(0, [Math]::Min(50, $content.Length))
                Error = $_.Exception.Message
            })
        }
        
        return $similarContent
    }
    
    [hashtable] GetIndexStatistics() {
        return @{
            TotalVectors = $this.VectorIndex.Count
            TotalDocuments = $this.TotalDocuments
            VocabularySize = $this.Vocabulary.Count
            VectorDimensions = $this.VectorDimensions
            AverageTermsPerDocument = if ($this.TotalDocuments -gt 0) { 
                ($this.TermFrequency.Values | Measure-Object -Sum).Sum / $this.TotalDocuments 
            } else { 0 }
            TopTerms = $this.GetTopTerms(10)
            IsInitialized = $this.IsInitialized
        }
    }
    
    # Private helper methods
    hidden [void] BuildBaseVocabulary() {
        # Common M365 and organizational terms
        $baseTerms = @(
            # M365 terms
            'user', 'mailbox', 'email', 'calendar', 'group', 'distribution', 'security',
            'permission', 'access', 'rights', 'license', 'subscription', 'tenant',
            'exchange', 'outlook', 'teams', 'sharepoint', 'onedrive', 'azure',
            
            # Action terms
            'create', 'delete', 'modify', 'update', 'add', 'remove', 'grant', 'revoke',
            'enable', 'disable', 'configure', 'manage', 'assign', 'unassign',
            
            # Department terms
            'department', 'division', 'office', 'bureau', 'unit', 'team', 'group',
            'admin', 'administration', 'facilities', 'finance', 'hr', 'human resources',
            'it', 'technology', 'sheriff', 'police', 'public safety', 'health',
            'parks', 'recreation', 'library', 'planning', 'utilities',
            
            # Status terms
            'active', 'inactive', 'enabled', 'disabled', 'success', 'failed', 'error',
            'warning', 'complete', 'pending', 'approved', 'denied',
            
            # Time terms
            'today', 'yesterday', 'week', 'month', 'year', 'recent', 'old', 'new',
            'current', 'previous', 'next', 'last', 'first',
            
            # Pierce County specific
            'pierce', 'county', 'washington', 'tacoma', 'lakewood', 'puyallup',
            'government', 'municipal', 'public', 'citizen', 'service'
        )
        
        foreach ($term in $baseTerms) {
            if ($term -notin $this.Vocabulary) {
                $this.Vocabulary.Add($term.ToLower())
            }
        }
        
        # Pad vocabulary to reach target dimensions
        $currentSize = $this.Vocabulary.Count
        for ($i = $currentSize; $i -lt $this.VectorDimensions; $i++) {
            $this.Vocabulary.Add("term_$i")
        }
    }
    
    hidden [List[string]] TokenizeText([string]$text) {
        $tokens = [List[string]]::new()
        
        # Convert to lowercase and remove special characters
        $cleanText = $text.ToLower() -replace '[^\w\s@.-]', ' '
        
        # Split into words
        $words = $cleanText -split '\s+' | Where-Object { $_.Length -gt 2 }
        
        foreach ($word in $words) {
            # Handle email addresses specially
            if ($word -like '*@*') {
                $tokens.Add($word)
                # Also add domain part
                $domain = $word -split '@' | Select-Object -Last 1
                if ($domain) {
                    $tokens.Add($domain)
                }
            } else {
                $tokens.Add($word)
            }
        }
        
        return $tokens
    }
    
    hidden [Dictionary[string, int]] CountTerms([List[string]]$tokens) {
        $termCounts = [Dictionary[string, int]]::new()
        
        foreach ($token in $tokens) {
            if ($termCounts.ContainsKey($token)) {
                $termCounts[$token]++
            } else {
                $termCounts[$token] = 1
            }
        }
        
        return $termCounts
    }
    
    hidden [double[]] GenerateTFIDFVector([Dictionary[string, int]]$termCounts, [int]$totalTerms) {
        $vector = @(0.0) * $this.VectorDimensions
        
        for ($i = 0; $i -lt $this.Vocabulary.Count -and $i -lt $this.VectorDimensions; $i++) {
            $term = $this.Vocabulary[$i]
            
            if ($termCounts.ContainsKey($term)) {
                # Term Frequency
                $tf = $termCounts[$term] / $totalTerms
                
                # Inverse Document Frequency
                $idf = if ($this.DocumentFrequency.ContainsKey($term) -and $this.DocumentFrequency[$term] -gt 0) {
                    [Math]::Log($this.TotalDocuments / $this.DocumentFrequency[$term])
                } else {
                    [Math]::Log($this.TotalDocuments + 1)  # Smooth for unseen terms
                }
                
                # TF-IDF score
                $vector[$i] = $tf * $idf
            }
        }
        
        return $vector
    }
    
    hidden [double[]] NormalizeVector([double[]]$vector) {
        # Calculate magnitude
        $magnitude = [Math]::Sqrt(($vector | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
        
        if ($magnitude -eq 0) {
            return $vector
        }
        
        # Normalize
        $normalized = @()
        foreach ($component in $vector) {
            $normalized += $component / $magnitude
        }
        
        return $normalized
    }
    
    hidden [double] CalculateCosineSimilarity([double[]]$vector1, [double[]]$vector2) {
        if ($vector1.Length -ne $vector2.Length) {
            return 0.0
        }
        
        $dotProduct = 0.0
        $magnitude1 = 0.0
        $magnitude2 = 0.0
        
        for ($i = 0; $i -lt $vector1.Length; $i++) {
            $dotProduct += $vector1[$i] * $vector2[$i]
            $magnitude1 += $vector1[$i] * $vector1[$i]
            $magnitude2 += $vector2[$i] * $vector2[$i]
        }
        
        $magnitude1 = [Math]::Sqrt($magnitude1)
        $magnitude2 = [Math]::Sqrt($magnitude2)
        
        if ($magnitude1 -eq 0 -or $magnitude2 -eq 0) {
            return 0.0
        }
        
        return $dotProduct / ($magnitude1 * $magnitude2)
    }
    
    hidden [void] UpdateVocabularyStatistics([List[string]]$tokens) {
        $uniqueTerms = $tokens | Sort-Object -Unique
        
        foreach ($term in $uniqueTerms) {
            # Update document frequency
            if ($this.DocumentFrequency.ContainsKey($term)) {
                $this.DocumentFrequency[$term]++
            } else {
                $this.DocumentFrequency[$term] = 1
            }
            
            # Add to vocabulary if not present and we have space
            if ($term -notin $this.Vocabulary -and $this.Vocabulary.Count -lt $this.VectorDimensions) {
                $this.Vocabulary.Add($term)
            }
        }
        
        # Update term frequency for all tokens
        foreach ($token in $tokens) {
            if ($this.TermFrequency.ContainsKey($token)) {
                $this.TermFrequency[$token]++
            } else {
                $this.TermFrequency[$token] = 1
            }
        }
    }
    
    hidden [List[hashtable]] GetTopTerms([int]$count) {
        $topTerms = [List[hashtable]]::new()
        
        $sortedTerms = $this.TermFrequency.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First $count
        
        foreach ($term in $sortedTerms) {
            $topTerms.Add(@{
                Term = $term.Key
                Frequency = $term.Value
                DocumentFrequency = if ($this.DocumentFrequency.ContainsKey($term.Key)) { 
                    $this.DocumentFrequency[$term.Key] 
                } else { 0 }
            })
        }
        
        return $topTerms
    }
}

# Supporting classes
class VectorSimilarity {
    [string] $Id
    [double] $Similarity
}

class SemanticSearchResult {
    [string] $Id
    [double] $Similarity
    [string] $Content
}

# Export the semantic index class
if ($MyInvocation.InvocationName -ne '.') {
    return [SemanticIndex]
}
