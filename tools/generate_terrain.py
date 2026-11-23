"""
generate_terrain.py
Generador cientifico y artistico de terreno y relieve terrestre para Roblox Studio.
Calcula elevacion fisica (cordilleras reales, fosas oceanicas), sombreado de relieve 3D
(hillshading direccional noroccidental), clasificacion de biomas (temperatura y humedad)
y genera la textura base definitiva para la cuadricula de 960x400.
"""

import math
import os
import struct

W = 960
H = 400
LAT_TOP = 84.0
LAT_BOT = -60.0

def row_to_lat(y):
    return LAT_TOP - (y + 0.5) * (LAT_TOP - LAT_BOT) / H

def col_to_lon(x):
    return (x + 0.5) / W * 360.0 - 180.0

# Ruido Perlin 2D determinista en Python puro
class PerlinNoise:
    def __init__(self, seed=42):
        self.p = list(range(256))
        # Barajado determinista simple
        v = seed
        for i in range(255, 0, -1):
            v = (v * 1664525 + 1013904223) & 0xFFFFFFFF
            j = (v >> 16) % (i + 1)
            self.p[i], self.p[j] = self.p[j], self.p[i]
        self.p += self.p

    def _fade(self, t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    def _lerp(self, a, b, t):
        return a + t * (b - a)

    def _grad(self, hash_val, x, y):
        h = hash_val & 7
        u = x if h < 4 else y
        v = y if h < 4 else x
        return (u if (h & 1) == 0 else -u) + (v if (h & 2) == 0 else -v)

    def noise2d(self, x, y):
        xi = int(math.floor(x)) & 255
        yi = int(math.floor(y)) & 255
        xf = x - math.floor(x)
        yf = y - math.floor(y)

        u = self._fade(xf)
        v = self._fade(yf)

        aa = self.p[self.p[xi] + yi]
        ab = self.p[self.p[xi] + yi + 1]
        ba = self.p[self.p[xi + 1] + yi]
        bb = self.p[self.p[xi + 1] + yi + 1]

        x1 = self._lerp(self._grad(aa, xf, yf), self._grad(ba, xf - 1, yf), u)
        x2 = self._lerp(self._grad(ab, xf, yf - 1), self._grad(bb, xf - 1, yf - 1), u)
        return self._lerp(x1, x2, v)

    def fbm(self, x, y, octaves=4, lacunarity=2.0, persistence=0.5):
        total = 0.0
        freq = 1.0
        amp = 1.0
        max_amp = 0.0
        for _ in range(octaves):
            total += self.noise2d(x * freq, y * freq) * amp
            max_amp += amp
            amp *= persistence
            freq *= lacunarity
        return total / max_amp

perlin = PerlinNoise(seed=1337)
moisture_noise = PerlinNoise(seed=777)
relief_noise = PerlinNoise(seed=999)

def load_land_mask():
    """Genera la mascara de tierra evaluando los poligonos de WorldGrid o lee WorldGrid."""
    # Usaremos una matriz WxH booleana
    # Para consistencia exacta con WorldGrid.lua, podemos ejecutar un script auxiliar o rasterizar
    return None

def compute_elevation(lon, lat, x, y, is_land):
    """Calcula la elevacion real en metros (positiva en tierra, negativa en oceano)."""
    if not is_land:
        # Fosas y relieve oceanico
        base_depth = -3500.0
        # Dorsal mesoatlantica
        if -45.0 <= lon <= -15.0 and -50.0 <= lat <= 65.0:
            dist_ridge = abs(lon - (-30.0 + lat * 0.12))
            if dist_ridge < 12.0:
                base_depth += (12.0 - dist_ridge) * 180.0
        # Ruido de lecho marino
        bathy_noise = perlin.fbm(x * 0.04, y * 0.04, octaves=3) * 600.0
        return base_depth + bathy_noise

    # ELEVACION EN TIERRA
    elev = 200.0 + perlin.fbm(x * 0.03, y * 0.03, octaves=4) * 280.0

    # 1. Cordillera de los Andes (Sudamerica)
    if -82.0 <= lon <= -64.0 and -55.0 <= lat <= 11.0:
        center_lon = -72.0 - lat * 0.14
        dist = abs(lon - center_lon)
        if dist < 4.8:
            height = math.cos(dist / 4.8 * (math.pi / 2.0)) * 4800.0
            height += relief_noise.fbm(x * 0.15, y * 0.15, octaves=3) * 1200.0
            elev = max(elev, height)

    # 2. Himalaya y Meseta del Tibet (Asia)
    if 68.0 <= lon <= 104.0 and 24.0 <= lat <= 40.0:
        center_lat = 30.0 + math.sin(lon * 0.08) * 3.0
        dist = abs(lat - center_lat)
        if dist < 7.0:
            height = math.cos(dist / 7.0 * (math.pi / 2.0)) * 5500.0
            height += relief_noise.fbm(x * 0.12, y * 0.12, octaves=3) * 1600.0
            elev = max(elev, height)

    # 3. Montañas Rocosas y Cadena Costera (Norteamerica)
    if -128.0 <= lon <= -102.0 and 30.0 <= lat <= 64.0:
        center_lon = -114.0 + (lat - 40.0) * 0.35
        dist = abs(lon - center_lon)
        if dist < 5.5:
            height = math.cos(dist / 5.5 * (math.pi / 2.0)) * 3600.0
            height += relief_noise.fbm(x * 0.14, y * 0.14, octaves=3) * 900.0
            elev = max(elev, height)

    # 4. Alpes Europeos
    if 4.5 <= lon <= 17.0 and 43.5 <= lat <= 48.5:
        dist = math.sqrt((lon - 10.0)**2 + (lat - 46.0)**2)
        if dist < 4.5:
            height = math.cos(dist / 4.5 * (math.pi / 2.0)) * 3400.0
            elev = max(elev, height)

    # 5. Escandinavia / Tierras Altas
    if 5.0 <= lon <= 22.0 and 58.0 <= lat <= 70.0:
        elev += perlin.fbm(x * 0.08, y * 0.08, octaves=3) * 800.0

    # 6. Gran Cordillera Divisoria (Este de Australia)
    if 140.0 <= lon <= 154.0 and -38.0 <= lat <= -14.0:
        dist = abs(lon - (148.0 - (lat + 25.0) * 0.15))
        if dist < 3.5:
            elev = max(elev, 800.0 + math.cos(dist / 3.5 * (math.pi / 2.0)) * 1100.0)

    # 7. Macizo de las Guayanas y Sierra del Mar (Brasil)
    if -55.0 <= lon <= -40.0 and -28.0 <= lat <= -15.0:
        elev += 600.0

    return max(15.0, elev)

def get_biome_color(lon, lat, elev, moisture, shade):
    """Calcula el color RGB artistico en base a bioma y sombreado 3D."""
    abs_lat = abs(lat)

    # Nieves perpetuas y cumbres glaciares
    snowline = 4600.0 - abs_lat * 48.0
    if elev > snowline or abs_lat > 72.0 or (abs_lat > 64.0 and elev > 300.0):
        # Blanco y celeste nieve
        r, g, b = 238, 244, 252
        return (r * shade, g * shade, b * shade)

    # Cumbres rocosas y pedregales alpinos
    if elev > snowline - 700.0:
        r, g, b = 142, 138, 146
        return (r * shade, g * shade, b * shade)

    # Zonas deserticas
    is_sahara = (14.0 <= lat <= 32.0 and -18.0 <= lon <= 55.0)
    is_arabia = (12.0 <= lat <= 34.0 and 35.0 <= lon <= 60.0)
    is_gobi = (38.0 <= lat <= 48.0 and 90.0 <= lon <= 118.0)
    is_outback = (-34.0 <= lat <= -18.0 and 116.0 <= lon <= 144.0)
    is_atacama = (-28.0 <= lat <= -18.0 and -73.0 <= lon <= -68.0)

    if is_sahara or is_arabia:
        r, g, b = 232, 202, 128 # Dunas doradas
    elif is_outback:
        r, g, b = 218, 142, 84 # Tierra roja australiana
    elif is_gobi or is_atacama or (moisture < 0.28 and abs_lat < 42.0):
        r, g, b = 210, 184, 124 # Desierto rocoso
    elif abs_lat > 54.0:
        # Taiga y coniferas
        r, g, b = 44, 98, 52
    elif -14.0 <= lat <= 12.0 and moisture > 0.45:
        # Selvas tropicales de Panama, Amazonas, Congo e Indonesia
        if -84.0 <= lon <= -76.0 and 7.0 <= lat <= 11.0:
            # Istmo de Panama: Selva costera vibrante
            r, g, b = 32, 146, 58
        elif -78.0 <= lon <= -46.0 and -14.0 <= lat <= 5.0:
            # Cuenca Amazonica
            r, g, b = 24, 126, 46
        else:
            r, g, b = 28, 132, 52
    elif moisture > 0.52:
        # Bosques templados humedos
        r, g, b = 58, 142, 60
    elif moisture > 0.35:
        # Praderas y sabanas
        r, g, b = 88, 156, 68
    else:
        # Estepa y matorral seco
        r, g, b = 182, 172, 108

    # Altura moderada: añade tonos pardos y rocosos
    if elev > 1800.0:
        f = min(1.0, (elev - 1800.0) / 1500.0)
        r = r * (1.0 - f) + 148 * f
        g = g * (1.0 - f) + 138 * f
        b = b * (1.0 - f) + 128 * f

    return (r * shade, g * shade, b * shade)

def get_water_color(dist_to_land, depth, shade):
    """Calcula el color del agua en base a la proximidad a la costa y profundidad."""
    if dist_to_land <= 1.5:
        # Arrecife de coral / arena de playa turquesa brillante
        r, g, b = 56, 162, 196
    elif dist_to_land <= 3.5:
        # Plataforma continental poco profunda
        r, g, b = 38, 124, 172
    elif dist_to_land <= 6.5:
        # Mar costero
        r, g, b = 24, 82, 138
    elif dist_to_land <= 12.0:
        # Azul marino abierto
        r, g, b = 16, 52, 102
    else:
        # Abismo oceanico profundo
        r, g, b = 10, 28, 58

    return (r * shade, g * shade, b * shade)

print("Cargando mascara de tierra desde WorldGrid...")
