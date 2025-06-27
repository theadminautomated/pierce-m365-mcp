#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Vector Memory Bank System
.DESCRIPTION
    Advanced memory storage and retrieval system using vector embeddings,
    semantic search, and persistent storage for enterprise-grade context management.
    Based on open-source vector database patterns and semantic similarity algorithms.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Memory Architecture: Vector-based with semantic search capabilities
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Numerics
using namespace System.IO
using namespace System.Text.Json

class VectorMemoryBank {
    hidden [Logger] $Logger
    hidden [string] $StoragePath
    hidden [ConcurrentDictionary[string, MemoryVector]] $VectorStore
    hidden [ConcurrentDictionary[string, ConversationContext]] $ConversationHistory
    hidden [ConcurrentDictionary[string, EntityMemory]] $EntityDatabase
    hidden [SemanticIndex] $SemanticIndex
    hidden [PatternAnalyzer] $PatternAnalyzer
    hidden [MemoryPersistence] $Persistence
    hidden [int] $VectorDimensions = 384  # Standard embedding size
    hidden [double] $SimilarityThreshold = 0.75
    hidden [int] $MaxMemoryItems = 10000
    hidden [DateTime] $LastCleanup
    
    VectorMemoryBank([Logger]$logger, [string]$storagePath) {
        $this.Logger = $logger
        $this.StoragePath = $storagePath
        $this.VectorStore = [ConcurrentDictionary[string, MemoryVector]]::new()
        $this.ConversationHistory = [ConcurrentDictionary[string, ConversationContext]]::new()
        $this.EntityDatabase = [ConcurrentDictionary[string, EntityMemory]]::new()
        $this.SemanticIndex = [SemanticIndex]::new($logger)
        $this.PatternAnalyzer = [PatternAnalyzer]::new($logger)
        $this.Persistence = [MemoryPersistence]::new($storagePath, $logger)
        $this.LastCleanup = Get-Date
        
        $this.InitializeMemoryBank()
    }
    
    [void] InitializeMemoryBank() {
        try {
            # Create storage directory
            if (-not (Test-Path $this.StoragePath)) {
                New-Item -ItemType Directory -Path $this.StoragePath -Force | Out-Null
            }
            
            # Load existing memory
            $this.LoadPersistedMemory()
            
            # Initialize semantic index
            $this.SemanticIndex.Initialize()
            
            $this.Logger.Info("Vector Memory Bank initialized", @{
                StoragePath = $this.StoragePath
                VectorDimensions = $this.VectorDimensions
                MaxMemoryItems = $this.MaxMemoryItems
                ExistingMemories = $this.VectorStore.Count
            })
            
        } catch {
            $this.Logger.Error("Failed to initialize Vector Memory Bank", @{
                Error = $_.Exception.Message
                StoragePath = $this.StoragePath
            })
            throw
        }
    }
    
    [string] StoreMemory([string]$content, [string]$context, [hashtable]$metadata, [string]$sessionId) {
        try {
            $memoryId = [Guid]::NewGuid().ToString()
            $timestamp = Get-Date
            
            # Generate semantic vector for content
            $vector = $this.SemanticIndex.GenerateEmbedding($content)
            
            # Create memory object
            $memory = [MemoryVector]@{
                Id = $memoryId
                Content = $content
                Context = $context
                Vector = $vector
                Metadata = $metadata
                SessionId = $sessionId
                Created = $timestamp
                LastAccessed = $timestamp
                AccessCount = 0
                Importance = $this.CalculateImportance($content, $metadata)
                Tags = $this.ExtractTags($content, $metadata)
            }
            
            # Store in vector database
            $this.VectorStore.TryAdd($memoryId, $memory)
            
            # Update semantic index
            $this.SemanticIndex.AddVector($memoryId, $vector, $content)
            
            # Update conversation context
            $this.UpdateConversationContext($sessionId, $memory)
            
            # Extract and store entities
            $this.ExtractAndStoreEntities($content, $metadata, $memoryId)
            
            # Analyze patterns
            $this.PatternAnalyzer.AnalyzeNewMemory($memory)
            
            $this.Logger.Debug("Memory stored", @{
                MemoryId = $memoryId
                Content = $content.Substring(0, [Math]::Min(100, $content.Length)) + "..."
                Context = $context
                SessionId = $sessionId
                Importance = $memory.Importance
            })
            
            # Cleanup if needed
            $this.PerformMaintenanceIfNeeded()
            
            return $memoryId
            
        } catch {
            $this.Logger.Error("Failed to store memory", @{
                Content = $content.Substring(0, [Math]::Min(50, $content.Length))
                Error = $_.Exception.Message
                SessionId = $sessionId
            })
            throw
        }
    }
    
    [List[MemorySearchResult]] SearchMemory([string]$query, [string]$sessionId, [int]$maxResults = 10) {
        try {
            $results = [List[MemorySearchResult]]::new()
            
            # Generate query vector
            $queryVector = $this.SemanticIndex.GenerateEmbedding($query)
            
            # Semantic search
            $semanticResults = $this.SemanticIndex.Search($queryVector, $maxResults * 2)
            
            # Score and rank results
            foreach ($result in $semanticResults) {
                if ($this.VectorStore.ContainsKey($result.Id)) {
                    $memory = $this.VectorStore[$result.Id]
                    
                    # Calculate composite score
                    $score = $this.CalculateCompositeScore($memory, $result.Similarity, $query, $sessionId)
                    
                    if ($score -gt $this.SimilarityThreshold) {
                        $searchResult = [MemorySearchResult]@{
                            Memory = $memory
                            Similarity = $result.Similarity
                            CompositeScore = $score
                            MatchType = $this.DetermineMatchType($memory, $query)
                            Explanation = $this.GenerateExplanation($memory, $query, $score)
                        }
                        
                        $results.Add($searchResult)
                        
                        # Update access statistics
                        $memory.LastAccessed = Get-Date
                        $memory.AccessCount++
                    }
                }
            }
            
            # Sort by composite score and limit results
            $finalResults = $results | Sort-Object CompositeScore -Descending | Select-Object -First $maxResults
            
            $this.Logger.Debug("Memory search completed", @{
                Query = $query
                SessionId = $sessionId
                ResultCount = $finalResults.Count
                MaxScore = if ($finalResults.Count -gt 0) { $finalResults[0].CompositeScore } else { 0 }
            })
            
            return $finalResults
            
        } catch {
            $this.Logger.Error("Memory search failed", @{
                Query = $query
                Error = $_.Exception.Message
                SessionId = $sessionId
            })
            return [List[MemorySearchResult]]::new()
        }
    }
    
    [ConversationContext] GetConversationContext([string]$sessionId) {
        $context = $null
        if ($this.ConversationHistory.TryGetValue($sessionId, [ref]$context)) {
            return $context
        }
        
        # Create new conversation context
        $newContext = [ConversationContext]@{
            SessionId = $sessionId
            Started = Get-Date
            LastActivity = Get-Date
            MemoryIds = [List[string]]::new()
            EntityReferences = [Dictionary[string, EntityReference]]::new()
            Topics = [List[string]]::new()
            IntentHistory = [List[string]]::new()
            UserPreferences = @{}
        }
        
        $this.ConversationHistory.TryAdd($sessionId, $newContext)
        return $newContext
    }
    
    [List[EntityMemory]] GetRelatedEntities([string]$entityId, [string]$entityType, [int]$maxResults = 5) {
        try {
            $relatedEntities = [List[EntityMemory]]::new()
            
            # Search for entities with similar vectors
            if ($this.EntityDatabase.ContainsKey($entityId)) {
                $sourceEntity = $this.EntityDatabase[$entityId]
                $similarEntities = $this.SemanticIndex.Search($sourceEntity.Vector, $maxResults * 2)
                
                foreach ($similar in $similarEntities) {
                    if ($similar.Id -ne $entityId -and $this.EntityDatabase.ContainsKey($similar.Id)) {
                        $entity = $this.EntityDatabase[$similar.Id]
                        if ($similar.Similarity -gt 0.6) {  # Lower threshold for entity relationships
                            $relatedEntities.Add($entity)
                        }
                    }
                }
            }
            
            # Also check for explicit relationships
            $explicitRelations = $this.FindExplicitRelationships($entityId, $entityType)
            foreach ($relation in $explicitRelations) {
                if ($this.EntityDatabase.ContainsKey($relation) -and 
                    -not ($relatedEntities | Where-Object { $_.Id -eq $relation })) {
                    $relatedEntities.Add($this.EntityDatabase[$relation])
                }
            }
            
            return $relatedEntities | Select-Object -First $maxResults
            
        } catch {
            $this.Logger.Error("Failed to get related entities", @{
                EntityId = $entityId
                EntityType = $entityType
                Error = $_.Exception.Message
            })
            return [List[EntityMemory]]::new()
        }
    }
    
    [List[PatternInsight]] AnalyzePatterns([string]$sessionId, [TimeSpan]$timeWindow) {
        try {
            return $this.PatternAnalyzer.AnalyzeSessionPatterns($sessionId, $timeWindow, $this.VectorStore, $this.ConversationHistory)
        } catch {
            $this.Logger.Error("Pattern analysis failed", @{
                SessionId = $sessionId
                Error = $_.Exception.Message
            })
            return [List[PatternInsight]]::new()
        }
    }
    
    [void] UpdateMemoryImportance([string]$memoryId, [double]$importanceBoost, [string]$reason) {
        if ($this.VectorStore.ContainsKey($memoryId)) {
            $memory = $this.VectorStore[$memoryId]
            $oldImportance = $memory.Importance
            $memory.Importance = [Math]::Min(1.0, $memory.Importance + $importanceBoost)
            
            $this.Logger.Debug("Memory importance updated", @{
                MemoryId = $memoryId
                OldImportance = $oldImportance
                NewImportance = $memory.Importance
                Reason = $reason
            })
        }
    }
    
    [void] ForgetMemory([string]$memoryId, [string]$reason) {
        try {
            if ($this.VectorStore.TryRemove($memoryId, [ref]$null)) {
                $this.SemanticIndex.RemoveVector($memoryId)
                $this.EntityDatabase.TryRemove($memoryId, [ref]$null)
                
                $this.Logger.Info("Memory forgotten", @{
                    MemoryId = $memoryId
                    Reason = $reason
                })
            }
        } catch {
            $this.Logger.Error("Failed to forget memory", @{
                MemoryId = $memoryId
                Error = $_.Exception.Message
            })
        }
    }
    
    [hashtable] GetMemoryStatistics() {
        try {
            $now = Get-Date
            $dayAgo = $now.AddDays(-1)
            $weekAgo = $now.AddDays(-7)
            
            $recentMemories = $this.VectorStore.Values | Where-Object { $_.Created -gt $dayAgo }
            $weeklyMemories = $this.VectorStore.Values | Where-Object { $_.Created -gt $weekAgo }
            
            return @{
                TotalMemories = $this.VectorStore.Count
                TotalEntities = $this.EntityDatabase.Count
                ActiveSessions = $this.ConversationHistory.Count
                RecentMemories = $recentMemories.Count
                WeeklyMemories = $weeklyMemories.Count
                AverageImportance = ($this.VectorStore.Values | Measure-Object Importance -Average).Average
                TopTags = $this.GetTopTags(10)
                MemoryByType = $this.GetMemoryDistribution()
                StorageSize = $this.GetStorageSize()
                LastCleanup = $this.LastCleanup
            }
        } catch {
            $this.Logger.Error("Failed to calculate memory statistics", @{
                Error = $_.Exception.Message
            })
            return @{}
        }
    }
    
    # Private helper methods
    hidden [double] CalculateImportance([string]$content, [hashtable]$metadata) {
        $importance = 0.5  # Base importance
        
        # Boost for certain keywords
        $importantKeywords = @('error', 'critical', 'security', 'compliance', 'audit', 'violation')
        foreach ($keyword in $importantKeywords) {
            if ($content -ilike "*$keyword*") {
                $importance += 0.1
            }
        }
        
        # Boost for certain entity types
        if ($metadata.ContainsKey('EntityType')) {
            switch ($metadata.EntityType) {
                'User' { $importance += 0.1 }
                'SecurityGroup' { $importance += 0.15 }
                'AdminAction' { $importance += 0.2 }
            }
        }
        
        # Boost for successful operations
        if ($metadata.ContainsKey('Status') -and $metadata.Status -eq 'Success') {
            $importance += 0.05
        }
        
        return [Math]::Min(1.0, $importance)
    }
    
    hidden [List[string]] ExtractTags([string]$content, [hashtable]$metadata) {
        $tags = [List[string]]::new()
        
        # Extract from metadata
        if ($metadata.ContainsKey('EntityType')) {
            $tags.Add($metadata.EntityType)
        }
        if ($metadata.ContainsKey('Operation')) {
            $tags.Add($metadata.Operation)
        }
        if ($metadata.ContainsKey('Department')) {
            $tags.Add($metadata.Department)
        }
        
        # Extract from content using simple keyword matching
        $contentLower = $content.ToLower()
        $keywordTags = @{
            'mailbox' = @('mailbox', 'email', 'exchange')
            'user' = @('user', 'account', 'person')
            'group' = @('group', 'distribution', 'security')
            'permission' = @('permission', 'access', 'rights')
            'calendar' = @('calendar', 'meeting', 'appointment')
            'license' = @('license', 'subscription', 'sku')
        }
        
        foreach ($tag in $keywordTags.Keys) {
            foreach ($keyword in $keywordTags[$tag]) {
                if ($contentLower.Contains($keyword)) {
                    $tags.Add($tag)
                    break
                }
            }
        }
        
        return $tags
    }
    
    hidden [void] UpdateConversationContext([string]$sessionId, [MemoryVector]$memory) {
        $context = $this.GetConversationContext($sessionId)
        $context.LastActivity = Get-Date
        $context.MemoryIds.Add($memory.Id)
        
        # Extract topics and intents
        foreach ($tag in $memory.Tags) {
            if ($tag -notin $context.Topics) {
                $context.Topics.Add($tag)
            }
        }
        
        # Limit conversation memory to recent items
        if ($context.MemoryIds.Count -gt 100) {
            $context.MemoryIds.RemoveRange(0, $context.MemoryIds.Count - 100)
        }
    }
    
    hidden [void] ExtractAndStoreEntities([string]$content, [hashtable]$metadata, [string]$memoryId) {
        # Extract entities using regex patterns and metadata
        $emailPattern = '[a-zA-Z0-9._%+-]+@piercecountywa\.gov'
        $emails = [regex]::Matches($content, $emailPattern) | ForEach-Object { $_.Value }
        
        foreach ($email in $emails) {
            $entityId = "user_$($email.ToLower())"
            if (-not $this.EntityDatabase.ContainsKey($entityId)) {
                $entityVector = $this.SemanticIndex.GenerateEmbedding("user email $email")
                $entity = [EntityMemory]@{
                    Id = $entityId
                    Type = 'User'
                    Identifier = $email
                    Vector = $entityVector
                    Properties = @{ Email = $email }
                    RelatedMemories = [List[string]]::new()
                    Created = Get-Date
                    LastSeen = Get-Date
                }
                $this.EntityDatabase.TryAdd($entityId, $entity)
            }
            $this.EntityDatabase[$entityId].RelatedMemories.Add($memoryId)
            $this.EntityDatabase[$entityId].LastSeen = Get-Date
        }
    }
    
    hidden [double] CalculateCompositeScore([MemoryVector]$memory, [double]$similarity, [string]$query, [string]$sessionId) {
        $score = $similarity * 0.6  # Base semantic similarity (60%)
        
        # Importance boost (20%)
        $score += $memory.Importance * 0.2
        
        # Recency boost (10%)
        $daysSinceCreated = (Get-Date - $memory.Created).TotalDays
        $recencyScore = [Math]::Max(0, 1 - ($daysSinceCreated / 30))  # Decay over 30 days
        $score += $recencyScore * 0.1
        
        # Session relevance boost (10%)
        if ($memory.SessionId -eq $sessionId) {
            $score += 0.1
        }
        
        return $score
    }
    
    hidden [void] PerformMaintenanceIfNeeded() {
        $now = Get-Date
        if (($now - $this.LastCleanup).TotalHours -gt 24) {
            $this.PerformMaintenance()
            $this.LastCleanup = $now
        }
    }
    
    hidden [void] PerformMaintenance() {
        try {
            $this.Logger.Info("Starting memory maintenance")
            
            # Remove old, low-importance memories if over limit
            if ($this.VectorStore.Count -gt $this.MaxMemoryItems) {
                $memoriesToRemove = $this.VectorStore.Values |
                    Sort-Object @{Expression={$_.Importance}; Ascending=$true}, @{Expression={$_.LastAccessed}; Ascending=$true} |
                    Select-Object -First ($this.VectorStore.Count - $this.MaxMemoryItems + 100)
                
                foreach ($memory in $memoriesToRemove) {
                    $this.ForgetMemory($memory.Id, "Maintenance cleanup")
                }
            }
            
            # Clean up old conversation contexts
            $oldSessions = $this.ConversationHistory.Values | 
                Where-Object { (Get-Date - $_.LastActivity).TotalDays -gt 30 }
            
            foreach ($session in $oldSessions) {
                $this.ConversationHistory.TryRemove($session.SessionId, [ref]$null)
            }
            
            # Persist memory to disk
            $this.Persistence.SaveMemoryData($this.VectorStore, $this.EntityDatabase, $this.ConversationHistory)
            
            $this.Logger.Info("Memory maintenance completed", @{
                TotalMemories = $this.VectorStore.Count
                TotalEntities = $this.EntityDatabase.Count
                ActiveSessions = $this.ConversationHistory.Count
            })
            
        } catch {
            $this.Logger.Error("Memory maintenance failed", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    hidden [void] LoadPersistedMemory() {
        try {
            $loadedData = $this.Persistence.LoadMemoryData()
            if ($loadedData) {
                $this.VectorStore = $loadedData.VectorStore ?? [ConcurrentDictionary[string, MemoryVector]]::new()
                $this.EntityDatabase = $loadedData.EntityDatabase ?? [ConcurrentDictionary[string, EntityMemory]]::new()
                $this.ConversationHistory = $loadedData.ConversationHistory ?? [ConcurrentDictionary[string, ConversationContext]]::new()
                
                # Rebuild semantic index
                foreach ($memory in $this.VectorStore.Values) {
                    $this.SemanticIndex.AddVector($memory.Id, $memory.Vector, $memory.Content)
                }
                
                $this.Logger.Info("Persisted memory loaded", @{
                    MemoryCount = $this.VectorStore.Count
                    EntityCount = $this.EntityDatabase.Count
                    SessionCount = $this.ConversationHistory.Count
                })
            }
        } catch {
            $this.Logger.Warning("Failed to load persisted memory", @{
                Error = $_.Exception.Message
            })
        }
    }
}

# Supporting classes for the Vector Memory Bank
class MemoryVector {
    [string] $Id
    [string] $Content
    [string] $Context
    [double[]] $Vector
    [hashtable] $Metadata
    [string] $SessionId
    [DateTime] $Created
    [DateTime] $LastAccessed
    [int] $AccessCount
    [double] $Importance
    [List[string]] $Tags
}

class MemorySearchResult {
    [MemoryVector] $Memory
    [double] $Similarity
    [double] $CompositeScore
    [string] $MatchType
    [string] $Explanation
}

class ConversationContext {
    [string] $SessionId
    [DateTime] $Started
    [DateTime] $LastActivity
    [List[string]] $MemoryIds
    [Dictionary[string, EntityReference]] $EntityReferences
    [List[string]] $Topics
    [List[string]] $IntentHistory
    [hashtable] $UserPreferences
}

class EntityMemory {
    [string] $Id
    [string] $Type
    [string] $Identifier
    [double[]] $Vector
    [hashtable] $Properties
    [List[string]] $RelatedMemories
    [DateTime] $Created
    [DateTime] $LastSeen
}

class EntityReference {
    [string] $Id
    [string] $Type
    [string] $Name
    [int] $MentionCount
    [DateTime] $LastMentioned
}

class PatternInsight {
    [string] $Pattern
    [string] $Description
    [double] $Confidence
    [List[string]] $EvidenceMemoryIds
    [hashtable] $Metadata
}

class PatternAnalyzer {
    hidden [Logger] $Logger
    
    PatternAnalyzer([Logger]$logger) {
        $this.Logger = $logger
    }
    
    [void] AnalyzeNewMemory([MemoryVector]$memory) {
        # Stub implementation
        $this.Logger.Debug("Analyzing new memory pattern", @{
            MemoryId = $memory.Id
            Content = $memory.Content.Substring(0, [Math]::Min(50, $memory.Content.Length))
        })
    }
    
    [PatternInsight[]] AnalyzeSessionPatterns([string]$sessionId, [TimeSpan]$timeWindow, [object]$vectorStore, [object]$conversationHistory) {
        # Stub implementation
        $this.Logger.Debug("Analyzing session patterns", @{
            SessionId = $sessionId
            TimeWindow = $timeWindow.ToString()
        })
        return @()
    }
}

class MemoryPersistence {
    hidden [string] $StoragePath
    hidden [Logger] $Logger
    
    MemoryPersistence([string]$storagePath, [Logger]$logger) {
        $this.StoragePath = $storagePath
        $this.Logger = $logger
        
        # Ensure storage directory exists
        if (-not (Test-Path $storagePath)) {
            New-Item -Path $storagePath -ItemType Directory -Force | Out-Null
        }
    }
    
    [void] SaveMemoryBank([object]$memoryBank) {
        # Stub implementation
        $this.Logger.Debug("Saving memory bank to persistence", @{
            StoragePath = $this.StoragePath
        })
    }
    
    [hashtable] LoadMemoryBank() {
        # Stub implementation
        $this.Logger.Debug("Loading memory bank from persistence", @{
            StoragePath = $this.StoragePath
        })
        return @{}
    }
}

# Export the memory bank class
if ($MyInvocation.InvocationName -ne '.') {
    return [VectorMemoryBank]
}
