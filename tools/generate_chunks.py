import json

def chunk_file(name, target_path, file_path, chunk_size=25000):
    with open(file_path, "r", encoding="utf-8") as f:
        src = f.read()
    
    chunks = [src[i:i+chunk_size] for i in range(0, len(src), chunk_size)]
    print(f"{name}: {len(src)} chars in {len(chunks)} chunks")
    
    for i, c in enumerate(chunks):
        var_name = f"_G._chunk_{name}"
        if i == 0:
            lua = f"{var_name} = {{ {json.dumps(c)} }}\nreturn true"
        elif i < len(chunks) - 1:
            lua = f"table.insert({var_name}, {json.dumps(c)})\nreturn true"
        else:
            lua = f'table.insert({var_name}, {json.dumps(c)})\nlocal full = table.concat({var_name}, "")\n{target_path}.Source = full\n{var_name} = nil\nprint("Successfully set source on {name}!")\nreturn "DONE"'
        
        with open(f"tools/sync_scripts/{name}_{i}.luau", "w", encoding="utf-8") as out:
            out.write(lua)

chunk_file("client", 'game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldClient', "src/client/WorldClient.client.lua")
chunk_file("grid", 'game:GetService("ReplicatedStorage").Shared.WorldGrid', "src/shared/WorldGrid.lua")
chunk_file("engine", 'game:GetService("ServerScriptService").Server.WorldEngine', "src/server/WorldEngine.lua")
chunk_file("server", 'game:GetService("ServerScriptService").Server.WorldServer', "src/server/WorldServer.server.lua")
chunk_file("fwm", 'game:GetService("ReplicatedStorage").Shared.FrontWarsMaps', "src/shared/FrontWarsMaps.lua")

for m in ['world', 'pangaea', 'europe', 'asia', 'africa', 'mena', 'mars', 'oceania']:
    tpath = f'game:GetService("ReplicatedStorage").Shared.frontwars_maps.{m}'
    chunk_file(f"map_{m}", tpath, f"src/shared/frontwars_maps/{m}.lua")

print("All chunks generated!")
