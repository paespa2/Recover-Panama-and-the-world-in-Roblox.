#!/usr/bin/env python3
"""
fetch_satellite.py
Descarga una imagen satelital REAL de la Tierra (NASA GIBS, gratuita y sin clave), la reduce a la
cuadricula del juego (960x400, latitudes 84N .. 60S) y genera src/shared/TerrainData.lua.

Uso normal (foto de ayer, MODIS Terra en color real):
    python tools/fetch_satellite.py

Opciones utiles:
    --date 2026-11-20          fecha concreta (por defecto: ayer, UTC)
    --layer NOMBRE             capa GIBS principal (por defecto MODIS_Terra_CorrectedReflectance_TrueColor)
    --backup NOMBRE            capa de relleno para huecos sin datos (por defecto BlueMarble_ShadedRelief_Bathymetry)
    --scale 2                  supermuestreo: descarga W*scale x H*scale y promedia (mas nitido, mas lento)
    --out-dir RUTA             carpeta de salida (por defecto src/shared)
    --demo                     NO usa red: genera un degradado sintetico para probar el pipeline

Salida:
    TerrainData.lua            paleta de 256 colores + indices base64 (~0.5 MB), lo lee WorldGrid.BuildBase
    satellite_preview.png      vista previa 960x400 (para mirarla en el explorador de archivos)

Solo necesita Python 3 y numpy (decodifica PNG con zlib, no requiere Pillow).
"""

import argparse
import base64
import datetime
import os
import struct
import sys
import time
import urllib.parse
import urllib.request
import zlib

import numpy as np

W, H = 960, 400
LAT_TOP, LAT_BOT = 84.0, -60.0
WMS_URL = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
DEFAULT_LAYER = "MODIS_Terra_CorrectedReflectance_TrueColor"
DEFAULT_BACKUP = "BlueMarble_ShadedRelief_Bathymetry"
NODATA_SUM = 24  # suma R+G+B por debajo de la cual el pixel se considera "sin datos"


# ---------------------------------------------------------------------------
# PNG: decodificador minimo (8 bits, sin entrelazado) y codificador
# ---------------------------------------------------------------------------
def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode_png(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("no es un PNG")
    pos = 8
    idat = []
    palette = None
    width = height = depth = ctype = interlace = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = np.frombuffer(body, dtype=np.uint8).reshape(-1, 3)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    if depth != 8 or interlace != 0 or ctype not in (0, 2, 3, 6):
        raise ValueError(f"PNG no soportado (depth={depth}, color={ctype}, interlace={interlace})")

    channels = {0: 1, 2: 3, 3: 1, 6: 4}[ctype]
    stride = width * channels
    raw = zlib.decompress(b"".join(idat))
    out = np.zeros((height, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.uint8)
    p = 0
    for y in range(height):
        ft = raw[p]
        line = np.frombuffer(raw, dtype=np.uint8, count=stride, offset=p + 1).copy()
        p += 1 + stride
        if ft == 1:  # Sub
            line = (np.cumsum(line.reshape(-1, channels).astype(np.uint32), axis=0) & 255).astype(np.uint8).reshape(-1)
        elif ft == 2:  # Up
            line = ((line.astype(np.uint16) + prev) & 255).astype(np.uint8)
        elif ft == 3:  # Average
            buf = bytearray(line.tobytes())
            pv = prev.tobytes()
            for i in range(stride):
                left = buf[i - channels] if i >= channels else 0
                buf[i] = (buf[i] + ((left + pv[i]) >> 1)) & 255
            line = np.frombuffer(bytes(buf), dtype=np.uint8)
        elif ft == 4:  # Paeth
            buf = bytearray(line.tobytes())
            pv = prev.tobytes()
            for i in range(stride):
                a = buf[i - channels] if i >= channels else 0
                c = pv[i - channels] if i >= channels else 0
                buf[i] = (buf[i] + _paeth(a, pv[i], c)) & 255
            line = np.frombuffer(bytes(buf), dtype=np.uint8)
        elif ft != 0:
            raise ValueError(f"filtro PNG desconocido: {ft}")
        out[y] = line
        prev = line

    img = out.reshape(height, width, channels)
    if ctype == 0:
        img = np.repeat(img, 3, axis=2)
    elif ctype == 3:
        img = palette[img[:, :, 0]]
    elif ctype == 6:
        img = img[:, :, :3]
    return img


def encode_png(img):
    """Codifica RGB (h,w,3) o RGBA (h,w,4) a PNG de 8 bits."""
    h, w, channels = img.shape
    color_type = 6 if channels == 4 else 2
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(kind, body):
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


# ---------------------------------------------------------------------------
# NASA GIBS
# ---------------------------------------------------------------------------
def fetch_layer(layer, date, scale):
    params = {
        "SERVICE": "WMS",
        "REQUEST": "GetMap",
        "VERSION": "1.3.0",
        "LAYERS": layer,
        "STYLES": "",
        "CRS": "EPSG:4326",
        # WMS 1.3.0 con EPSG:4326 usa el orden lat,lon: minLat,minLon,maxLat,maxLon
        "BBOX": f"{LAT_BOT},-180,{LAT_TOP},180",
        "WIDTH": str(W * scale),
        "HEIGHT": str(H * scale),
        "FORMAT": "image/png",
    }
    if date:
        params["TIME"] = date
    url = WMS_URL + "?" + urllib.parse.urlencode(params)
    # Las capas estaticas (sin fecha) se guardan en cache: se descargan una sola vez
    cache_path = None
    if not date:
        cache_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
        cache_path = os.path.join(cache_dir, f"{layer}_{W * scale}x{H * scale}.png")
        if os.path.exists(cache_path):
            print(f"  cache {layer} ({W * scale}x{H * scale})")
            with open(cache_path, "rb") as f:
                return decode_png(f.read())
    print(f"  GET {layer} ({W * scale}x{H * scale}, fecha={date or 'estatica'})")
    req = urllib.request.Request(url, headers={"User-Agent": "recover-panama-tools/1.0"})
    data = b""
    for attempt in range(1, 5):  # GIBS a veces devuelve errores transitorios de MapServer
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = resp.read()
        except Exception as exc:
            data = str(exc).encode()
        if data[:4] == b"\x89PNG":
            break
        print(f"  intento {attempt}/4 fallido, reintentando...")
        time.sleep(3 * attempt)
    if data[:4] != b"\x89PNG":
        raise RuntimeError("GIBS no devolvio una imagen: " + data[:300].decode("utf-8", "replace"))
    print(f"  recibido {len(data) / 1024:.0f} KB, decodificando...")
    img = decode_png(data)
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "wb") as f:
            f.write(data)
    return img


def downsample(img, scale):
    if scale == 1:
        return img
    h, w, c = img.shape
    return img.reshape(h // scale, scale, w // scale, scale, c).mean(axis=(1, 3))


def demo_image():
    """Degradado sintetico (sin red) para probar el pipeline."""
    y, x = np.mgrid[0:H, 0:W]
    r = 40 + 120 * (x / W)
    g = 60 + 140 * (y / H)
    b = 90 + 100 * np.sin(x / 55.0) ** 2
    return np.stack([r, g, b], axis=2)


# ---------------------------------------------------------------------------
# Cuantizacion a paleta de 256 colores (median cut)
# ---------------------------------------------------------------------------
def median_cut(pixels, n_colors=256):
    boxes = [np.arange(len(pixels))]
    while len(boxes) < n_colors:
        best, best_score = -1, -1
        for i, idx in enumerate(boxes):
            if len(idx) < 2:
                continue
            sub = pixels[idx]
            rng = sub.max(axis=0).astype(np.int32) - sub.min(axis=0).astype(np.int32)
            score = rng.max() * np.log2(len(idx) + 1)
            if score > best_score:
                best, best_score = i, score
        if best < 0:
            break
        idx = boxes.pop(best)
        sub = pixels[idx]
        channel = int(np.argmax(sub.max(axis=0).astype(np.int32) - sub.min(axis=0).astype(np.int32)))
        order = np.argsort(sub[:, channel], kind="stable")
        idx = idx[order]
        mid = len(idx) // 2
        boxes.append(idx[:mid])
        boxes.append(idx[mid:])
    palette = np.zeros((256, 3), dtype=np.uint8)
    labels = np.zeros(len(pixels), dtype=np.uint8)
    for i, idx in enumerate(boxes):
        palette[i] = np.round(pixels[idx].mean(axis=0)).astype(np.uint8)
        labels[idx] = i
    return palette, labels


# ---------------------------------------------------------------------------
# Salida: TerrainData.lua
# ---------------------------------------------------------------------------
LUA_TEMPLATE = '''--!nonstrict
-- TerrainData.lua  (GENERADO por tools/fetch_satellite.py, no editar a mano)
-- Imagen satelital real de la Tierra: {source}
-- Fecha: {date} | Cuadricula {w}x{h} | Latitudes {lat_top}N a {lat_bot}S | Paleta de 256 colores.
local TerrainData = {{}}

TerrainData.W = {w}
TerrainData.H = {h}
TerrainData.SOURCE = "{source}"
TerrainData.DATE = "{date}"

local PALETTE = "{palette}"

local INDICES = {{
{chunks}}}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP = {{}}
for i = 1, #B64 do
	LOOKUP[string.byte(B64, i)] = i - 1
end

-- Decodifica base64 escribiendo bytes en un buffer (no depende de buffer.frombase64)
local function decodeInto(str, out, outOffset)
	local pos = outOffset
	local n = #str
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(str, i, i + 3)
		local v = (LOOKUP[a] or 0) * 262144 + (LOOKUP[b] or 0) * 4096 + (LOOKUP[c] or 0) * 64 + (LOOKUP[d] or 0)
		if c == 61 then -- "=="
			buffer.writeu8(out, pos, v // 65536)
			pos += 1
		elseif d == 61 then -- "="
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

-- Devuelve un buffer RGB de W*H*3 bytes (fila a fila, de arriba a abajo)
function TerrainData.GetBuffer()
	if cached then
		return cached
	end
	local pal = buffer.create(768)
	decodeInto(PALETTE, pal, 0)

	local idx = buffer.create({w} * {h})
	local pos = 0
	for _, part in ipairs(INDICES) do
		pos = decodeInto(part, idx, pos)
	end

	local rgb = buffer.create({w} * {h} * 3)
	for i = 0, {w} * {h} - 1 do
		local p = buffer.readu8(idx, i) * 3
		local o = i * 3
		buffer.writeu8(rgb, o, buffer.readu8(pal, p))
		buffer.writeu8(rgb, o + 1, buffer.readu8(pal, p + 1))
		buffer.writeu8(rgb, o + 2, buffer.readu8(pal, p + 2))
	end
	cached = rgb
	return rgb
end

return TerrainData
'''


def write_outputs(img_u8, out_dir, source, date):
    os.makedirs(out_dir, exist_ok=True)
    flat = img_u8.reshape(-1, 3)
    print("Cuantizando a 256 colores...")
    palette, labels = median_cut(flat, 256)

    # Vista previa con la paleta (lo que realmente vera el juego)
    preview = palette[labels].reshape(H, W, 3)
    with open(os.path.join(out_dir, "satellite_preview.png"), "wb") as f:
        f.write(encode_png(preview))

    pal_b64 = base64.b64encode(palette.tobytes()).decode("ascii")
    idx_b64 = base64.b64encode(labels.tobytes()).decode("ascii")
    # Trozos multiplos de 4 caracteres para que cada uno se decodifique de forma independiente
    size = 20000
    chunks = "".join(f'\t"{idx_b64[i:i + size]}",\n' for i in range(0, len(idx_b64), size))

    lua = LUA_TEMPLATE.format(
        source=source,
        date=date,
        w=W,
        h=H,
        lat_top=int(LAT_TOP),
        lat_bot=abs(int(LAT_BOT)),
        palette=pal_b64,
        chunks=chunks,
    )
    path = os.path.join(out_dir, "TerrainData.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua)
    print(f"OK -> {path} ({os.path.getsize(path) / 1024:.0f} KB)")
    print(f"OK -> {os.path.join(out_dir, 'satellite_preview.png')}")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", help="AAAA-MM-DD de la capa diaria (por defecto: ayer UTC)")
    ap.add_argument("--layer", default=DEFAULT_LAYER, help="capa diaria 'en vivo' (MODIS color real)")
    ap.add_argument("--base", default=DEFAULT_BACKUP, help="capa base sin nubes (Blue Marble)")
    ap.add_argument(
        "--live",
        type=float,
        default=0.0,
        help="0..1: peso de la foto diaria sobre la base. 0 = solo base limpia (recomendado para jugar); "
        "0.3 = un toque de nubes y estaciones reales; 1 = foto diaria pura (tapa la tierra con nubes)",
    )
    ap.add_argument("--scale", type=int, default=2, choices=[1, 2, 3, 4])
    ap.add_argument("--out-dir", default=os.path.join(here, "..", "src", "shared"))
    ap.add_argument("--demo", action="store_true", help="sin red: imagen sintetica de prueba")
    args = ap.parse_args()

    if args.demo:
        print("Modo demo (sin red).")
        img = demo_image()
        source, date = "DEMO sintetica", "n/a"
    else:
        yesterday = datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=1)
        live = min(1.0, max(0.0, args.live))
        date = args.date or yesterday.isoformat()
        print("Descargando imagen satelital NASA GIBS...")
        base = fetch_layer(args.base, None, args.scale).astype(np.float32)
        source = f"NASA GIBS {args.base}"
        if live > 0:
            daily = fetch_layer(args.layer, date, args.scale).astype(np.float32)
            valid = (daily.sum(axis=2) >= NODATA_SUM)[:, :, None]
            weight = np.where(valid, live, 0.0)
            base = base * (1 - weight) + daily * weight
            source += f" + {args.layer} ({int(live * 100)}%)"
            print(f"  mezcla con la foto diaria de {date}: {live:.0%} (solo donde hay datos)")
        else:
            date = "estatica (sin nubes)"
        img = downsample(base, args.scale)

    img_u8 = np.clip(np.round(img), 0, 255).astype(np.uint8)
    assert img_u8.shape == (H, W, 3), img_u8.shape
    write_outputs(img_u8, args.out_dir, source, date)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
