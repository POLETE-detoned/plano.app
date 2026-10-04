# Diseño y motion

Fuente única de los tokens en código: `ios/Plano/Design/Theme.swift` y `Transitions.swift`.

## Tokens

| Token | Valor | Código |
|---|---|---|
| Fondo (tinta) | `#0B0D10` | `Color.planoBackground` (papel en modo claro) |
| Papel | `#F2F0EA` | `Color.planoForeground` (tinta en modo claro) |
| Acento naranja señal | `#FF5A1F` | `Color.signal` |
| Línea de plano | papel al 90 % | `Color.planoLine` |
| Malla de escaneo | acento al 40 % | `Color.scanMesh` |
| Títulos | Space Grotesk, mayúsculas, tracking −2 % | `.planoTitle(size)` |
| Cotas y datos | JetBrains Mono | `.planoMono(size)` |
| Tamaños | 64 / 32 / 17 / 13 | `TypeScale` |
| Rejilla | módulo 8 pt, márgenes 20 pt | `Grid.unit`, `Grid.margin` |

## Curvas y tiempos

| Uso | Valor | Código |
|---|---|---|
| Entrada | `cubic-bezier(0.22, 1, 0.36, 1)`, 480 ms | `Motion.enter` |
| Salida | `cubic-bezier(0.64, 0, 0.78, 0)`, 240 ms | `Motion.exit` |
| Muelle de botones | respuesta 0,45, amortiguación 0,82 | `Motion.button`, `PlanoButtonStyle` |
| Escalonado | 60 ms | `Motion.stagger`, `Motion.staggered(i)` |
| Transición de pantalla | 320 ms, speed ramp `cubic-bezier(0.12, 0.9, 0.2, 1)` | `Motion.screen`, `.maskSlide` |
| Reducir movimiento | fundido 150 ms | `Motion.reduced` |

## Secuencias

| # | Secuencia | Estado | Dónde |
|---|---|---|---|
| 1 | Intro 5 s: PLANO letra a letra con máscara, línea 600 ms, habitación trim 0→1 900 ms, match cut | Hecha | `IntroView` |
| 2 | Escaneo: barrido Metal 1,6 s, cuadrantes con destello 120 ms, contador con rueda numérica | Contadores con rueda numérica hechos; barrido y cuadrantes pendientes | `ScanScreen` |
| 3 | Procesado: cinta de 5 pasos con wipe de 240 ms | Pendiente (va con el procesador) | — |
| 4 | Resultado: muros 900 ms + 60 ms escalonado, puertas 240 ms, cotas contando 480 ms | Hecha | `FloorPlanView` |
| 5 | Transiciones: máscara 320 ms con speed ramp | Hecha | `Router`, `.maskSlide` |

## Reglas

- 120 fps en ProMotion (8 ms por fotograma): las animaciones usan `trim`, `offset`,
  `opacity` y máscaras, sin recalcular geometría por fotograma.
- "Reducir movimiento" sustituye todo por fundidos de 150 ms.
- Sonido opcional (clics secos), apagado por defecto: ajuste creado, sonidos pendientes.
