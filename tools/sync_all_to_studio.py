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
        studios = data.get("studios", [])
        if not studios:
            raise RuntimeError("No active Roblox Studio instance found. Please launch Roblox Studio!")
        studio = studios[0]
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

    def ensure_instance(self, parent_expr, class_name, name):
        code = f"""
local p = {parent_expr}
local child = p:FindFirstChild("{name}")
if not child then
    child = Instance.new("{class_name}")
    child.Name = "{name}"
    child.Parent = p
end
return child.Name
"""
        return self.execute_luau(code)

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

def sync_openfront(client):
    print("=== SYNCHRONIZING OPENFRONT ARCHITECTURE TO ROBLOX STUDIO ===")

    # 1. Ensure folders in ReplicatedStorage, ServerScriptService, StarterPlayerScripts
    client.ensure_instance('game:GetService("ReplicatedStorage")', "Folder", "OpenFront")
    client.ensure_instance('game:GetService("ReplicatedStorage").OpenFront', "Folder", "Shared")
    client.ensure_instance('game:GetService("ReplicatedStorage")', "Folder", "Shared")
    client.ensure_instance('game:GetService("ReplicatedStorage").Shared', "Folder", "frontwars_maps")

    client.ensure_instance('game:GetService("ServerScriptService")', "Folder", "OpenFront")
    client.ensure_instance('game:GetService("ServerScriptService").OpenFront', "Folder", "Server")
    client.ensure_instance('game:GetService("ServerScriptService").OpenFront.Server', "Folder", "execution")

    client.ensure_instance('game:GetService("StarterPlayer").StarterPlayerScripts', "Folder", "OpenFront")
    client.ensure_instance('game:GetService("StarterPlayer").StarterPlayerScripts.OpenFront', "Folder", "Client")

    # 2. Sync Shared Modules
    shared_files = ["GameTypes", "TerrainBytes", "Config", "EngineConfig", "MapRegistry"]
    for mod_name in shared_files:
        fpath = f"src/openfront/shared/{mod_name}.lua"
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            client.ensure_instance('game:GetService("ReplicatedStorage").OpenFront.Shared', "ModuleScript", mod_name)
            target = f'game:GetService("ReplicatedStorage").OpenFront.Shared.{mod_name}'
            l = client.set_script_source(target, src)
            print(f"  [Shared] {mod_name} synced: {l} bytes")

    # 3. Sync FrontWars Maps
    maps = ['world', 'pangaea', 'europe', 'asia', 'africa', 'mena', 'mars', 'oceania', 'achiran', 'baikal']
    for m in maps:
        fpath = f"src/shared/frontwars_maps/{m}.lua"
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            client.ensure_instance('game:GetService("ReplicatedStorage").Shared.frontwars_maps', "ModuleScript", m)
            target = f'game:GetService("ReplicatedStorage").Shared.frontwars_maps.{m}'
            l = client.set_script_source(target, src)
            print(f"  [Map] {m} synced: {l} bytes")

    # 4. Sync Server Execution Modules
    exec_modules = [
        "AttackExecution", "TransportShipExecution", "WarshipExecution",
        "ConstructionExecution", "NukeExecution", "MIRVExecution",
        "SAMLauncherExecution", "WinCheckExecution", "NationExecution"
    ]
    for mod_name in exec_modules:
        fpath = f"src/openfront/server/execution/{mod_name}.lua"
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            client.ensure_instance('game:GetService("ServerScriptService").OpenFront.Server.execution', "ModuleScript", mod_name)
            target = f'game:GetService("ServerScriptService").OpenFront.Server.execution.{mod_name}'
            l = client.set_script_source(target, src)
            print(f"  [Server.execution] {mod_name} synced: {l} bytes")

    # 5. Sync Server Core Modules
    server_core = ["GameMap", "Player", "UnitGrid", "ExecutionManager", "GameRunner"]
    for mod_name in server_core:
        fpath = f"src/openfront/server/{mod_name}.lua"
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            client.ensure_instance('game:GetService("ServerScriptService").OpenFront.Server', "ModuleScript", mod_name)
            target = f'game:GetService("ServerScriptService").OpenFront.Server.{mod_name}'
            l = client.set_script_source(target, src)
            print(f"  [Server] {mod_name} synced: {l} bytes")

    # 6. Sync ServerMain Script
    fpath = "src/openfront/server/ServerMain.server.lua"
    if os.path.exists(fpath):
        with open(fpath, "r", encoding="utf-8") as f:
            src = f.read()
        client.ensure_instance('game:GetService("ServerScriptService").OpenFront.Server', "Script", "ServerMain")
        target = 'game:GetService("ServerScriptService").OpenFront.Server.ServerMain'
        l = client.set_script_source(target, src)
        print(f"  [ServerScript] ServerMain synced: {l} bytes")

    # 7. Sync Client Modules & LocalScript
    client_modules = ["TerrainRenderer", "TerritoryRenderer", "InGameHUD", "HubScreen"]
    for mod_name in client_modules:
        fpath = f"src/openfront/client/{mod_name}.lua"
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                src = f.read()
            client.ensure_instance('game:GetService("StarterPlayer").StarterPlayerScripts.OpenFront.Client', "ModuleScript", mod_name)
            target = f'game:GetService("StarterPlayer").StarterPlayerScripts.OpenFront.Client.{mod_name}'
            l = client.set_script_source(target, src)
            print(f"  [Client] {mod_name} synced: {l} bytes")

    fpath = "src/openfront/client/ClientMain.client.lua"
    if os.path.exists(fpath):
        with open(fpath, "r", encoding="utf-8") as f:
            src = f.read()
        client.ensure_instance('game:GetService("StarterPlayer").StarterPlayerScripts.OpenFront.Client', "LocalScript", "ClientMain")
        target = 'game:GetService("StarterPlayer").StarterPlayerScripts.OpenFront.Client.ClientMain'
        l = client.set_script_source(target, src)
        print(f"  [ClientScript] ClientMain synced: {l} bytes")

    print("\n>>> ALL OPENFRONT MODULES SYNCHRONIZED CLEANLY TO STUDIO! <<<")

def main():
    try:
        client = StudioClient()
        try:
            sync_openfront(client)
        finally:
            client.close()
    except Exception as e:
        print("Studio Sync Notice:", e)
        print("Note: When Roblox Studio is opened, run 'python tools/sync_all_to_studio.py' to push all files directly into the active Studio DataModel.")

if __name__ == "__main__":
    main()
