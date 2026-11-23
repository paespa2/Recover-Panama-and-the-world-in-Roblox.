# 🇵🇦 Recover Panama and the World in Roblox (2D Pixel Conquest)

Juego de estrategia en tiempo real (RTS) en **2D Pixel Art** para **Roblox**, creado mediante ingeniería inversa de mecánicas (*Reverse Engineering Anything - REA*) combinando lo mejor de tres referentes del género:

1. **[Wargame 🚀 \[Map Conquest\] / OpenFront](https://www.roblox.com/games/83632485006147)**: Expansión territorial en tiempo real sobre mapas reales, victoria por dominio del **65% del mapa**, economía de ciudades/puertos y silos tácticos.
2. **[WorldBox - God Simulator](https://www.superworldbox.com/)**: Estética **2D Pixel Art** por bloques y herramientas del **Dedo Divino (*God Finger*)**, **Escudo Soberano** y **Meteoro / Bomba Táctica**.
3. **[Country Balls: World War](https://play.google.com/store/apps/details?id=state.countryballs.dictators.io&hl=es_CO)**: Representación visual de cada provincia/nación con **Countryballs pixelados** con expresiones propias, economía de **Oro + Petróleo + Tropas (Manpower)** y conexiones entre nodos.

---

## 🎮 Dinámica Principal: Jugador vs. IA de Defensa Territorial

Tal como fue diseñado:
- **Responsabilidad del Jugador (Construcción y Expansión):**
  - Tú decides **qué edificios construir** en cada provincia panameña conquistada:
    - 🏙️ **Ciudad** (`+18 Oro/s`, `+250 Límite de Tropas`)
    - ⛺ **Cuartel** (`+28 Tropas/s`, `+15% Defensa`)
    - 🛢️ **Refinería** (`+12 Petróleo/s`, `+8 Oro/s`)
    - 🛡️ **Búnker / Fuerte** (`+65% Defensa` + **Fuego Automático IA** contra enemigos adyacentes)
    - ⚓ **Puerto / Canal** (`+25 Oro/s` y habilita invasiones marítimas a distancia)
    - 🚀 **Silo Táctico** (Desbloquea el lanzamiento de Meteoros/Bombas del Dedo Divino)
  - Tú diriges **toda la expansión territorial** seleccionando una provincia propia, eligiendo el porcentaje de tropas (`25%`, `50%`, `75%`, `85%`) y haciendo clic en el territorio vecino o ruta marítima a conquistar.
- **Responsabilidad de la IA de Defensa de tu País (`src/server/DefenseAI.lua`):**
  - La IA de Defensa **nunca gasta tu oro ni invade sin tu orden**, pero **protege automáticamente las fronteras de tu país**:
    - **🤖 Modo Inteligente (`SMART`)**: Evalúa en tiempo real el puntaje de amenaza (*Threat Score*) de todas tus fronteras, mueve reservas automáticamente desde provincias interiores seguras hacia las fronteras en peligro y responde inmediatamente cuando una provincia tuya es atacada.
    - **🛡️ Modo Muralla (`FORTIFY`)**: Concentra hasta el 85% de las guarniciones en las fronteras exteriores.
    - **🎯 Modo Solo Torretas (`MANUAL`)**: Los Búnkeres/Fuertes disparan automáticamente contra tropas hostiles adyacentes, pero ningún soldado se mueve sin tu clic directo.

---

## 🗺️ Dos Campañas Incluidas (Cambio en Vivo desde el HUD)

1. **Operación 1: Recuperar Panamá (`PANAMA`)**:
   - Mapa 2D Pixel detallado del Istmo de Panamá: **Ciudad de Panamá, Zona del Canal, Colón, Panamá Oeste, Coclé, Herrera, Los Santos (Azuero), Veraguas, Comarca Ngäbe-Buglé, Bocas del Toro, Chiriquí, Guna Yala, Panamá Este y Darién**.
2. **Operación 2: Panamá Conquista el Mundo (`WORLD`)**:
   - Panamá (`Hub Canal de Panamá`) como centro geoestratégico mundial conectado con Norteamérica, Sudamérica, Caribe, Europa, África, Asia y Oceanía.

---

## 🛠️ Estructura del Proyecto (Rojo + Roblox Studio)

```text
├── default.project.json              # Configuración de Rojo para Roblox Studio
├── rokit.toml                        # Toolchain (Rojo 7.4.4, StyLua 2.0.2, Selene)
├── RecoverPanamaAndTheWorld.rbxl     # Archivo compilado listo para abrir en Roblox Studio
└── src/
    ├── shared/
    │   ├── GameConfig.lua            # Configuración de edificios, Dedo Divino, IA y Countryballs
    │   └── MapData.lua               # Mapas 2D Pixel de Panamá y el Mundo con matrices 5x5
    ├── server/
    │   ├── DefenseAI.lua             # Agente de IA de Defensa Territorial y Bots Rivales
    │   └── GameServer.server.lua     # Motor RTS, economía, combate y sincronización
    └── client/
        ├── CountryballUI.lua         # Renderizador procedural 2D Pixel de Countryballs
        └── ConquestClient.client.lua # Lienzo 2D Pixel, HUD, Dedo Divino y efectos visuales
```

## 🚀 Cómo abrir y jugar en Roblox Studio

1. **Directamente con el archivo compilado:**
   - Haz doble clic en `RecoverPanamaAndTheWorld.rbxl` para abrirlo directamente en **Roblox Studio** y presiona **Play (F5)**.
2. **O sincronizando en vivo con Rojo:**
   - Ejecuta `rojo serve` en esta carpeta y conéctalo desde el plugin de Rojo en Roblox Studio.
