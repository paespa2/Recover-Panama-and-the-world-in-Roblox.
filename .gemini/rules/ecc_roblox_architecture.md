# Reglas de Arquitectura ECC para Roblox Luau (Recuperar Panamá y el Mundo)

Basado en el marco de ingeniería de **ECC (Everything Claude Code / Agent Harness OS)** adaptado a Roblox Luau de alto rendimiento.

## 1. Principios de Arquitectura & Ejecución
- **Separación de Responsabilidades**:
  - `src/shared/`: Lógica compartida, tipos, constantes globales, utilidades de red y algoritmos puros (`WorldGrid`, `Quadtree`, buffers de compresión).
  - `src/server/`: Autoridad del juego (`WorldEngine`, bucle de simulación a 10 Hz, validación de acciones, economía y balance).
  - `src/client/`: Renderizado gráfico (`EditableImage`, ScreenGui), entrada del usuario (clic, pan, zoom, atajos de teclado), interpolación y efectos visuales (`TweenService`, partículas).
- **Zero Allocations en el Bucle Crítico**:
  - Para grillas masivas (960x400 = 384,000 celdas), usar **Buffers Luau nativos** (`buffer.readu8`, `buffer.writeu8`, `buffer.readu32`, `buffer.writeu32`).
  - Prohibido instanciar tablas temporales en bucles de 60 FPS o 10 Hz. Reutilizar arrays preasignados (`_nb`, colas predimensionadas).

## 2. Red y Diff Syncing
- Las actualizaciones del mapa deben enviarse exclusivamente como **diffs delta**:
  - Empaquetar `cellIndex` (24 bits) + `ownerId` (8 bits) en un solo entero `u32` de 4 bytes.
  - El cliente solo repinta los píxeles modificados mediante `EditableImage:WritePixelsBuffer`.

## 3. Protocolo de Desarrollo & Verificación ECC (Verification Loop)
- **Paso 1: Análisis e Invariantes**: Identificar invariantes antes de tocar código (costos de tropas, límites de celdas, límites de memoria de Luau < 200 KB por script).
- **Paso 2: Edición Atómica**: Mantener código formateado con `stylua src`.
- **Paso 3: Sincronización en Vivo**: Probar en Roblox Studio mediante Rojo o MCP `execute_luau`.
- **Paso 4: Auditoría de Rendimiento**: Validar que el uso de CPU se mantenga bajo y sin caídas de framerate en clientes móviles o PC de gama baja.
