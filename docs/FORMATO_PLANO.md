# Formato de paquete `.plano` (versión 1)

Contrato entre la app iOS (productora) y el procesador de escritorio (consumidor).
Un `.plano` es un ZIP. El procesador acepta también la carpeta sin comprimir y
tolera que todo el contenido cuelgue de una carpeta raíz (así lo genera
`NSFileCoordinator` en iOS).

```
MiPiso.plano
├── manifest.json
├── rooms/
│   ├── <uuid>.json        CapturedRoom (Codable de RoomPlan, sin modificar)
│   └── <uuid>.usdz        Modelo paramétrico de la estancia (opcional)
├── mesh.ply               Malla ARKit en coordenadas de mundo (opcional)
├── model.usdz             Modelo combinado (opcional, semana 3-4)
└── frames/
    ├── 000001.heic        Foto de alta resolución (48 MP si el formato lo permite)
    ├── 000001.json        Metadatos del fotograma
    ├── 000001.depth       Profundidad, float32 little-endian, fila a fila
    └── 000001.conf        Confianza de profundidad, uint8 (0, 1, 2) (opcional)
```

## Sistema de coordenadas

- Mundo ARKit: metros, Y hacia arriba, mano derecha, −Z hacia delante al iniciar.
- Todas las estancias de un mismo proyecto se capturan con la **misma `ARSession`**
  (`stop(pauseARSession: false)` entre estancias), por lo que comparten sistema
  de coordenadas. Si una estancia se capturó en otra sesión, `rooms[].alignment`
  lleva la matriz 4×4 que la lleva al mundo del proyecto.
- Planta 2D: `X = x`, `Y = −z` (vista desde arriba).
- Matrices: 16 números en orden **column-major** (como `simd_float4x4`).
  El procesador acepta también `[[c0],[c1],[c2],[c3]]` (lista de columnas).

## `manifest.json`

```json
{
  "format": "plano",
  "version": 1,
  "createdAt": "2026-10-04T10:00:00Z",
  "app": { "name": "Plano", "version": "0.1.0", "device": "iPhone18,1", "os": "26.0" },
  "project": { "id": "UUID", "name": "Piso Ruzafa" },
  "units": "m",
  "coordinateSystem": "arkit-y-up",
  "rooms": [
    {
      "id": "UUID",
      "name": "Salón",
      "file": "rooms/UUID.json",
      "usdz": "rooms/UUID.usdz",
      "capturedAt": "2026-10-04T10:03:00Z",
      "session": "UUID",
      "alignment": null
    }
  ],
  "mesh": "mesh.ply",
  "model": null,
  "frames": { "dir": "frames", "count": 412 }
}
```

`mesh`, `model`, `usdz` y `alignment` pueden ser `null`. Las estancias con el mismo
`session` comparten sistema de coordenadas.

## `frames/NNNNNN.json`

```json
{
  "index": 1,
  "roomId": "UUID",
  "timestamp": 1234.567,
  "image": { "file": "000001.heic", "width": 8064, "height": 6048 },
  "intrinsics": [fx, 0, 0, 0, fy, 0, cx, cy, 1],
  "cameraTransform": [16 números column-major, cámara→mundo],
  "depth": {
    "file": "000001.depth",
    "width": 256, "height": 192,
    "format": "float32le",
    "confidence": "000001.conf",
    "intrinsics": [9 números, ya escalados a la resolución de profundidad],
    "cameraTransform": [16 números, pose de la cámara en el instante de la profundidad],
    "timestamp": 1234.601
  },
  "trackingState": "normal"
}
```

- `intrinsics` es `simd_float3x3` column-major y corresponde a la resolución de `image`.
- La foto de alta resolución no trae profundidad: se toma del `ARFrame` más reciente
  justo después de la foto, con su propia pose (`depth.cameraTransform`) e intrínsecos.
  Para proyectar la profundidad usar siempre la pose e intrínsecos de `depth`.
- `depth` puede ser `null` si el dispositivo no la entregó.

## `mesh.ply`

PLY binario little-endian con `vertex (x, y, z float)` y
`face (vertex_indices list uchar uint, classification uchar)`.
La clasificación sigue `ARMeshClassification` (0 none, 1 wall, 2 floor, 3 ceiling,
4 table, 5 seat, 6 window, 7 door).
