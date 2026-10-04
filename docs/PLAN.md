# Plan y estado

## Entregas

| Semana | Entrega | Estado |
|---|---|---|
| 1-2 | Captura de una estancia + DXF desde RoomPlan | Código hecho. Procesador probado; app pendiente de prueba en dispositivo |
| 3-4 | Multi-estancia y paquete `.plano` | Adelantado: estancias encadenadas en la misma `ARSession` y paquete completo. Falta alinear estancias de sesiones distintas |
| 5-6 | Procesador con refinado de bordes e IFC | Pendiente |
| 7 | Motion completo, pruebas y documentación | Intro, transiciones, dibujo del plano y contadores hechos. Faltan barrido Metal, cobertura, cinta de procesado, Figma y vídeo |

## Hecho en esta entrega

**App iOS** (`ios/`)
- `CaptureController`: `RoomCaptureView(frame:arSession:)` con `ARSession` propia; tras arrancar
  RoomPlan amplía su configuración con `meshWithClassification`, `sceneDepth`,
  `smoothedSceneDepth` y el formato de vídeo recomendado para alta resolución (se puede
  desactivar en Ajustes).
- `FrameRecorder`: `captureHighResolutionFrame` → HEIC + JSON (pose 4×4, intrínsecos) +
  profundidad float32 y confianza. Sin fotos repetidas con el móvil quieto.
- Varias estancias seguidas con `stop(pauseARSession: false)`: mismas coordenadas.
- `MeshExporter`: malla de ARKit a PLY binario con clasificación.
- `ProjectStore`: proyectos en Documents, JSON de `CapturedRoom`, USDZ paramétrico, planta 2D.
- `PlanoPackageWriter`: `.plano` con enlaces duros y ZIP vía `NSFileCoordinator` (sin dependencias).
- `QuickDXFWriter`: DXF R12 en el propio móvil (capas MUROS, HUECOS, COTAS).
- Pantallas: Intro, Proyectos, Escaneo, Revisión (2D animado + 3D), Exportar (tamaño, AirDrop), Ajustes
  (unidades, tolerancia, captura, calibración con láser).

**Procesador** (`processor/`): ver su README.

## Verificar en dispositivo

Este código se escribió sin Xcode (entorno Linux). Antes de dar la semana 1-2 por cerrada:

1. `xcodegen && xcodebuild` compila sin errores (lo comprueba también el workflow `ios.yml`).
2. Con "Malla y profundidad ampliadas (experimental)" activado, RoomPlan sigue funcionando
   tras `enhanceARConfiguration()`. Si la cámara se congela, dejarlo apagado.
3. Resolución real de `captureHighResolutionFrame` (¿48 MP con el formato recomendado?).
4. `frames/*.depth` tiene 256×192 float32 y valores en metros.
5. El JSON de `CapturedRoom` guardado lo lee `plano info` (formato de `transform`).
6. El `.plano` generado abre con `plano info` y `plano dxf`.
7. DXF rápido y DXF del procesador abren en AutoCAD con capas separadas.
8. 15 minutos seguidos de escaneo sin cierres (vigilar memoria y temperatura).
9. Calibración: 10 paredes de 3-5 m con láser → Ajustes → Calibración.

## Decisiones tomadas

- **Disparo de fotos:** el brief dice "cada 0,5 s o 30 cm". Una foto de 48 MP cada 0,5 s son
  ~12 GB en 10 minutos, así que se exige el intervalo mínimo **y** un desplazamiento de 30 cm
  o un giro de 20° (configurable en Ajustes).
- **Profundidad:** la foto de alta resolución no trae profundidad; se guarda la del
  `ARFrame` más reciente con su propia pose e intrínsecos (documentado en el formato).
- **Grosor de muro:** RoomPlan no lo mide; 10 cm por defecto, hacia fuera de la estancia.
- **Cámara al entrar:** la pantalla de escaneo pide permiso y arranca RoomPlan nada más
  abrirse; el nombre de la estancia se pone al guardarla. Si falta el permiso, se explica
  y hay un botón a Ajustes.
- **Configuración AR ampliada apagada por defecto:** relanzar la `ARSession` mientras
  RoomPlan la usa (sobre todo cambiando el formato de vídeo) puede dejar la cámara congelada.
  Queda como opción experimental, ya sin tocar el formato de vídeo.
- **Navegación propia** en lugar de `NavigationStack` para poder hacer la transición con
  máscara y speed ramp del brief.

## Pendiente (por orden)

1. Prueba en iPhone y corrección de lo que salga de la lista anterior.
2. Edición de muros y huecos en Revisión (hoy solo selección y medida).
3. Alineación de estancias capturadas en sesiones distintas (ARWorldMap o anclas compartidas).
4. Procesador: refinado con fotos, Cloud2BIM, IFC 4, PLY/E57, PDF.
5. Motion: barrido Metal (ciclo 1,6 s), cuadrantes de cobertura, cinta de 5 pasos, sonido.
6. Figma con prototipo de las 5 secuencias y vídeo de referencia de 30 s.
