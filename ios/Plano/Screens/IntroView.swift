import SwiftUI

/// Intro (5 s, una sola vez): corte a negro, PLANO letra a letra con máscara vertical,
/// línea naranja que cruza en 600 ms y dibuja una habitación (trim 0→1 en 900 ms).
/// El rectángulo cierra la secuencia como *match cut* hacia la lista de proyectos.
struct IntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lettersIn = false
    @State private var lineProgress: CGFloat = 0
    @State private var roomProgress: CGFloat = 0
    @State private var finished = false

    private let word = Array("PLANO")
    private let letterHeight: CGFloat = 76

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(Palette.ink).ignoresSafeArea()

                VStack(spacing: Grid.u(4)) {
                    HStack(spacing: 0) {
                        ForEach(Array(word.enumerated()), id: \.offset) { index, letter in
                            Text(String(letter))
                                .font(PlanoFont.grotesk(TypeScale.display, weight: 700))
                                .tracking(TypeScale.tracking(TypeScale.display))
                                .foregroundStyle(Color(Palette.paper))
                                .offset(y: lettersIn ? 0 : letterHeight)
                                .frame(height: letterHeight)
                                .clipped() // máscara vertical
                                .animation(reduceMotion ? Motion.reduced : Motion.staggered(index), value: lettersIn)
                        }
                    }

                    Rectangle()
                        .fill(Color.signal)
                        .frame(width: geo.size.width * lineProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .trim(from: 0, to: roomProgress)
                        .stroke(Color.signal, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                        .frame(width: Grid.u(30), height: Grid.u(20))
                }
                .opacity(finished ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { finish() }
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plano")
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            withAnimation(Motion.reduced) {
                lettersIn = true
                lineProgress = 1
                roomProgress = 1
            }
            try? await Task.sleep(for: .seconds(1.2))
            finish()
            return
        }
        try? await Task.sleep(for: .milliseconds(250)) // corte seco a negro
        lettersIn = true
        try? await Task.sleep(for: .milliseconds(480 + 60 * word.count))
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.6)) { lineProgress = 1 }
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.9)) { roomProgress = 1 }
        try? await Task.sleep(for: .milliseconds(900 + 1500)) // pausa sobre el rectángulo
        finish()
    }

    private func finish() {
        guard !finished else { return }
        withAnimation(Motion.exit) { finished = true }
        onFinish()
    }
}
