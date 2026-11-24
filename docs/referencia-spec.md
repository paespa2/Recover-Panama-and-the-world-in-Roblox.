# Especificación de referencia (juegos "World PvP" de Roblox)

Fuente: guía pública de RoFront [World PvP] (allthings.how). El juego enlazado por el usuario es
RoWorld [World PvP]; su página exige iniciar sesión y no hay guía pública, así que RoFront se usa como
referencia del género. Todo lo de abajo es **observado en una guía de terceros, sin verificar en RoWorld**.

## Flujo de partida
| Elemento | Referencia | Estado en nuestro juego |
|---|---|---|
| Colocar capital | "Elige tu ubicación: toca tierra libre", cuenta atrás, banner "La guerra comienza" | Hecho (fase SPAWN 25 s) |
| Expansión | Porcentaje de tropas por empuje; pista "sigue hasta encontrar un vecino" | Hecho (ratio + auto) |
| Victoria | ~80 % de la tierra | Nosotros 65 % individual; equipos 55 % (pendiente) |
| Invasión naval | "Llegaste al mar: toca una costa lejana para enviar un barco"; rutas punteadas | Parcial (desembarco 3x3); falta barco animado con ruta punteada |
| Aviso de ataque | Panel de ataques; "Los puestos de defensa endurecen fronteras" | Hecho (defensa, panel de frentes) |
| Edificios | Ciudad, fábrica, puerto, puesto de defensa, buque, silo, SAM (varios niveles) | Parcial (faltan puerto, buque, SAM) |
| Arsenal | Mega bomba, dispersión, refuerzos, artillería, ataque aéreo, cañón de riel | Parcial (armas propias) |
| Alianzas | Solicitudes; romper = "TRAIDOR" 30 s, ataques contra él cuestan 50 % | Pendiente (modo Alianzas) |
| Modos | Mundo, mapas regionales, equipos, humanos vs naciones (IA) | Continentes/equipos en curso |

## Observado en la grabación del usuario (Grabación 2026-11-23 215631.mp4, 18,8 s, 1080x604)
Parece el clip promocional de RoWorld (título "ROWORLD"), no una partida completa; es casi estático
(cambio de fotograma mínimo), así que solo da estilo visual, no tiempos de animación.
- **Frente de batalla:** línea blanca brillante y dentada entre rojo y azul (se ve más gruesa y luminosa que
  los contornos normales); sirve de "zona de combate".
- **Flechas de ataque:** dos flechas curvas opuestas (roja y azul claro con borde blanco) que apuntan al frente,
  con la **cifra de tropas** debajo en tipografía gruesa: "102K" / "329K".
- **Iconos de edificios:** insignias circulares oscuras con borde claro sobre el territorio: ciudad (edificio),
  puerto (ancla), fábrica, puesto de defensa (pentágono). Cada color de nación tiene su tono de insignia.
- **Territorios:** rellenos planos muy saturados (rojo, azul celeste), borde propio blanco fino; vecinos neutrales
  en verde apagado y gris; las fronteras interiores son líneas finas oscuras; relieve y océano azul oscuro.
- **Forma:** bordes suaves y redondeados (no por celdas) con ondulación orgánica.

## Observado en la grabación de 4 min (Grabación 2026-11-23 220717.mp4, 289 s, 1888x918) — partida real de RoWorld
Primeros ~60 s: menú principal (PLAY SOLO, partidas públicas, tienda). Después, partida en Colombia/Venezuela.
- **Territorios:** relleno translúcido sobre el mapa de relieve claro (tono pergamino). Jugador en azul con borde azul
  más oscuro; rivales en rojo/naranja; neutrales en crema. Fronteras interiores finas azul oscuro.
- **Etiquetas de país:** nombre en negrita oscura y debajo las tropas ("Guyana 21.1K", "Chocó 39.1K"); el jugador lleva
  corona, avatar circular y nombre ("paespa 32.3K"). El tamaño del texto crece con el tamaño del territorio.
- **Iconos:** pequeños cuadrados claros sobre el mapa (ciudad, ancla de puerto, castillo de defensa).
- **Aviso sobre el mapa:** píldora "Atacando a Ecuador con 10.2K" junto al objetivo y cifra pequeña "11.1K" en el frente.
- **Tooltip al pasar el ratón:** "Ecuador · AT WAR", Nación • Llanuras, Tropas 10.7K, Tierra 2.1 %, pista de clic derecho.
- **Feed de eventos (izquierda):** tarjetas "Has eliminado a Tejedores de Galawea" (verde), "¡Ecuador (42.4K) te está
  atacando!" (rojo), "Ecuador te está contraatacando", y una tarjeta de **alianza** ("Chocó propone una alianza") con
  barra de tiempo y botones Accept / Decline.
- **Panel ATTACKS (arriba derecha):** lista de ataques en curso con tropas y botón para cancelar.
- **Barra inferior:** Tropas (+1.86K/s), % de ataque (25 %), Oro (+3.2K/s) y ranuras de construcción numeradas 1-9.
- **Arriba al centro:** clasificación ("Tú lideras · 3.4 %").

## Pendiente de verificar con material visual
Colores, tamaño del píxel, duraciones y easing de las animaciones. Requiere vídeo o capturas.
