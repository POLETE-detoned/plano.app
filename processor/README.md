# Procesador de Plano

Línea de comandos que importa un paquete `.plano` exportado desde la app y genera planos.

```bash
pip install -e '.[dev]'
plano info  MiPiso.plano
plano dxf   MiPiso.plano -o MiPiso.dxf [--tolerance 3] [--wall-thickness 0.10] [--room Salón]
            [--no-ortho] [--keep-orientation] [--no-dims]
plano sample muestra.plano     # paquete sintético para pruebas
```

## Qué hace hoy (`plano dxf`)

1. Lee el `CapturedRoom` de RoomPlan de cada estancia (`rooms/*.json`).
2. Convierte muros y huecos a planta (`X = x`, `Y = −z`); asigna cada hueco a su muro
   por `parentIdentifier` o, si falta, por proximidad y paralelismo.
3. Orienta el grosor hacia fuera de la estancia (prueba de paridad de rayo).
4. **Ortogonaliza:** dirección dominante ponderada por longitud (módulo 90°) y giro de los
   muros que se desvían menos de la tolerancia. Es la versión geométrica; la de puntos de
   fuga sobre las fotos llega en la semana 5-6.
5. **Cierra esquinas:** une extremos a menos de 30 cm en la intersección de las caras
   interiores y calcula el inglete exterior.
6. Alinea la planta con los ejes (salvo `--keep-orientation`).
7. Exporta DXF R2010 en metros:
   - `MUROS`: polilíneas cerradas por tramo macizo (los huecos parten el muro).
   - `HUECOS`: ventanas (3 líneas), puertas (hoja + arco de 90° hacia dentro), pasos (discontinua).
   - `COTAS`: `DIMENSION` lineales de la cara interior (la que se mide con láser).
   - `TEXTOS`: nombre de la estancia.

## Módulos

| Módulo | Responsabilidad |
|---|---|
| `package.py` | Lectura del ZIP o carpeta, manifiesto, fotogramas y profundidad |
| `roomplan.py` | JSON de `CapturedRoom` → superficies (tolerante a variantes de serialización) |
| `plan.py` | Planta 2D, normales, huecos, ortogonalización, esquinas, alineación |
| `dxf.py` | Escritura DXF con ezdxf |
| `sample.py` | Generador de paquetes sintéticos |
| `cli.py` | Comandos |

## Próximo (semana 5-6)

- Refinado de bordes con las fotos de 48 MP + profundidad (`FrameEntry.depth_*`).
- Paredes, huecos y habitaciones adaptando **Cloud2BIM** (MIT), citando el artículo de
  Zbirovský y Nežerka que lo describe (referencia completa en el README cuando se integre).
- IFC 4 (IfcOpenShell, LGPL), PLY/E57 y PDF acotado.
