#if DEBUG
import Foundation
import simd

/// Datos de demostración para las pruebas en el simulador, donde RoomPlan no funciona.
/// Solo se compila en Debug y solo se usa con el argumento de arranque `-uiTestDemo`.
///
/// La estancia es la misma que genera `plano sample` en el procesador: 4,20 × 3,10 m,
/// una puerta, una ventana y un hueco de paso.
enum DemoData {
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestDemo") }

    static let width: Float = 4.20
    static let depth: Float = 3.10
    static let height: Float = 2.60
    static let floorY: Float = -1.35

    /// Almacén limpio en una carpeta temporal con un proyecto de ejemplo.
    static func makeStore() -> ProjectStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlanoDemo-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(root: root)
        _ = try? seed(store)
        return store
    }

    /// Crea "Vivienda demo" con una estancia: JSON con forma de `CapturedRoom` y planta 2D.
    @discardableResult
    static func seed(_ store: ProjectStore) throws -> Project {
        var project = try store.create(name: "Vivienda demo")
        let roomId = UUID()
        let room = RoomRecord(id: roomId, name: "Salón", capturedAt: Date(), sessionId: UUID(), hasUSDZ: false)
        let (json, plan) = sampleRoom(roomId: roomId)
        let dir = store.directory(for: project)
        try json.write(to: dir.appendingPathComponent(room.jsonPath), options: .atomic)
        project.rooms = [room]
        try store.save(project)
        try store.savePlan(plan, for: project)
        return store.project(id: project.id) ?? project
    }

    private struct Wall {
        let id = UUID()
        let start: SIMD2<Float>
        let end: SIMD2<Float>
        var length: Float { simd_distance(start, end) }
        var direction: SIMD2<Float> { simd_normalize(end - start) }
        var midpoint: SIMD2<Float> { (start + end) / 2 }
    }

    /// Superficie vertical: eje X a lo largo de `direction` (planta → mundo: x = X, z = −Y).
    private static func transform(center: SIMD2<Float>, direction: SIMD2<Float>, centerY: Float) -> [Float] {
        let x = simd_normalize(SIMD3<Float>(direction.x, 0, -direction.y))
        let y = SIMD3<Float>(0, 1, 0)
        let z = simd_cross(x, y)
        let m = simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(center.x, centerY, -center.y, 1))
        return flat(m)
    }

    private static func surface(_ id: UUID, _ category: [String: Any], _ center: SIMD2<Float>, _ direction: SIMD2<Float>,
                                centerY: Float, size: SIMD2<Float>, parent: UUID?) -> [String: Any] {
        var s: [String: Any] = [
            "identifier": id.uuidString,
            "category": category,
            "confidence": ["high": [String: Any]()],
            "dimensions": [size.x, size.y, 0],
            "transform": transform(center: center, direction: direction, centerY: centerY),
        ]
        if let parent { s["parentIdentifier"] = parent.uuidString }
        return s
    }

    static func sampleRoom(roomId: UUID) -> (Data, FloorPlan2D) {
        let corners: [SIMD2<Float>] = [[0, 0], [width, 0], [width, depth], [0, depth]]
        let walls = (0..<4).map { Wall(start: corners[$0], end: corners[($0 + 1) % 4]) }

        // (muro, desplazamiento desde el centro del muro, ancho, alto, alféizar, tipo)
        let door = (wall: 0, offset: Float(-1.10), width: Float(0.82), height: Float(2.03), sill: Float(0))
        let window = (wall: 1, offset: Float(0), width: Float(1.20), height: Float(1.10), sill: Float(0.90))
        let gap = (wall: 2, offset: Float(0.90), width: Float(0.90), height: Float(2.10), sill: Float(0))

        var plan = FloorPlan2D()
        plan.rooms = [.init(id: roomId, name: "Salón")]
        plan.walls = walls.map { .init(id: $0.id, roomId: roomId, start: $0.start, end: $0.end, height: height) }

        func opening(_ o: (wall: Int, offset: Float, width: Float, height: Float, sill: Float),
                     kind: FloorPlan2D.OpeningKind, category: [String: Any], withParent: Bool) -> [String: Any] {
            let w = walls[o.wall]
            let center = w.midpoint + w.direction * o.offset
            let id = UUID()
            plan.openings.append(.init(id: id, kind: kind, wallId: w.id, center: center, width: o.width, height: o.height))
            return surface(id, category, center, w.direction, centerY: floorY + o.sill + o.height / 2,
                           size: [o.width, o.height], parent: withParent ? w.id : nil)
        }

        let room: [String: Any] = [
            "identifier": roomId.uuidString,
            "version": 2,
            "story": 0,
            "walls": walls.map {
                surface($0.id, ["wall": [String: Any]()], $0.midpoint, $0.direction,
                        centerY: floorY + height / 2, size: [$0.length, height], parent: nil)
            },
            "doors": [opening(door, kind: .door, category: ["door": ["isOpen": false]], withParent: true)],
            "windows": [opening(window, kind: .window, category: ["window": [String: Any]()], withParent: true)],
            "openings": [opening(gap, kind: .opening, category: ["opening": [String: Any]()], withParent: false)],
            "objects": [Any](),
            "floors": [Any](),
            "sections": [Any](),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: room, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return (data, plan)
    }
}
#endif
