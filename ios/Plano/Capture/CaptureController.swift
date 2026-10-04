import ARKit
import AVFoundation
import RoomPlan
import SwiftUI

/// Orquesta una sesión de escaneo: RoomPlan sobre una `ARSession` propia, grabación de
/// fotogramas de 48 MP y guardado de cada estancia en el proyecto.
///
/// Todas las estancias escaneadas sin salir de esta pantalla comparten la `ARSession`
/// (`stop(pauseARSession: false)`), así que quedan en el mismo sistema de coordenadas.
final class CaptureController: NSObject, ObservableObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    enum Phase: Equatable {
        case ready // esperando a empezar una estancia
        case scanning
        case processing // RoomPlan generando el resultado
        case reviewing // resultado listo para guardar
        case saved
        case cameraDenied // sin permiso de cámara
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var wallCount = 0
    @Published private(set) var doorCount = 0
    @Published private(set) var windowCount = 0
    @Published private(set) var openingCount = 0
    @Published private(set) var framesThisRoom = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var roomsSaved = 0
    @Published var roomName = ""

    let arSession = ARSession()
    let sessionId = UUID()
    private(set) var captureView: RoomCaptureView!

    private let store: ProjectStore
    private let projectId: UUID
    private let settings: AppSettings
    private var recorder: FrameRecorder?
    private var currentRoomId = UUID()
    private var finalRoom: CapturedRoom?
    private let saveQueue = DispatchQueue(label: "app.plano.save", qos: .userInitiated)

    init(store: ProjectStore, projectId: UUID, settings: AppSettings) {
        self.store = store
        self.projectId = projectId
        self.settings = settings
        super.init()
        captureView = RoomCaptureView(frame: .zero, arSession: arSession)
        captureView.delegate = self
        captureView.captureSession.delegate = self
    }

    // RoomCaptureViewDelegate hereda de NSCoding; este objeto nunca se archiva.
    required init?(coder: NSCoder) { fatalError("CaptureController no admite NSCoding") }
    func encode(with coder: NSCoder) {}

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    var project: Project? { store.project(id: projectId) }

    // MARK: - Ciclo de vida

    /// Abre la cámara y empieza a escanear en cuanto hay permiso. Se llama al entrar en la
    /// pantalla, así que la cámara arranca sin pasos previos.
    func begin() {
        guard phase == .ready || phase == .saved || phase == .cameraDenied else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startRoom()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.startRoom() } else { self.phase = .cameraDenied }
                }
            }
        default:
            phase = .cameraDenied
        }
    }

    private func startRoom() {
        guard let project else { return }
        if roomName.trimmingCharacters(in: .whitespaces).isEmpty {
            roomName = "Estancia \(project.rooms.count + 1)"
        }
        currentRoomId = UUID()
        finalRoom = nil
        wallCount = 0; doorCount = 0; windowCount = 0; openingCount = 0; framesThisRoom = 0

        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
        phase = .scanning
        startedAt = Date()

        if settings.enhancedAR {
            // RoomPlan configura la sesión al arrancar; se amplía justo después.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.enhanceARConfiguration() }
        }

        let firstIndex = project.frameCount
        let recorder = FrameRecorder(
            session: arSession,
            framesDir: store.directory(for: project).appendingPathComponent("frames"),
            lastIndex: firstIndex,
            roomId: currentRoomId,
            config: .init(interval: settings.frameInterval,
                          distance: Float(settings.frameDistance),
                          angle: Float(settings.frameAngle)))
        recorder.onFrameWritten = { [weak self] index in self?.framesThisRoom = index - firstIndex }
        recorder.start()
        self.recorder = recorder
    }

    /// Detiene la captura; RoomPlan procesa y llama a `captureView(didPresent:error:)`.
    func finishRoom() {
        guard phase == .scanning else { return }
        stopRecorder()
        captureView.captureSession.stop(pauseARSession: false)
        phase = .processing
    }

    func discardRoom() {
        finalRoom = nil
        roomName = ""
        phase = .ready
    }

    /// Guarda la estancia (JSON de RoomPlan, USDZ, planta 2D) y la malla acumulada.
    func saveRoom() {
        guard let room = finalRoom else { return }
        let name = roomName
        let roomId = currentRoomId
        let meshAnchors = arSession.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        let meshURL = project.map { store.directory(for: $0).appendingPathComponent("mesh.ply") }
        phase = .processing
        do {
            try store.addRoom(room, id: roomId, name: name, sessionId: sessionId, to: projectId)
            roomsSaved += 1
            roomName = ""
            phase = .saved
        } catch {
            phase = .failed("No se pudo guardar la estancia: \(error.localizedDescription)")
        }
        if let meshURL {
            saveQueue.async { try? MeshExporter.writePLY(anchors: meshAnchors, to: meshURL) }
        }
    }

    /// Cierra la sesión AR al salir de la pantalla.
    func tearDown() {
        stopRecorder()
        if phase == .scanning { captureView.captureSession.stop() }
        arSession.pause()
    }

    private func stopRecorder() {
        guard let recorder else { return }
        recorder.stop()
        store.updateFrameCount(recorder.lastIndex, for: projectId)
        self.recorder = nil
    }

    /// Experimental (apagado por defecto): añade malla clasificada y profundidad a la
    /// configuración que ha puesto RoomPlan. Relanzar la sesión AR mientras RoomPlan la usa
    /// puede congelar la cámara; no se toca el formato de vídeo por ese motivo.
    private func enhanceARConfiguration() {
        guard phase == .scanning,
              let current = arSession.configuration as? ARWorldTrackingConfiguration,
              let configuration = current.copy() as? ARWorldTrackingConfiguration else { return }
        var changed = false
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
           configuration.sceneReconstruction != .meshWithClassification {
            configuration.sceneReconstruction = .meshWithClassification
            changed = true
        }
        for semantic: ARConfiguration.FrameSemantics in [.sceneDepth, .smoothedSceneDepth]
        where ARWorldTrackingConfiguration.supportsFrameSemantics(semantic)
            && !configuration.frameSemantics.contains(semantic) {
            configuration.frameSemantics.insert(semantic)
            changed = true
        }
        if changed { arSession.run(configuration) } // sin opciones: conserva el tracking y las anclas
    }

    // MARK: - RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async {
            self.wallCount = room.walls.count
            self.doorCount = room.doors.count
            self.windowCount = room.windows.count
            self.openingCount = room.openings.count
        }
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.stopRecorder()
            self.phase = .failed("El escaneo se ha detenido: \(error.localizedDescription)")
        }
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.phase = .failed(error.localizedDescription)
                return
            }
            self.finalRoom = processedResult
            self.phase = .reviewing
        }
    }
}

/// Envoltorio SwiftUI de la vista de RoomPlan (malla viva y guía de cobertura).
struct RoomCaptureContainer: UIViewRepresentable {
    let controller: CaptureController

    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
