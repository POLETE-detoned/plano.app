# Plano

App gratuita y de uso personal que escanea una vivienda con un iPhone Pro (LiDAR) y
exporta planos y modelo BIM sin modelar a mano. Sin cuentas, sin nube, sin anuncios:
todo se procesa en el móvil y en tu ordenador.

| Pieza | Carpeta | Tecnología |
|---|---|---|
| App iOS (captura, revisión, exportación) | [`ios/`](ios) | Swift, SwiftUI, ARKit, RoomPlan (iOS 17+) |
| Procesador de escritorio | [`processor/`](processor) | Python 3.11, ezdxf (IfcOpenShell en semana 5-6) |
| Contrato entre ambas | [`docs/FORMATO_PLANO.md`](docs/FORMATO_PLANO.md) | paquete `.plano` (ZIP) |

Documentación: [brief](docs/BRIEF.md) · [plan y estado](docs/PLAN.md) · [diseño y motion](docs/DISENO.md).

## Estado: entrega semana 1-2

- **App iOS:** captura por estancia con RoomPlan sobre `ARSession` propia, fotos de alta
  resolución con pose, intrínsecos y profundidad, malla PLY, varias estancias en la misma
  sesión, paquete `.plano`, DXF rápido en el móvil, las 6 pantallas y la intro animada.
  **Pendiente de compilar y probar en un iPhone real** (ver lista en [PLAN](docs/PLAN.md#verificar-en-dispositivo)).
- **Procesador:** lee `.plano`, ortogonaliza (tolerancia 3°), cierra esquinas con inglete,
  da grosor a los muros y exporta **DXF** con capas `MUROS`, `HUECOS`, `COTAS`, `TEXTOS`.
  Probado con un paquete sintético (`plano sample`).

## Arranque rápido

### Procesador (macOS / Linux / Windows)

```bash
cd processor
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
pytest                                # 12 tests
plano sample muestra.plano            # paquete sintético de 4,20 × 3,10 m
plano info muestra.plano
plano dxf muestra.plano -o muestra.dxf
```

### App iOS (Mac con Xcode 16+ e iPhone con LiDAR)

```bash
brew install xcodegen
cd ios && xcodegen          # genera Plano.xcodeproj a partir de project.yml
open Plano.xcodeproj        # Signing → tu equipo personal → ejecutar en el iPhone
```

RoomPlan no funciona en el simulador: hace falta un dispositivo con LiDAR.

## Flujo

1. **Escanear** cada estancia en la app (Proyectos → Nuevo escaneo → Empezar estancia).
   Encadena estancias con "Siguiente estancia" sin salir: comparten coordenadas.
2. **Revisar** el plano 2D (cotas) y el modelo 3D.
3. **Exportar** el `.plano` por AirDrop al ordenador (o un DXF rápido directamente).
4. **Procesar:** `plano dxf MiPiso.plano`.

## Licencias

Código propio bajo MIT. Fuentes Space Grotesk y JetBrains Mono bajo SIL OFL 1.1
(`ios/Plano/Resources/Fonts/OFL-*.txt`). No se usa código ni marca de Canvas ni de SiteScape.
