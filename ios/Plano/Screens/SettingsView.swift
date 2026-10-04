import SwiftUI

/// Ajustes: unidades, tolerancia, captura y calibración con medidor láser.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: Router

    @State private var laser = ""
    @State private var app = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Ajustes", back: router.pop)
            Form {
                Section("Unidades") {
                    Picker("Unidades", selection: $settings.units) {
                        Text("Metros").tag(LengthUnit.meters)
                        Text("Pies").tag(LengthUnit.feet)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper(value: $settings.orthoTolerance, in: 0...10, step: 0.5) {
                        row("Tolerancia 90°", String(format: "%.1f°", settings.orthoTolerance))
                    }
                    Stepper(value: $settings.wallThickness, in: 0.05...0.50, step: 0.01) {
                        row("Grosor de muro", String(format: "%.2f m", settings.wallThickness))
                    }
                } header: {
                    Text("Plano")
                } footer: {
                    Text("Se usan en el procesador de escritorio (--tolerance, --wall-thickness).")
                }

                Section {
                    Toggle("Malla y profundidad ampliadas (experimental)", isOn: $settings.enhancedAR)
                    Stepper(value: $settings.frameInterval, in: 0.2...3, step: 0.1) {
                        row("Intervalo mínimo", String(format: "%.1f s", settings.frameInterval))
                    }
                    Stepper(value: $settings.frameDistance, in: 0.1...1, step: 0.05) {
                        row("Desplazamiento", String(format: "%.2f m", settings.frameDistance))
                    }
                    Stepper(value: $settings.frameAngle, in: 5...45, step: 5) {
                        row("Giro", String(format: "%.0f°", settings.frameAngle))
                    }
                } header: {
                    Text("Captura")
                } footer: {
                    Text("Se guarda una foto de 48 MP cuando pasa el intervalo y el móvil se ha movido o girado lo indicado. La malla ampliada relanza la sesión de RoomPlan y puede congelar la cámara: déjala apagada salvo para probar.")
                }

                Section {
                    if let summary = settings.calibrationSummary {
                        row("Error medio", String(format: "±%.1f cm", summary.mean * 100))
                        row("Error máximo", String(format: "±%.1f cm", summary.max * 100))
                        row("Objetivo", "±2,0 cm")
                    }
                    ForEach(settings.calibration) { sample in
                        row(String(format: "Láser %.3f m", sample.laser),
                            String(format: "%+.1f cm", sample.error * 100))
                    }
                    .onDelete { settings.calibration.remove(atOffsets: $0) }
                    HStack {
                        TextField("Láser (m)", text: $laser).keyboardType(.decimalPad)
                        TextField("App (m)", text: $app).keyboardType(.decimalPad)
                        Button("Añadir", action: addSample).disabled(parse(laser) == nil || parse(app) == nil)
                    }
                } header: {
                    Text("Calibración")
                } footer: {
                    Text("Mide 10 paredes de 3 a 5 m con un medidor láser y compara con la cota de Plano. El error real queda documentado aquí.")
                }

                Section("Otros") {
                    Toggle("Sonido en transiciones", isOn: $settings.sound)
                    Button("Ver la intro otra vez") { settings.introSeen = false }
                }
            }
            .scrollContentBackground(.hidden)
            .font(PlanoFont.grotesk(TypeScale.body, weight: 400))
        }
        .tint(.signal)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).planoMono(TypeScale.body).foregroundStyle(Color.planoSecondary)
        }
    }

    private func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func addSample() {
        guard let l = parse(laser), let a = parse(app) else { return }
        settings.calibration.append(CalibrationSample(laser: l, app: a))
        laser = ""
        app = ""
    }
}
