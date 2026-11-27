import json
import base64
import os

MAPS = [
    ("world", "MUNDO", "POPULAR", "70 Naciones Oficiales · Global FFA"),
    ("achiran", "ACHIRAN", "COMPETITIVO", "4 Naciones · Isla Estratégica"),
    ("europe", "EUROPA", "CLÁSICO", "52 Naciones · Alta Densidad"),
    ("asia", "ASIA", "BATALLA", "25 Naciones · Potencias Históricas"),
    ("africa", "ÁFRICA", "ESTRATÉGICO", "72 Naciones · Riqueza de Recursos"),
    ("pangaea", "PANGAEA", "GIGANTE", "29 Naciones · Supercontinente Primitivo"),
    ("mars", "MARTE", "ESPACIAL", "6 Bases Espaciales · Planeta Rojo"),
    ("oceania", "OCEANÍA", "ISLAS", "22 Naciones · Archipiélagos y Guerra Naval"),
    ("mena", "MEDIO ORIENTE", "TÁCTICO", "35 Naciones · Encrucijada Estratégica"),
    ("baikal", "BAIKAL", "NUCLEAR", "11 Regiones · Lago Sagrado"),
]

def snap_to_land(raw, w, h, x, y, max_r=30):
    b = raw[y * w + x]
    if (b & 0x80) != 0 and (b & 0x1f) != 31:
        return x, y
    for r in range(1, max_r + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if abs(dx) == r or abs(dy) == r:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        nb = raw[ny * w + nx]
                        if (nb & 0x80) != 0 and (nb & 0x1f) != 31:
                            return nx, ny
    return x, y

def convert_map(map_id, display_name, tag, subtitle):
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
        raw = f.read()

    # 1. 1-bit land mask (passable land only)
    num_bytes = (w * h + 7) // 8
    land_bits = bytearray(num_bytes)
    impassable_bits = bytearray(num_bytes)
    
    land_count = 0
    impassable_count = 0
    land_elev_nibbles = []

    for idx, b in enumerate(raw):
        is_land = (b & 0x80) != 0
        mag = b & 0x1f
        is_imp = is_land and (mag == 31)

        byte_idx = idx // 8
        bit_idx = idx % 8

        if is_imp:
            impassable_bits[byte_idx] |= (1 << bit_idx)
            impassable_count += 1
        elif is_land:
            land_bits[byte_idx] |= (1 << bit_idx)
            land_count += 1
            # Scale 0..30 to 0..14 (nibble)
            level = min(14, int(mag * 15 / 31))
            land_elev_nibbles.append(level)

    mask_b64 = base64.b64encode(land_bits).decode("ascii")
    
    # 2. Packed elevation nibbles for land cells (2 cells per byte)
    packed_elev = bytearray((len(land_elev_nibbles) + 1) // 2)
    for i, nib in enumerate(land_elev_nibbles):
        b_idx = i // 2
        if i % 2 == 0:
            packed_elev[b_idx] |= (nib & 0x0f)
        else:
            packed_elev[b_idx] |= ((nib & 0x0f) << 4)
    elev_b64 = base64.b64encode(packed_elev).decode("ascii")

    # 3. Impassable mask (only if impassable cells exist)
    imp_b64 = ""
    if impassable_count > 0:
        imp_b64 = base64.b64encode(impassable_bits).decode("ascii")

    # 4. Extract and snap nations
    nations_lua = []
    sx = w / full_w
    sy = h / full_h
    raw_nations = man.get("nations", [])
    for n in raw_nations:
        coords = n.get("coordinates", [0, 0])
        init_x = max(0, min(w - 1, int(round(coords[0] * sx))))
        init_y = max(0, min(h - 1, int(round(coords[1] * sy))))
        nx, ny = snap_to_land(raw, w, h, init_x, init_y, max_r=30)
        name = n.get("name", "Nación").replace('"', '\\"')
        flag = n.get("flag", "un").replace('"', '')
        nations_lua.append(f'\t\t{{ name = "{name}", x = {nx}, y = {ny}, flag = "{flag}" }},')

    nations_block = "\n".join(nations_lua)
    themes = man.get("themes", ["classic"])
    theme_str = themes[0] if themes else "classic"

    lua_code = f"""--!native
-- Official OpenFront.io Map: {display_name} ({map_id})
-- Dimensions: {w}x{h} ({w*h} cells), Passable Land: {land_count}, Impassable: {impassable_count}
return {{
\tid = "{map_id}",
\tname = "{display_name}",
\tw = {w},
\th = {h},
\ttag = "{tag}",
\tsubtitle = "{subtitle}",
\ttheme = "{theme_str}",
\tlandTiles = {land_count},
\timpassableTiles = {impassable_count},
\tmaskB64 = "{mask_b64}",
\televB64 = "{elev_b64}",
\timpB64 = "{imp_b64}",
\tnations = {{
{nations_block}
\t}}
}}
"""

    out_path = os.path.join("src", "shared", "frontwars_maps", f"{map_id}.lua")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(lua_code)

    print(f"Converted {map_id:10s} ({display_name}): {w}x{h}, land={land_count}, imp={impassable_count}, nations={len(raw_nations)} -> {out_path} ({len(lua_code)} bytes)")

def main():
    os.makedirs(os.path.join("src", "shared", "frontwars_maps"), exist_ok=True)
    for map_id, display_name, tag, subtitle in MAPS:
        convert_map(map_id, display_name, tag, subtitle)
    print("\nALL OFFICIAL OPENFRONT.IO MAPS CONVERTED WITH FULL DETAILS!")

if __name__ == "__main__":
    main()
