"""
export_land_mask.py
Servidor ligero temporal que recibe la mascara de tierra generada por WorldGrid en Roblox Studio
y ejecuta la generacion completa de terreno 3D con sombreado de relieve y biomas.
"""

import http.server
import socketserver
import os
import struct
import math

PORT = 18464
OUTPUT_MASK = os.path.join(os.path.dirname(__file__), "land_mask_960x400.bin")
OUTPUT_TERRAIN = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "terrain_960x400.bin")
OUTPUT_PREVIEW = os.path.join(os.path.dirname(__file__), "terrain_preview.bmp")

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length)
        with open(OUTPUT_MASK, "wb") as f:
            f.write(data)
        print(f"[Python] Mascara de tierra recibida: {len(data)} bytes guardados en {OUTPUT_MASK}")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK")

        # Iniciar generacion de terreno
        generate_terrain(data)

def generate_terrain(mask_bytes):
    from generate_terrain import W, H, row_to_lat, col_to_lon, compute_elevation, get_biome_color, get_water_color, perlin, moisture_noise

    print(f"[Python] Generando terreno 3D HD ({W}x{H} = {W*H} celdas)...")

    # 1. Crear matriz de tierra
    is_land_map = [b == 1 for b in mask_bytes]

    # 2. Calcular mapa de distancia a la costa para el agua
    dist_map = [0.0] * (W * H)
    print("[Python] Calculando batimetria costera y arrecifes...")
    for y in range(H):
        for x in range(W):
            idx = y * W + x
            if not is_land_map[idx]:
                # Buscar distancia a la tierra mas cercana en radio de 12
                min_d = 99.0
                for dy in range(-6, 7):
                    ny = y + dy
                    if 0 <= ny < H:
                        for dx in range(-6, 7):
                            nx = (x + dx) % W
                            if is_land_map[ny * W + nx]:
                                d = math.sqrt(dx*dx + dy*dy)
                                if d < min_d:
                                    min_d = d
                dist_map[idx] = min_d

    # 3. Calcular mapa de elevacion
    print("[Python] Modelando cordilleras (Andes, Himalaya, Rocosas, Alpes) y relieve...")
    elev_map = [0.0] * (W * H)
    for y in range(H):
        lat = row_to_lat(y)
        for x in range(W):
            idx = y * W + x
            lon = col_to_lon(x)
            is_l = is_land_map[idx]
            elev_map[idx] = compute_elevation(lon, lat, x, y, is_l)

    # 4. Calcular sombreado de relieve 3D (Hillshading direccional desde el Noroeste)
    print("[Python] Calculando iluminacion y sombreado 3D de relieve...")
    shade_map = [1.0] * (W * H)
    for y in range(H):
        for x in range(W):
            idx = y * W + x
            if is_land_map[idx]:
                # Gradiente en X (Este - Oeste)
                left_x = (x - 1) % W
                right_x = (x + 1) % W
                dz_dx = (elev_map[y * W + right_x] - elev_map[y * W + left_x]) / 2.0

                # Gradiente en Y (Sur - Norte)
                up_y = max(0, y - 1)
                down_y = min(H - 1, y + 1)
                dz_dy = (elev_map[down_y * W + x] - elev_map[up_y * W + x]) / 2.0

                # Vector de luz desde el Noroeste (-1, -1)
                illum = (-(dz_dx * 0.0018) - (dz_dy * 0.0018))
                shade = 1.0 + math.tanh(illum) * 0.28
                shade_map[idx] = max(0.68, min(1.35, shade))
            else:
                shade_map[idx] = 1.0 + perlin.noise2d(x * 0.1, y * 0.1) * 0.05

    # 5. Generar colores finales y buffer RGB
    print("[Python] Sintetizando biomas y colores...")
    rgb_bytes = bytearray(W * H * 3)
    bmp_pixels = bytearray(W * H * 3)

    for y in range(H):
        lat = row_to_lat(y)
        for x in range(W):
            idx = y * W + x
            lon = col_to_lon(x)
            is_l = is_land_map[idx]
            shade = shade_map[idx]

            if is_l:
                elev = elev_map[idx]
                moisture = (moisture_noise.fbm(x * 0.05, y * 0.05, octaves=3) + 1.0) * 0.5
                r, g, b = get_biome_color(lon, lat, elev, moisture, shade)
            else:
                dist = dist_map[idx]
                depth = elev_map[idx]
                r, g, b = get_water_color(dist, depth, shade)

            r_byte = max(0, min(255, int(r)))
            g_byte = max(0, min(255, int(g)))
            b_byte = max(0, min(255, int(b)))

            # Guardar en buffer RGB (para Roblox)
            off = idx * 3
            rgb_bytes[off] = r_byte
            rgb_bytes[off + 1] = g_byte
            rgb_bytes[off + 2] = b_byte

            # Para BMP (filas invertidas verticalmente y orden BGR)
            bmp_y = H - 1 - y
            bmp_off = (bmp_y * W + x) * 3
            bmp_pixels[bmp_off] = b_byte
            bmp_pixels[bmp_off + 1] = g_byte
            bmp_pixels[bmp_off + 2] = r_byte

    # Guardar buffer binario para Roblox
    with open(OUTPUT_TERRAIN, "wb") as f:
        f.write(rgb_bytes)
    print(f"[Python] Textura de terreno guardada: {len(rgb_bytes)} bytes en {OUTPUT_TERRAIN}")

    # Guardar BMP para vista previa
    write_bmp(OUTPUT_PREVIEW, W, H, bmp_pixels)
    print(f"[Python] Vista previa guardada en {OUTPUT_PREVIEW}")

def write_bmp(path, w, h, bgr_bytes):
    file_size = 54 + len(bgr_bytes)
    # Encabezado BMP de 14 bytes
    bmp_header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    # Encabezado DIB (BITMAPINFOHEADER) de 40 bytes
    dib_header = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(bgr_bytes), 2835, 2835, 0, 0)
    with open(path, "wb") as f:
        f.write(bmp_header)
        f.write(dib_header)
        f.write(bgr_bytes)

if __name__ == "__main__":
    server = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
    print(f"[Python] Servidor de exportacion escuchando en http://127.0.0.1:{PORT}...")
    server.handle_request()
