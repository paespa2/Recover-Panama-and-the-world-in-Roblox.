import json, os

with open("src/shared/maps/frontwars_maps.json", "r", encoding="utf-8") as f:
    data = json.load(f)

os.makedirs("src/shared/frontwars_maps", exist_ok=True)

# Generate an index module
index_lines = [
    "--!native",
    "local FrontWarsMaps = {}",
    "FrontWarsMaps.LIST = {"
]

for map_id, info in data.items():
    if "w" not in info: continue
    w = info["w"]
    h = info["h"]
    b64 = info["b64"]
    nations = info.get("nations", [])
    title = map_id.upper()

    index_lines.append(f'\t{{ id = "{map_id}", name = "{title}", w = {w}, h = {h}, nationsCount = {len(nations)} }},')

    # Individual file for this map
    map_lines = [
        "--!native",
        f"return {{",
        f'\tid = "{map_id}",',
        f'\tname = "{title}",',
        f'\tw = {w},',
        f'\th = {h},',
        f'\tmaskB64 = "{b64}",',
        f'\tnations = {{'
    ]
    for n in nations:
        name_esc = n["name"].replace('"', '\\"')
        flag = n.get("flag", "")
        map_lines.append(f'\t\t{{ name = "{name_esc}", x = {n["x"]}, y = {n["y"]}, flag = "{flag}" }},')
    map_lines.append("\t},")
    map_lines.append("}")

    with open(f"src/shared/frontwars_maps/{map_id}.lua", "w", encoding="utf-8") as out:
        out.write("\n".join(map_lines))

index_lines.append("}")
index_lines.append("")
index_lines.append("function FrontWarsMaps.get(id)")
index_lines.append("\tlocal scriptParent = script")
index_lines.append("\tlocal child = scriptParent:FindFirstChild(id)")
index_lines.append("\tif child then return require(child) end")
index_lines.append("\treturn nil")
index_lines.append("end")
index_lines.append("")
index_lines.append("return FrontWarsMaps")

with open("src/shared/FrontWarsMaps.lua", "w", encoding="utf-8") as out:
    out.write("\n".join(index_lines))

print("Created modular frontwars_maps successfully!")
