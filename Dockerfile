FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

# Create app directory
WORKDIR /app

# Install OS packages
RUN apt-get update && \
    apt-get install -y python3 python3-pip curl && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies first for caching
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

# Install required PowerShell modules
RUN pwsh -NoLogo -NonInteractive -Command \
    "Install-Module Microsoft.Graph -Force -AllowClobber; Install-Module ExchangeOnlineManagement -Force -AllowClobber"

# Copy source code and scripts
COPY src ./src
COPY scripts ./scripts
COPY mcp.config.json ./mcp.config.json

# Create non-root user
RUN useradd -ms /bin/bash mcpuser
USER mcpuser

ENV POWERSHELL_TELEMETRY_OPTOUT=1

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s CMD pwsh -File /app/scripts/docker-health-check.ps1

ENTRYPOINT ["pwsh", "-File", "/app/src/MCPServer.ps1"]
