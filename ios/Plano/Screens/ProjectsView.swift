import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: Router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var naming = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Proyectos").planoTitle(TypeScale.title)
                Spacer()
                Button { router.push(.settings) } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Ajustes")
                .accessibilityIdentifier("settingsButton")
            }
            .padding(.horizontal, Grid.margin)
            .padding(.top, Grid.u(2))
            .padding(.bottom, Grid.u(3))

            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Grid.u(2)) {
                        ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                            Button { router.push(.review(project.id)) } label: {
                                ProjectRow(project: project, plan: store.plans[project.id])
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projectRow")
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : Grid.u(3))
                            .animation(reduceMotion ? Motion.reduced : Motion.staggered(index), value: appeared)
                            .contextMenu {
                                Button(role: .destructive) { try? store.delete(project) } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Grid.margin)
                    .padding(.bottom, Grid.u(12))
                }
            }
        }
        .overlay(alignment: .bottom) {
            Button("Nuevo escaneo") {
                newName = "Vivienda \(store.projects.count + 1)"
                naming = true
            }
            .buttonStyle(PlanoButtonStyle())
            .accessibilityIdentifier("newScan")
            .padding(.horizontal, Grid.margin)
            .padding(.bottom, Grid.u(2))
        }
        .onAppear { appeared = true }
        .alert("Nuevo proyecto", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Escanear") { createProject() }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Grid.u(2)) {
            Rectangle()
                .stroke(Color.signal, lineWidth: 2)
                .frame(width: Grid.u(30), height: Grid.u(20)) // el rectángulo del match cut de la intro
            Text("Escanea tu primera vivienda").planoTitle(TypeScale.body)
            Text("Recorre cada estancia con el iPhone. Plano dibuja la planta y la exporta a DXF; IFC y PDF llegarán con el procesador de escritorio.")
                .font(PlanoFont.grotesk(TypeScale.caption, weight: 400))
                .foregroundStyle(Color.planoSecondary)
        }
        .padding(.horizontal, Grid.margin)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func createProject() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        do {
            let project = try store.create(name: name.isEmpty ? "Vivienda" : name)
            router.push(.scan(project.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProjectRow: View {
    var project: Project
    var plan: FloorPlan2D?

    var body: some View {
        HStack(spacing: Grid.u(2)) {
            FloorPlanThumbnail(plan: plan)
                .frame(width: Grid.u(12), height: Grid.u(12))
            VStack(alignment: .leading, spacing: Grid.u(1)) {
                Text(project.name).planoTitle(TypeScale.body).lineLimit(1)
                Text("\(project.rooms.count) ESTANCIAS · \(project.frameCount) FOTOS")
                    .planoMono(11)
                    .foregroundStyle(Color.planoSecondary)
                Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .planoMono(11)
                    .foregroundStyle(Color.planoSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.planoSecondary)
        }
        .padding(Grid.u(1))
        .overlay(Rectangle().stroke(Color.planoHairline, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
