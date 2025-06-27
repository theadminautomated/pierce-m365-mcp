param(
    [string]$ComposeFile = 'docker-compose.yml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Write-Host "Deploying containers using $ComposeFile..."
    docker compose -f $ComposeFile up -d
    Write-Host "Deployment successful"
} catch {
    Write-Error "Docker deployment failed: $($_.Exception.Message)"
    exit 1
}
