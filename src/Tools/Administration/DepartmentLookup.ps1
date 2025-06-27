#Requires -Version 7.0
<#
.SYNOPSIS
    Enterprise Department Lookup Tool - Agentic MCP Implementation
.DESCRIPTION
    Comprehensive organizational structure lookup with autonomous intelligence,
    fuzzy matching, and enterprise audit trails. Provides complete department
    information, user relationships, and organizational hierarchy mapping.
.NOTES
    Author: Pierce County IT Solutions Architecture
    Version: 2.0.0
    Compatible: PowerShell 7.0+, MCP Protocol, Agentic Orchestration
#>

using namespace System.Collections.Generic
using namespace System.Management.Automation

class DepartmentLookupTool {
    [string]$ToolName = "department_lookup"
    [hashtable]$Config
    [Logger]$Logger
    [ValidationEngine]$Validator
    [SecurityManager]$Security
    [hashtable]$DepartmentCache
    [DateTime]$LastCacheUpdate

    DepartmentLookupTool([hashtable]$config, [Logger]$logger, [ValidationEngine]$validator, [SecurityManager]$security) {
        $this.Config = $config
        $this.Logger = $logger
        $this.Validator = $validator
        $this.Security = $security
        $this.DepartmentCache = @{}
        $this.LastCacheUpdate = [DateTime]::MinValue
        $this.InitializeDepartmentData()
    }

    [hashtable] GetSchema() {
        return @{
            name = $this.ToolName
            description = "Lookup Pierce County department information by user, department name, ID, or partial match with intelligent fuzzy matching"
            inputSchema = @{
                type = "object"
                properties = @{
                    Query = @{
                        type = "string"
                        description = "Username, department name, short name, ID, or partial match to search for"
                        minLength = 1
                        maxLength = 100
                    }
                    Format = @{
                        type = "string"
                        enum = @("JSON", "Table", "CSV", "Detailed")
                        description = "Output format for results"
                        default = "JSON"
                    }
                    IncludeUsers = @{
                        type = "boolean"
                        description = "Include user list in department results"
                        default = $false
                    }
                    IncludeHierarchy = @{
                        type = "boolean"
                        description = "Include organizational hierarchy information"
                        default = $false
                    }
                    FuzzyMatch = @{
                        type = "boolean"
                        description = "Enable fuzzy matching for approximate searches"
                        default = $true
                    }
                    MaxResults = @{
                        type = "integer"
                        description = "Maximum number of results to return"
                        minimum = 1
                        maximum = 100
                        default = 10
                    }
                    Initiator = @{
                        type = "string"
                        description = "Identity of the requesting user or system"
                        default = "MCPAgent"
                    }
                }
                required = @("Query")
            }
            outputSchema = @{
                type = "object"
                properties = @{
                    status = @{ type = "string"; enum = @("success", "partial", "failed") }
                    query = @{ type = "string" }
                    matchType = @{ type = "string"; enum = @("exact", "partial", "fuzzy", "user", "multiple") }
                    results = @{
                        type = "array"
                        items = @{
                            type = "object"
                            properties = @{
                                departmentId = @{ type = "string" }
                                name = @{ type = "string" }
                                shortName = @{ type = "string" }
                                description = @{ type = "string" }
                                parentDepartment = @{ type = "string" }
                                division = @{ type = "string" }
                                manager = @{ type = "string" }
                                contact = @{
                                    type = "object"
                                    properties = @{
                                        email = @{ type = "string" }
                                        phone = @{ type = "string" }
                                        address = @{ type = "string" }
                                    }
                                }
                                budget = @{
                                    type = "object"
                                    properties = @{
                                        center = @{ type = "string" }
                                        fund = @{ type = "string" }
                                        program = @{ type = "string" }
                                    }
                                }
                                users = @{ type = "array" }
                                hierarchy = @{ type = "object" }
                                matchScore = @{ type = "number" }
                                matchReason = @{ type = "string" }
                            }
                        }
                    }
                    suggestions = @{ type = "array" }
                    metadata = @{
                        type = "object"
                        properties = @{
                            totalDepartments = @{ type = "integer" }
                            searchTime = @{ type = "number" }
                            cacheAge = @{ type = "number" }
                            lastUpdated = @{ type = "string" }
                        }
                    }
                    auditTrail = @{
                        type = "object"
                        properties = @{
                            sessionId = @{ type = "string" }
                            timestamp = @{ type = "string" }
                            initiator = @{ type = "string" }
                            query = @{ type = "string" }
                            resultCount = @{ type = "integer" }
                        }
                    }
                }
            }
        }
    }

    [hashtable] Execute([hashtable]$params) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $sessionId = [Guid]::NewGuid().ToString()
        
        try {
            # Initialize audit trail
            $auditTrail = @{
                sessionId = $sessionId
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                initiator = $params.Initiator ?? "MCPAgent"
                query = $params.Query
                resultCount = 0
            }

            $this.Logger.LogInfo("Department lookup session started", @{
                sessionId = $sessionId
                query = $params.Query
                initiator = $auditTrail.initiator
            })

            # Validate inputs
            $validationResult = $this.ValidateInputs($params)
            if ($validationResult.HasErrors) {
                return $this.BuildErrorResponse($validationResult.Errors, $auditTrail)
            }

            # Security validation (for sensitive queries)
            if ($params.IncludeUsers -or $params.IncludeHierarchy) {
                $securityValidation = $this.Security.ValidateLookupRequest($params.Query, $auditTrail.initiator)
                if (-not $securityValidation.IsAuthorized) {
                    return $this.BuildSecurityErrorResponse($securityValidation, $auditTrail)
                }
            }

            # Refresh cache if needed
            $this.RefreshCacheIfNeeded()

            # Perform lookup with intelligent matching
            $searchResult = $this.PerformLookup($params)
            
            # Enhance results with additional data if requested
            if ($params.IncludeUsers) {
                $searchResult.results = $this.EnhanceWithUserData($searchResult.results)
            }
            
            if ($params.IncludeHierarchy) {
                $searchResult.results = $this.EnhanceWithHierarchy($searchResult.results)
            }

            # Build comprehensive response
            $response = $this.BuildSuccessResponse($searchResult, $params, $auditTrail, $stopwatch.ElapsedMilliseconds)
            
            $this.Logger.LogInfo("Department lookup session completed", @{
                sessionId = $sessionId
                query = $params.Query
                resultCount = $searchResult.results.Count
                matchType = $searchResult.matchType
                duration = $stopwatch.ElapsedMilliseconds
            })

            return $response

        } catch {
            $this.Logger.LogError("Critical error in department lookup", @{
                sessionId = $sessionId
                query = $params.Query
                error = $_.Exception.Message
                stackTrace = $_.ScriptStackTrace
            })

            return @{
                status = "failed"
                error = "Critical system error during lookup"
                sessionId = $sessionId
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                auditTrail = $auditTrail
            }
        } finally {
            $stopwatch.Stop()
        }
    }

    [void] InitializeDepartmentData() {
        # Initialize comprehensive Pierce County department structure
        $this.DepartmentCache = @{
            "ADMIN" = @{
                departmentId = "ADMIN"
                name = "Administrative Services"
                shortName = "Admin"
                description = "County administration, HR, finance, and support services"
                parentDepartment = "EXECUTIVE"
                division = "General Government"
                manager = "admin.manager@piercecountywa.gov"
                contact = @{
                    email = "admin@piercecountywa.gov"
                    phone = "(253) 798-7300"
                    address = "930 Tacoma Ave S, Tacoma, WA 98402"
                }
                budget = @{
                    center = "1001"
                    fund = "001"
                    program = "100"
                }
                aliases = @("Administration", "Admin Services", "County Admin")
                keywords = @("administration", "admin", "finance", "hr", "human resources", "payroll")
            }
            
            "SHERIFF" = @{
                departmentId = "SHERIFF"
                name = "Sheriff's Department"
                shortName = "Sheriff"
                description = "Law enforcement, corrections, and public safety services"
                parentDepartment = "PUBLIC_SAFETY"
                division = "Public Safety"
                manager = "sheriff@piercecountywa.gov"
                contact = @{
                    email = "sheriff@piercecountywa.gov"
                    phone = "(253) 798-7530"
                    address = "910 Tacoma Ave S, Tacoma, WA 98402"
                }
                budget = @{
                    center = "2001"
                    fund = "001"
                    program = "200"
                }
                aliases = @("PCSO", "Sheriff's Office", "Law Enforcement")
                keywords = @("sheriff", "police", "law", "enforcement", "jail", "corrections", "deputies")
            }
            
            "FACILITIES" = @{
                departmentId = "FACILITIES"
                name = "Facilities Management"
                shortName = "Facilities"
                description = "Building maintenance, utilities, and facility operations"
                parentDepartment = "ADMIN"
                division = "General Government"
                manager = "facilities.manager@piercecountywa.gov"
                contact = @{
                    email = "facilities@piercecountywa.gov"
                    phone = "(253) 798-7350"
                    address = "2401 S 35th St, Tacoma, WA 98409"
                }
                budget = @{
                    center = "1050"
                    fund = "001"
                    program = "105"
                }
                aliases = @("Facilities Mgmt", "Building Services", "FM")
                keywords = @("facilities", "buildings", "maintenance", "utilities", "hvac", "janitorial")
            }
            
            "PUBLICWORKS" = @{
                departmentId = "PUBLICWORKS"
                name = "Public Works"
                shortName = "PW"
                description = "Infrastructure, transportation, and environmental services"
                parentDepartment = "OPERATIONS"
                division = "Public Works"
                manager = "pw.director@piercecountywa.gov"
                contact = @{
                    email = "publicworks@piercecountywa.gov"
                    phone = "(253) 798-7250"
                    address = "2702 S 42nd St, Tacoma, WA 98409"
                }
                budget = @{
                    center = "3001"
                    fund = "101"
                    program = "300"
                }
                aliases = @("PW", "Public Works Dept", "Infrastructure")
                keywords = @("public works", "roads", "bridges", "water", "sewer", "transportation", "infrastructure")
            }
            
            "PARKS" = @{
                departmentId = "PARKS"
                name = "Parks and Recreation"
                shortName = "Parks"
                description = "Parks, recreation facilities, and community programs"
                parentDepartment = "COMMUNITY"
                division = "Community Services"
                manager = "parks.director@piercecountywa.gov"
                contact = @{
                    email = "parks@piercecountywa.gov"
                    phone = "(253) 798-4141"
                    address = "9112 Lakewood Dr SW, Lakewood, WA 98499"
                }
                budget = @{
                    center = "4001"
                    fund = "001"
                    program = "400"
                }
                aliases = @("Parks & Rec", "Recreation", "Parks Dept")
                keywords = @("parks", "recreation", "community", "programs", "facilities", "sports")
            }
            
            "HEALTH" = @{
                departmentId = "HEALTH"
                name = "Health Department"
                shortName = "Health"
                description = "Public health services, environmental health, and community wellness"
                parentDepartment = "HEALTH_HUMAN"
                division = "Health & Human Services"
                manager = "health.director@piercecountywa.gov"
                contact = @{
                    email = "health@piercecountywa.gov"
                    phone = "(253) 798-6500"
                    address = "3629 S D St, Tacoma, WA 98418"
                }
                budget = @{
                    center = "5001"
                    fund = "001"
                    program = "500"
                }
                aliases = @("Public Health", "Health Dept", "TPCHD")
                keywords = @("health", "public health", "environmental", "wellness", "medical", "clinics")
            }
            
            "LIBRARY" = @{
                departmentId = "LIBRARY"
                name = "Pierce County Library"
                shortName = "Library"
                description = "Public library services, resources, and community programs"
                parentDepartment = "COMMUNITY"
                division = "Community Services"
                manager = "library.director@piercecountywa.gov"
                contact = @{
                    email = "library@piercecountywa.gov"
                    phone = "(253) 536-6500"
                    address = "3005 112th St E, Tacoma, WA 98446"
                }
                budget = @{
                    center = "6001"
                    fund = "001"
                    program = "600"
                }
                aliases = @("PCL", "County Library", "Library System")
                keywords = @("library", "books", "resources", "community", "programs", "literacy")
            }
            
            "IT" = @{
                departmentId = "IT"
                name = "Information Technology"
                shortName = "IT"
                description = "Technology services, infrastructure, and digital solutions"
                parentDepartment = "ADMIN"
                division = "General Government"
                manager = "it.director@piercecountywa.gov"
                contact = @{
                    email = "it@piercecountywa.gov"
                    phone = "(253) 798-7777"
                    address = "930 Tacoma Ave S, Tacoma, WA 98402"
                }
                budget = @{
                    center = "1025"
                    fund = "001"
                    program = "102"
                }
                aliases = @("Information Technology", "IT Services", "Technology")
                keywords = @("it", "technology", "computers", "network", "software", "infrastructure", "digital")
            }
        }
        
        $this.LastCacheUpdate = Get-Date
    }

    [hashtable] ValidateInputs([hashtable]$params) {
        $result = @{
            HasErrors = $false
            Errors = @()
            Warnings = @()
        }

        # Validate query
        if (-not $params.Query -or $params.Query.Trim().Length -eq 0) {
            $result.Errors += "Query parameter is required and cannot be empty"
            $result.HasErrors = $true
        }

        # Validate format
        if ($params.Format -and $params.Format -notin @("JSON", "Table", "CSV", "Detailed")) {
            $result.Errors += "Invalid format. Must be one of: JSON, Table, CSV, Detailed"
            $result.HasErrors = $true
        }

        # Validate max results
        if ($params.MaxResults -and ($params.MaxResults -lt 1 -or $params.MaxResults -gt 100)) {
            $result.Errors += "MaxResults must be between 1 and 100"
            $result.HasErrors = $true
        }

        return $result
    }

    [void] RefreshCacheIfNeeded() {
        $cacheAge = (Get-Date) - $this.LastCacheUpdate
        if ($cacheAge.TotalHours -gt 24) {
            # In a real implementation, this would refresh from authoritative sources
            $this.Logger.LogInfo("Department cache refresh needed", @{
                cacheAge = $cacheAge.TotalHours
                lastUpdate = $this.LastCacheUpdate
            })
            # For now, we'll just update the timestamp
            $this.LastCacheUpdate = Get-Date
        }
    }

    [hashtable] PerformLookup([hashtable]$params) {
        $query = $params.Query.Trim()
        $fuzzyMatch = $params.FuzzyMatch ?? $true
        $maxResults = $params.MaxResults ?? 10
        
        $results = @()
        $matchType = "none"
        $suggestions = @()

        # Check if query looks like an email (user lookup)
        if ($query -match '@piercecountywa\.gov$') {
            $userLookupResult = $this.LookupUserDepartment($query)
            if ($userLookupResult.Found) {
                $results = @($userLookupResult.Department)
                $matchType = "user"
            }
        } else {
            # Department lookup strategies
            $lookupStrategies = @(
                { $this.ExactDepartmentMatch($query) },
                { $this.DepartmentIdMatch($query) },
                { $this.ShortNameMatch($query) },
                { $this.AliasMatch($query) },
                { $this.KeywordMatch($query) }
            )

            if ($fuzzyMatch) {
                $lookupStrategies += { $this.FuzzyDepartmentMatch($query) }
            }

            foreach ($strategy in $lookupStrategies) {
                $strategyResult = & $strategy
                if ($strategyResult.results.Count -gt 0) {
                    $results = $strategyResult.results
                    $matchType = $strategyResult.matchType
                    break
                }
            }

            # Generate suggestions if no exact matches
            if ($results.Count -eq 0) {
                $suggestions = $this.GenerateSuggestions($query)
            }
        }

        # Limit results and sort by relevance
        if ($results.Count -gt $maxResults) {
            $results = $results | Sort-Object matchScore -Descending | Select-Object -First $maxResults
        }

        return @{
            results = $results
            matchType = $matchType
            suggestions = $suggestions
        }
    }

    [hashtable] ExactDepartmentMatch([string]$query) {
        $matches = @()
        foreach ($dept in $this.DepartmentCache.Values) {
            if ($dept.name -eq $query) {
                $dept.matchScore = 1.0
                $dept.matchReason = "Exact name match"
                $matches += $dept
            }
        }
        return @{ results = $matches; matchType = "exact" }
    }

    [hashtable] DepartmentIdMatch([string]$query) {
        $matches = @()
        $upperQuery = $query.ToUpper()
        foreach ($deptId in $this.DepartmentCache.Keys) {
            if ($deptId -eq $upperQuery) {
                $dept = $this.DepartmentCache[$deptId]
                $dept.matchScore = 1.0
                $dept.matchReason = "Department ID match"
                $matches += $dept
            }
        }
        return @{ results = $matches; matchType = "exact" }
    }

    [hashtable] ShortNameMatch([string]$query) {
        $matches = @()
        foreach ($dept in $this.DepartmentCache.Values) {
            if ($dept.shortName -ieq $query) {
                $dept.matchScore = 0.95
                $dept.matchReason = "Short name match"
                $matches += $dept
            }
        }
        return @{ results = $matches; matchType = "exact" }
    }

    [hashtable] AliasMatch([string]$query) {
        $matches = @()
        foreach ($dept in $this.DepartmentCache.Values) {
            if ($dept.aliases) {
                foreach ($alias in $dept.aliases) {
                    if ($alias -ieq $query) {
                        $dept.matchScore = 0.9
                        $dept.matchReason = "Alias match: $alias"
                        $matches += $dept
                        break
                    }
                }
            }
        }
        return @{ results = $matches; matchType = "partial" }
    }

    [hashtable] KeywordMatch([string]$query) {
        $matches = @()
        $queryLower = $query.ToLower()
        
        foreach ($dept in $this.DepartmentCache.Values) {
            $score = 0
            $matchedKeywords = @()
            
            if ($dept.keywords) {
                foreach ($keyword in $dept.keywords) {
                    if ($queryLower -like "*$keyword*" -or $keyword -like "*$queryLower*") {
                        $score += 0.1
                        $matchedKeywords += $keyword
                    }
                }
            }
            
            # Also check name and description
            if ($dept.name.ToLower() -like "*$queryLower*") {
                $score += 0.3
                $matchedKeywords += "name"
            }
            
            if ($dept.description.ToLower() -like "*$queryLower*") {
                $score += 0.2
                $matchedKeywords += "description"
            }
            
            if ($score -gt 0) {
                $dept.matchScore = [Math]::Min($score, 0.8)
                $dept.matchReason = "Keyword match: $($matchedKeywords -join ', ')"
                $matches += $dept
            }
        }
        
        return @{ results = ($matches | Sort-Object matchScore -Descending); matchType = "partial" }
    }

    [hashtable] FuzzyDepartmentMatch([string]$query) {
        $matches = @()
        $queryLower = $query.ToLower()
        
        foreach ($dept in $this.DepartmentCache.Values) {
            # Calculate Levenshtein distance for fuzzy matching
            $nameScore = $this.CalculateSimilarity($queryLower, $dept.name.ToLower())
            $shortScore = $this.CalculateSimilarity($queryLower, $dept.shortName.ToLower())
            
            $maxScore = [Math]::Max($nameScore, $shortScore)
            
            if ($maxScore -gt 0.6) {
                $dept.matchScore = $maxScore * 0.7  # Reduce score for fuzzy matches
                $dept.matchReason = "Fuzzy match (similarity: $([Math]::Round($maxScore, 2)))"
                $matches += $dept
            }
        }
        
        return @{ results = ($matches | Sort-Object matchScore -Descending); matchType = "fuzzy" }
    }

    [double] CalculateSimilarity([string]$str1, [string]$str2) {
        # Simple similarity calculation (Jaro-Winkler approximation)
        if ($str1 -eq $str2) { return 1.0 }
        if ($str1.Length -eq 0 -or $str2.Length -eq 0) { return 0.0 }
        
        $maxLength = [Math]::Max($str1.Length, $str2.Length)
        $distance = $this.LevenshteinDistance($str1, $str2)
        
        return 1.0 - ($distance / $maxLength)
    }

    [int] LevenshteinDistance([string]$str1, [string]$str2) {
        $matrix = New-Object 'int[,]' ($str1.Length + 1), ($str2.Length + 1)
        
        for ($i = 0; $i -le $str1.Length; $i++) { $matrix[$i, 0] = $i }
        for ($j = 0; $j -le $str2.Length; $j++) { $matrix[0, $j] = $j }
        
        for ($i = 1; $i -le $str1.Length; $i++) {
            for ($j = 1; $j -le $str2.Length; $j++) {
                $cost = if ($str1[$i-1] -eq $str2[$j-1]) { 0 } else { 1 }
                $matrix[$i, $j] = [Math]::Min([Math]::Min($matrix[$i-1, $j] + 1, $matrix[$i, $j-1] + 1), $matrix[$i-1, $j-1] + $cost)
            }
        }
        
        return $matrix[$str1.Length, $str2.Length]
    }

    [hashtable] LookupUserDepartment([string]$userEmail) {
        # In a real implementation, this would query AD/Azure AD
        # For now, return a mock result based on email patterns
        $results = @{
            Found = $false
            Department = $null
        }
        
        # Mock logic based on email patterns
        switch -Regex ($userEmail) {
            '.*admin.*|.*hr.*|.*finance.*' { 
                $results.Found = $true
                $results.Department = $this.DepartmentCache["ADMIN"]
                $results.Department.matchScore = 1.0
                $results.Department.matchReason = "User department lookup"
            }
            '.*sheriff.*|.*deputy.*|.*jail.*' {
                $results.Found = $true
                $results.Department = $this.DepartmentCache["SHERIFF"]
                $results.Department.matchScore = 1.0
                $results.Department.matchReason = "User department lookup"
            }
            '.*facilities.*|.*maintenance.*' {
                $results.Found = $true
                $results.Department = $this.DepartmentCache["FACILITIES"]
                $results.Department.matchScore = 1.0
                $results.Department.matchReason = "User department lookup"
            }
            '.*it.*|.*tech.*' {
                $results.Found = $true
                $results.Department = $this.DepartmentCache["IT"]
                $results.Department.matchScore = 1.0
                $results.Department.matchReason = "User department lookup"
            }
        }
        
        return $results
    }

    [array] GenerateSuggestions([string]$query) {
        $suggestions = @()
        $queryLower = $query.ToLower()
        
        # Generate suggestions based on partial matches
        foreach ($dept in $this.DepartmentCache.Values) {
            if ($dept.name.ToLower().Contains($queryLower.Substring(0, [Math]::Min(3, $queryLower.Length)))) {
                $suggestions += $dept.name
            }
            if ($dept.shortName.ToLower().Contains($queryLower.Substring(0, [Math]::Min(2, $queryLower.Length)))) {
                $suggestions += $dept.shortName
            }
        }
        
        return ($suggestions | Select-Object -Unique | Select-Object -First 5)
    }

    [array] EnhanceWithUserData([array]$departments) {
        # In a real implementation, this would query AD/Exchange for actual user lists
        foreach ($dept in $departments) {
            $dept.users = @("user1@piercecountywa.gov", "user2@piercecountywa.gov")  # Mock data
        }
        return $departments
    }

    [array] EnhanceWithHierarchy([array]$departments) {
        # Add organizational hierarchy information
        foreach ($dept in $departments) {
            $dept.hierarchy = @{
                level = 2
                parent = $dept.parentDepartment
                children = @()  # Would be populated from actual data
                siblings = @()  # Would be populated from actual data
            }
        }
        return $departments
    }

    [hashtable] BuildSuccessResponse([hashtable]$searchResult, [hashtable]$params, [hashtable]$auditTrail, [int]$duration) {
        $metadata = @{
            totalDepartments = $this.DepartmentCache.Count
            searchTime = $duration
            cacheAge = ((Get-Date) - $this.LastCacheUpdate).TotalHours
            lastUpdated = $this.LastCacheUpdate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }

        $auditTrail.resultCount = $searchResult.results.Count

        return @{
            status = "success"
            query = $params.Query
            matchType = $searchResult.matchType
            results = $searchResult.results
            suggestions = $searchResult.suggestions
            metadata = $metadata
            auditTrail = $auditTrail
            executionTime = $duration
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildErrorResponse([array]$errors, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            errors = $errors
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    [hashtable] BuildSecurityErrorResponse([hashtable]$securityValidation, [hashtable]$auditTrail) {
        return @{
            status = "failed"
            error = "Security validation failed: $($securityValidation.Reason)"
            securityFlags = $securityValidation.Flags
            auditTrail = $auditTrail
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
}

# Export the tool class for the registry
if ($MyInvocation.InvocationName -ne '.') {
    return [DepartmentLookupTool]
}
