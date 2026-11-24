# 🌍 Recuperar Panamá y el Mundo (Roblox)

Juego de conquista territorial en tiempo real, para hasta 20 jugadores por servidor, sobre un mapa del mundo de
**960 × 400 celdas** (≈ 384.000) generado a partir de imágenes de la NASA. Estilo OpenFront / Territorial.io:
creces tropas con interés compuesto, las gastas para conquistar celdas vecinas y el primero que domina el
**65 % de la tierra** gana.

## Modos de juego

| Modo | Cómo se empieza |
| :--- | :--- |
| **Países vs Países** (recomendado, solo Tierra) | Eliges un país real (164, con fronteras de Natural Earth) desde el mapa o desde la lista por continente. Los bots llevan el resto. |
| **Libre** | Colocas tu capital donde quieras (el círculo verde/rojo indica si cabe). Hay otros mundos: Pangea, Marte, Luna, Venus y Andrómeda. |
| _Continentes_ | Aún no implementado (aparece como "próximamente" en el lobby). |

Durante la **fase de aparición** (25 s) puedes cambiar de ubicación o de país las veces que quieras. Quien no elige
recibe uno automáticamente.

## Mecánicas

- **Tropas**: crecen con interés compuesto y tienen un tope según territorio y ciudades. El HUD muestra tropas/tope y el
  ritmo real por segundo calculado por el servidor.
- **Ataque**: clic en una frontera con el porcentaje de tropas elegido (20–100 %). Sin frontera terrestre hace falta un
  **Puerto** para desembarcar.
- **Edificios**: Ciudad (+tope y +ingresos), Puerto (desembarcos), Puesto defensivo (encarece conquistar su zona) y
  Silo de misiles (misil nuclear, 900 oro).
- **IA de Defensa** (interruptor en el HUD): contraataca automáticamente a quien te ataca.
- **Bots** (`src/server/BotAI.lua`): seis personalidades (Conquistador, Mercader, Defensor, Oportunista, Navegante,
  Estratega Nuclear). Construyen, desembarcan, guardan rencor, lanzan misiles y se coalicionan contra quien pasa del 35 % del mapa.
  Piensan con presupuesto por tick y escanean solo la caja envolvente de su nación.

## Controles

Arrastrar con el botón izquierdo (o un dedo) mueve el mapa · un clic corto actúa · rueda o pellizco: zoom hacia el cursor ·
WASD / flechas: mover · Q / E: zoom · H o ⌂: ver el mundo entero.

## Cómo se dibuja el mapa

`WorldClient` intenta pintar el mapa con un `EditableImage` (1 píxel por celda, solo se reenvía el rectángulo modificado).
Eso exige activar **Experience Settings → Security → Allow Mesh / Image APIs** y publicar. **Si no está permitido**, el
cliente cambia solo a un respaldo: teselas de imagen subidas a Roblox (relieve NASA y fronteras) + bloques de color de
5×5 celdas para los territorios, con detalle celda por celda al acercar y una animación de frente de conquista.

## Estructura del proyecto (Rojo + Roblox Studio)

```text
├── default.project.json        # Mapeo de Rojo
├── rokit.toml                  # Herramientas: Rojo 7.7.1, StyLua, Selene, Wally
├── .mcp.json                   # Servidor MCP de Roblox Studio (opcional)
├── src/
│   ├── shared/
│   │   ├── WorldGrid.lua       # Máscara de tierra y mundos; usa TerrainData si existe
│   │   ├── TerrainData.lua     # (generado) mapa base 960×400, paleta de 256 colores
│   │   └── CountryData.lua     # (generado) país de cada celda, nombres, continentes, población
│   ├── server/
│   │   ├── WorldServer.server.lua  # Red, partidas, comandos y lobby
│   │   ├── WorldEngine.lua         # Motor: territorio, tropas, ataques, edificios, economía
│   │   └── BotAI.lua               # IA de los bots
│   └── client/
│       └── WorldClient.client.lua  # Lobby, HUD, mapa, zoom, animaciones
└── tools/                      # Pipeline de datos (Python 3 + numpy)
    ├── fetch_satellite.py          # Descarga imagen NASA GIBS → TerrainData.lua
    ├── generate_relief_style.py    # Estilo relieve; --tiles exporta teselas de alta resolución
    └── build_countries.py          # Fronteras Natural Earth → CountryData.lua; --borders exporta la capa de fronteras
```

> **Código heredado (no usado por el juego actual):** `src/shared/GameConfig.lua`, `src/shared/MapData.lua`,
> `src/server/DefenseAI.lua`, `src/client/CountryballUI.lua` y los `*.disabled` pertenecen a la primera versión (campaña de
> Panamá con provincias, Countryballs y edificios Barracón/Refinería). Siguen en el repositorio como referencia.
> `docs/REA_ANALYSIS.md` describe también ese diseño original.

## Cómo abrir y jugar

```powershell
rokit install        # una vez, instala Rojo 7.7.1 y las herramientas
rojo serve           # deja el servidor corriendo
```

Abre el lugar en Roblox Studio, conecta el plugin de Rojo (**Connect** y luego **Accept**) y pulsa **Play**. Para probar
multijugador: *Test → Clients and Servers*.

## Regenerar el mapa

```powershell
python tools/fetch_satellite.py                       # foto satelital base (sin nubes)
python tools/generate_relief_style.py --relief 2.2 --tiles   # estilo relieve + teselas para subir
python tools/build_countries.py --borders             # países y capa de fronteras
```

Los datos se descargan de NASA GIBS y Natural Earth (dominio público) y se guardan en `tools/.cache/`. Las teselas
(`tools/previews/`) hay que **subirlas a Roblox** y poner sus ids en `EARTH_TILES` y `BORDER_TILES` de
`WorldClient.client.lua`.
