import SwiftUI
import simd

/// Ajusta la planta al rectángulo de la vista (Y de planta hacia arriba).
struct PlanTransform {
    let scale: CGFloat
    let origin: CGPoint
    let minP: SIMD2<Float>
    let maxP: SIMD2<Float>

    init(plan: FloorPlan2D, size: CGSize, padding: CGFloat) {
        let b = plan.bounds
        minP = b.min
        maxP = b.max
        let w = CGFloat(max(b.max.x - b.min.x, 0.01))
        let h = CGFloat(max(b.max.y - b.min.y, 0.01))
        let availW = max(size.width - 2 * padding, 1)
        let availH = max(size.height - 2 * padding, 1)
        scale = min(availW / w, availH / h)
        origin = CGPoint(x: (size.width - w * scale) / 2, y: (size.height - h * scale) / 2)
    }

    func point(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x - minP.x) * scale,
                y: origin.y + CGFloat(maxP.y - p.y) * scale)
    }
}

private struct SegmentShape: Shape {
    var a: CGPoint
    var b: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }
}

/// Símbolo de puerta: hoja + arco de 90°, en coordenadas de pantalla.
private struct DoorShape: Shape {
    var hinge: CGPoint
    var closed: CGPoint // extremo de la hoja cerrada
    var open: CGPoint // extremo de la hoja abierta

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: hinge)
        p.addLine(to: open)
        let r = hypot(open.x - hinge.x, open.y - hinge.y)
        let a0 = atan2(open.y - hinge.y, open.x - hinge.x)
        let a1 = atan2(closed.y - hinge.y, closed.x - hinge.x)
        var delta = a1 - a0
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        p.addArc(center: hinge, radius: r, startAngle: .radians(a0), endAngle: .radians(a0 + delta),
                 clockwise: delta < 0)
        return p
    }
}

/// Cifra que cuenta de 0 a su valor (secuencia "Resultado": cotas en 480 ms).
private struct CountingLabel: View, Animatable {
    var value: Double
    var units: LengthUnit

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(units.format(value))
            .planoMono(11)
            .foregroundStyle(Color.planoSecondary)
    }
}

/// Plano que se dibuja solo: muros (900 ms, escalonado 60 ms), puertas (240 ms) y cotas (480 ms).
struct FloorPlanView: View {
    var plan: FloorPlan2D
    var units: LengthUnit = .meters
    var animated = true
    var showDimensions = true
    var lineWidth: CGFloat = 3
    var padding: CGFloat = Grid.u(5)
    var selectedWallId: UUID?
    var onSelectWall: ((UUID) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private let wallDuration = 0.9

    init(plan: FloorPlan2D, units: LengthUnit = .meters, animated: Bool = true, showDimensions: Bool = true,
         lineWidth: CGFloat = 3, padding: CGFloat = Grid.u(5), selectedWallId: UUID? = nil,
         onSelectWall: ((UUID) -> Void)? = nil) {
        self.plan = plan
        self.units = units
        self.animated = animated
        self.showDimensions = showDimensions
        self.lineWidth = lineWidth
        self.padding = padding
        self.selectedWallId = selectedWallId
        self.onSelectWall = onSelectWall
    }

    private var doorsStart: Double { wallDuration + Double(plan.walls.count) * Motion.stagger }
    private var dimsStart: Double { doorsStart + 0.24 }

    var body: some View {
        GeometryReader { geo in
            let tf = PlanTransform(plan: plan, size: geo.size, padding: padding)
            ZStack {
                ForEach(Array(plan.walls.enumerated()), id: \.element.id) { index, wall in
                    SegmentShape(a: tf.point(wall.start), b: tf.point(wall.end))
                        .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                        .stroke(wall.id == selectedWallId ? Color.signal : Color.planoLine,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
                        .contentShape(SegmentShape(a: tf.point(wall.start), b: tf.point(wall.end))
                            .stroke(style: StrokeStyle(lineWidth: 24)))
                        .onTapGesture { onSelectWall?(wall.id) }
                        .animation(timing(Motion.enterCurve(wallDuration)
                                    .delay(Double(index) * Motion.stagger)), value: drawn)
                }

                ForEach(plan.openings) { opening in
                    openingView(opening, tf: tf)
                        .opacity(drawn ? 1 : 0)
                        .animation(timing(Motion.enterCurve(0.24).delay(doorsStart)), value: drawn)
                }

                if showDimensions {
                    ForEach(plan.walls) { wall in
                        CountingLabel(value: drawn ? Double(wall.length) : 0, units: units)
                            .rotationEffect(readableAngle(wall, tf: tf))
                            .position(dimensionPosition(wall, tf: tf))
                            .opacity(drawn ? 1 : 0)
                            .animation(timing(Motion.enterCurve(0.48).delay(dimsStart)), value: drawn)
                    }
                }
            }
        }
        .onAppear { drawn = true }
    }

    private func timing(_ full: Animation) -> Animation {
        reduceMotion ? Motion.reduced : (animated ? full : .linear(duration: 0))
    }

    private func inward(_ wall: FloorPlan2D.Wall) -> SIMD2<Float> {
        let d = wall.direction
        var n = SIMD2<Float>(-d.y, d.x)
        if let c = plan.center(of: wall.roomId), simd_dot(c - wall.midpoint, n) < 0 { n = -n }
        return n
    }

    private func dimensionPosition(_ wall: FloorPlan2D.Wall, tf: PlanTransform) -> CGPoint {
        let offset = Float(Grid.u(2) / max(tf.scale, 1))
        return tf.point(wall.midpoint + inward(wall) * offset)
    }

    private func readableAngle(_ wall: FloorPlan2D.Wall, tf: PlanTransform) -> Angle {
        let a = tf.point(wall.start), b = tf.point(wall.end)
        var angle = atan2(b.y - a.y, b.x - a.x)
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        return .radians(angle)
    }

    @ViewBuilder
    private func openingView(_ o: FloorPlan2D.Opening, tf: PlanTransform) -> some View {
        if let wall = plan.wall(o.wallId) {
            let d = wall.direction
            let s = simd_dot(o.center - wall.start, d)
            let a = wall.start + d * max(0, s - o.width / 2)
            let b = wall.start + d * min(wall.length, s + o.width / 2)
            ZStack {
                // "Borra" el muro en el hueco.
                SegmentShape(a: tf.point(a), b: tf.point(b))
                    .stroke(Color.planoBackground, style: StrokeStyle(lineWidth: lineWidth + 2))
                switch o.kind {
                case .door:
                    DoorShape(hinge: tf.point(a), closed: tf.point(b),
                              open: tf.point(a + inward(wall) * simd_distance(a, b)))
                        .stroke(Color.signal, lineWidth: 1)
                case .window:
                    SegmentShape(a: tf.point(a), b: tf.point(b))
                        .stroke(Color.signal, style: StrokeStyle(lineWidth: lineWidth))
                case .opening:
                    SegmentShape(a: tf.point(a), b: tf.point(b))
                        .stroke(Color.signal, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
    }
}

/// Miniatura estática para la lista de proyectos.
struct FloorPlanThumbnail: View {
    var plan: FloorPlan2D?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.planoHairline.opacity(0.4))
            if let plan, !plan.isEmpty {
                FloorPlanView(plan: plan, animated: false, showDimensions: false, lineWidth: 1.5, padding: Grid.u(1))
            } else {
                Image(systemName: "square.dashed").foregroundStyle(Color.planoSecondary)
            }
        }
    }
}
