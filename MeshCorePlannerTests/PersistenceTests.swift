import SwiftData
import XCTest
@testable import MeshCorePlanner

@MainActor
final class PersistenceTests: XCTestCase {
    func testSiteSurvivesContextReset() throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let siteID = UUID()
        try harness.useContainer { container in
            let site = PlannedSite(
                id: siteID,
                name: "North Ridge",
                latitude: 40.12345,
                longitude: -105.54321,
                antennaHeightM: 12,
                txPowerDbm: 22,
                frequencyMHz: 910.525,
                antennaGainDbi: 2,
                cableLossDb: 1,
                role: .repeater,
                isVisible: true,
                notes: "ridge line",
                hardwarePresetID: "heltec-v3-v4",
                radioPresetID: "us-canada"
            )
            container.mainContext.insert(site)
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let loaded = try XCTUnwrap(try fetchSite(id: siteID, in: container))
            XCTAssertEqual(loaded.name, "North Ridge")
            XCTAssertEqual(loaded.latitude, 40.12345, accuracy: 0.000001)
            XCTAssertEqual(loaded.longitude, -105.54321, accuracy: 0.000001)
            XCTAssertEqual(loaded.antennaHeightM, 12, accuracy: 0.001)
            XCTAssertEqual(loaded.txPowerDbm, 22, accuracy: 0.001)
            XCTAssertEqual(loaded.frequencyMHz, 910.525, accuracy: 0.0001)
            XCTAssertEqual(loaded.antennaGainDbi, 2, accuracy: 0.001)
            XCTAssertEqual(loaded.cableLossDb, 1, accuracy: 0.001)
            XCTAssertEqual(loaded.role, .repeater)
            XCTAssertTrue(loaded.isVisible)
            XCTAssertEqual(loaded.notes, "ridge line")
            XCTAssertEqual(loaded.hardwarePresetID, "heltec-v3-v4")
            XCTAssertEqual(loaded.radioPresetID, "us-canada")
        }
    }

    func testVisibilityToggleSurvivesReopen() throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let siteID = UUID()
        try harness.useContainer { container in
            container.mainContext.insert(PlannedSite(
                id: siteID,
                name: "Hidden Repeater",
                latitude: 41,
                longitude: -106,
                isVisible: true
            ))
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let hidden = try XCTUnwrap(try fetchSite(id: siteID, in: container))
            hidden.isVisible = false
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let stillHidden = try XCTUnwrap(try fetchSite(id: siteID, in: container))
            XCTAssertFalse(stillHidden.isVisible)
            stillHidden.isVisible = true
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let shown = try XCTUnwrap(try fetchSite(id: siteID, in: container))
            XCTAssertTrue(shown.isVisible)
        }
    }

    func testDeleteSurvivesReopen() throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let siteID = UUID()
        try harness.useContainer { container in
            let site = PlannedSite(id: siteID, name: "Temporary", latitude: 10, longitude: 20)
            container.mainContext.insert(site)
            try container.mainContext.save()
            container.mainContext.delete(site)
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let fetched = try container.mainContext.fetch(FetchDescriptor<PlannedSite>())
            XCTAssertFalse(fetched.contains { $0.id == siteID })
        }
    }

    func testPathSketchRoundTripsOrderedIDs() throws {
        let harness = try StoreHarness()
        defer { harness.cleanup() }
        let ids = [UUID(), UUID(), UUID()]
        let sketchID = UUID()
        try harness.useContainer { container in
            container.mainContext.insert(PathSketch(id: sketchID, name: "Valley hop", orderedSiteIDs: ids))
            try container.mainContext.save()
        }

        try harness.useContainer { container in
            let loaded = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<PathSketch>()).first { $0.id == sketchID })
            XCTAssertEqual(loaded.orderedSiteIDs, ids)
            XCTAssertEqual(loaded.name, "Valley hop")
        }
    }

    func testPresetsFillSiteFields() throws {
        let site = PlannedSite(
            name: "Bench",
            latitude: 1,
            longitude: 2,
            txPowerDbm: 0,
            frequencyMHz: 100,
            antennaGainDbi: 0,
            hardwarePresetID: nil,
            radioPresetID: nil
        )
        let heltec = try XCTUnwrap(PresetLibrary.hardware(id: "heltec-v3-v4"))
        site.apply(hardware: heltec)
        XCTAssertEqual(site.txPowerDbm, 22, accuracy: 0.001)
        XCTAssertEqual(site.antennaGainDbi, 2, accuracy: 0.001)
        XCTAssertEqual(site.hardwarePresetID, heltec.id)

        site.txPowerDbm = 21
        site.reconcilePresetIDs()
        XCTAssertEqual(site.hardwarePresetID, heltec.id)
        site.txPowerDbm = 5
        site.reconcilePresetIDs()
        XCTAssertNil(site.hardwarePresetID)

        let europe = try XCTUnwrap(PresetLibrary.radio(id: "eu-uk-narrow"))
        site.apply(radio: europe)
        XCTAssertEqual(site.frequencyMHz, 869.618, accuracy: 0.0001)
        XCTAssertEqual(site.radioPresetID, europe.id)
        site.frequencyMHz = 915
        site.reconcilePresetIDs()
        XCTAssertNil(site.radioPresetID)
    }

    func testGeoJSONOmitsHiddenSites() {
        let visible = PlannedSite(name: "Visible Ridge", latitude: 40, longitude: -105, isVisible: true)
        let hidden = PlannedSite(name: "Hidden Gulch", latitude: 41, longitude: -106, isVisible: false)
        let json = GeoJSONExporter.featureCollection(sites: [visible, hidden], grids: [:], sensitivityDbm: -130)
        XCTAssertTrue(json.contains("Visible Ridge"))
        XCTAssertFalse(json.contains("Hidden Gulch"))
    }

    private func fetchSite(id: UUID, in container: ModelContainer) throws -> PlannedSite? {
        try container.mainContext.fetch(FetchDescriptor<PlannedSite>()).first { $0.id == id }
    }
}

@MainActor
private struct StoreHarness {
    let directory: URL
    let storeURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("Planner.store")
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([PlannedSite.self, PlannedLink.self, PathSketch.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Opens one store, runs the body, then releases that container before the caller opens another.
    func useContainer(_ body: (ModelContainer) throws -> Void) throws {
        let container = try makeContainer()
        try body(container)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
