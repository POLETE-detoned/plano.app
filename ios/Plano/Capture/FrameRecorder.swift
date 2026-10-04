import ARKit
import CoreImage
import ImageIO

/// Copia de la profundidad del `ARFrame` más reciente (los `CVPixelBuffer` de ARKit
/// no deben retenerse: se reciclan).
struct DepthSnapshot {
    let depth: Data // float32 little-endian, fila a fila
    let confidence: Data? // uint8
    let width: Int
    let height: Int
    let intrinsics: simd_float3x3 // ya escalados a la resolución de profundidad
    let cameraTransform: simd_float4x4
    let timestamp: TimeInterval

    init?(frame: ARFrame) {
        guard let scene = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = scene.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        width = CVPixelBufferGetWidth(map)
        height = CVPixelBufferGetHeight(map)
        guard let depth = Self.copy(map, bytesPerPixel: 4) else { return nil }
        self.depth = depth
        confidence = scene.confidenceMap.flatMap { Self.copy($0, bytesPerPixel: 1) }

        let resolution = frame.camera.imageResolution
        let sx = Float(width) / Float(resolution.width)
        let sy = Float(height) / Float(resolution.height)
        var k = frame.camera.intrinsics // columnas: k[col][fila]
        k[0][0] *= sx
        k[1][1] *= sy
        k[2][0] *= sx
        k[2][1] *= sy
        intrinsics = k
        cameraTransform = frame.camera.transform
        timestamp = frame.timestamp
    }

    private static func copy(_ buffer: CVPixelBuffer, bytesPerPixel: Int) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var data = Data(capacity: width * height * bytesPerPixel)
        for y in 0..<height {
            data.append(base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self),
                        count: width * bytesPerPixel)
        }
        return data
    }
}

/// Graba fotogramas de alta resolución (HEIC) con pose, intrínsecos y profundidad.
///
/// Dispara un fotograma cuando han pasado al menos `interval` segundos **y** el móvil se ha
/// desplazado `distance` metros o girado `angle` grados desde el anterior. Así no se
/// acumulan fotos idénticas con el móvil quieto (cada HEIC de 48 MP pesa ~8-12 MB).
final class FrameRecorder {
    struct Config {
        var interval: TimeInterval = 0.5
        var distance: Float = 0.30
        var angle: Float = 20
    }

    private let session: ARSession
    private let framesDir: URL
    private let config: Config
    private let roomId: UUID
    private let queue = DispatchQueue(label: "app.plano.frames", qos: .utility)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var timer: Timer?
    private var lastPose: simd_float4x4?
    private var lastTime: TimeInterval?
    private var inFlight = false

    /// Último índice escrito (los índices son globales al proyecto).
    private(set) var lastIndex: Int
    var onFrameWritten: ((Int) -> Void)?

    init(session: ARSession, framesDir: URL, lastIndex: Int, roomId: UUID, config: Config) {
        self.session = session
        self.framesDir = framesDir
        self.lastIndex = lastIndex
        self.roomId = roomId
        self.config = config
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func shouldCapture(_ frame: ARFrame) -> Bool {
        guard case .normal = frame.camera.trackingState else { return false }
        // Con el móvil caliente se prioriza que RoomPlan no se cierre.
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            return false
        }
        guard let lastPose, let lastTime else { return true }
        guard frame.timestamp - lastTime >= config.interval else { return false }
        let pose = frame.camera.transform
        let moved = simd_distance(pose.columns.3, lastPose.columns.3)
        let forwardA = simd_normalize(-SIMD3(lastPose.columns.2.x, lastPose.columns.2.y, lastPose.columns.2.z))
        let forwardB = simd_normalize(-SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z))
        let angle = acos(simd_clamp(simd_dot(forwardA, forwardB), -1, 1)) * 180 / .pi
        return moved >= config.distance || angle >= config.angle
    }

    private func tick() {
        guard !inFlight, let frame = session.currentFrame, shouldCapture(frame) else { return }
        inFlight = true
        lastPose = frame.camera.transform
        lastTime = frame.timestamp

        session.captureHighResolutionFrame { [weak self] hiRes, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let hiRes else {
                    self.inFlight = false
                    return
                }
                // La foto de alta resolución no trae profundidad: se toma la del frame actual.
                let depth = self.session.currentFrame.flatMap(DepthSnapshot.init(frame:))
                self.lastIndex += 1
                let index = self.lastIndex
                let roomId = self.roomId
                self.queue.async {
                    self.write(index: index, roomId: roomId, frame: hiRes, depth: depth)
                    DispatchQueue.main.async {
                        self.inFlight = false
                        self.onFrameWritten?(index)
                    }
                }
            }
        }
    }

    private func write(index: Int, roomId: UUID, frame: ARFrame, depth: DepthSnapshot?) {
        let name = String(format: "%06d", index)
        let imageURL = framesDir.appendingPathComponent("\(name).heic")
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        do {
            try ciContext.writeHEIFRepresentation(
                of: image, to: imageURL, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [quality: 0.85])
        } catch {
            return
        }

        var depthMeta: Any = NSNull()
        if let depth {
            let depthFile = "\(name).depth"
            try? depth.depth.write(to: framesDir.appendingPathComponent(depthFile))
            var confFile: Any = NSNull()
            if let conf = depth.confidence {
                try? conf.write(to: framesDir.appendingPathComponent("\(name).conf"))
                confFile = "\(name).conf"
            }
            depthMeta = [
                "file": depthFile,
                "width": depth.width,
                "height": depth.height,
                "format": "float32le",
                "confidence": confFile,
                "intrinsics": flat(depth.intrinsics),
                "cameraTransform": flat(depth.cameraTransform),
                "timestamp": depth.timestamp,
            ] as [String: Any]
        }

        let resolution = frame.camera.imageResolution
        let meta: [String: Any] = [
            "index": index,
            "roomId": roomId.uuidString,
            "timestamp": frame.timestamp,
            "image": ["file": "\(name).heic", "width": Int(resolution.width), "height": Int(resolution.height)],
            "intrinsics": flat(frame.camera.intrinsics),
            "cameraTransform": flat(frame.camera.transform),
            "depth": depthMeta,
            "trackingState": "normal",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: framesDir.appendingPathComponent("\(name).json"), options: .atomic)
        }
    }
}

/// Matriz → lista column-major (como la serializa `simd` en Codable).
func flat(_ m: simd_float4x4) -> [Float] {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
}

func flat(_ m: simd_float3x3) -> [Float] {
    [m.columns.0, m.columns.1, m.columns.2].flatMap { [$0.x, $0.y, $0.z] }
}
