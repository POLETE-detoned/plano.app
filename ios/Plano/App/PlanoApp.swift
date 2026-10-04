import SwiftUI

@main
struct PlanoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .tint(.signal)
        }
    }
}

/// Las 6 pantallas: Intro, Proyectos, Escaneo, Revisión, Exportar y Ajustes.
enum Route: Hashable {
    case scan(UUID)
    case review(UUID)
    case export(UUID)
    case settings
}

/// Pila de navegación propia para controlar las transiciones (máscara + speed ramp).
final class Router: ObservableObject {
    @Published private(set) var stack: [Route] = []

    func push(_ route: Route) {
        withAnimation(Motion.screen) { stack.append(route) }
    }

    func pop() {
        guard !stack.isEmpty else { return }
        withAnimation(Motion.exit) { _ = stack.removeLast() }
    }

    func replaceTop(with route: Route) {
        withAnimation(Motion.screen) {
            if !stack.isEmpty { stack.removeLast() }
            stack.append(route)
        }
    }

    func popToRoot() {
        withAnimation(Motion.exit) { stack.removeAll() }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showIntro = true

    var body: some View {
        ZStack {
            Color.planoBackground.ignoresSafeArea()
            ProjectsView()
            ForEach(Array(router.stack.enumerated()), id: \.element) { index, route in
                screen(for: route)
                    .background(Color.planoBackground.ignoresSafeArea())
                    .transition(reduceMotion ? .opacity : .maskSlide)
                    .zIndex(Double(index + 1))
            }
            if showIntro && !settings.introSeen {
                IntroView {
                    settings.introSeen = true
                    withAnimation(Motion.curve(Motion.exit, reduceMotion: reduceMotion)) { showIntro = false }
                }
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .foregroundStyle(Color.planoForeground)
    }

    @ViewBuilder
    private func screen(for route: Route) -> some View {
        switch route {
        case .scan(let id): ScanScreen(projectId: id)
        case .review(let id): ReviewView(projectId: id)
        case .export(let id): ExportView(projectId: id)
        case .settings: SettingsView()
        }
    }
}
