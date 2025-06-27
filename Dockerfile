FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

WORKDIR /opt/mcp

# Install Python and dependencies
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

COPY . /opt/mcp

ENV POWERSHELL_TELEMETRY_OPTOUT=1
ENV MCP_SCRIPT=/opt/mcp/src/MCPServer.ps1

EXPOSE 8080

CMD ["uvicorn", "src.python.mcp_http_api:app", "--host", "0.0.0.0", "--port", "8080"]
