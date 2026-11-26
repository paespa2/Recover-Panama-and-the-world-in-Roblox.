import json
import base64
import os

MAPS = [
    ("world", "MUNDO"),
    ("achiran", "ACHIRAN"),
    ("europe", "EUROPA"),
    ("asia", "ASIA"),
    ("africa", "ÁFRICA"),
    ("pangaea", "PANGAEA"),
    ("mars", "MARTE"),
    ("oceania", "OCEANÍA"),
    ("mena", "MEDIO ORIENTE"),
    ("baikal", "BAIKAL"),
]

def convert_map(map_id, display_name):
    folder = os.path.join("openfront_src", "resources", "maps", map_id)
    man_path = os.path.join(folder, "manifest.json")
    if not os.path.exists(man_path):
        print(f"Skipping {map_id}: no manifest.json")
        return

    with open(man_path, "r", encoding="utf-8") as f:
        man = json.load(f)

    scale = "map16x" if "map16x" in man else "map4x"
    bin_path = os.path.join(folder, f"{scale}.bin")
    if not os.path.exists(bin_path):
        print(f"Skipping {map_id}: no {scale}.bin")
        return

    w = man[scale]["width"]
    h = man[scale]["height"]
    full_w = man["map"]["width"]
    full_h = man["map"]["height"]

    with open(bin_path, "rb") as f:
        data = f.read()

    # Pack bits
    num_bytes = (w * h + 7) // 8
    land_bits = bytearray(num_bytes)
    land_count = 0

    for idx, b in enumerate(data):
        # 0x80 is land, 0x1f == 31 is impassable
        if (b & 0x80) != 0 and (b & 0x1f) != 31:
            byte_idx = idx // 8
            bit_idx = idx % 8
            land_bits[byte_idx] |= (1 << bit_idx)
            land_count += 1

    b64 = base64.b64encode(land_bits).decode("ascii")

    # Extract nations
    nations_lua = []
    sx = w / full_w
    sy = h / full_h
    raw_nations = man.get("nations", [])
    for n in raw_nations:
        coords = n.get("coordinates", [0, 0])
        nx = max(0, min(w - 1, int(round(coords[0] * sx))))
        ny = max(0, min(h - 1, int(round(coords[1] * sy))))
        name = n.get("name", "Nación")
        flag = n.get("flag", "un")
        nations_lua.append(f'\t\t{{ name = "{name}", x = {nx}, y = {ny}, flag = "{flag}" }},')

    nations_block = "\n".join(nations_lua)

    lua_code = f"""--!native
-- Official OpenFront.io pixel map: {display_name} ({map_id})
-- Dimensions: {w}x{h} ({w*h} pixels, {land_count} land tiles)
return {{
\tid = "{map_id}",
\tname = "{display_name}",
\tw = {w},
\th = {h},
\tlandTiles = {land_count},
\tmaskB64 = "{b64}",
\tnations = {{
{nations_block}
\t}}
}}
"""

    out_path = os.path.join("src", "shared", "frontwars_maps", f"{map_id}.lua")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(lua_code)

    print(f"Converted {map_id} ({display_name}): {w}x{h}, {land_count} land tiles -> {out_path} ({len(lua_code)} bytes)")

def main():
    os.makedirs(os.path.join("src", "shared", "frontwars_maps"), exist_ok=True)
    for map_id, display_name in MAPS:
        convert_map(map_id, display_name)
    print("\nALL OFFICIAL OPENFRONT.IO PIXEL MAPS CONVERTED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
