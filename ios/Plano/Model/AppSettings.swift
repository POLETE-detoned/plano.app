import Foundation

enum LengthUnit: String, CaseIterable, Identifiable, Codable {
    case meters = "m"
    case feet = "ft"

    var id: String { rawValue }

    /// "4,20" en metros o "13' 9\"" en pies.
    func format(_ meters: Double, decimals: Int = 2) -> String {
        switch self {
        case .meters:
            return meters.formatted(.number.precision(.fractionLength(decimals)))
        case .feet:
            let totalInches = (meters / 0.0254).rounded()
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches) - feet * 12
            return "\(feet)' \(inches)\""
        }
    }
}

/// Una comprobación con medidor láser: lo que mide el láser frente a lo que da la app.
struct CalibrationSample: Identifiable, Codable, Hashable {
    var id = UUID()
    var laser: Double // m
    var app: Double // m
    var error: Double { app - laser }
}

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var units: LengthUnit { didSet { defaults.set(units.rawValue, forKey: "units") } }
    /// Tolerancia de ortogonalización en grados.
    @Published var orthoTolerance: Double { didSet { defaults.set(orthoTolerance, forKey: "orthoTolerance") } }
    /// Grosor de muro por defecto en metros (RoomPlan no lo mide).
    @Published var wallThickness: Double { didSet { defaults.set(wallThickness, forKey: "wallThickness") } }
    /// Activa malla clasificada y profundidad en la sesión AR de RoomPlan.
    @Published var enhancedAR: Bool { didSet { defaults.set(enhancedAR, forKey: "enhancedAR") } }
    /// Intervalo mínimo entre fotogramas de 48 MP (s).
    @Published var frameInterval: Double { didSet { defaults.set(frameInterval, forKey: "frameInterval") } }
    /// Desplazamiento (m) o giro (°) que dispara un fotograma nuevo.
    @Published var frameDistance: Double { didSet { defaults.set(frameDistance, forKey: "frameDistance") } }
    @Published var frameAngle: Double { didSet { defaults.set(frameAngle, forKey: "frameAngle") } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    @Published var introSeen: Bool { didSet { defaults.set(introSeen, forKey: "introSeen") } }
    @Published var calibration: [CalibrationSample] {
        didSet { defaults.set(try? JSONEncoder().encode(calibration), forKey: "calibration") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "units": LengthUnit.meters.rawValue,
            "orthoTolerance": 3.0,
            "wallThickness": 0.10,
            "enhancedAR": true,
            "frameInterval": 0.5,
            "frameDistance": 0.30,
            "frameAngle": 20.0,
            "sound": false,
            "introSeen": false,
        ])
        units = LengthUnit(rawValue: defaults.string(forKey: "units") ?? "") ?? .meters
        orthoTolerance = defaults.double(forKey: "orthoTolerance")
        wallThickness = defaults.double(forKey: "wallThickness")
        enhancedAR = defaults.bool(forKey: "enhancedAR")
        frameInterval = defaults.double(forKey: "frameInterval")
        frameDistance = defaults.double(forKey: "frameDistance")
        frameAngle = defaults.double(forKey: "frameAngle")
        sound = defaults.bool(forKey: "sound")
        introSeen = defaults.bool(forKey: "introSeen")
        calibration = defaults.data(forKey: "calibration")
            .flatMap { try? JSONDecoder().decode([CalibrationSample].self, from: $0) } ?? []
    }

    /// Error medio absoluto y máximo de la calibración, en metros.
    var calibrationSummary: (mean: Double, max: Double)? {
        let errors = calibration.map { abs($0.error) }
        guard !errors.isEmpty else { return nil }
        return (errors.reduce(0, +) / Double(errors.count), errors.max() ?? 0)
    }
}
