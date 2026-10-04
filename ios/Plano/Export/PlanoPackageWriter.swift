import Foundation

/// Genera el paquete `.plano` (ZIP) a partir de la carpeta del proyecto.
/// Formato: docs/FORMATO_PLANO.md.
enum PlanoPackageWriter {
    struct Options {
        var includeFrames = true
        var includeMesh = true
        var includeUSDZ = true
    }

    static let formatVersion = 1

    static func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Plano" : cleaned
    }

    /// Ficheros (ruta relativa) que entrarán en el paquete, sin el manifiesto.
    static func files(for project: Project, in dir: URL, options: Options) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for room in project.rooms {
            out.append(room.jsonPath)
            if options.includeUSDZ, room.hasUSDZ, fm.fileExists(atPath: dir.appendingPathComponent(room.usdzPath).path) {
                out.append(room.usdzPath)
            }
        }
        if options.includeMesh, fm.fileExists(atPath: dir.appendingPathComponent("mesh.ply").path) {
            out.append("mesh.ply")
        }
        if options.includeFrames {
            let frames = (try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent("frames").path)) ?? []
            out += frames.sorted().map { "frames/\($0)" }
        }
        return out
    }

    static func estimatedSize(of project: Project, in dir: URL, options: Options) -> Int64 {
        files(for: project, in: dir, options: options).reduce(Int64(0)) { total, rel in
            let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(rel).path)[.size])
                as? NSNumber
            return total + (size?.int64Value ?? 0)
        }
    }

    static func manifest(for project: Project, files: Set<String>, options: Options) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let info = Bundle.main.infoDictionary
        var system = utsname()
        uname(&system)
        let device = withUnsafeBytes(of: system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let frameCount = options.includeFrames ? project.frameCount : 0
        return [
            "format": "plano",
            "version": formatVersion,
            "createdAt": iso.string(from: Date()),
            "app": [
                "name": "Plano",
                "version": info?["CFBundleShortVersionString"] as? String ?? "?",
                "device": device,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
            ],
            "project": ["id": project.id.uuidString, "name": project.name],
            "units": "m",
            "coordinateSystem": "arkit-y-up",
            "rooms": project.rooms.map { room -> [String: Any] in
                [
                    "id": room.id.uuidString,
                    "name": room.name,
                    "file": room.jsonPath,
                    "usdz": files.contains(room.usdzPath) ? room.usdzPath as Any : NSNull(),
                    "capturedAt": iso.string(from: room.capturedAt),
                    "session": room.sessionId.uuidString,
                    "alignment": NSNull(),
                ]
            },
            "mesh": files.contains("mesh.ply") ? "mesh.ply" as Any : NSNull(),
            "model": NSNull(),
            "frames": ["dir": "frames", "count": frameCount],
        ]
    }

    /// Crea `<Nombre>.plano` en el directorio temporal y devuelve su URL.
    static func export(project: Project, from dir: URL, options: Options = Options()) throws -> URL {
        let fm = FileManager.default
        let name = safeName(project.name)
        let work = fm.temporaryDirectory.appendingPathComponent("plano-export-\(UUID().uuidString)", isDirectory: true)
        let staging = work.appendingPathComponent(name, isDirectory: true)
        defer { try? fm.removeItem(at: work) }

        let entries = files(for: project, in: dir, options: options)
        for rel in entries {
            let target = staging.appendingPathComponent(rel)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let source = dir.appendingPathComponent(rel)
            // Enlace duro: no duplica gigas de fotos; si falla, copia.
            do { try fm.linkItem(at: source, to: target) } catch { try fm.copyItem(at: source, to: target) }
        }
        let manifestObject = manifest(for: project, files: Set(entries), options: options)
        let data = try JSONSerialization.data(withJSONObject: manifestObject, options: [.prettyPrinted, .sortedKeys])
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: staging.appendingPathComponent("manifest.json"))

        // NSFileCoordinator comprime la carpeta en un ZIP (sin dependencias externas).
        let destination = fm.temporaryDirectory.appendingPathComponent("\(name).plano")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { zip in
            do {
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: zip, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }
}
