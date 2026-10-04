import SwiftUI

/// Pantalla de escaneo: cámara + malla viva de RoomPlan, contadores y controles por fase.
/// El barrido en shader Metal y los cuadrantes de cobertura llegan en la semana 7.
struct ScanScreen: View {
    let projectId: UUID

    init(projectId: UUID) {
        self.projectId = projectId
    }

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router

    var body: some View {
        if CaptureController.isSupported {
            ScanContent(controller: CaptureController(store: store, projectId: projectId, settings: settings),
                        projectId: projectId)
        } else {
            VStack(alignment: .leading, spacing: Grid.u(2)) {
                ScreenHeader(title: "Escaneo", back: router.pop)
                Spacer()
                Text("Este dispositivo no tiene LiDAR").planoTitle(TypeScale.body).padding(.horizontal, Grid.margin)
                Text("RoomPlan necesita un iPhone o iPad Pro con LiDAR.")
                    .foregroundStyle(Color.planoSecondary)
                    .padding(.horizontal, Grid.margin)
                Spacer()
            }
        }
    }
}

private struct ScanContent: View {
    @StateObject var controller: CaptureController
    let projectId: UUID

    @EnvironmentObject private var router: Router

    init(controller: @autoclosure @escaping () -> CaptureController, projectId: UUID) {
        _controller = StateObject(wrappedValue: controller())
        self.projectId = projectId
    }

    var body: some View {
        ZStack {
            RoomCaptureContainer(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                hud
                Spacer()
                controls
            }
        }
        .background(Color(Palette.ink).ignoresSafeArea())
        .foregroundStyle(Color(Palette.paper))
        .onDisappear { controller.tearDown() }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: Grid.u(1)) {
            HStack {
                Button { router.pop() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Cerrar")
                Text(controller.roomName.isEmpty ? "ESCANEO" : controller.roomName.uppercased())
                    .planoTitle(TypeScale.body)
                Spacer()
                if let start = controller.startedAt, controller.phase == .scanning {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(elapsed(from: start, to: context.date)).planoMono(TypeScale.body)
                    }
                }
            }
            HStack(spacing: Grid.u(2)) {
                counter("MUROS", controller.wallCount)
                counter("PUERTAS", controller.doorCount)
                counter("VENT.", controller.windowCount)
                counter("HUECOS", controller.openingCount)
                counter("FOTOS", controller.framesThisRoom)
            }
        }
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.u(1))
        .background(Color(Palette.ink).opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private func counter(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .planoMono(TypeScale.body)
                .contentTransition(.numericText(value: Double(value))) // rueda numérica
                .animation(Motion.enter, value: value)
            Text(label).planoMono(10).foregroundStyle(Color(Palette.paper).opacity(0.6))
        }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Controles

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: Grid.u(1)) {
            switch controller.phase {
            case .ready:
                TextField("Nombre de la estancia", text: $controller.roomName)
                    .textFieldStyle(.plain)
                    .padding(Grid.u(2))
                    .overlay(Rectangle().stroke(Color(Palette.paper).opacity(0.4)))
                Button("Empezar estancia") { controller.startRoom() }
                    .buttonStyle(PlanoButtonStyle())
            case .scanning:
                Button("Terminar estancia") { controller.finishRoom() }
                    .buttonStyle(PlanoButtonStyle())
            case .processing:
                HStack(spacing: Grid.u(1)) {
                    ProgressView().tint(.signal)
                    Text("PROCESANDO").planoMono(TypeScale.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(Grid.u(2))
            case .reviewing:
                Button("Guardar estancia") { controller.saveRoom() }
                    .buttonStyle(PlanoButtonStyle())
                Button("Descartar") { controller.discardRoom() }
                    .buttonStyle(PlanoButtonStyle(prominent: false))
            case .saved:
                Text("\(controller.roomsSaved) ESTANCIA\(controller.roomsSaved == 1 ? "" : "S") GUARDADA\(controller.roomsSaved == 1 ? "" : "S")")
                    .planoMono(TypeScale.caption)
                Button("Siguiente estancia") { controller.startRoom() }
                    .buttonStyle(PlanoButtonStyle())
                Button("Listo") { router.replaceTop(with: .review(projectId)) }
                    .buttonStyle(PlanoButtonStyle(prominent: false))
            case .failed(let message):
                Text(message).planoMono(TypeScale.caption).multilineTextAlignment(.center)
                Button("Reintentar") { controller.discardRoom() }
                    .buttonStyle(PlanoButtonStyle())
            }
        }
        .padding(.horizontal, Grid.margin)
        .padding(.vertical, Grid.u(2))
        .background(Color(Palette.ink).opacity(0.72).ignoresSafeArea(edges: .bottom))
    }
}
