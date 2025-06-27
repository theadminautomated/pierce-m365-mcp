#Requires -Version 7.0
<#
.SYNOPSIS
    Installs or updates the MCP Server watchdog service for automatic start.
.DESCRIPTION
    Creates a platform-appropriate service entry that launches the watchdog
    script which ensures the MCP server stays running. Supports Windows
    (New-Service) and Linux (systemd). Requires administrator or root rights.
#>

param(
    [string]$ServiceName = "PierceMCP",
    [string]$ServerScript = (Join-Path $PSScriptRoot '..\src\MCPServer.ps1'),
    [string]$WatchdogScript = (Join-Path $PSScriptRoot 'watchdog.ps1')
)

function Install-WindowsService {
    param([string]$name, [string]$binaryPath)

    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        New-Service -Name $name -BinaryPathName $binaryPath -Description 'Pierce County MCP Server Watchdog' -StartupType Automatic
    } else {
        Set-Service -Name $name -StartupType Automatic
        $wmi = Get-WmiObject -Class Win32_Service -Filter "Name='$name'"
        $null = $wmi.Change($null,$null,$null,$null,$null,$null,$binaryPath,$null,$null,$null)
    }
    Start-Service -Name $name
}

function Install-SystemdService {
    param([string]$name, [string]$binaryPath)

    $servicePath = "/etc/systemd/system/$name.service"
    $content = @"
[Unit]
Description=Pierce County MCP Server Watchdog
After=network.target

[Service]
Type=simple
ExecStart=$binaryPath
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
"@
    Set-Content -Path $servicePath -Value $content -Force
    systemctl daemon-reload
    systemctl enable $name
    systemctl restart $name
}

$binary = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$WatchdogScript`" -ServerScript `"$ServerScript`""

if ($IsWindows) {
    Install-WindowsService -name $ServiceName -binaryPath $binary
} else {
    Install-SystemdService -name $ServiceName -binaryPath $binary
}
