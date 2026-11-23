# Análisis de Ingeniería Inversa (REA) Aplicado al Diseño del Juego

Siguiendo la metodología de **REA (`reverse-engineer-anything`)**, se desglosaron las mecánicas de los tres juegos de referencia para sintetizar la arquitectura de **Recuperar Panamá y el Mundo**:

| Sistema | Referencia Original | Evidencia / Mecánica Extraída | Implementación en nuestro Juego (`src/`) |
| :--- | :--- | :--- | :--- |
| **Dominio y Mapas Reales** | *Wargame 🚀 [Map Conquest]* (`PlaceId: 83632485006147`, basado en *OpenFront*) | Crecimiento de nación provincia por provincia, fábricas/ciudades, silos y victoria al alcanzar el **65% del mapa**. | `GameConfig.VICTORY_PERCENTAGE = 0.65`, `MapData.lua` con mapas reales 2D Pixel de **Panamá** (14 regiones) y **El Mundo** (22 regiones). |
| **Dedo Divino y Estética 2D Pixel** | *WorldBox - God Simulator* | Renderizado 2D por bloques pixelados + intervención directa mediante el **Dedo Divino (God Finger)** y desastres/bendiciones. | Matrices de silueta pixel 5x5 en `MapData.lua` y barra de herramientas en `ConquestClient.client.lua` (`Dedo de Dios`, `Escudo Soberano`, `Bomba/Meteoro`). |
| **Countryballs, Nodos y Economía** | *Country Balls: World War* (`state.countryballs.dictators.io`) | Avatares Countryballs expresivos sobre cada territorio, conexión por rutas entre nodos y balance de recursos + edificios militares. | `CountryballUI.lua` dibuja cada Countryball en 2D Pixel Art (incluyendo la bandera de 4 cuadrantes de Panamá) y `GameServer.server.lua` gestiona Oro, Petróleo y Manpower. |
| **IA de Defensa vs. Control del Jugador** | Diseño personalizado solicitado | La IA administra la defensa de las fronteras y el fuego de los búnkeres, mientras el jugador controla el 100% de la construcción de edificios y la expansión territorial. | `DefenseAI.StepPlayerCountryDefense` calcula `ThreatScore` por provincia, dispara torretas de `Fortress` y redistribuye reservas internas hacia fronteras amenazadas sin gastar el oro del jugador. |
