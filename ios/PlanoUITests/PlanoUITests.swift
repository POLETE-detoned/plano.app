import XCTest

/// Recorre las pantallas con datos de demostración y guarda una captura de cada una.
final class PlanoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-introSeen", "NO",
                               "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    func testTourOfScreens() throws {
        snap("01-intro", after: 1.2)

        let row = app.buttons["projectRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "la lista de proyectos no aparece")
        snap("02-proyectos", after: 1)

        row.tap()
        let export = app.buttons["exportButton"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "no se abre la revisión")
        snap("03-revision-2d", after: 2.5)

        app.buttons["3D"].firstMatch.tap()
        snap("04-revision-3d", after: 1.5)
        app.buttons["2D"].firstMatch.tap()

        export.tap()
        let generate = app.buttons["generatePackage"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5), "no se abre Exportar")
        snap("05-exportar", after: 1)
        generate.tap()
        XCTAssertTrue(app.buttons["sharePackage"].waitForExistence(timeout: 20), "no se genera el .plano")
        app.buttons["generateDXF"].firstMatch.tap()
        snap("06-exportado", after: 1)

        app.buttons["back"].firstMatch.tap() // a Revisión
        let addRoom = app.buttons["addRoom"]
        XCTAssertTrue(addRoom.waitForExistence(timeout: 5))
        addRoom.tap()
        snap("07-escaneo-simulador", after: 1.5) // sin LiDAR: debe mostrar el aviso, no cerrarse
        XCTAssertTrue(app.staticTexts["Este dispositivo no tiene LiDAR"].exists
                      || app.staticTexts["ESTE DISPOSITIVO NO TIENE LIDAR"].exists,
                      "en el simulador debería avisar de que no hay LiDAR")

        app.buttons["back"].firstMatch.tap() // a Revisión
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 5))
        app.buttons["back"].firstMatch.tap() // a Proyectos
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        snap("08-ajustes", after: 1)

        XCTAssertEqual(app.state, .runningForeground, "la app se ha cerrado")
    }

    private func snap(_ name: String, after seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
