#!/usr/bin/env python3
"""
build_countries.py
Convierte las fronteras reales de Natural Earth (dominio publico) en un mapa de paises por celda
para la cuadricula del juego (960x400, latitudes 84N .. 60S) y genera src/shared/CountryData.lua.

Que produce CountryData.lua:
  CountryData.countries   lista { id, name (es), iso, continent (1..7), pop, cells }
  CountryData.continents  nombres de continentes en espanol
  CountryData.GetBuffer() buffer de W*H bytes: id de pais por celda (0 = mar)

Los modos de juego "Paises vs Paises" y "Continentes" usan estos datos; las fronteras visibles se
dibujan comparando el id de celdas vecinas.

Uso:
    python tools/build_countries.py
    python tools/build_countries.py --out-dir RUTA   (para probar sin tocar el proyecto)
Datos: https://github.com/nvkelso/natural-earth-vector (ne_50m_admin_0_countries, dominio publico)
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.request

import numpy as np

import fetch_satellite as fs

W, H = fs.W, fs.H
LAT_TOP, LAT_BOT = fs.LAT_TOP, fs.LAT_BOT
GEOJSON_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"

CONTINENTS = ["África", "Antártida", "Asia", "Europa", "Norteamérica", "Oceanía", "Sudamérica"]
CONTINENT_INDEX = {
    "Africa": 1,
    "Antarctica": 2,
    "Asia": 3,
    "Europe": 4,
    "North America": 5,
    "Oceania": 6,
    "South America": 7,
}


def download(path):
    if os.path.exists(path):
        print(f"  cache {os.path.basename(path)} ({os.path.getsize(path) / 1024:.0f} KB)")
        return
    print(f"  GET {GEOJSON_URL}")
    req = urllib.request.Request(GEOJSON_URL, headers={"User-Agent": "recover-panama-tools/1.0"})
    data = b""
    for attempt in range(1, 5):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            if data[:1] == b"{":
                break
        except Exception as exc:
            print(f"  intento {attempt}/4 fallido: {exc}")
        time.sleep(3 * attempt)
    if data[:1] != b"{":
        raise RuntimeError("no se pudo descargar el GeoJSON de Natural Earth")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print(f"  recibido {len(data) / 1024:.0f} KB")


def to_grid(ring):
    pts = np.asarray(ring, dtype=np.float64)[:, :2]
    gx = (pts[:, 0] + 180.0) / 360.0 * W
    gy = (LAT_TOP - pts[:, 1]) / (LAT_TOP - LAT_BOT) * H
    return gx, gy


def fill_polygon(mask, rings):
    """Relleno par-impar por filas: el anillo exterior y los huecos juntos."""
    x1s, y1s, x2s, y2s = [], [], [], []
    for ring in rings:
        if len(ring) < 3:
            continue
        gx, gy = to_grid(ring)
        x1s.append(gx[:-1])
        y1s.append(gy[:-1])
        x2s.append(gx[1:])
        y2s.append(gy[1:])
    if not x1s:
        return
    x1, y1, x2, y2 = (np.concatenate(a) for a in (x1s, y1s, x2s, y2s))
    row_lo = max(0, int(np.floor(min(y1.min(), y2.min()))))
    row_hi = min(H - 1, int(np.ceil(max(y1.max(), y2.max()))))
    for row in range(row_lo, row_hi + 1):
        yc = row + 0.5
        cross = ((y1 <= yc) & (y2 > yc)) | ((y2 <= yc) & (y1 > yc))
        if not cross.any():
            continue
        xs = x1[cross] + (yc - y1[cross]) * (x2[cross] - x1[cross]) / (y2[cross] - y1[cross])
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            a = int(np.ceil(xs[i] - 0.5))
            b = int(np.floor(xs[i + 1] - 0.5))
            if b >= a:
                a, b = max(a, 0), min(b, W - 1)
                if b >= a:
                    mask[row, a : b + 1] = True


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


LUA_TEMPLATE = '''--!nonstrict
-- CountryData.lua  (GENERADO por tools/build_countries.py, no editar a mano)
-- Paises por celda sobre la cuadricula {w}x{h} (latitudes {lat_top}N a {lat_bot}S).
-- Fuente: Natural Earth (dominio publico), ne_50m_admin_0_countries.
local CountryData = {{}}

CountryData.W = {w}
CountryData.H = {h}
CountryData.continents = {{ {continents} }}

-- {{ id, nombre, iso3, continente(1..7), poblacion, celdas }}
CountryData.countries = {{
{rows}}}

local INDICES = {{
{chunks}}}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP = {{}}
for i = 1, #B64 do
	LOOKUP[string.byte(B64, i)] = i - 1
end

local function decodeInto(str, out, outOffset)
	local pos = outOffset
	for i = 1, #str, 4 do
		local a, b, c, d = string.byte(str, i, i + 3)
		local v = (LOOKUP[a] or 0) * 262144 + (LOOKUP[b] or 0) * 4096 + (LOOKUP[c] or 0) * 64 + (LOOKUP[d] or 0)
		if c == 61 then
			buffer.writeu8(out, pos, v // 65536)
			pos += 1
		elseif d == 61 then
			buffer.writeu8(out, pos, v // 65536)
			buffer.writeu8(out, pos + 1, (v // 256) % 256)
			pos += 2
		else
			buffer.writeu8(out, pos, v // 65536)
			buffer.writeu8(out, pos + 1, (v // 256) % 256)
			buffer.writeu8(out, pos + 2, v % 256)
			pos += 3
		end
	end
	return pos
end

local cached = nil

-- Buffer de {w}*{h} bytes: id de pais por celda (0 = mar / sin pais)
function CountryData.GetBuffer()
	if cached then
		return cached
	end
	local buf = buffer.create({w} * {h})
	local pos = 0
	for _, part in ipairs(INDICES) do
		pos = decodeInto(part, buf, pos)
	end
	cached = buf
	return buf
end

return CountryData
'''


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out-dir", default=os.path.join(here, "..", "src", "shared"))
    ap.add_argument("--mask", default=os.path.join(here, "land_mask_960x400.bin"))
    ap.add_argument(
        "--borders",
        action="store_true",
        help="exporta una capa PNG transparente con las fronteras entre paises (2x2 px por celda) en "
        "tools/previews/border_tile_N.png, partida en teselas de 960 px de ancho",
    )
    args = ap.parse_args()

    cache = os.path.join(here, ".cache", "ne_50m_admin_0_countries.geojson")
    print("Fronteras de Natural Earth...")
    download(cache)
    with open(cache, encoding="utf-8") as f:
        feats = json.load(f)["features"]
    print(f"  {len(feats)} entidades")

    land = np.fromfile(args.mask, dtype=np.uint8).reshape(H, W) == 1

    # Rasterizar: las entidades mas grandes primero, las pequenas despues (ganan en solapes)
    def area_key(ft):
        p = ft["properties"]
        return -float(p.get("POP_EST") or 0)

    ordered = sorted(feats, key=area_key)
    raster = np.zeros((H, W), dtype=np.int32)  # indice de entidad + 1
    for k, ft in enumerate(ordered, start=1):
        geom = ft.get("geometry")
        if not geom:
            continue
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        mask = np.zeros((H, W), dtype=bool)
        for rings in polys:
            fill_polygon(mask, rings)
        raster[mask] = k

    # Solo tierra del motor; las celdas de tierra sin pais toman el vecino mas cercano
    raster[~land] = 0
    for _ in range(8):
        missing = land & (raster == 0)
        if not missing.any():
            break
        cand = np.zeros_like(raster)
        for shift, axis in ((1, 1), (-1, 1), (1, 0), (-1, 0)):
            sh = np.roll(raster, shift, axis=axis)
            if axis == 0:  # sin envoltura vertical
                if shift == 1:
                    sh[0, :] = 0
                else:
                    sh[-1, :] = 0
            cand = np.where(cand == 0, sh, cand)
        raster = np.where(missing & (cand != 0), cand, raster)

    # Asignar ids finales (1..255) solo a entidades con celdas
    counts = np.bincount(raster.ravel(), minlength=len(ordered) + 1)
    final_id = {}
    countries = []
    for k, ft in enumerate(ordered, start=1):
        if counts[k] == 0:
            continue
        if len(countries) >= 255:
            break
        p = ft["properties"]
        name = p.get("NAME_ES") or p.get("NAME") or p.get("ADMIN") or "?"
        iso = p.get("ISO_A3_EH") or p.get("ISO_A3") or p.get("ADM0_A3") or "???"
        cont = CONTINENT_INDEX.get(p.get("CONTINENT"), 6)
        cid = len(countries) + 1
        final_id[k] = cid
        countries.append((cid, name, iso, cont, int(p.get("POP_EST") or 0), int(counts[k])))

    lut = np.zeros(len(ordered) + 1, dtype=np.uint8)
    for k, cid in final_id.items():
        lut[k] = cid
    ids = lut[raster]
    dropped = len(feats) - len(countries)
    print(f"  paises con celdas: {len(countries)} (sin celdas por ser diminutos: {dropped})")

    os.makedirs(args.out_dir, exist_ok=True)

    # Vista previa por colores
    rng = np.random.default_rng(7)
    palette = rng.integers(60, 235, size=(256, 3), dtype=np.uint8)
    palette[0] = (40, 90, 140)
    preview = palette[ids]
    # fronteras: celdas cuyo vecino (der./abajo) es otro pais
    edge = np.zeros((H, W), dtype=bool)
    edge[:, :-1] |= (ids[:, :-1] != ids[:, 1:]) & (ids[:, :-1] > 0) & (ids[:, 1:] > 0)
    edge[:-1, :] |= (ids[:-1, :] != ids[1:, :]) & (ids[:-1, :] > 0) & (ids[1:, :] > 0)
    preview[edge] = (30, 30, 30)
    preview_dir = os.path.join(here, "previews")  # fuera de src/ para que Rojo no lo sincronice
    os.makedirs(preview_dir, exist_ok=True)
    preview_path = os.path.join(preview_dir, "countries_preview.png")
    with open(preview_path, "wb") as f:
        f.write(fs.encode_png(preview))

    idx_b64 = base64.b64encode(ids.astype(np.uint8).tobytes()).decode("ascii")
    size = 20000
    chunks = "".join(f'\t"{idx_b64[i:i + size]}",\n' for i in range(0, len(idx_b64), size))
    rows = "".join(
        f"\t{{ {cid}, {lua_str(name)}, {lua_str(iso)}, {cont}, {pop}, {cells} }},\n"
        for cid, name, iso, cont, pop, cells in countries
    )
    lua = LUA_TEMPLATE.format(
        w=W,
        h=H,
        lat_top=int(LAT_TOP),
        lat_bot=abs(int(LAT_BOT)),
        continents=", ".join(lua_str(c) for c in CONTINENTS),
        rows=rows,
        chunks=chunks,
    )
    path = os.path.join(args.out_dir, "CountryData.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua)
    print(f"OK -> {path} ({os.path.getsize(path) / 1024:.0f} KB)")
    print(f"OK -> {preview_path}")

    if args.borders:
        s = 2  # pixeles por celda: igual que las teselas del mapa (1920x800)
        hi_ids = np.kron(ids.astype(np.uint8), np.ones((s, s), dtype=np.uint8))
        edge = np.zeros(hi_ids.shape, dtype=bool)
        dx = (hi_ids[:, :-1] != hi_ids[:, 1:]) & (hi_ids[:, :-1] > 0) & (hi_ids[:, 1:] > 0)
        dy = (hi_ids[:-1, :] != hi_ids[1:, :]) & (hi_ids[:-1, :] > 0) & (hi_ids[1:, :] > 0)
        edge[:, :-1] |= dx
        edge[:, 1:] |= dx
        edge[:-1, :] |= dy
        edge[1:, :] |= dy
        rgba = np.zeros(hi_ids.shape + (4,), dtype=np.uint8)
        rgba[edge] = (22, 24, 34, 215)
        for t in range((W * s) // 960):
            tile = np.ascontiguousarray(rgba[:, t * 960 : (t + 1) * 960])
            path = os.path.join(preview_dir, f"border_tile_{t}.png")
            with open(path, "wb") as f:
                f.write(fs.encode_png(tile))
            print(f"OK -> {path} ({tile.shape[1]}x{tile.shape[0]}, {os.path.getsize(path) / 1024:.0f} KB)")

    by_cells = sorted(countries, key=lambda c: c[5])
    print("Mas pequenos:", ", ".join(f"{c[1]}({c[5]})" for c in by_cells[:8]))
    print("Mas grandes:", ", ".join(f"{c[1]}({c[5]})" for c in by_cells[-6:]))
    for c in countries:
        if c[2] in ("PAN", "COL", "CRI"):
            print(f"  {c[1]} [{c[2]}]: {c[5]} celdas")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
