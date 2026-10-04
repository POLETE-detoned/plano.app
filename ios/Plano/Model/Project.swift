import Foundation

/// Un proyecto es una vivienda: varias estancias capturadas y sus fotogramas.
///
/// En disco (Documents/Projects/<id>/) la carpeta ya tiene la forma del paquete
/// `.plano` (ver docs/FORMATO_PLANO.md) más `project.json` y `plan.json`.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var rooms: [RoomRecord]
    var frameCount: Int

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        updatedAt = createdAt
        rooms = []
        frameCount = 0
    }
}

struct RoomRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var capturedAt: Date
    /// Estancias con la misma sesión AR comparten sistema de coordenadas.
    var sessionId: UUID
    var hasUSDZ: Bool

    var jsonPath: String { "rooms/\(id.uuidString).json" }
    var usdzPath: String { "rooms/\(id.uuidString).usdz" }
}
