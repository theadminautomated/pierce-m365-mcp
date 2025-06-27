#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Context and Memory Management System
.DESCRIPTION
    Provides persistent context management, memory storage, and intelligent
    relationship tracking for the Pierce County M365 MCP Server.
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.IO

class ContextManager {
    hidden [Logger] $Logger
    hidden [ConcurrentDictionary[string, ContextStore]] $ContextStores
    hidden [VectorMemoryBank] $VectorMemoryBank
    hidden [RelationshipGraph] $RelationshipGraph
    hidden [string] $PersistencePath
    hidden [System.Threading.Timer] $PersistenceTimer
    
    ContextManager([Logger]$logger) {
        $this.Logger = $logger
        $this.ContextStores = [ConcurrentDictionary[string, ContextStore]]::new()
        $this.PersistencePath = Join-Path $env:TEMP "PierceCountyMCP\Context"
        $this.VectorMemoryBank = [VectorMemoryBank]::new($logger, (Join-Path $this.PersistencePath "VectorMemory"))
        $this.RelationshipGraph = [RelationshipGraph]::new($logger)
        
        $this.InitializeContextManager()
        $this.StartPersistenceTimer()
    }
    
    [ContextStore] GetOrCreateContext([string]$sessionId) {
        $context = $null
        if (-not $this.ContextStores.TryGetValue($sessionId, [ref]$context)) {
            $context = [ContextStore]::new($sessionId)
            $this.ContextStores.TryAdd($sessionId, $context)
        }
        return $context
    }
    
    [void] StoreEntityRelationships([EntityCollection]$entities, [string]$sessionId) {
        $this.Logger.Debug("Storing entity relationships", @{
            SessionId = $sessionId
            UserCount = $entities.Users.Count
            MailboxCount = $entities.Mailboxes.Count
            GroupCount = $entities.Groups.Count
        })
        
        try {
            # Store user relationships
            foreach ($user in $entities.Users) {
                $this.RelationshipGraph.AddEntity($user.Email, "User", @{
                    DisplayName = $user.DisplayName
                    Department = $user.Department
                    Title = $user.Title
                })
                
                # Link to department
                if ($user.Department) {
                    $this.RelationshipGraph.AddRelationship($user.Email, $user.Department, "MemberOf")
                }
                
                # Link to manager
                if ($user.Manager) {
                    $this.RelationshipGraph.AddRelationship($user.Email, $user.Manager, "ReportsTo")
                }
            }
            
            # Store mailbox relationships
            foreach ($mailbox in $entities.Mailboxes) {
                $this.RelationshipGraph.AddEntity($mailbox.Email, "Mailbox", @{
                    Type = $mailbox.Type.ToString()
                    DisplayName = $mailbox.DisplayName
                    Owner = $mailbox.Owner
                })
                
                # Link to owner
                if ($mailbox.Owner) {
                    $this.RelationshipGraph.AddRelationship($mailbox.Email, $mailbox.Owner, "OwnedBy")
                }
            }
            
            # Store group relationships
            foreach ($group in $entities.Groups) {
                $this.RelationshipGraph.AddEntity($group.Name, "Group", @{
                    Email = $group.Email
                    Type = $group.Type
                    Description = $group.Description
                })
                
                # Link members
                foreach ($member in $group.Members) {
                    $this.RelationshipGraph.AddRelationship($group.Name, $member, "HasMember")
                }
                
                # Link owners
                foreach ($owner in $group.Owners) {
                    $this.RelationshipGraph.AddRelationship($group.Name, $owner, "OwnedBy")
                }
            }
            
            # Store action relationships
            foreach ($action in $entities.Actions) {
                $actionId = "Action_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
                $this.RelationshipGraph.AddEntity($actionId, "Action", @{
                    Type = $action.Type.ToString()
                    OriginalText = $action.OriginalText
                    Context = $action.Context
                    SessionId = $sessionId
                })
                
                # Link to related users
                foreach ($user in $action.RelatedUsers) {
                    $this.RelationshipGraph.AddRelationship($actionId, $user.Email, "TargetsUser")
                }
                
                # Link to related permissions
                foreach ($permission in $action.RelatedPermissions) {
                    $permissionId = "Permission_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
                    $this.RelationshipGraph.AddEntity($permissionId, "Permission", @{
                        Level = $permission.Level.ToString()
                        OriginalText = $permission.OriginalText
                    })
                    $this.RelationshipGraph.AddRelationship($actionId, $permissionId, "InvolvesPermission")
                }
            }
            
            $this.Logger.Info("Entity relationships stored", @{
                SessionId = $sessionId
                TotalEntities = $this.RelationshipGraph.GetEntityCount()
                TotalRelationships = $this.RelationshipGraph.GetRelationshipCount()
            })
        }
        catch {
            $this.Logger.Error("Failed to store entity relationships", @{
                Error = $_.Exception.Message
                SessionId = $sessionId
            })
        }
    }
    
    [EntityCollection] EnrichEntitiesWithContext([EntityCollection]$entities, [string]$sessionId) {
        $this.Logger.Debug("Enriching entities with context", @{
            SessionId = $sessionId
        })
        
        try {
            # Enrich users with relationship data
            foreach ($user in $entities.Users) {
                $this.EnrichUserWithContext($user)
            }
            
            # Enrich mailboxes with usage patterns
            foreach ($mailbox in $entities.Mailboxes) {
                $this.EnrichMailboxWithContext($mailbox)
            }
            
            # Enrich groups with membership history
            foreach ($group in $entities.Groups) {
                $this.EnrichGroupWithContext($group)
            }
            
            return $entities
        }
        catch {
            $this.Logger.Warning("Failed to enrich entities with context", @{
                Error = $_.Exception.Message
                SessionId = $sessionId
            })
            return $entities
        }
    }
    
    [List[ContextualSuggestion]] GetContextualSuggestions([EntityCollection]$entities, [string]$sessionId) {
        $suggestions = [List[ContextualSuggestion]]::new()
        
        try {
            # Analyze patterns and provide suggestions using VectorMemoryBank
            $patterns = $this.VectorMemoryBank.AnalyzePatterns($sessionId, [TimeSpan]::FromHours(24))
            
            foreach ($pattern in $patterns) {
                $suggestion = $this.CreateSuggestionFromPattern($pattern, $entities)
                if ($suggestion) {
                    $suggestions.Add($suggestion)
                }
            }
            
            # Add relationship-based suggestions
            $relationshipSuggestions = $this.GetRelationshipSuggestions($entities)
            $suggestions.AddRange($relationshipSuggestions)
            
            $this.Logger.Debug("Generated contextual suggestions", @{
                SuggestionCount = $suggestions.Count
                SessionId = $sessionId
            })
            
            return $suggestions
        }
        catch {
            $this.Logger.Warning("Failed to generate contextual suggestions", @{
                Error = $_.Exception.Message
                SessionId = $sessionId
            })
            return $suggestions
        }
    }
    
    [void] StoreMemoryFromSession([OrchestrationSession]$session) {
        try {
            # Store conversation context in vector memory
            $conversationContext = @{
                SessionId = $session.SessionId
                Initiator = $session.Initiator
                StartTime = $session.StartTime
                Duration = ((Get-Date) - $session.StartTime).TotalMinutes
                Actions = @($session.Actions | ForEach-Object { $_.ToString() })
                Entities = @($session.Entities | ForEach-Object { $_.ToString() })
                Results = $session.Results
            }
            
            $this.VectorMemoryBank.StoreConversation(
                $session.SessionId,
                $session.Initiator,
                $session.OriginalRequest,
                $conversationContext
            )
            
            # Store entity memories
            foreach ($entity in $session.Entities) {
                $this.VectorMemoryBank.StoreEntityMemory(
                    $entity.Identifier,
                    $entity.Type,
                    $entity.ToHashtable(),
                    $session.SessionId
                )
            }
            
            # Store pattern analysis results
            $patterns = $this.VectorMemoryBank.AnalyzeSessionPatterns($session)
            foreach ($pattern in $patterns) {
                $this.VectorMemoryBank.StoreMemory(
                    "Pattern: $($pattern.Type)",
                    "SessionPattern",
                    @{
                        PatternType = $pattern.Type
                        Confidence = $pattern.Confidence
                        SessionId = $session.SessionId
                        Description = $pattern.Description
                    },
                    $session.SessionId
                )
            }
            
            $this.Logger.Debug("Memory stored from session using VectorMemoryBank", @{
                SessionId = $session.SessionId
                EntityCount = $session.Entities.Count
                PatternCount = $patterns.Count
            })
        }
        catch {
            $this.Logger.Warning("Failed to store memory from session", @{
                Error = $_.Exception.Message
                SessionId = $session.SessionId
            })
        }
    }
    
    [string[]] GetSemanticSuggestions([string]$query, [string]$sessionId, [int]$maxResults = 5) {
        try {
            # Use VectorMemoryBank for semantic search
            $similarMemories = $this.VectorMemoryBank.SearchSimilarMemories($query, $maxResults)
            
            $suggestions = @()
            foreach ($memory in $similarMemories) {
                $suggestions += "Based on similar context: $($memory.Content)"
            }
            
            # Get conversation-based suggestions
            $conversationSuggestions = $this.VectorMemoryBank.GetConversationSuggestions($sessionId, $maxResults)
            $suggestions += $conversationSuggestions
            
            return $suggestions
        }
        catch {
            $this.Logger.Warning("Failed to get semantic suggestions", @{
                Error = $_.Exception.Message
                Query = $query
                SessionId = $sessionId
            })
            return @()
        }
    }
    
    [hashtable] GetEntityIntelligence([string]$entityId, [string]$entityType) {
        try {
            # Get comprehensive entity intelligence from VectorMemoryBank
            $entityMemory = $this.VectorMemoryBank.GetEntityMemory($entityId)
            
            $intelligence = @{
                EntityId = $entityId
                EntityType = $entityType
                AccessPatterns = @()
                RelationshipHistory = @()
                PermissionHistory = @()
                RecentActivity = @()
                PredictedNeeds = @()
            }
            
            if ($entityMemory) {
                $intelligence.AccessPatterns = $entityMemory.AccessPatterns
                $intelligence.RelationshipHistory = $entityMemory.RelationshipHistory
                $intelligence.PermissionHistory = $entityMemory.PermissionHistory
                $intelligence.RecentActivity = $entityMemory.RecentActivity
                
                # Get AI-driven predictions
                $predictions = $this.VectorMemoryBank.PredictEntityNeeds($entityId)
                $intelligence.PredictedNeeds = $predictions
            }
            
            return $intelligence
        }
        catch {
            $this.Logger.Warning("Failed to get entity intelligence", @{
                Error = $_.Exception.Message
                EntityId = $entityId
                EntityType = $entityType
            })
            return @{}
        }
    }
    
    [void] LoadPersistedContext() {
        $this.Logger.Info("Loading persisted context with VectorMemoryBank")
        
        try {
            # Ensure persistence directory exists
            if (-not (Test-Path $this.PersistencePath)) {
                New-Item -Path $this.PersistencePath -ItemType Directory -Force | Out-Null
                $this.Logger.Info("Created persistence directory", @{
                    Path = $this.PersistencePath
                })
                return
            }
            
            # VectorMemoryBank handles its own persistence automatically
            # Just load relationship graph
            $relationshipFile = Join-Path $this.PersistencePath "relationships.json"
            if (Test-Path $relationshipFile) {
                $this.RelationshipGraph.LoadFromFile($relationshipFile)
            }
            
            $this.Logger.Info("Persisted context loaded", @{
                VectorMemoryCount = $this.VectorMemoryBank.GetMemoryCount()
                RelationshipCount = $this.RelationshipGraph.GetRelationshipCount()
            })
        }
        catch {
            $this.Logger.Warning("Failed to load persisted context", @{ Error = $_.Exception.Message })
        }
    }
    
    [void] PersistContext() {
        try {
            # Ensure persistence directory exists
            if (-not (Test-Path $this.PersistencePath)) {
                New-Item -Path $this.PersistencePath -ItemType Directory -Force | Out-Null
            }
            
            # VectorMemoryBank handles its own persistence automatically
            # Just persist relationship graph
            $relationshipFile = Join-Path $this.PersistencePath "relationships.json"
            $this.RelationshipGraph.SaveToFile($relationshipFile)
            
            # Cleanup old context stores (keep only recent ones)
            $this.CleanupOldContextStores()
            
            $this.Logger.Debug("Context persisted with VectorMemoryBank", @{
                RelationshipFile = $relationshipFile
                VectorMemoryCount = $this.VectorMemoryBank.GetMemoryCount()
            })
        }
        catch {
            $this.Logger.Warning("Failed to persist context", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    hidden [void] InitializeContextManager() {
        $this.Logger.Debug("Initializing context manager", @{
            PersistencePath = $this.PersistencePath
        })
        
        # Create persistence directory if it doesn't exist
        if (-not (Test-Path $this.PersistencePath)) {
            New-Item -Path $this.PersistencePath -ItemType Directory -Force | Out-Null
        }
    }
    
    hidden [void] StartPersistenceTimer() {
        # Persist context every 5 minutes
        $this.PersistenceTimer = [System.Threading.Timer]::new(
            { param($state) $state.PersistContext() },
            $this,
            300000,  # 5 minutes
            300000   # 5 minutes
        )
    }
    
    hidden [void] EnrichUserWithContext([UserEntity]$user) {
        # Get related entities from relationship graph
        $relationships = $this.RelationshipGraph.GetRelationships($user.Email)
        
        foreach ($relationship in $relationships) {
            switch ($relationship.Type) {
                "MemberOf" {
                    if (-not $user.Department) {
                        $user.Department = $relationship.TargetId
                    }
                }
                "ReportsTo" {
                    if (-not $user.Manager) {
                        $user.Manager = $relationship.TargetId
                    }
                }
            }
        }
        
        # Get usage patterns from memory
        $entityMemory = $this.VectorMemoryBank.GetEntityMemory($user.Email)
        $user.Metadata['UsagePatterns'] = $entityMemory ? $entityMemory.AccessPatterns.Count : 0
        $user.Metadata['LastActivity'] = $entityMemory ? $entityMemory.LastAccessed : [DateTime]::MinValue
    }
    
    hidden [void] EnrichMailboxWithContext([MailboxEntity]$mailbox) {
        # Get ownership information
        $relationships = $this.RelationshipGraph.GetRelationships($mailbox.Email)
        
        foreach ($relationship in $relationships) {
            if ($relationship.Type -eq "OwnedBy") {
                $mailbox.Owner = $relationship.TargetId
                break
            }
        }
        
        # Get usage statistics
        $entityMemory = $this.VectorMemoryBank.GetEntityMemory($mailbox.Email)
        $mailbox.Metadata['AccessCount'] = $entityMemory ? $entityMemory.AccessPatterns.Count : 0
        $mailbox.Metadata['PermissionChanges'] = $entityMemory ? $entityMemory.PermissionHistory.Count : 0
    }
    
    hidden [void] EnrichGroupWithContext([GroupEntity]$group) {
        # Get membership information
        $relationships = $this.RelationshipGraph.GetRelationships($group.Name)
        
        $members = @()
        $owners = @()
        
        foreach ($relationship in $relationships) {
            switch ($relationship.Type) {
                "HasMember" { $members += $relationship.TargetId }
                "OwnedBy" { $owners += $relationship.TargetId }
            }
        }
        
        if ($group.Members.Count -eq 0) {
            $group.Members.AddRange($members)
        }
        if ($group.Owners.Count -eq 0) {
            $group.Owners.AddRange($owners)
        }
        
        # Get group activity patterns
        $entityMemory = $this.VectorMemoryBank.GetEntityMemory($group.Name)
        $group.Metadata['MembershipChanges'] = $entityMemory ? $entityMemory.RelationshipHistory.Count : 0
        $group.Metadata['LastModified'] = $entityMemory ? $entityMemory.LastAccessed : [DateTime]::MinValue
    }
    
    hidden [List[MemoryFact]] ExtractFactsFromSession([OrchestrationSession]$session) {
        $facts = [List[MemoryFact]]::new()
        
        # Extract user preferences
        $initiator = $session.Initiator
        if ($initiator) {
            $userFact = [MemoryFact]::new(
                "UserActivity",
                @{
                    User = $initiator
                    Activity = "MCPSession"
                    Timestamp = $session.StartTime
                    Duration = ((Get-Date) - $session.StartTime).TotalMinutes
                },
                0.8,
                "User"
            )
            $facts.Add($userFact)
        }
        
        # Extract context patterns
        foreach ($contextItem in $session.Context.GetEnumerator()) {
            $contextFact = [MemoryFact]::new(
                "ContextPattern",
                @{
                    Key = $contextItem.Key
                    ValueType = $contextItem.Value.GetType().Name
                    SessionId = $session.SessionId
                    Timestamp = Get-Date
                },
                0.6,
                "Context"
            )
            $facts.Add($contextFact)
        }
        
        # Extract audit trail patterns
        foreach ($auditEntry in $session.AuditTrail) {
            $auditFact = [MemoryFact]::new(
                "AuditEvent",
                @{
                    Event = $auditEntry
                    SessionId = $session.SessionId
                    User = $session.Initiator
                    Timestamp = Get-Date
                },
                1.0,
                "Audit"
            )
            $facts.Add($auditFact)
        }
        
        return $facts
    }
    
    hidden [ContextualSuggestion] CreateSuggestionFromPattern([MemoryPattern]$pattern, [EntityCollection]$entities) {
        switch ($pattern.Type) {
            "FrequentUserOperation" {
                return [ContextualSuggestion]::new(
                    "Consider automating this frequent operation",
                    "UserAutomation",
                    $pattern.Confidence,
                    @{
                        Pattern = $pattern.Description
                        Frequency = $pattern.Frequency
                    }
                )
            }
            "PermissionAnomaly" {
                return [ContextualSuggestion]::new(
                    "Unusual permission pattern detected - review required",
                    "SecurityReview",
                    $pattern.Confidence,
                    @{
                        Pattern = $pattern.Description
                        Risk = $pattern.Risk
                    }
                )
            }
            default {
                return $null
            }
        }
    }
    
    hidden [List[ContextualSuggestion]] GetRelationshipSuggestions([EntityCollection]$entities) {
        $suggestions = [List[ContextualSuggestion]]::new()
        
        # Suggest related entities that might be relevant
        foreach ($user in $entities.Users) {
            $relatedEntities = $this.RelationshipGraph.GetRelatedEntities($user.Email, 2)
            
            if ($relatedEntities.Count -gt 0) {
                $suggestion = [ContextualSuggestion]::new(
                    "Consider including related entities in this operation",
                    "RelatedEntities",
                    0.7,
                    @{
                        User = $user.Email
                        RelatedEntities = $relatedEntities
                    }
                )
                $suggestions.Add($suggestion)
            }
        }
        
        return $suggestions
    }
    
    hidden [DateTime] GetLastActivity([MemoryFact[]]$facts) {
        if ($facts.Count -eq 0) {
            return [DateTime]::MinValue
        }
        
        $latestFact = $facts | Sort-Object { $_.Timestamp } -Descending | Select-Object -First 1
        return $latestFact.Timestamp
    }
    
    hidden [void] CleanupOldContextStores() {
        $cutoffTime = (Get-Date).AddDays(-7)  # Keep contexts for 7 days
        
        $expiredStores = @()
        foreach ($store in $this.ContextStores.Values) {
            if ($store.CreatedAt -lt $cutoffTime) {
                $expiredStores += $store.SessionId
            }
        }
        
        foreach ($sessionId in $expiredStores) {
            $store = $null
            $this.ContextStores.TryRemove($sessionId, [ref]$store)
        }
        
        if ($expiredStores.Count -gt 0) {
            $this.Logger.Debug("Cleaned up expired context stores", @{
                ExpiredCount = $expiredStores.Count
            })
        }
    }
    
    [void] Dispose() {
        if ($this.PersistenceTimer) {
            $this.PersistenceTimer.Dispose()
        }
        
        # Final persistence
        $this.PersistContext()
    }
}

# Supporting classes
class ContextStore {
    [string] $SessionId
    [DateTime] $CreatedAt
    [ConcurrentDictionary[string, object]] $Data
    [List[string]] $AccessLog
    
    ContextStore([string]$sessionId) {
        $this.SessionId = $sessionId
        $this.CreatedAt = Get-Date
        $this.Data = [ConcurrentDictionary[string, object]]::new()
        $this.AccessLog = [List[string]]::new()
    }
    
    [void] Store([string]$key, [object]$value) {
        $this.Data.AddOrUpdate($key, $value, { param($k, $v) $value })
        $this.AccessLog.Add("Store: $key at $(Get-Date)")
    }
    
    [object] Retrieve([string]$key) {
        $value = $null
        $this.Data.TryGetValue($key, [ref]$value)
        $this.AccessLog.Add("Retrieve: $key at $(Get-Date)")
        return $value
    }
    
    [bool] Contains([string]$key) {
        return $this.Data.ContainsKey($key)
    }
}

class RelationshipGraph {
    hidden [Logger] $Logger
    hidden [ConcurrentDictionary[string, GraphEntity]] $Entities
    hidden [ConcurrentDictionary[string, List[GraphRelationship]]] $Relationships
    
    RelationshipGraph([Logger]$logger) {
        $this.Logger = $logger
        $this.Entities = [ConcurrentDictionary[string, GraphEntity]]::new()
        $this.Relationships = [ConcurrentDictionary[string, List[GraphRelationship]]]::new()
    }
    
    [void] AddEntity([string]$id, [string]$type, [hashtable]$properties) {
        $entity = [GraphEntity]::new($id, $type, $properties)
        $this.Entities.AddOrUpdate($id, $entity, { param($k, $v) $entity })
    }
    
    [void] AddRelationship([string]$sourceId, [string]$targetId, [string]$type) {
        $relationship = [GraphRelationship]::new($sourceId, $targetId, $type)
        
        $relationships = $this.Relationships.GetOrAdd($sourceId, { [List[GraphRelationship]]::new() })
        $relationships.Add($relationship)
    }
    
    [GraphRelationship[]] GetRelationships([string]$entityId) {
        $relationships = $null
        if ($this.Relationships.TryGetValue($entityId, [ref]$relationships)) {
            return $relationships.ToArray()
        }
        return @()
    }
    
    [string[]] GetRelatedEntities([string]$entityId, [int]$maxHops) {
        $visited = [HashSet[string]]::new()
        $queue = [Queue[object]]::new()
        $related = [List[string]]::new()
        
        $queue.Enqueue(@{ EntityId = $entityId; Hops = 0 })
        $visited.Add($entityId)
        
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            
            if ($current.Hops -ge $maxHops) {
                continue
            }
            
            $relationships = $this.GetRelationships($current.EntityId)
            foreach ($relationship in $relationships) {
                if (-not $visited.Contains($relationship.TargetId)) {
                    $visited.Add($relationship.TargetId)
                    $related.Add($relationship.TargetId)
                    $queue.Enqueue(@{ EntityId = $relationship.TargetId; Hops = $current.Hops + 1 })
                }
            }
        }
        
        return $related.ToArray()
    }
    
    [int] GetEntityCount() {
        return $this.Entities.Count
    }
    
    [int] GetRelationshipCount() {
        $count = 0
        foreach ($relationshipList in $this.Relationships.Values) {
            $count += $relationshipList.Count
        }
        return $count
    }
    
    [void] LoadFromFile([string]$filePath) {
        try {
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            
            # Load entities
            foreach ($entity in $content.entities) {
                $this.AddEntity($entity.id, $entity.type, $entity.properties)
            }
            
            # Load relationships
            foreach ($relationship in $content.relationships) {
                $this.AddRelationship($relationship.sourceId, $relationship.targetId, $relationship.type)
            }
            
            $this.Logger.Debug("Relationship graph loaded from file", @{
                FilePath = $filePath
                EntityCount = $this.GetEntityCount()
                RelationshipCount = $this.GetRelationshipCount()
            })
        }
        catch {
            $this.Logger.Warning("Failed to load relationship graph from file", @{
                FilePath = $filePath
                Error = $_.Exception.Message
            })
        }
    }
    
    [void] SaveToFile([string]$filePath) {
        try {
            $entities = @($this.Entities.Values | ForEach-Object {
                @{
                    id = $_.Id
                    type = $_.Type
                    properties = $_.Properties
                }
            })
            
            $relationships = @()
            foreach ($entityRelationships in $this.Relationships.GetEnumerator()) {
                foreach ($relationship in $entityRelationships.Value) {
                    $relationships += @{
                        sourceId = $relationship.SourceId
                        targetId = $relationship.TargetId
                        type = $relationship.Type
                    }
                }
            }
            
            $graphData = @{
                entities = $entities
                relationships = $relationships
            }
            
            $graphData | ConvertTo-Json -Depth 5 | Set-Content $filePath
            
            $this.Logger.Debug("Relationship graph saved to file", @{
                FilePath = $filePath
                EntityCount = $entities.Count
                RelationshipCount = $relationships.Count
            })
        }
        catch {
            $this.Logger.Warning("Failed to save relationship graph to file", @{
                FilePath = $filePath
                Error = $_.Exception.Message
            })
        }
    }
}

# Data classes
class MemoryFact {
    [string] $Type
    [hashtable] $Data
    [double] $Confidence
    [string] $Category
    [DateTime] $Timestamp
    
    MemoryFact([string]$type, [hashtable]$data, [double]$confidence, [string]$category) {
        $this.Type = $type
        $this.Data = $data
        $this.Confidence = $confidence
        $this.Category = $category
        $this.Timestamp = Get-Date
    }
}

class MemoryPattern {
    [string] $Type
    [string] $Description
    [int] $Frequency
    [double] $Confidence
    [string] $Risk
    
    MemoryPattern([string]$type, [string]$description, [int]$frequency, [double]$confidence, [string]$risk) {
        $this.Type = $type
        $this.Description = $description
        $this.Frequency = $frequency
        $this.Confidence = $confidence
        $this.Risk = $risk
    }
}

class ContextualSuggestion {
    [string] $Suggestion
    [string] $Type
    [double] $Confidence
    [hashtable] $Context
    [DateTime] $CreatedAt
    
    ContextualSuggestion([string]$suggestion, [string]$type, [double]$confidence, [hashtable]$context) {
        $this.Suggestion = $suggestion
        $this.Type = $type
        $this.Confidence = $confidence
        $this.Context = $context
        $this.CreatedAt = Get-Date
    }
}

class GraphEntity {
    [string] $Id
    [string] $Type
    [hashtable] $Properties
    [DateTime] $CreatedAt
    
    GraphEntity([string]$id, [string]$type, [hashtable]$properties) {
        $this.Id = $id
        $this.Type = $type
        $this.Properties = $properties ?? @{}
        $this.CreatedAt = Get-Date
    }
}

class GraphRelationship {
    [string] $SourceId
    [string] $TargetId
    [string] $Type
    [DateTime] $CreatedAt
    
    GraphRelationship([string]$sourceId, [string]$targetId, [string]$type) {
        $this.SourceId = $sourceId
        $this.TargetId = $targetId
        $this.Type = $type
        $this.CreatedAt = Get-Date
    }
}

# Strategy classes for self-healing
class RetryStrategy {
    [int] $MaxRetries
    [int] $DelayMs
    
    RetryStrategy([int]$maxRetries, [int]$delayMs) {
        $this.MaxRetries = $maxRetries
        $this.DelayMs = $delayMs
    }
    
    [SelfHealingResult] Attempt([ToolStep]$toolStep, [Exception]$error, [OrchestrationSession]$session, [OrchestrationEngine]$engine) {
        for ($i = 1; $i -le $this.MaxRetries; $i++) {
            Start-Sleep -Milliseconds $this.DelayMs
            
            try {
                # Retry the tool execution
                $tool = $engine.ToolRegistry.GetTool($toolStep.ToolName)
                $executionContext = $engine.PrepareExecutionContext($toolStep, @{}, $session)
                $result = $tool.Execute($executionContext)
                
                return [SelfHealingResult]::Success($result, "RetryStrategy")
            }
            catch {
                if ($i -eq $this.MaxRetries) {
                    break
                }
            }
        }
        
        return [SelfHealingResult]::Failure("All retry attempts failed")
    }
}

class FallbackStrategy {
    [SelfHealingResult] Attempt([ToolStep]$toolStep, [Exception]$error, [OrchestrationSession]$session, [OrchestrationEngine]$engine) {
        # Attempt to find a fallback tool
        $fallbackTool = $this.FindFallbackTool($toolStep.ToolName, $engine)
        
        if ($fallbackTool) {
            try {
                $tool = $engine.ToolRegistry.GetTool($fallbackTool)
                $executionContext = $engine.PrepareExecutionContext($toolStep, @{}, $session)
                $result = $tool.Execute($executionContext)
                
                return [SelfHealingResult]::Success($result, "FallbackStrategy")
            }
            catch {
                # Fallback also failed
            }
        }
        
        return [SelfHealingResult]::Failure("No suitable fallback tool found")
    }
    
    hidden [string] FindFallbackTool([string]$originalTool, [OrchestrationEngine]$engine) {
        # Simple fallback mapping
        $fallbackMap = @{
            'add_mailbox_permissions' = 'grant_permissions'
            'remove_mailbox_permissions' = 'revoke_permissions'
            'deprovision_account' = 'disable_account'
        }
        
        return $fallbackMap[$originalTool]
    }
}

class ContextAdjustmentStrategy {
    [SelfHealingResult] Attempt([ToolStep]$toolStep, [Exception]$error, [OrchestrationSession]$session, [OrchestrationEngine]$engine) {
        # Attempt to adjust parameters based on the error
        $adjustedParameters = $this.AdjustParameters($toolStep.Parameters, $error)
        
        if ($adjustedParameters) {
            try {
                $adjustedStep = [ToolStep]::new($toolStep.ToolName, $adjustedParameters)
                $tool = $engine.ToolRegistry.GetTool($toolStep.ToolName)
                $executionContext = $engine.PrepareExecutionContext($adjustedStep, @{}, $session)
                $result = $tool.Execute($executionContext)
                
                return [SelfHealingResult]::Success($result, "ContextAdjustmentStrategy")
            }
            catch {
                # Adjustment didn't work
            }
        }
        
        return [SelfHealingResult]::Failure("Context adjustment failed")
    }
    
    hidden [hashtable] AdjustParameters([hashtable]$originalParameters, [Exception]$error) {
        $adjusted = $originalParameters.Clone()
        
        # Example adjustments based on common error patterns
        if ($error.Message -match "not found") {
            # Try without optional parameters
            $optionalParams = @('Description', 'Notes', 'Metadata')
            foreach ($param in $optionalParams) {
                if ($adjusted.ContainsKey($param)) {
                    $adjusted.Remove($param)
                }
            }
        }
        
        if ($error.Message -match "permission") {
            # Try with reduced permissions
            if ($adjusted.ContainsKey('AccessRights')) {
                $adjusted['AccessRights'] = 'Reviewer'
            }
        }
        
        return $adjusted
    }
}

class ToolSubstitutionStrategy {
    [SelfHealingResult] Attempt([ToolStep]$toolStep, [Exception]$error, [OrchestrationSession]$session, [OrchestrationEngine]$engine) {
        # Find an alternative tool that can achieve the same result
        $alternativeTool = $this.FindAlternativeTool($toolStep.ToolName, $engine)
        
        if ($alternativeTool) {
            try {
                $tool = $engine.ToolRegistry.GetTool($alternativeTool)
                $mappedParameters = $this.MapParameters($toolStep.Parameters, $toolStep.ToolName, $alternativeTool)
                $alternativeStep = [ToolStep]::new($alternativeTool, $mappedParameters)
                $executionContext = $engine.PrepareExecutionContext($alternativeStep, @{}, $session)
                $result = $tool.Execute($executionContext)
                
                return [SelfHealingResult]::Success($result, "ToolSubstitutionStrategy")
            }
            catch {
                # Alternative tool also failed
            }
        }
        
        return [SelfHealingResult]::Failure("No suitable alternative tool found")
    }
    
    hidden [string] FindAlternativeTool([string]$originalTool, [OrchestrationEngine]$engine) {
        # Map tools to alternatives
        $alternativeMap = @{
            'set_calendar_permissions' = 'add_mailbox_permissions'
            'new_distribution_list' = 'new_m365_group'
        }
        
        return $alternativeMap[$originalTool]
    }
    
    hidden [hashtable] MapParameters([hashtable]$originalParameters, [string]$fromTool, [string]$toTool) {
        $mapped = @{}
        
        # Common parameter mappings
        $parameterMap = @{
            'MailboxIdentity' = 'Mailbox'
            'CalendarName' = 'Folder'
            'AccessRights' = 'Permission'
        }
        
        foreach ($param in $originalParameters.GetEnumerator()) {
            $mappedKey = $parameterMap[$param.Key] ?? $param.Key
            $mapped[$mappedKey] = $param.Value
        }
        
        return $mapped
    }
}

Export-ModuleMember -Cmdlet * -Function * -Variable * -Alias *
