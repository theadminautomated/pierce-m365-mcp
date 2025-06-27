#Requires -Version 7.0
<#
.SYNOPSIS
    Pluggable AI Provider Manager for MCP Server
.DESCRIPTION
    Provides dynamic configuration and invocation of external or local LLM endpoints.
    Supports multiple providers and secure invocation with audit logging.
#>

using namespace System.Collections.Generic

class AIProviderConfig {
    [string]$Name
    [string]$Type
    [string]$Endpoint
    [string]$Model
    [hashtable]$Headers
    [string]$AuthToken
    [int]$TimeoutSec

    AIProviderConfig() {
        $this.Headers = @{}
        $this.TimeoutSec = 30
    }
}

class AIProvider {
    [AIProviderConfig]$Config
    [Logger]$Logger

    AIProvider([AIProviderConfig]$cfg,[Logger]$logger) {
        $this.Config = $cfg
        $this.Logger = $logger
    }

    [hashtable] Invoke([hashtable]$payload) {
        $headers = @{}
        if ($this.Config.AuthToken) { $headers['Authorization'] = "Bearer $($this.Config.AuthToken)" }
        foreach ($k in $this.Config.Headers.Keys) { $headers[$k] = $this.Config.Headers[$k] }
        $payload.model = $this.Config.Model
        $this.Logger.Debug('Invoking AI provider', @{Provider=$this.Config.Name; Endpoint=$this.Config.Endpoint})
        try {
            $resp = Invoke-RestMethod -Uri $this.Config.Endpoint -Method Post -Headers $headers -Body ($payload | ConvertTo-Json -Depth 5) -TimeoutSec $this.Config.TimeoutSec
            $this.Logger.Info('AI provider response', @{Provider=$this.Config.Name; Length=($resp | Out-String).Length})
            return $resp
        } catch {
            $this.Logger.Error('AI provider invocation failed', @{Provider=$this.Config.Name; Error=$_.Exception.Message})
            throw
        }
    }
}

class AIManager {
    [Dictionary[string,AIProvider]]$Providers
    [string]$DefaultProvider
    [Logger]$Logger

    AIManager([Logger]$logger,[hashtable]$config) {
        $this.Logger = $logger
        $this.Providers = [Dictionary[string,AIProvider]]::new()
        if($config -and $config.AIProviders){ $this.LoadProviders($config.AIProviders) }
        if($config){ $this.DefaultProvider = $config.DefaultAIProvider }
    }

    [void] LoadProviders([object[]]$providerConfigs) {
        foreach($p in $providerConfigs){
            $cfg = [AIProviderConfig]::new()
            $cfg.Name = $p.Name
            $cfg.Type = $p.Type
            $cfg.Endpoint = $p.Endpoint
            $cfg.Model = $p.Model
            $cfg.Headers = $p.Headers
            $cfg.AuthToken = $p.AuthToken
            if($p.TimeoutSec){ $cfg.TimeoutSec = [int]$p.TimeoutSec }
            $prov = [AIProvider]::new($cfg,$this.Logger)
            $this.Providers[$cfg.Name] = $prov
        }
    }

    [AIProvider] GetProvider([string]$name) {
        if(-not $name){ $name = $this.DefaultProvider }
        $prov = $null
        if($this.Providers.TryGetValue($name,[ref]$prov)){ return $prov }
        throw "AI provider '$name' not found"
    }

    [string] InvokeCompletion([string]$prompt,[string]$providerName) {
        $prov = $this.GetProvider($providerName)
        $payload = @{ prompt = $prompt }
        $res = $prov.Invoke($payload)
        if($res.choices){ return $res.choices[0].text }
        elseif($res.content){ return $res.content }
        return $res | ConvertTo-Json -Depth 5
    }

    [EntityCollection] ParseEntities([string]$text,[string]$providerName) {
        $prov = $this.GetProvider($providerName)
        $payload = @{ input = $text; operation = 'parse_entities' }
        $res = $prov.Invoke($payload)
        $entities = [EntityCollection]::new()
        foreach($u in $res.users){ $entities.AddUsers([UserEntity]::new($u)) }
        foreach($m in $res.mailboxes){ $entities.AddMailboxes([MailboxEntity]::new($m,[MailboxType]::Shared)) }
        foreach($g in $res.groups){ $entities.AddGroups([GroupEntity]::new($g)) }
        foreach($a in $res.actions){ $act = [ActionEntity]::new([ActionType]::$('Generic')); $act.OriginalText = $a; $entities.AddActions($act) }
        return $entities
    }
}

