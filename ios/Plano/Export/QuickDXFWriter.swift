import Foundation
import simd

/// DXF rápido (R12 ASCII) generado en el propio móvil a partir de la planta 2D sin refinar:
/// cara interior de los muros, huecos y cotas como texto. Capas MUROS, HUECOS y COTAS.
/// El DXF definitivo (grosores, ingletes, ortogonalización, cotas DIMENSION) lo genera
/// el procesador de escritorio: `plano dxf proyecto.plano`.
enum QuickDXFWriter {
    static let layers: [(name: String, color: Int)] = [("MUROS", 7), ("HUECOS", 30), ("COTAS", 8), ("TEXTOS", 7)]

    static func dxf(for plan: FloorPlan2D, units: LengthUnit = .meters) -> String {
        var out = DXFBuffer()
        out.section("HEADER") {
            $0.pair(9, "$ACADVER"); $0.pair(1, "AC1009")
            $0.pair(9, "$INSUNITS"); $0.pair(70, 6) // metros
        }
        out.section("TABLES") { t in
            t.pair(0, "TABLE"); t.pair(2, "LTYPE"); t.pair(70, 1)
            t.pair(0, "LTYPE"); t.pair(2, "CONTINUOUS"); t.pair(70, 0); t.pair(3, "Solid line")
            t.pair(72, 65); t.pair(73, 0); t.pair(40, 0.0)
            t.pair(0, "ENDTAB")
            t.pair(0, "TABLE"); t.pair(2, "LAYER"); t.pair(70, layers.count)
            for layer in layers {
                t.pair(0, "LAYER"); t.pair(2, layer.name); t.pair(70, 0); t.pair(62, layer.color); t.pair(6, "CONTINUOUS")
            }
            t.pair(0, "ENDTAB")
        }
        out.section("ENTITIES") { e in
            for wall in plan.walls {
                let d = wall.direction
                var inward = SIMD2<Float>(-d.y, d.x)
                if let c = plan.center(of: wall.roomId), simd_dot(c - wall.midpoint, inward) < 0 { inward = -inward }

                // Tramos macizos entre huecos.
                let gaps = plan.openings.filter { $0.wallId == wall.id }.map { o -> (Float, Float, FloorPlan2D.Opening) in
                    let s = simd_dot(o.center - wall.start, d)
                    return (max(0, s - o.width / 2), min(wall.length, s + o.width / 2), o)
                }.sorted { $0.0 < $1.0 }
                var cursor: Float = 0
                for (a, b, opening) in gaps {
                    if a > cursor { e.line("MUROS", wall.start + d * cursor, wall.start + d * a) }
                    cursor = max(cursor, b)
                    let pa = wall.start + d * a, pb = wall.start + d * b
                    switch opening.kind {
                    case .window:
                        e.line("HUECOS", pa, pb)
                    case .door:
                        let width = b - a
                        e.line("HUECOS", pa, pa + inward * width)
                        let leaf = atan2(inward.y, inward.x) * 180 / .pi
                        let closed = atan2(d.y, d.x) * 180 / .pi
                        let ccw = inward.x * d.y - inward.y * d.x > 0
                        e.arc("HUECOS", center: pa, radius: width,
                              start: ccw ? leaf : closed, end: ccw ? closed : leaf)
                    case .opening:
                        break
                    }
                }
                if wall.length > cursor { e.line("MUROS", wall.start + d * cursor, wall.end) }

                // Cota como texto, hacia dentro de la estancia y legible.
                var angle = atan2(d.y, d.x) * 180 / .pi
                if angle > 90 { angle -= 180 }
                if angle <= -90 { angle += 180 }
                e.text("COTAS", units.format(Double(wall.length)), at: wall.midpoint + inward * 0.25,
                       height: 0.08, rotation: angle)
            }
            for room in plan.rooms {
                if let c = plan.center(of: room.id) {
                    e.text("TEXTOS", room.name.uppercased(), at: c, height: 0.15, rotation: 0)
                }
            }
        }
        out.pair(0, "EOF")
        return out.text
    }

    static func write(_ plan: FloorPlan2D, name: String, units: LengthUnit) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(PlanoPackageWriter.safeName(name))-rapido.dxf")
        try dxf(for: plan, units: units).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct DXFBuffer {
    var text = ""

    mutating func pair(_ code: Int, _ value: String) {
        // R12 no es Unicode: los caracteres no ASCII (Ó, Ñ…) se escriben como \U+XXXX.
        let escaped = value.unicodeScalars
            .map { $0.isASCII ? String($0) : String(format: "\\U+%04X", $0.value) }
            .joined()
        text += "\(code)\n\(escaped)\n"
    }
    mutating func pair(_ code: Int, _ value: Int) { pair(code, String(value)) }
    mutating func pair(_ code: Int, _ value: Double) { pair(code, String(format: "%.4f", value)) }
    mutating func pair(_ code: Int, _ value: Float) { pair(code, Double(value)) }

    mutating func section(_ name: String, _ body: (inout DXFBuffer) -> Void) {
        pair(0, "SECTION"); pair(2, name)
        body(&self)
        pair(0, "ENDSEC")
    }

    mutating func line(_ layer: String, _ a: SIMD2<Float>, _ b: SIMD2<Float>) {
        pair(0, "LINE"); pair(8, layer)
        pair(10, a.x); pair(20, a.y); pair(30, 0.0)
        pair(11, b.x); pair(21, b.y); pair(31, 0.0)
    }

    mutating func arc(_ layer: String, center: SIMD2<Float>, radius: Float, start: Float, end: Float) {
        pair(0, "ARC"); pair(8, layer)
        pair(10, center.x); pair(20, center.y); pair(30, 0.0)
        pair(40, radius); pair(50, start); pair(51, end)
    }

    mutating func text(_ layer: String, _ value: String, at p: SIMD2<Float>, height: Float, rotation: Float) {
        // Centrado (72 = 1, 73 = 2): requiere el punto de alineación 11/21.
        pair(0, "TEXT"); pair(8, layer)
        pair(10, p.x); pair(20, p.y); pair(30, 0.0)
        pair(40, height); pair(1, value); pair(50, rotation)
        pair(72, 1); pair(73, 2)
        pair(11, p.x); pair(21, p.y); pair(31, 0.0)
    }
}
