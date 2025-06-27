$ErrorActionPreference='Stop'
. $PSScriptRoot/../src/Core/OrchestrationTypes.ps1
. $PSScriptRoot/../src/Core/Logger.ps1
. $PSScriptRoot/../src/Core/EntityExtractor.ps1
$logger = [Logger]::new([LogLevel]::Error)
$ex = [EntityExtractor]::new($logger)
$obj = @{Synonyms=$ex.Synonyms; Corrections=$ex.Corrections}
$obj | ConvertTo-Json -Depth 4
