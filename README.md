# 🌍 Dominación Mundial Total (Total World Domination RTS)

Juego multijugador masivo de **Estrategia en Tiempo Real (RTS / Gran Estrategia)** para **Roblox**, construido sobre una cuadrícula planetaria de alta resolución (960×400 celdas) con datos geoespaciales reales, simulación territorial por celdas, economía de naciones, silos balísticos y un ecosistema de **Inteligencia Artificial** con personalidades tácticas, memoria de rencor y dinámicas de coalición anti-hegemónica.

---

## 🎯 Premisa y Jugabilidad

Cada jugador asume el liderazgo de su propia nación soberana (identificada por un color neón único en el mapa) o toma el control de países históricos en el modo diplomático (`COUNTRIES`), compitiendo contra otros jugadores humanos y decenas de bots autónomos por el control de la Tierra y otros mundos.

* **🗺️ Cuadrícula Mundial Realista (960×400):** Basada en datos geográficos de *Natural Earth* con más de 100 países reconocidos (fronteras, población y códigos ISO3), buffer de relieve 3D precomputado (`TerrainData.lua`) para la Tierra y caché en memoria por planeta (`WorldGrid.BuildBase`) con instrumentación de rendimiento en `WorldGrid.LastBuildTimeMs` y telemetría de cliente en `state.perf`.
* **📍 Aparición Validada sin Solapamiento:** Cada capital inicial reclama un disco de radio `5` celdas (`dx² + dy² ≤ 26`) y valida un radio libre de `8` celdas (`isClear(cell, 8)`), garantizando al menos `3` celdas neutrales de separación entre territorios iniciales.
* **⚔️ Expansión Territorial, Logística y Botín Estratégico:**
  * Movilización flexible de tropas con selector de ratio (`20%`, `40%`, `60%`, `80%`, `100%`), invasiones terrestres fronterizas y operaciones anfibias de desembarco marítimo mediante puertos (alcance de `160` celdas).
  * **Líneas de Suministro (`getLogisticsFactor`):** La Capital, Ciudades, Puertos y Puestos Defensivos actúan como nodos logísticos. Atacar a más de `45` celdas del nodo propio más cercano aplica un factor progresivo de sobreextensión (hasta `+45%` de costo), incentivando construir infraestructura de avance.
  * **Valor Estratégico y Botín:** Capturar una celda con infraestructura enemiga otorga `+150` a `+220 Oro` de botín; capturar una **Capital enemiga** otorga `+250 Oro + 15%` de su tesoro nacional, reduce un `15%` la moral/tropas del defensor y reubica su capital a su siguiente Ciudad.
* **🏙️ Infraestructura con Costos Progresivos y Marcadores en Mapa:**
  * 🏢 **Ciudad (`City`, `500 + 200·n Oro`):** `+5.5 Oro/s`, `+30 Tropas base/s` y `+15,000 Tope de Tropas`.
  * ⚓ **Puerto (`Port`, `400 + 100·n Oro`, costa):** `+4.0 Oro/s` de comercio marítimo, `+8 Tropas base/s`, `+5,000 Tope de Tropas`, alcance anfibio de `160` celdas y cabeza de playa ampliada con 2+ puertos.
  * 🛡️ **Puesto Defensivo (`Post`, `350 + 75·n Oro`):** Fortifica un radio de `20` celdas (`2.5×` costo de conquista enemigo, `3.25×` con puestos solapados, desgaste activo) y actúa como **escudo antibalístico (ABM)** que amortigua un `35%` el radio y un `50%` las bajas de misiles nucleares protegiendo su núcleo `3×3`.
  * 🚀 **Silo de Misiles (`Silo`, `1200 + 600·n Oro`):** Habilita ataques nucleares (`NUKE`, `900 Oro`, radio `16`, enfriamiento base de `16 s` reducido en `2 s` por cada Silo adicional hasta `8 s`).
  * Todas las construcciones se representan visualmente sobre el mapa con insignias escalables por zoom y contadores + costos dinámicos en los botones del HUD (`CIUDAD (n)`, `$700 Oro`, etc.).
* **⚡ Servidor Optimizado (`O(B)` en Fronteras y Control de Paquetes):**
  * **Seguimiento Incremental de Fronteras (`borderSet` / `coastalSet`):** `Engine:setOwner()` actualiza en `O(1)` el estado fronterizo y costero únicamente de la celda modificada y sus 4 vecinas. Tanto `Engine:fillQueue()` como `BotAI` operan solo sobre el perímetro activo en lugar de escanear cajas envolventes completas.
  * **Colas y Diffs sin Duplicados:** `atk.inQueue` impide encolar celdas repetidas en frentes de ataque, `self.changedSet` deduplica cambios territoriales por tick y `Engine:flushDiff()` limita cada paquete a `MAX_DIFF_CELLS_PER_TICK = 4096` celdas (`16 KiB` máx/tick), conservando cualquier excedente para el siguiente tick.
* **📊 HUD Económico y Ranking Sincronizados:**
  * El servidor calcula las tasas reales de crecimiento de tropas (`troopRate`, con rendimientos decrecientes suaves en mega-imperios e interés compuesto) e ingreso de oro (`income`) en `Engine:getEconomyRates()` y las envía en `WorldMe`.
  * El ranking (`WorldStats`) destaca siempre al jugador (`👑 [TÚ]`), mostrándolo en su posición dentro del Top 7 o fijándolo en la 7.ª fila con su puesto global real (`#rank`) si está fuera del Top 7.
* **🎨 Renderizado Incremental de Fronteras y Sub-Regiones Sucias (*Dirty Tiles*):**
  * Al recibir `WorldDiff`, el cliente aplica primero todos los cambios en `state.owner` y luego redibuja en una segunda pasada cada celda modificada y sus 4 vecinas cardinales (`redrawCellsWithNeighbors`).
  * `flushImage()` particiona el lienzo en macro-tiles de `120×100 px` y solo transfiere a `EditableImage:WritePixelsBuffer` los sub-rectángulos cuyos píxeles cambiaron realmente de color, evitando reescribir los `1,46 MiB` del mapa completo en cada tick.
* **🤖 Ecosistema de IA de Bots (`src/server/BotAI.lua`):**
  * **Personalidades Tácticas Únicas:** *Conquistador* (agresivo y directo a la capital), *Mercader* (económico y cauto), *Defensor* (muralla fortificada), *Oportunista* (castiga al más débil), *Navegante* (dominio ultramarino) y *Nuclear* (carrera armamentista).
  * **Coalición Anti-Hegemónica:** Si cualquier jugador o bot domina el **35% o más** del mapa, todos los bots se alían de inmediato para concentrar sus ejércitos contra el líder.
  * **Memoria de Rencor (*Spite Matrix*):** Los bots recuerdan las agresiones sufridas y priorizan la contraofensiva contra quien invadió sus territorios.
  * **Muestreo Adaptativo (*Stride*):** Algoritmo de alto rendimiento que mantiene el servidor a 60 FPS estables incluso cuando las naciones controlan miles de celdas.
* **🛡️ Defensa Asistida del Jugador (`src/server/DefenseAI.lua`):**
  * El jugador puede delegar la protección de sus fronteras a la IA de Defensa, la cual redistribuye guarniciones desde provincias interiores hacia los frentes en peligro y repele agresiones sin gastar recursos del jugador ni interferir en sus ataques manuales.
* **📡 Replicación Delta de Alta Eficiencia (`WorldDiff`):**
  * La simulación calcula el mundo a 5 Hz (ticks de 0.2s) en el servidor y transmite únicamente los parches comprimidos de celdas modificadas, reduciendo el consumo de red al mínimo en partidas masivas.

---

## 🏛️ Estructura Modular del Proyecto

El código está organizado en tres capas estrictamente desacopladas compatibles con **Rojo**:

```text
├── default.project.json              # Configuración de sincronización de Rojo
├── rokit.toml                        # Gestor de herramientas (Rojo, StyLua, Selene)
├── selene.toml                       # Reglas de linting de Luau
├── tools/                            # Scripts de procesamiento de mapas y terrenos
│   ├── export_land_mask.py           # Extractor de máscaras continentales
│   ├── generate_terrain.py           # Generador de texturas de relieve
│   └── make_terrain_data.py          # Empaquetador binario en Lua
├── docs/                             # Documentación técnica
│   └── ARCHITECTURE.md               # Especificación completa de arquitectura y protocolos
└── src/
    ├── shared/                       # Dominio compartido (Cliente + Servidor)
    │   ├── WorldGrid.lua             # Geometría de cuadrícula, proyecciones y vecinos
    │   ├── CountryData.lua           # Datos de 100+ países, códigos ISO3 y población
    │   ├── TerrainData.lua           # Buffer comprimido de relieve 3D precomputado
    │   ├── GameConfig.lua            # Balance, costos de edificios y fórmulas económicas
    │   └── MapData.lua               # Definición de planetas y presets de escenarios
    ├── server/                       # Servidor de simulación (Autoridad absoluta)
    │   ├── WorldServer.server.lua    # Ciclo de vida, Heartbeat (5 Hz) y RemoteEvents
    │   ├── WorldEngine.lua           # Motor RTS, fronteras O(B), logística, combate y deltas
    │   ├── BotAI.lua                 # IA con personalidades, coalición, rencor y objetivos tácticos
    │   ├── DefenseAI.lua             # Asistente de defensa territorial para jugadores
    │   └── GameTests.lua             # Suite automatizada de pruebas (aparición, economía, combate y red)
    └── client/                       # Presentación y controles de usuario
        ├── WorldClient.client.lua    # Lienzo 2D interactivo, HUD táctico, cámara y audio
        └── CountryballUI.lua         # Renderizador vectorial procedural de Countryballs
```

Para una explicación exhaustiva del flujo de datos, ciclo de vida de ticks y diagramas de secuencia, consulta [`docs/ARCHITECTURE.md`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/docs/ARCHITECTURE.md).

---

## 📡 Protocolo de Comunicación de Red

Todas las comunicaciones cliente-servidor se gestionan mediante `RemoteEvents` en `ReplicatedStorage.WorldRemotes`:

| Evento | Dirección | Frecuencia | Descripción |
| :--- | :--- | :--- | :--- |
| `WorldInit` | Servidor ➔ Cliente | Al unirse / reiniciar | Envía las dimensiones del mapa, máscara de tierra, roster y propiedad inicial de celdas. |
| `WorldDiff` | Servidor ➔ Cliente | Cada `0.2 s` (5 Hz) | Transmite exclusivamente las celdas mutadas en el último tick para actualizar el lienzo gráfico. |
| `WorldStats` | Servidor ➔ Cliente | Cada `1.0 s` | Envía el marcador global de líderes territoriales y estadísticas del servidor. |
| `WorldMe` | Servidor ➔ Cliente | Cada `0.5 s` | Informa al cliente de sus tropas disponibles, ingresos, edificios y estado de defensa. |
| `WorldNotice` | Servidor ➔ Cliente | Por evento | Notificaciones contextuales (declaraciones de guerra, victorias, bombas atómicas). |
| `WorldCommand` | Cliente ➔ Servidor | Por acción (≤ 12/s) | Peticiones del jugador: `PLAY`, `SPAWN`, `ATTACK`, `BUILD`, `NUKE`, `RETREAT`, `DEFENSE_AI`. |

---

## 🚀 Flujo de Desarrollo con Rojo

### 1. Sincronización en Vivo con Roblox Studio
Para conectar los archivos locales con Roblox Studio:
```bash
# 1. En la raíz del repositorio, inicia el servidor de Rojo:
rojo serve default.project.json

# 2. En Roblox Studio, abre el plugin de Rojo y presiona "Connect" (puerto 34872).
```

### 2. Compilación del Archivo Place
Para compilar un archivo `.rbxl` listo para abrir sin plugin:
```bash
rojo build default.project.json -o DominacionMundialTotal.rbxl
```

### 3. Ejecución de Pruebas Automatizadas (`GameTests.lua`)
En la barra de comandos de Roblox Studio (o mediante MCP `execute_luau`), ejecuta:
```lua
local GameTests = require(game.ServerScriptService.Server.GameTests)
print(GameTests.runAll())
```

### 4. Calidad de Código (Linting y Formateo)
```bash
# Verificar código con Selene
selene src/

# Formatear archivos con StyLua
stylua src/
```

---

## 🧭 Guía para Extender el Juego

* **Añadir un nuevo Edificio:** Agrega la configuración en [`src/shared/GameConfig.lua`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/src/shared/GameConfig.lua), procesa su lógica de construcción en [`src/server/WorldEngine.lua`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/src/server/WorldEngine.lua) y enlaza su botón en [`src/client/WorldClient.client.lua`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/src/client/WorldClient.client.lua).
* **Crear una nueva Personalidad de IA:** Añade un nuevo perfil a la tabla `BotAI.PERSONAS` en [`src/server/BotAI.lua`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/src/server/BotAI.lua) ajustando los coeficientes de agresividad, reserva, rencor y enfoque hacia capitales.
* **Crear un nuevo Planeta / Mapa:** Utiliza los scripts de [`tools/`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/tools) para convertir mapas de bits en matrices binarias e intégralos en [`src/shared/WorldGrid.lua`](file:///c:/Users/dadada/Desktop/Dominacion%20total%20mundial/src/shared/WorldGrid.lua).
