# Codex Agent Guidelines for Pierce County M365 MCP Server

This repository contains the Pierce County M365 MCP Server. The server is an enterprise-grade PowerShell and Python platform for Microsoft 365 automation. Use these guidelines when modifying or analyzing the repository.

## Repository Overview
- **PowerShell core modules** are under `src/Core/`.
- **Entry point** is `src/MCPServer.ps1` which imports `src/Mcp.Core.psm1`.
- **Python modules** for reasoning and the HTTP API are in `src/python/`.
- **Administrative scripts** live in `scripts/`.
- **Tests** are in `tests/` (Python) and `scripts/test-*.ps1` (PowerShell).
- **Configuration** lives in `mcp.config.json` and `.vscode/mcp.json`.

## General Development Rules
1. **Keep code modular**. All new functionality should be added as standalone modules or tools.
2. **Follow existing naming patterns** for files and functions.
3. **Preserve GCC compliance and audit logging** when adding features.
4. **Do not include secrets** in code or logs. Use environment variables when required.

## Testing
Run both Python and PowerShell tests before committing:
```bash
python -m pytest -q
pwsh ./scripts/test-core-modules.ps1
pwsh ./scripts/test-syntax.ps1
pwsh ./scripts/validate-architecture.ps1
```
Some tests rely on PowerShell 7 (`pwsh`). If `pwsh` is unavailable the tests may fail.

## Useful Scripts
- `scripts/watchdog.ps1` — ensures the server stays running.
- `scripts/install-autostart.ps1` — installs the watchdog service.
- `scripts/test-memory-integration.ps1` — validates the vector memory bank.

## Documentation
- Primary documentation is in `README.md` and the `docs/` directory.
- `.github/copilot-instructions.md` and `.github/copilot-codeCompletions-instructions.md` define additional coding rules for Copilot.

## Commit Guidance
- Provide clear commit messages summarizing the change.
- Ensure all tests pass before opening a pull request.

