---
name: replicar-referencia
description: Analiza vídeos o capturas de un juego de referencia (modo de juego, animaciones, pixelar) y reproduce sus mecánicas y efectos visuales en el proyecto Roblox "Recuperar Panamá y el Mundo". Úsalo cuando el usuario pida copiar o acercarse al modo de juego o a las animaciones de otro juego.
---

# Replicar un juego de referencia

No puedes abrir ni jugar el juego de referencia. Trabajas solo con el material que el usuario aporte
(vídeo, capturas, descripción). Replicas mecánicas y estética observadas; no copias código, assets ni
nombres de terceros. Todo el arte sale de nuestra propia canalización (tools/*.py, rbxassetid propios).

## 1. Reunir material
- Busca vídeos/imágenes nuevos en la carpeta del proyecto (mp4, mov, webm, gif, png, jpg).
- Si no hay, pide: ~20-30 s por cada cosa: aparecer, expandirse, atacar, armas, desastres, victoria.
- Si hay Computer use disponible, úsalo para capturar el juego en vivo; si no, no insistas.

## 2. Extraer fotogramas
- Si hay `ffmpeg`: `ffmpeg -i video.mp4 -vf fps=4,scale=960:-1 frames/f_%03d.png` (carpeta en scratchpad).
- Lee los fotogramas con Read (imágenes). Elige los clave: inicio, mitad y final de cada animación.
- Mide en los fotogramas: tamaño del píxel/celda, colores, grosor de borde, duración (nº fotogramas / fps),
  dirección y velocidad de propagación, easing, partículas.

## 3. Especificación
Escribe una tabla antes de programar (`docs/referencia-spec.md`): efecto → cómo se ve → duración →
colores (hex) → disparador en el juego. Marca lo dudoso como "suposición" y pregunta solo lo imprescindible.

## 4. Implementación (dónde tocar)
- Reglas y modos: `src/server/WorldEngine.lua` (modo, `isAlly`, `checkWin`, `getStats`), `BotAI.lua`
  (que los bots respeten reglas), `WorldServer.server.lua` (`sanitize`, `sendInit`).
- Visual: `src/client/WorldClient.client.lua` (frente de expansión, EdgeLayer, FX de armas/desastres,
  nubes, lobby, marcador). ZIndexBehavior es Global: usa Z explícitos. Usa `state.*` para funciones
  declaradas más abajo.
- Mapa/arte: `tools/*.py` y `src/shared/*Data.lua` (generados; no editar a mano).
- Rendimiento: lotes con `task.wait()`, nada de miles de Instances por frame; probar con 20 jugadores.

## 5. Verificar
1. `stylua src` y comprobar que `rojo serve` responde; el usuario reconecta y pulsa Accept si hace falta.
2. En Studio (MCP): `start_stop_play`, `screen_capture`, `get_console_output`; usar los desastres de
   depuración (`DEBUG_DISASTER`) para ver cada animación.
3. Comparar capturas propias con los fotogramas de referencia y ajustar colores/tiempos.

## 6. Informar
Resume: qué efectos/mecánicas se replicaron, cuáles son suposiciones, qué falta y qué no se pudo
verificar. Nunca afirmes igualdad con el original sin comparación visual.

## Límites
- Sin material de referencia, no inventes: pídelo.
- No subas imágenes a Roblox, no hagas push ni descargues archivos sin permiso explícito.
