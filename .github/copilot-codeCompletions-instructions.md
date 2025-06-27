PIERCE COUNTY — COPILOT CODE-GENERATION INSTRUCTIONS
===================================================

SCOPE
-----
These instructions apply to GitHub Copilot (or any inline code-completion model) when invoked by the “Universal AI Orchestration Agent” in Pierce County’s regulated Microsoft 365 (GCC) environment.

MISSION
-------
Copilot must generate minimal, production-ready snippets that **conform 100 %** to Pierce County’s MCP tool architecture, security standards, and naming conventions.

GLOBAL RULES
------------
1. **No Ad-Hoc Code:**  
   Generate code **only** when explicitly requested by the orchestration agent or a human approver.  
2. **MCP Pattern Only:**  
   All PowerShell/TypeScript/Python snippets **must** follow the MCP tool template:  
   - **Input:** single JSON object via parameter or `stdin`.  
   - **Output:** single compressed JSON object to `stdout`.  
   - Non-interactive, idempotent, `-Confirm:$false`, no host prompts.  
3. **Naming & Compliance:**  
   - File/Script names: `snake_case` or `kebab-case`, lowercase.  
   - Functions: `PascalCase` with verb-noun (`Set-RetentionPolicy`).  
   - Variables: `camelCase`.  
   - User emails: `first.last@piercecountywa.gov`.  
   - Resource mailboxes: `[a-z0-9_-]+@piercecountywa.gov` (no dots).  
4. **Security:**  
   - Never include secrets, tokens, client IDs, or tenant IDs.  
   - Use `$env:` variables or Azure Key Vault references when placeholders are unavoidable.  
5. **Logging:**  
   - Use structured JSON arrays `actions` and `failures`.  
   - No `Write-Host`, `Write-Output`, or plaintext logs.  
6. **Validation Stub:**  
   Always insert an “entity validation” block × TODO comment to enforce naming rules if not already present.

DEFAULT TEMPLATES
-----------------

### PowerShell MCP Tool Template
```powershell
<#
.SYNOPSIS  : <One-line description>
.INPUT JSON: { paramA (string), paramB (string) }
.OUTPUT JSON: { status, actions[], failures[] }
#>
param([Parameter(Mandatory)][string]$InputJson)
$ErrorActionPreference = 'Stop'
$result = @{status='success'; actions=@(); failures=@()}
try {
    $in  = $InputJson | ConvertFrom-Json
    # TODO: Validate entities
    # === ACTION LOGIC HERE ===
}
catch { $result.status='failed'; $result.failures+=($_.Exception.Message) }
finally { $result | ConvertTo-Json -Compress }
VS Code mcp.json Snippet

"NewToolName": {
  "type": "stdio",
  "command": "powershell",
  "args": ["-File","${workspaceFolder}/tools/new_tool.ps1"],
  "description": "Short description"
}
OpenAPI Stub (optional)

post:
  summary: <Action>
  operationId: newTool
  requestBody:
    content:
      application/json:
        schema: { "$ref": "#/components/schemas/NewToolRequest" }
  responses:
    "200":
      description: Success
      content:
        application/json:
          schema: { "$ref": "#/components/schemas/NewToolResponse" }
BEHAVIOR PROMPTS
When generating code, Copilot should reason silently with these steps:

Understand Intent (from agent payload).

Insert Validation Block (naming/domain compliance).

Follow Template (input JSON → actions → output JSON).

Return Minimal Snippet (no extra comments except TODOs).

EXAMPLES
Request:

“Create a tool that assigns a retention policy based on CustomAttribute1.”

Copilot Output:
(only the ps1 template filled out; no prose, no markdown)

Request:

“Generate the mcp.json block for that tool.”

Copilot Output:
(exact JSONC snippet as template above)

FAIL-SAFE
If context is missing or entities are invalid, Copilot must emit a single-line TODO comment indicating what is required.

CHANGE CONTROL
All new code produced via Copilot must be committed through pull-request and peer-review in the m365-agent-orchestration repo.

END-OF-INSTRUCTIONS

