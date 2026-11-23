#!/usr/bin/env python3
"""
generate_relief_style.py
Mapamundi 960x400 en estilo "relieve de estrategia": tierras bajas verdes, tierras secas beige, nieve y
picos blancos, sombreado de montanas y oceano azul plano con plataforma continental mas clara.
Genera src/shared/TerrainData.lua (misma salida que fetch_satellite.py, asi el juego no cambia).

Fuentes (NASA GIBS, gratuitas, sin clave):
  - BlueMarble_ShadedRelief_Bathymetry : color/vegetacion de la tierra (sin nubes)
  - ASTER_GDEM_Greyscale_Shaded_Relief : sombreado de montanas (opcional; si falla se usa la luminancia)
La mascara de tierra del motor (tools/land_mask_960x400.bin) decide que celda es tierra o mar.

Uso:
    python tools/generate_relief_style.py
    python tools/generate_relief_style.py --out-dir RUTA     (para probar sin tocar el proyecto)
    python tools/generate_relief_style.py --relief 1.2       (mas contraste de relieve)
"""

import argparse
import os
import sys

import numpy as np

import fetch_satellite as fs

W, H = fs.W, fs.H
BLUE_MARBLE = "BlueMarble_ShadedRelief_Bathymetry"
ASTER = "ASTER_GDEM_Greyscale_Shaded_Relief"

# Paleta (RGB)
FOREST = np.array([86, 148, 78], dtype=np.float32)
GREEN = np.array([148, 196, 104], dtype=np.float32)
TAN = np.array([228, 210, 158], dtype=np.float32)
DRY = np.array([214, 184, 128], dtype=np.float32)
ROCK = np.array([156, 146, 134], dtype=np.float32)
SNOW = np.array([246, 247, 250], dtype=np.float32)
OCEAN_DEEP = np.array([58, 118, 168], dtype=np.float32)
OCEAN_SHALLOW = np.array([104, 172, 212], dtype=np.float32)


def box_blur(a, radius):
    """Desenfoque de caja separable (con envoltura horizontal, como el mapa)."""
    k = 2 * radius + 1
    out = a.astype(np.float32)
    # horizontal con envoltura
    padded = np.concatenate([out[:, -radius:], out, out[:, :radius]], axis=1)
    c = np.cumsum(padded, axis=1, dtype=np.float64)
    c = np.concatenate([np.zeros((out.shape[0], 1)), c], axis=1)
    out = ((c[:, k:] - c[:, :-k]) / k).astype(np.float32)
    # vertical (bordes replicados)
    padded = np.concatenate([np.repeat(out[:1], radius, 0), out, np.repeat(out[-1:], radius, 0)], axis=0)
    c = np.cumsum(padded, axis=0, dtype=np.float64)
    c = np.concatenate([np.zeros((1, out.shape[1])), c], axis=0)
    return ((c[k:] - c[:-k]) / k).astype(np.float32)


def luminance(img):
    return img[:, :, 0] * 0.299 + img[:, :, 1] * 0.587 + img[:, :, 2] * 0.114


def build(base, shade_gray, land, relief, k=1):
    """k = factor de escala respecto a 960x400 (los radios de los filtros se multiplican por k)."""
    r, g, b = base[:, :, 0], base[:, :, 1], base[:, :, 2]
    lum = luminance(base)
    mx, mn = base.max(axis=2), base.min(axis=2)

    # --- Relieve: contraste local del sombreado (ASTER es muy suave a esta escala) -------------
    s = shade_gray.astype(np.float32)
    detail = s - box_blur(s, 6 * k)
    d_std = float(detail[land].std()) if land.any() else 1.0
    d_std = max(d_std, 1e-3)
    detail_n = detail / d_std  # ~N(0,1) en tierra
    rough = box_blur(np.abs(detail_n), 3 * k)  # rugosidad: alta en cordilleras
    rough_n = np.clip((rough - 0.9) / 1.1, 0.0, 1.0)[:, :, None]

    # --- Color de tierra ----------------------------------------------------
    # vegetacion: el verde domina sobre el rojo; zonas secas: rojo >= verde
    green_t = np.clip((g - r + 4.0) / 26.0, 0.0, 1.0)
    forest_t = np.clip((105.0 - lum) / 45.0, 0.0, 1.0) * green_t
    dry_t = np.clip((r - b - 50.0) / 80.0, 0.0, 1.0)
    green3 = green_t[:, :, None]
    land_col = TAN + (GREEN - TAN) * green3
    land_col = land_col + (DRY - land_col) * (dry_t * (1.0 - green_t))[:, :, None] * 0.6
    land_col = land_col + (FOREST - land_col) * forest_t[:, :, None]
    # montanas: roca por rugosidad
    land_col = land_col + (ROCK - land_col) * (rough_n * 0.55)
    # nieve / hielo: muy claro y poco saturado (casquetes, Himalaya, Andes...)
    snow_t = np.clip((mn - 175.0) / 55.0, 0.0, 1.0) * np.clip((45.0 - (mx - mn)) / 45.0, 0.0, 1.0)
    peaks = np.clip((rough - 1.6) / 0.8, 0.0, 1.0) * (lum > 120)
    snow_t = np.maximum(snow_t, peaks * 0.85)
    land_col = land_col + (SNOW - land_col) * snow_t[:, :, None]

    # celdas de tierra donde la foto parece mar (desajuste de costa): verde llano
    looks_ocean = (b > r + 12) & (b > g - 4)
    land_col = np.where(looks_ocean[:, :, None], GREEN, land_col)

    # --- Sombreado de montanas (luz desde el noroeste) ---------------------------------------------
    shade = 1.0 + detail_n * 0.11 * relief
    shade = np.clip(shade, 0.6, 1.4)[:, :, None]
    land_col = land_col * shade

    # --- Oceano ----------------------------------------------------------------
    near = box_blur(land.astype(np.float32), 5 * k)  # 0 mar abierto .. >0 cerca de costa
    near = np.clip(near * 3.2, 0.0, 1.0)[:, :, None]
    # plataforma continental: profundidad suave a partir de la luminancia batimetrica
    bathy = np.clip((lum - 18.0) / 70.0, 0.0, 1.0)[:, :, None]
    shallow_t = np.clip(near * 0.75 + bathy * 0.35, 0.0, 1.0)
    ocean_col = OCEAN_DEEP + (OCEAN_SHALLOW - OCEAN_DEEP) * shallow_t

    out = np.where(land[:, :, None], land_col, ocean_col)
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out-dir", default=os.path.join(here, "..", "src", "shared"))
    ap.add_argument("--scale", type=int, default=2, choices=[1, 2, 3, 4])
    ap.add_argument("--relief", type=float, default=1.0, help="contraste del sombreado (por defecto 1.0)")
    ap.add_argument("--mask", default=os.path.join(here, "land_mask_960x400.bin"))
    ap.add_argument(
        "--tiles",
        action="store_true",
        help="ademas exporta el mapa en alta resolucion (scale*960 x scale*400) partido en teselas de 960 px "
        "de ancho en tools/previews/ (Roblox limita las imagenes a ~1024 px por lado)",
    )
    args = ap.parse_args()

    land = np.fromfile(args.mask, dtype=np.uint8).reshape(H, W) == 1

    print("Descargando color base (NASA GIBS)...")
    base_full = fs.fetch_layer(BLUE_MARBLE, None, args.scale).astype(np.float32)
    base = fs.downsample(base_full, args.scale)

    shade_gray = None
    shade_full = None
    source = f"NASA GIBS {BLUE_MARBLE}"
    try:
        print("Descargando relieve sombreado (NASA GIBS)...")
        aster_full = fs.fetch_layer(ASTER, None, args.scale).astype(np.float32)
        aster = fs.downsample(aster_full, args.scale)
        gray = luminance(aster)
        gray_full = luminance(aster_full)
        valid_full = gray_full > 3
        if valid_full.any():
            shade_full = np.where(valid_full, gray_full, float(np.median(gray_full[valid_full])))
        # ASTER solo cubre hasta 83N: filas sin datos (negro) se rellenan con la mediana
        valid = gray > 3
        if valid.mean() > 0.2:
            fill = float(np.median(gray[valid]))
            shade_gray = np.where(valid, gray, fill)
            source += f" + {ASTER}"
        else:
            print("  aviso: ASTER vino casi vacio; se usa la luminancia de Blue Marble")
    except Exception as exc:
        print(f"  aviso: no se pudo obtener ASTER ({exc}); se usa la luminancia de Blue Marble")
    if shade_gray is None:
        shade_gray = box_blur(luminance(base), 1)

    print("Generando estilo relieve...")
    img = build(base, shade_gray, land, args.relief)
    fs.write_outputs(img, args.out_dir, source + " (estilo relieve)", "estatica (sin nubes)")

    if args.tiles:
        s = args.scale
        if shade_full is None:
            shade_full = box_blur(luminance(base_full), 1)
        # La mascara del motor se amplia por celdas (cada celda = s x s pixeles): el mapa conserva el aspecto "cuadro por cuadro"
        land_hi = np.kron(land.astype(np.uint8), np.ones((s, s), dtype=np.uint8)).astype(bool)
        print(f"Generando mapa en alta resolucion ({W * s}x{H * s})...")
        hi = build(base_full, shade_full, land_hi, args.relief, k=s)
        tile_dir = os.path.join(here, "previews")
        os.makedirs(tile_dir, exist_ok=True)
        tiles = (W * s) // 960
        for t in range(tiles):
            tile = hi[:, t * 960 : (t + 1) * 960]
            path = os.path.join(tile_dir, f"map_tile_{t}.png")
            with open(path, "wb") as f:
                f.write(fs.encode_png(np.ascontiguousarray(tile)))
            print(f"OK -> {path} ({tile.shape[1]}x{tile.shape[0]}, {os.path.getsize(path) / 1024:.0f} KB)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
