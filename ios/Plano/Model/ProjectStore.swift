import Foundation
import RoomPlan

/// Persistencia local de proyectos. Sin nube: todo vive en Documents/Projects.
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    /// Plantas 2D en caché para miniaturas y revisión.
    @Published private(set) var plans: [UUID: FloorPlan2D] = [:]

    let root: URL
    private let fm = FileManager.default

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    func directory(for project: Project) -> URL {
        root.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    func reload() {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Project] = []
        var loadedPlans: [UUID: FloorPlan2D] = [:]
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
                  let project = try? Self.decoder.decode(Project.self, from: data) else { continue }
            loaded.append(project)
            if let planData = try? Data(contentsOf: dir.appendingPathComponent("plan.json")),
               let plan = try? Self.decoder.decode(FloorPlan2D.self, from: planData) {
                loadedPlans[project.id] = plan
            }
        }
        projects = loaded.sorted { $0.updatedAt > $1.updatedAt }
        plans = loadedPlans
    }

    @discardableResult
    func create(name: String) throws -> Project {
        let project = Project(name: name)
        let dir = directory(for: project)
        for sub in ["rooms", "frames"] {
            try fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try save(project)
        return project
    }

    func save(_ project: Project) throws {
        var project = project
        project.updatedAt = Date()
        let data = try Self.encoder.encode(project)
        try data.write(to: directory(for: project).appendingPathComponent("project.json"), options: .atomic)
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.insert(project, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ project: Project) throws {
        try fm.removeItem(at: directory(for: project))
        projects.removeAll { $0.id == project.id }
        plans[project.id] = nil
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: Estancias

    /// Guarda una estancia terminada: JSON de RoomPlan, USDZ paramétrico y planta 2D.
    @discardableResult
    func addRoom(_ room: CapturedRoom, id: UUID, name: String, sessionId: UUID, to projectId: UUID) throws -> Project {
        guard var project = project(id: projectId) else { throw CocoaError(.fileNoSuchFile) }
        let dir = directory(for: project)
        var record = RoomRecord(id: id, name: name, capturedAt: Date(), sessionId: sessionId, hasUSDZ: false)

        let json = try Self.encoder.encode(room)
        try json.write(to: dir.appendingPathComponent(record.jsonPath), options: .atomic)
        do {
            try room.export(to: dir.appendingPathComponent(record.usdzPath), exportOptions: .parametric)
            record.hasUSDZ = true
        } catch {
            // El USDZ es opcional: el procesador trabaja con el JSON.
        }

        project.rooms.append(record)
        try save(project)
        try rebuildPlan(for: project)
        return self.project(id: projectId) ?? project
    }

    func loadRoom(_ record: RoomRecord, in project: Project) -> CapturedRoom? {
        let url = directory(for: project).appendingPathComponent(record.jsonPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(CapturedRoom.self, from: data)
    }

    func rebuildPlan(for project: Project) throws {
        let rooms = project.rooms.compactMap { record in
            loadRoom(record, in: project).map { (record, $0) }
        }
        let plan = FloorPlan2D(rooms: rooms)
        try Self.encoder.encode(plan).write(
            to: directory(for: project).appendingPathComponent("plan.json"), options: .atomic)
        plans[project.id] = plan
    }

    /// Guarda una planta 2D ya construida (datos de demostración y pruebas).
    func savePlan(_ plan: FloorPlan2D, for project: Project) throws {
        try Self.encoder.encode(plan).write(
            to: directory(for: project).appendingPathComponent("plan.json"), options: .atomic)
        plans[project.id] = plan
    }

    func updateFrameCount(_ count: Int, for projectId: UUID) {
        guard var project = project(id: projectId) else { return }
        project.frameCount = count
        try? save(project)
    }
}
