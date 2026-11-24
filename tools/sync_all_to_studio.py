import subprocess
import json
import time
import os

MCP_EXE = r"C:\Users\ppaes\AppData\Local\Roblox\Versions\version-8d7a1009c17e4ff8\StudioMCP.exe"

class StudioClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            [MCP_EXE],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8"
        )
        self.msg_id = 0
        self._init_mcp()
        self.studio_id = self._get_studio_id()

    def _send(self, method, params=None):
        self.msg_id += 1
        req = {"jsonrpc": "2.0", "id": self.msg_id, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("Empty response from StudioMCP")
        return json.loads(line)

    def _init_mcp(self):
        resp = self._send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "sync_tool", "version": "1.0"}
        })
        self._send("notifications/initialized")
        print("MCP Initialized successfully.")

    def _get_studio_id(self):
        resp = self._send("tools/call", {
            "name": "list_roblox_studios",
            "arguments": {}
        })
        content_text = resp["result"]["content"][0]["text"]
        data = json.loads(content_text)
        studio = data["studios"][0]
        mode_str = studio.get("mode", "Edit")
        print(f"Found Studio: {studio['name']} (ID: {studio['id']}, Mode: {mode_str})")
        return studio["id"]

    def execute_luau(self, code, datamodel_type="Edit"):
        resp = self._send("tools/call", {
            "name": "execute_luau",
            "arguments": {
                "studio_id": self.studio_id,
                "datamodel_type": datamodel_type,
                "code": code
            }
        })
        result_text = resp["result"]["content"][0]["text"]
        is_error = resp["result"].get("isError", False)
        if is_error:
            raise RuntimeError(f"Luau execution error: {result_text}")
        return result_text

    def set_script_source(self, target_path, source_code, chunk_size=10000):
        raw_bytes = source_code.encode("utf-8")
        byte_chunks = [raw_bytes[i:i+chunk_size] for i in range(0, len(raw_bytes), chunk_size)]
        var_name = "_G._sync_buf"
        
        # Init buffer
        self.execute_luau(f"{var_name} = {{}}")
        for chunk in byte_chunks:
            escaped = "".join(f"\\x{b:02x}" for b in chunk)
            code = f'table.insert({var_name}, "{escaped}")'
            self.execute_luau(code)
            
        # Concat and assign
        finalize_code = f"""
local full = table.concat({var_name}, "")
{target_path}.Source = full
{var_name} = nil
return tostring(#({target_path}.Source))
"""
        new_len = self.execute_luau(finalize_code)
        return int(new_len)

    def close(self):
        self.proc.terminate()

def main():
    client = StudioClient()
    try:
        print("--- 1. Syncing WorldServer ---")
        with open("src/server/WorldServer.server.lua", "r", encoding="utf-8") as f:
            src = f.read()
        l = client.set_script_source('game:GetService("ServerScriptService").Server.WorldServer', src)
        print(f"WorldServer synced: {l} bytes")

        print("--- 2. Syncing WorldGrid ---")
        with open("src/shared/WorldGrid.lua", "r", encoding="utf-8") as f:
            src = f.read()
        l = client.set_script_source('game:GetService("ReplicatedStorage").Shared.WorldGrid', src)
        print(f"WorldGrid synced: {l} bytes")

        print("--- 3. Syncing WorldEngine ---")
        with open("src/server/WorldEngine.lua", "r", encoding="utf-8") as f:
            src = f.read()
        l = client.set_script_source('game:GetService("ServerScriptService").Server.WorldEngine', src)
        print(f"WorldEngine synced: {l} bytes")

        print("--- 4. Syncing FrontWarsMaps Module ---")
        with open("src/shared/FrontWarsMaps.lua", "r", encoding="utf-8") as f:
            src = f.read()
        l = client.set_script_source('game:GetService("ReplicatedStorage").Shared.FrontWarsMaps', src)
        print(f"FrontWarsMaps synced: {l} bytes")

        print("--- 5. Syncing FrontWars Maps ---")
        maps = ['world', 'pangaea', 'europe', 'asia', 'africa', 'mena', 'mars', 'oceania']
        for m in maps:
            fpath = f"src/shared/frontwars_maps/{m}.lua"
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            target = f'game:GetService("ReplicatedStorage").Shared.frontwars_maps.{m}'
            l = client.set_script_source(target, src)
            print(f"Map {m} synced: {l} bytes")

        print("--- 6. Syncing WorldClient ---")
        with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
            src = f.read()
        l = client.set_script_source('game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldClient', src)
        print(f"WorldClient synced: {l} bytes")

        print("\nALL SCRIPTS SYNCED SUCCESSFULLY TO ROBLOX STUDIO!")
    finally:
        client.close()

if __name__ == "__main__":
    main()
