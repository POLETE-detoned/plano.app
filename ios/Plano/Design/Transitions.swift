import SwiftUI

extension Motion {
    /// Transición entre pantallas: 320 ms con speed ramp (rápido al inicio, frena al final).
    static let screen = Animation.timingCurve(0.12, 0.9, 0.2, 1, duration: 0.32)
}

/// Revela la pantalla con una máscara que crece desde el borde derecho y un leve desplazamiento.
private struct MaskSlide: ViewModifier, Animatable {
    var progress: CGFloat // 0 oculto, 1 visible

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: (1 - progress) * Grid.u(6))
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: geo.size.width * progress)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .ignoresSafeArea()
            )
    }
}

extension AnyTransition {
    static var maskSlide: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: MaskSlide(progress: 0), identity: MaskSlide(progress: 1)),
            removal: .modifier(active: MaskSlide(progress: 0), identity: MaskSlide(progress: 1))
        )
    }
}

/// Barra superior común: volver + título en mayúsculas.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Grid.u(2)) {
            if let back {
                Button(action: back) {
                    Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Volver")
                .accessibilityIdentifier("back")
            }
            Text(title)
                .planoTitle(TypeScale.body)
                .lineLimit(1)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Grid.margin)
        .frame(height: Grid.u(7))
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) {
        self.init(title: title, back: back) { EmptyView() }
    }
}
