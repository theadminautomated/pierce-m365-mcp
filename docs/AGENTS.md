# Pierce County M365 MCP Server – Agent Guide

This repository hosts the Pierce County M365 MCP Server, a cross-platform orchestration engine for Microsoft 365 automation. The project delivers autonomous tool chaining, persistent context, and zero‑trust security for the Pierce County GCC environment.

## Mission
Provide self-healing Microsoft 365 administration through agentic workflows and strict compliance enforcement. The server orchestrates PowerShell and Python tools with full audit trails and memory-driven entity normalization.

## Tool Inventory
| ServerId | ScriptPath | Purpose | Input JSON Schema | Output JSON Schema | Lint Issues | Auth Dependencies |
|---------|-----------|---------|------------------|-------------------|------------|------------------|
| PierceCountyM365Admin | src/MCPServer.ps1 | MCP server entrypoint | Request object with tool, parameters | Standard MCP response | 0 | Exchange Online, Graph |

## Execution Modes
- **Manual CLI**: `pwsh ./src/MCPServer.ps1 -Request '{"tool":"help"}'`
- **Webhook (Jira)**: POST requests to the FastAPI gateway on port `3000`.
- **MCP/AI orchestration**: `.vscode/mcp.json` defines the standard server for Codex and Copilot.

## Validation & Naming Rules
Pierce County mailboxes and accounts follow strict naming conventions. Override defaults with environment variables:
- `MCP_DEFAULT_DOMAIN` – primary domain suffix
- `MCP_PYTHON` – custom Python path

## Security Findings
No hard-coded credentials or GUIDs were detected. Sensitive parameter checks are enforced in `SecurityManager.ps1`.

## Outstanding TODOs
- Architecture validation script reports warnings – review missing components.
- Several PowerShell scripts contain ScriptAnalyzer issues (see `psa_summary.json`).
- No dead MCP server entries detected.

