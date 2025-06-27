param(
    [string]$Tag = 'pierce-mcp:latest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Write-Host "Checking Docker daemon..."
    docker info | Out-Null
} catch {
    Write-Error "Docker daemon not reachable. Ensure Docker Desktop or the docker service is running."
    exit 1
}

try {
    Write-Host "Building Docker image $Tag..."
    docker build -t $Tag .
    Write-Host "Image built successfully"
} catch {
    Write-Error "Docker build failed: $($_.Exception.Message)"
    exit 1
}
