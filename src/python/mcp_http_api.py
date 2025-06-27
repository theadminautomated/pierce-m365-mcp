import asyncio
import json
import os
import uuid
import subprocess
from typing import Any, Dict

from fastapi import FastAPI, HTTPException

SCRIPT_PATH = os.environ.get("MCP_SCRIPT", "/opt/mcp/src/MCPServer.ps1")
CORE_MODULE = os.environ.get("MCP_CORE_MODULE", "/opt/mcp/src/Mcp.Core.psm1")

class MCPBridge:
    def __init__(self, script: str, module: str) -> None:
        self.proc = subprocess.Popen([
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            f"Import-Module '{module}'; & '{script}'"
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

    async def send(self, method: str, params: Dict[str, Any] | None = None) -> Any:
        request_id = str(uuid.uuid4())
        request = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}}
        assert self.proc.stdin
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()
        while True:
            line = await asyncio.get_event_loop().run_in_executor(None, self.proc.stdout.readline)
            if not line:
                raise HTTPException(status_code=500, detail="MCP server terminated")
            try:
                resp = json.loads(line)
            except json.JSONDecodeError:
                continue
            if resp.get("id") == request_id:
                if "error" in resp:
                    raise HTTPException(status_code=500, detail=resp["error"].get("message"))
                return resp.get("result")

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()

bridge = MCPBridge(SCRIPT_PATH, CORE_MODULE)
app = FastAPI()

@app.on_event("shutdown")
def shutdown_event() -> None:
    bridge.stop()

@app.post("/tools/call")
async def call_tool(payload: Dict[str, Any]):
    return await bridge.send("tools/call", payload)

@app.get("/health")
async def health() -> Dict[str, str]:
    return {"status": "ok"}

