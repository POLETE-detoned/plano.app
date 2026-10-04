import SwiftUI

/// Exportar: paquete `.plano` para el procesador de escritorio y DXF rápido.
/// El envío usa la hoja de compartir (AirDrop, Archivos…).
struct ExportView: View {
    let projectId: UUID

    init(projectId: UUID) {
        self.projectId = projectId
    }

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router

    @State private var options = PlanoPackageWriter.Options()
    @State private var estimatedBytes: Int64 = 0
    @State private var packageURL: URL?
    @State private var dxfURL: URL?
    @State private var working = false
    @State private var errorMessage: String?

    private var project: Project? { store.project(id: projectId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Exportar", back: router.pop)

            ScrollView {
                VStack(alignment: .leading, spacing: Grid.u(3)) {
                    section("Paquete .plano", detail: "Todo lo necesario para el procesador de escritorio: refinado con las fotos, IFC 4, DXF por capas, nube de puntos y PDF.") {
                        Toggle("Fotogramas 48 MP + profundidad", isOn: $options.includeFrames)
                        Toggle("Malla (PLY)", isOn: $options.includeMesh)
                        Toggle("Modelos USDZ", isOn: $options.includeUSDZ)
                        HStack {
                            Text("TAMAÑO").planoMono().foregroundStyle(Color.planoSecondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file))
                                .planoMono(TypeScale.body)
                                .contentTransition(.numericText())
                        }
                        if let packageURL {
                            ShareLink(item: packageURL) { Text("Enviar .plano") }
                                .buttonStyle(PlanoButtonStyle())
                                .accessibilityIdentifier("sharePackage")
                        } else {
                            Button(working ? "Generando…" : "Generar .plano") { exportPackage() }
                                .buttonStyle(PlanoButtonStyle())
                                .accessibilityIdentifier("generatePackage")
                                .disabled(working)
                        }
                    }

                    section("DXF rápido", detail: "Planta sin refinar generada en el móvil (cara interior de muros, huecos y cotas). Para el DXF definitivo usa el procesador.") {
                        if let dxfURL {
                            ShareLink(item: dxfURL) { Text("Enviar DXF") }
                                .buttonStyle(PlanoButtonStyle(prominent: false))
                        } else {
                            Button("Generar DXF") { exportDXF() }
                                .buttonStyle(PlanoButtonStyle(prominent: false))
                                .accessibilityIdentifier("generateDXF")
                        }
                    }

                    section("En el ordenador", detail: nil) {
                        Text("pip install -e processor\nplano dxf \"\(PlanoPackageWriter.safeName(project?.name ?? "Proyecto")).plano\"")
                            .planoMono(TypeScale.caption)
                            .textSelection(.enabled)
                            .padding(Grid.u(1.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().stroke(Color.planoHairline))
                    }
                }
                .padding(.horizontal, Grid.margin)
                .padding(.vertical, Grid.u(2))
            }
        }
        .tint(.signal)
        .onAppear(perform: refreshSize)
        .onChange(of: options.includeFrames) { _, _ in invalidate() }
        .onChange(of: options.includeMesh) { _, _ in invalidate() }
        .onChange(of: options.includeUSDZ) { _, _ in invalidate() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func section<Content: View>(_ title: String, detail: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Grid.u(1.5)) {
            Text(title).planoTitle(TypeScale.body)
            if let detail {
                Text(detail)
                    .font(PlanoFont.grotesk(TypeScale.caption, weight: 400))
                    .foregroundStyle(Color.planoSecondary)
            }
            content()
        }
    }

    private func invalidate() {
        packageURL = nil
        refreshSize()
    }

    private func refreshSize() {
        guard let project else { return }
        let dir = store.directory(for: project)
        let options = options
        DispatchQueue.global(qos: .userInitiated).async {
            let size = PlanoPackageWriter.estimatedSize(of: project, in: dir, options: options)
            DispatchQueue.main.async { withAnimation(Motion.enter) { estimatedBytes = size } }
        }
    }

    private func exportPackage() {
        guard let project else { return }
        working = true
        let dir = store.directory(for: project)
        let options = options
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PlanoPackageWriter.export(project: project, from: dir, options: options) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(let url): withAnimation(Motion.enter) { packageURL = url }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportDXF() {
        guard let project, let plan = store.plans[projectId] else { return }
        do {
            dxfURL = try QuickDXFWriter.write(plan, name: project.name, units: settings.units)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
