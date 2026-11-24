import json

def gen(name, target, path):
    src = open(path, "r", encoding="utf-8").read()
    code = f'{target}.Source = {json.dumps(src)}\nreturn "Updated {name}!"'
    with open(f"tools/sync_scripts/direct_{name}.luau", "w", encoding="utf-8") as f:
        f.write(code)
    print(f"direct_{name}.luau size: {len(code)}")

gen("server", 'game:GetService("ServerScriptService").Server.WorldServer', "src/server/WorldServer.server.lua")
gen("grid", 'game:GetService("ReplicatedStorage").Shared.WorldGrid', "src/shared/WorldGrid.lua")
gen("engine", 'game:GetService("ServerScriptService").Server.WorldEngine', "src/server/WorldEngine.lua")
gen("client", 'game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldClient', "src/client/WorldClient.client.lua")
gen("fwm", 'game:GetService("ReplicatedStorage").Shared.FrontWarsMaps', "src/shared/FrontWarsMaps.lua")

for m in ['world', 'pangaea', 'europe', 'asia', 'africa', 'mena', 'mars', 'oceania']:
    tpath = f'game:GetService("ReplicatedStorage").Shared.frontwars_maps.{m}'
    gen(f"map_{m}", tpath, f"src/shared/frontwars_maps/{m}.lua")

print("Generated all direct sync files!")
