import base64
import os

bin_path = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "terrain_960x400.bin")
lua_path = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "TerrainData.lua")

with open(bin_path, "rb") as f:
    raw = f.read()

b64 = base64.b64encode(raw).decode("ascii")

chunk_size = 20000
chunks = [b64[i:i+chunk_size] for i in range(0, len(b64), chunk_size)]

with open(lua_path, "w", encoding="utf-8") as f:
    f.write("--!nonstrict\n")
    f.write("-- TerrainData.lua\n")
    f.write("-- Textura base de relieve 3D precomputada cientificamente (960x400 RGB = 1.15MB).\n")
    f.write("local TerrainData = {}\n\n")
    f.write("local parts = {\n")
    for c in chunks:
        f.write(f'    "{c}",\n')
    f.write("}\n\n")
    f.write("local cached = nil\n")
    f.write("function TerrainData.GetBuffer()\n")
    f.write("    if cached then return cached end\n")
    f.write("    local fullStr = table.concat(parts)\n")
    f.write("    cached = buffer.frombase64(fullStr)\n")
    f.write("    return cached\n")
    f.write("end\n\n")
    f.write("return TerrainData\n")

print(f"TerrainData.lua created successfully: {len(chunks)} chunks, total length {len(b64)} chars")
