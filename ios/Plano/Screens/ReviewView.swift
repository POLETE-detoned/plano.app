import SceneKit
import SwiftUI

/// Revisión: plano 2D animado con cotas y modelo 3D (USDZ de RoomPlan).
/// Edición de muros y huecos: pendiente (ver docs/PLAN.md).
struct ReviewView: View {
    let projectId: UUID

    init(projectId: UUID) {
        self.projectId = projectId
    }

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router

    private enum Mode: String, CaseIterable { case plan = "2D", model = "3D" }
    @State private var mode: Mode = .plan
    @State private var selectedWall: UUID?

    private var project: Project? { store.project(id: projectId) }
    private var plan: FloorPlan2D { store.plans[projectId] ?? FloorPlan2D() }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: project?.name ?? "Revisión", back: router.pop) {
                Picker("Vista", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: Grid.u(14))
            }

            ZStack {
                switch mode {
                case .plan:
                    if plan.isEmpty {
                        Text("SIN ESTANCIAS").planoMono().foregroundStyle(Color.planoSecondary)
                    } else {
                        FloorPlanView(plan: plan, units: settings.units, selectedWallId: selectedWall) { id in
                            selectedWall = selectedWall == id ? nil : id
                        }
                        .id(plan) // vuelve a dibujarse cuando cambia
                    }
                case .model:
                    if let project {
                        ModelView(urls: project.rooms.filter(\.hasUSDZ).map {
                            store.directory(for: project).appendingPathComponent($0.usdzPath)
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            info
        }
    }

    @ViewBuilder
    private var info: some View {
        VStack(alignment: .leading, spacing: Grid.u(1)) {
            if let wall = plan.wall(selectedWall) {
                HStack {
                    Text("MURO").planoMono().foregroundStyle(Color.planoSecondary)
                    Spacer()
                    Text("\(settings.units.format(Double(wall.length))) × \(settings.units.format(Double(wall.height))) \(settings.units.rawValue)")
                        .planoMono(TypeScale.body)
                }
            }
            if let project {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Grid.u(1)) {
                        ForEach(project.rooms) { room in
                            Text(room.name.uppercased())
                                .planoMono(11)
                                .padding(.horizontal, Grid.u(1.5))
                                .padding(.vertical, Grid.u(1))
                                .overlay(Rectangle().stroke(Color.planoHairline))
                        }
                    }
                }
            }
            HStack(spacing: Grid.u(1)) {
                Button("Añadir estancia") { router.push(.scan(projectId)) }
                    .buttonStyle(PlanoButtonStyle(prominent: false))
                Button("Exportar") { router.push(.export(projectId)) }
                    .buttonStyle(PlanoButtonStyle())
                    .disabled(project?.rooms.isEmpty ?? true)
            }
        }
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.u(2))
    }
}

/// Une los USDZ de todas las estancias (comparten coordenadas si son de la misma sesión).
private struct ModelView: View {
    let urls: [URL]
    @State private var scene: SCNScene?

    init(urls: [URL]) {
        self.urls = urls
    }

    var body: some View {
        Group {
            if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else {
                Text(urls.isEmpty ? "SIN MODELO 3D" : "CARGANDO").planoMono().foregroundStyle(Color.planoSecondary)
            }
        }
        .task(id: urls) {
            let combined = SCNScene()
            for url in urls {
                guard let room = try? SCNScene(url: url) else { continue }
                for node in room.rootNode.childNodes {
                    combined.rootNode.addChildNode(node.clone())
                }
            }
            combined.background.contents = UIColor.clear
            scene = urls.isEmpty ? nil : combined
        }
    }
}
