import Foundation
import RoomPlan
import simd

/// Planta 2D ligera para miniaturas y revisión en el móvil.
/// Misma convención que el procesador: mundo ARKit → planta (x, −z).
/// El plano definitivo (grosores, ingletes, ortogonalización) lo hace el procesador.
struct FloorPlan2D: Codable, Hashable {
    struct Wall: Codable, Hashable, Identifiable {
        var id: UUID
        var roomId: UUID
        var start: SIMD2<Float>
        var end: SIMD2<Float>
        var height: Float

        var length: Float { simd_distance(start, end) }
        var direction: SIMD2<Float> { simd_normalize(end - start) }
        var midpoint: SIMD2<Float> { (start + end) / 2 }
    }

    enum OpeningKind: String, Codable { case door, window, opening }

    struct Opening: Codable, Hashable, Identifiable {
        var id: UUID
        var kind: OpeningKind
        var wallId: UUID?
        var center: SIMD2<Float>
        var width: Float
        var height: Float
    }

    struct Room: Codable, Hashable, Identifiable {
        var id: UUID
        var name: String
    }

    var rooms: [Room] = []
    var walls: [Wall] = []
    var openings: [Opening] = []

    static func planPoint(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, -p.z) }

    init() {}

    init(rooms captured: [(RoomRecord, CapturedRoom)]) {
        for (record, room) in captured {
            rooms.append(Room(id: record.id, name: record.name))
            var roomWalls: [Wall] = []
            for surface in room.walls {
                let t = surface.transform
                let center = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                let axis = simd_normalize(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
                let half = surface.dimensions.x / 2
                roomWalls.append(Wall(
                    id: surface.identifier,
                    roomId: record.id,
                    start: Self.planPoint(center - axis * half),
                    end: Self.planPoint(center + axis * half),
                    height: surface.dimensions.y
                ))
            }
            walls += roomWalls

            let groups: [(OpeningKind, [CapturedRoom.Surface])] = [
                (.door, room.doors), (.window, room.windows), (.opening, room.openings),
            ]
            for (kind, surfaces) in groups {
                for surface in surfaces {
                    let c = surface.transform.columns.3
                    let center = Self.planPoint(SIMD3(c.x, c.y, c.z))
                    let host = surface.parentIdentifier.flatMap { id in roomWalls.first { $0.id == id } }
                        ?? Self.nearestWall(to: center, in: roomWalls)
                    openings.append(Opening(
                        id: surface.identifier,
                        kind: kind,
                        wallId: host?.id,
                        center: center,
                        width: surface.dimensions.x,
                        height: surface.dimensions.y
                    ))
                }
            }
        }
    }

    private static func nearestWall(to p: SIMD2<Float>, in walls: [Wall]) -> Wall? {
        walls.min { Self.distance(p, $0) < Self.distance(p, $1) }.flatMap { Self.distance(p, $0) < 0.5 ? $0 : nil }
    }

    static func distance(_ p: SIMD2<Float>, _ wall: Wall) -> Float {
        let ab = wall.end - wall.start
        let t = simd_clamp(simd_dot(p - wall.start, ab) / max(simd_length_squared(ab), 1e-9), 0, 1)
        return simd_distance(p, wall.start + t * ab)
    }

    var isEmpty: Bool { walls.isEmpty }

    var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        let points = walls.flatMap { [$0.start, $0.end] }
        guard let first = points.first else { return (.zero, .zero) }
        return points.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    func wall(_ id: UUID?) -> Wall? { walls.first { $0.id == id } }

    /// Centro de la estancia (media de los puntos medios de sus muros).
    func center(of roomId: UUID) -> SIMD2<Float>? {
        let mids = walls.filter { $0.roomId == roomId }.map(\.midpoint)
        guard !mids.isEmpty else { return nil }
        return mids.reduce(.zero, +) / Float(mids.count)
    }
}
