# Brief: Plano

**ROL:** Sois el diseñador de producto/motion y el ingeniero iOS+Python de un equipo de dos. Construid **"Plano"** (nombre provisional): app gratuita, de uso personal, que escanea una vivienda con un iPhone 17 Pro y exporta planos y modelo BIM sin modelar a mano.

## 1. Alcance
- **Dispositivo:** iPhone 17 Pro, iOS 26 (mínimo iOS 17 por RoomPlan con ARSession propia).
- **Sin cuentas, sin nube, sin anuncios.** Todo se procesa en el móvil y en el ordenador del usuario.
- **Fuera de alcance:** Android, servicio humano de revisión, DWG nativo, curvas, escaleras.

## 2. Arquitectura (dos piezas)
**A. App iOS (Swift, SwiftUI, ARKit, RoomPlan)**
1. Captura por estancia con `RoomCaptureSession`, usando una `ARSession` propia con `ARWorldTrackingConfiguration` (`sceneReconstruction = .meshWithClassification`, `frameSemantics = [.sceneDepth, .smoothedSceneDepth]`).
2. Durante el escaneo, `captureHighResolutionFrame` cada 0,5 s o 30 cm de desplazamiento. Guardar HEIC de 48 MP, pose (4×4), intrínsecos y mapa de profundidad por fotograma.
3. Fusión multi-estancia (cada escaneo tiene su sistema de coordenadas, alinear por anclas compartidas).
4. Exportación en un paquete `.plano` (zip): `manifest.json`, `rooms/*.json` (CapturedRoom), `mesh.ply`, `frames/` (imagen + pose + intrínsecos + profundidad), `model.usdz`.
5. Envío con la hoja de compartir (AirDrop/Archivos).

**B. Procesador de escritorio (Python 3.11, línea de comandos + visor sencillo)**
1. Importa el `.plano`.
2. Refina bordes: detecta líneas en las fotos de 48 MP, las proyecta a 3D con profundidad y pose, y las usa para ajustar esquinas y marcos.
3. Ortogonaliza: dirección dominante por puntos de fuga, ángulos a 90° con tolerancia configurable (3° por defecto).
4. Paredes, huecos y habitaciones: adaptar **Cloud2BIM** (MIT, citar el artículo de Zbirovský y Nežerka), cruzando los huecos con las puertas y ventanas de RoomPlan para resolver puertas cerradas.
5. Exporta **IFC 4** (IfcOpenShell), **DXF** (ezdxf), **PLY/E57** (nube) y **PDF** de planta acotada.
- Licencias: respetar MIT/LGPL y no usar código ni marca de Canvas o SiteScape.

## 3. Pantallas (6)
1. **Intro** (título animado, una vez).
2. **Proyectos** (lista con miniatura del plano).
3. **Escaneo** (cámara + malla viva + cobertura).
4. **Revisión** (plano 2D y 3D, cotas, edición de paredes y huecos).
5. **Exportar** (formatos, tamaño, AirDrop).
6. **Ajustes** (unidades m/ft, tolerancia, calibración).

## 4. Dirección de arte y motion (estilo showreel)
Piensa en la apertura de un reel de estudio: cortes rápidos, tipografía cinética, máscaras y rotulado técnico.

**Tokens**
- **Color:** fondo tinta `#0B0D10`, papel `#F2F0EA`, acento naranja señal `#FF5A1F`, línea de plano `#F2F0EA` al 90 %, malla de escaneo acento al 40 %. Modo claro invertido.
- **Tipografía (licencias abiertas):** Space Grotesk (títulos, mayúsculas, tracking −2 %) y JetBrains Mono (cotas y datos). Tamaños 64/32/17/13.
- **Rejilla:** módulo 8 pt, márgenes 20 pt.

**Curvas y tiempos**
- Entrada: `cubic-bezier(0.22, 1, 0.36, 1)`, 480 ms.
- Salida: `cubic-bezier(0.64, 0, 0.78, 0)`, 240 ms.
- Muelle de botones: respuesta 0,45, amortiguación 0,82.
- Escalonado entre elementos: 60 ms.

**Secuencias clave**
1. **Intro (5 s):** corte seco a negro. La palabra PLANO entra letra a letra con máscara vertical (60 ms entre letras). Una línea naranja recorre el ancho en 600 ms y "dibuja" el rectángulo de una habitación (trim de trazo 0→1 en 900 ms). Corte a la lista de proyectos con un *match cut* en el rectángulo.
2. **Escaneo:** línea de barrido en shader Metal sobre la malla (ciclo 1,6 s). Los cuadrantes cubiertos pasan de vacío a relleno con un destello de 120 ms. Contador de cobertura en JetBrains Mono con rueda numérica.
3. **Procesado:** una "cinta" de 5 pasos (Importar, Refinar, Ortogonalizar, Paredes, Exportar). Cada paso salta a mayúsculas con un wipe horizontal de 240 ms al completarse.
4. **Resultado:** el plano se dibuja solo: paredes a 900 ms con 60 ms de escalonado, luego puertas con arco en 240 ms y por último las cotas contando de 0 a su valor en 480 ms.
5. **Transiciones entre pantallas:** deslizamiento con máscara de 320 ms y salida con *speed ramp* (rápido al inicio, frena al final).

**Reglas**
- 120 fps en ProMotion, presupuesto de 8 ms por fotograma.
- Respetar "Reducir movimiento": sustituir movimientos por fundidos de 150 ms.
- Sonido opcional (clics secos en transiciones), apagado por defecto.
- Entregar en Figma con *prototype* de las 5 secuencias y un vídeo de referencia de 30 s.

## 5. Criterios de aceptación
- Escanear un piso de 3 estancias en menos de 10 minutos.
- **Objetivo:** error ≤ ±2 cm en paredes de 3 a 5 m, validado con medidor láser en 10 distancias. Si no se cumple, documentar el error real en Ajustes.
- IFC abre sin errores en Archicad o Revit y en Blender con Bonsai.
- DXF abre en AutoCAD con capas separadas: muros, huecos, cotas.
- Sin cierres inesperados al escanear 15 minutos seguidos.

## 6. Entregas
1. **Semana 1-2:** captura de una estancia + DXF desde RoomPlan.
2. **Semana 3-4:** multi-estancia y paquete `.plano`.
3. **Semana 5-6:** procesador con refinado de bordes e IFC.
4. **Semana 7:** motion completo, pruebas y documentación.
