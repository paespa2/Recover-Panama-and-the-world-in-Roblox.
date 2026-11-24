import json, os

os.makedirs("tools/sync_scripts", exist_ok=True)

def make_sync(path_code, file_path, out_file):
    with open(file_path, "r", encoding="utf-8") as f:
        src = f.read()
    code = f"""
local target = {path_code}
if target then
    target.Source = {json.dumps(src)}
    print("Updated " .. target.Name)
else
    warn("Target not found")
end
return true
"""
    with open(f"tools/sync_scripts/{out_file}", "w", encoding="utf-8") as out:
        out.write(code)

make_sync('game:GetService("ServerScriptService").Server.WorldEngine', 'src/server/WorldEngine.lua', 'sync_engine.luau')
make_sync('game:GetService("ServerScriptService").Server.WorldServer', 'src/server/WorldServer.server.lua', 'sync_server.luau')
make_sync('game:GetService("ReplicatedStorage").Shared.WorldGrid', 'src/shared/WorldGrid.lua', 'sync_grid.luau')
make_sync('game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldClient', 'src/client/WorldClient.client.lua', 'sync_client.luau')

# Create maps folder and sync scripts for maps
maps_code = """
local shared = game:GetService("ReplicatedStorage").Shared
local fwm = shared:FindFirstChild("FrontWarsMaps")
if not fwm then
    fwm = Instance.new("ModuleScript")
    fwm.Name = "FrontWarsMaps"
    fwm.Parent = shared
end
local folder = shared:FindFirstChild("frontwars_maps")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "frontwars_maps"
    folder.Parent = shared
end
return true
"""
with open("tools/sync_scripts/sync_folders.luau", "w", encoding="utf-8") as out:
    out.write(maps_code)

make_sync('game:GetService("ReplicatedStorage").Shared.FrontWarsMaps', 'src/shared/FrontWarsMaps.lua', 'sync_fwm.luau')

for m in ['world', 'pangaea', 'europe', 'asia', 'africa', 'mena', 'mars', 'oceania']:
    map_code = f'''
local folder = game:GetService("ReplicatedStorage").Shared.frontwars_maps
local m = folder:FindFirstChild("{m}")
if not m then
    m = Instance.new("ModuleScript")
    m.Name = "{m}"
    m.Parent = folder
end
return m
'''
    make_sync(f'({map_code.strip()})', f'src/shared/frontwars_maps/{m}.lua', f'sync_map_{m}.luau')

print("All sync scripts generated successfully!")
