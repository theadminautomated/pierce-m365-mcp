#Requires -Version 7.0

param(
    [string]$Description,
    [string[]]$Tests = @("$PSScriptRoot/test-core-modules.ps1", "$PSScriptRoot/test-syntax.ps1"),
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/.."),
    [string]$NotifyEndpoint = ''
)

Import-Module "$PSScriptRoot/../src/Core/PRSuggestionEngine.ps1"
$engine = [PRSuggestionEngine]::new($RepoRoot, 'main', $NotifyEndpoint)
$engine.SuggestPullRequest($Description, $Tests)
