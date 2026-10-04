import XCTest
@testable import Plano

final class PlanoTests: XCTestCase {
    private var store: ProjectStore!
    private var project: Project!

    override func setUpWithError() throws {
        store = DemoData.makeStore()
        project = try XCTUnwrap(store.projects.first)
    }

    func testDemoPlanHasRoomGeometry() throws {
        let plan = try XCTUnwrap(store.plans[project.id])
        XCTAssertEqual(plan.walls.count, 4)
        XCTAssertEqual(plan.openings.count, 3)
        let lengths = plan.walls.map(\.length).sorted()
        XCTAssertEqual(lengths.first!, 3.10, accuracy: 0.001)
        XCTAssertEqual(lengths.last!, 4.20, accuracy: 0.001)
        XCTAssertTrue(plan.openings.allSatisfy { $0.wallId != nil }, "cada hueco debe tener muro")
    }

    func testQuickDXFHasLayersAndEntities() throws {
        let plan = try XCTUnwrap(store.plans[project.id])
        let dxf = QuickDXFWriter.dxf(for: plan)
        for layer in ["MUROS", "HUECOS", "COTAS", "TEXTOS"] {
            XCTAssertTrue(dxf.contains("\n\(layer)\n"), "falta la capa \(layer)")
        }
        XCTAssertTrue(dxf.contains("\nARC\n"), "falta el arco de la puerta")
        XCTAssertTrue(dxf.hasSuffix("0\nEOF\n"))
        XCTAssertTrue(dxf.contains("SAL\\U+00D3N"), "el nombre debe ir escapado para R12")
        try write(Data(dxf.utf8), name: "rapido.dxf")
    }

    func testPackageExport() throws {
        let dir = store.directory(for: project)
        let url = try PlanoPackageWriter.export(project: project, from: dir)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 200)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "debe ser un ZIP")
        try write(data, name: "demo.plano")
    }

    /// Copia el resultado fuera del simulador para que CI lo pase por el procesador Python.
    private func write(_ data: Data, name: String) throws {
        guard let out = ProcessInfo.processInfo.environment["PLANO_TEST_OUTPUT"], !out.isEmpty else { return }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name))
    }
}
