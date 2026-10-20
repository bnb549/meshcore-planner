import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MeshCorePlanner

final class QualityPackTests: XCTestCase {
    func testClutterAddsExpectedDecibelsForTreeCover() {
        let table = ClutterTable.meshCoreDefault
        let tree = table.setting(for: 10)
        XCTAssertEqual(tree?.attenuationDbPerMeter ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(tree?.maxLossDb ?? 0, 20, accuracy: 0.001)
        let points = [
            PathPoint(distanceM: 0, elevationM: 100, landCoverCode: 10),
            PathPoint(distanceM: 100, elevationM: 100, landCoverCode: 10)
        ]
        let result = ClutterMath.loss(
            points: points,
            txAntennaHeightM: 2,
            rxAntennaHeightM: 2,
            frequencyMHz: 900,
            table: table
        )
        XCTAssertEqual(result.lossDb, 2, accuracy: 0.05)
        XCTAssertTrue(result.summary.localizedCaseInsensitiveContains("tree"))
        XCTAssertFalse(result.incomplete)
    }

    func testSuburbanDefaultsStayInsideFiveToThirtyFiveDecibels() {
        let table = ClutterTable.meshCoreDefault
        XCTAssertEqual(table.setting(for: 50)?.attenuationDbPerMeter ?? 0, 0.01, accuracy: 0.0001)
        XCTAssertEqual(table.setting(for: 50)?.maxLossDb ?? 0, 18, accuracy: 0.001)
        XCTAssertEqual(table.setting(for: 30)?.attenuationDbPerMeter ?? -1, 0.01, accuracy: 0.0001)
        XCTAssertEqual(table.setting(for: 60)?.attenuationDbPerMeter ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(table.setting(for: 80)?.attenuationDbPerMeter ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(table.setting(for: 95)?.attenuationDbPerMeter ?? -1, 0.35, accuracy: 0.0001)
        XCTAssertEqual(ClutterTable.maxTotalLossDb, 35, accuracy: 0.001)
        XCTAssertLessThan(table.setting(for: 10)?.maxLossDb ?? 99, table.setting(for: 20)?.maxLossDb ?? 0)
        XCTAssertLessThan(table.setting(for: 50)?.maxLossDb ?? 99, table.setting(for: 95)?.maxLossDb ?? 0)

        // 4 km: 600 m trees + 800 m built-up + grass. 12 dB + 8 dB.
        let suburb = clutterLoss(mixedPath(treeM: 600, builtM: 800, openM: 2_600), table: table)
        XCTAssertEqual(suburb.lossDb, 20, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(suburb.lossDb, 5)
        XCTAssertLessThanOrEqual(suburb.lossDb, 35)

        // 2 km light cover: 200 m trees + 300 m built-up.
        let light = clutterLoss(mixedPath(treeM: 200, builtM: 300, openM: 1_500), table: table)
        XCTAssertEqual(light.lossDb, 7, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(light.lossDb, 5)
        XCTAssertLessThanOrEqual(light.lossDb, 35)

        // 8 km: each class hits its own cap, then the 35 dB path cap.
        let longer = clutterLoss(mixedPath(treeM: 2_000, builtM: 2_000, openM: 4_000), table: table)
        XCTAssertEqual(longer.lossDb, 35, accuracy: 0.05)
        XCTAssertTrue(longer.summary.localizedCaseInsensitiveContains("path cap"))
    }

    func testLongTreePathDoesNotExceedTheClassCap() {
        let table = ClutterTable.meshCoreDefault
        let cap = table.setting(for: 10)?.maxLossDb ?? -1
        let oneSegment = clutterLoss([
            PathPoint(distanceM: 0, elevationM: 100, landCoverCode: 10),
            PathPoint(distanceM: 50_000, elevationM: 100, landCoverCode: 10)
        ], table: table)
        XCTAssertEqual(oneSegment.lossDb, cap, accuracy: 0.05)
        XCTAssertLessThan(oneSegment.lossDb, 100)

        let many = clutterLoss(
            stride(from: 0.0, through: 50_000, by: 250).map {
                PathPoint(distanceM: $0, elevationM: 100, landCoverCode: 10)
            },
            table: table
        )
        XCTAssertEqual(many.lossDb, cap, accuracy: 0.05)
        XCTAssertLessThanOrEqual(many.lossDb, ClutterTable.maxTotalLossDb)
    }

    func testSavedClutterTableKeepsCustomRates() throws {
        let json = """
        {"classes":[
          {"code":10,"name":"Tree cover","attenuationDbPerMeter":0.4,"heightM":15},
          {"code":50,"name":"Built-up","attenuationDbPerMeter":0.55,"heightM":9}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClutterTable.self, from: json)
        let merged = decoded.mergingMissingDefaults()
        XCTAssertEqual(merged.setting(for: 10)?.attenuationDbPerMeter ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(merged.setting(for: 10)?.heightM ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(merged.setting(for: 50)?.attenuationDbPerMeter ?? 0, 0.55, accuracy: 0.0001)
        XCTAssertEqual(merged.setting(for: 50)?.heightM ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(merged.setting(for: 10)?.maxLossDb ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(merged.setting(for: 50)?.maxLossDb ?? 0, 18, accuracy: 0.001)
        XCTAssertNotEqual(
            merged.setting(for: 10)?.attenuationDbPerMeter,
            ClutterTable.meshCoreDefault.setting(for: 10)?.attenuationDbPerMeter
        )
        XCTAssertEqual(merged.setting(for: 30)?.attenuationDbPerMeter ?? -1, 0.01, accuracy: 0.0001)

        let capped = clutterLoss([
            PathPoint(distanceM: 0, elevationM: 50, landCoverCode: 10),
            PathPoint(distanceM: 10_000, elevationM: 50, landCoverCode: 10)
        ], table: merged)
        XCTAssertEqual(capped.lossDb, 20, accuracy: 0.05)

        let encoded = try JSONDecoder().decode(ClutterTable.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(encoded.setting(for: 10)?.attenuationDbPerMeter ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(encoded.setting(for: 10)?.maxLossDb ?? 0, 20, accuracy: 0.001)
    }

    func testClutterSkipsARayAboveTheCanopy() {
        let points = [
            PathPoint(distanceM: 0, elevationM: 100, landCoverCode: 10),
            PathPoint(distanceM: 100, elevationM: 100, landCoverCode: 10)
        ]
        let result = ClutterMath.loss(
            points: points,
            txAntennaHeightM: 40,
            rxAntennaHeightM: 40,
            frequencyMHz: 900,
            table: .meshCoreDefault
        )
        XCTAssertEqual(result.lossDb, 0, accuracy: 0.001)
    }

    func testIncludingClutterChangesLinkLossAndDisablingRestoresIt() async throws {
        let request = radioLink(distance: 200, height: 2, frequency: 900)
        let elevation = FixedElevation(meters: 100)
        let plain = SimplifiedTerrainEngine()
        let withClutter = SimplifiedTerrainEngine(options: SimulationOptions(
            includeClutter: true,
            clutterTable: .meshCoreDefault,
            landCover: FixedLandCover(code: 10)
        ))
        let off = try await plain.link(request, elevation: elevation)
        let on = try await withClutter.link(request, elevation: elevation)
        XCTAssertEqual(on.forward.pathLossDb - off.forward.pathLossDb, on.clutterLossDb, accuracy: 0.05)
        XCTAssertEqual(on.clutterLossDb, 4, accuracy: 0.2)
        XCTAssertGreaterThan(off.forward.marginDb, on.forward.marginDb + 3)
        XCTAssertEqual(off.engineName, "Simplified")
        XCTAssertEqual(on.engineName, "Simplified + clutter")
        XCTAssertTrue(on.clutterSummary?.localizedCaseInsensitiveContains("tree") == true)

        let disabled = SimplifiedTerrainEngine(options: SimulationOptions(includeClutter: false, landCover: FixedLandCover(code: 10)))
        let restored = try await disabled.link(request, elevation: elevation)
        XCTAssertEqual(restored.forward.pathLossDb, off.forward.pathLossDb, accuracy: 0.01)
        XCTAssertEqual(restored.clutterLossDb, 0, accuracy: 0.001)
    }

    func testDisablingClutterMatchesPureITM() async throws {
        let request = radioLink(distance: 4_000, height: 2, frequency: 900)
        let elevation = FixedElevation(meters: 100)
        let pure = ITMPropagationEngine()
        let off = ITMPropagationEngine(options: SimulationOptions(
            includeClutter: false,
            clutterTable: .meshCoreDefault,
            landCover: FixedLandCover(code: 10)
        ))
        let on = ITMPropagationEngine(options: SimulationOptions(
            includeClutter: true,
            clutterTable: .meshCoreDefault,
            landCover: FixedLandCover(code: 10)
        ))
        let baseline = try await pure.link(request, elevation: elevation)
        let restored = try await off.link(request, elevation: elevation)
        let cluttered = try await on.link(request, elevation: elevation)
        XCTAssertEqual(baseline.engineName, "ITM (Longley-Rice)")
        XCTAssertEqual(restored.engineName, "ITM (Longley-Rice)")
        XCTAssertEqual(restored.forward.pathLossDb, baseline.forward.pathLossDb, accuracy: 0.01)
        XCTAssertEqual(restored.reverse.pathLossDb, baseline.reverse.pathLossDb, accuracy: 0.01)
        XCTAssertEqual(restored.clutterLossDb, 0, accuracy: 0.001)
        XCTAssertFalse(baseline.usedFreeSpaceFallback)
        XCTAssertEqual(cluttered.engineName, "ITM + clutter")
        XCTAssertEqual(cluttered.forward.pathLossDb - baseline.forward.pathLossDb, cluttered.clutterLossDb, accuracy: 0.05)
        XCTAssertGreaterThan(cluttered.clutterLossDb, 0)
        XCTAssertLessThanOrEqual(cluttered.clutterLossDb, ClutterTable.maxTotalLossDb)
    }

    func testFresnelRadiusMatchesTheStandardFormula() {
        let frequency = 915.0
        let d1 = 4_000.0
        let d2 = 6_000.0
        let lambda = PropagationMath.wavelengthM(frequencyMHz: frequency)
        let expected = sqrt(lambda * d1 * d2 / (d1 + d2))
        XCTAssertEqual(
            PropagationMath.firstFresnelRadiusM(distance1M: d1, distance2M: d2, frequencyMHz: frequency),
            expected,
            accuracy: 0.001
        )
    }

    func testFresnelClearanceSignFollowsTheTerrain() {
        let clear = PropagationMath.propagationLoss(
            points: flatPoints(distance: 10_000, elevation: 0),
            txAntennaHeightM: 80,
            rxAntennaHeightM: 80,
            frequencyMHz: 900,
            includeProfile: true
        )
        let blocked = PropagationMath.propagationLoss(
            points: flatPoints(distance: 10_000, elevation: 0),
            txAntennaHeightM: 1,
            rxAntennaHeightM: 1,
            frequencyMHz: 900,
            includeProfile: true
        )
        let clearWorst = worstClearance(clear.profile)
        let blockedWorst = worstClearance(blocked.profile)
        XCTAssertGreaterThan(clearWorst, 0)
        XCTAssertLessThan(blockedWorst, 0)
        XCTAssertEqual(clear.profile.first { $0.fresnelClearanceM == clearWorst }?.fresnelBand, .clear)
        XCTAssertEqual(blocked.profile.first { abs($0.fresnelClearanceM - blockedWorst) < 0.001 }?.fresnelBand, .blocked)
        XCTAssertTrue(PropagationMath.fresnelClearanceLabel(profile: clear.profile).contains("+"))
        XCTAssertTrue(PropagationMath.fresnelClearanceLabel(profile: blocked.profile).contains("-"))
    }

    func testMultiEdgeExceedsFreeSpaceOnADoubleRidge() {
        let points = [
            PathPoint(distanceM: 0, elevationM: 0),
            PathPoint(distanceM: 2_000, elevationM: 0),
            PathPoint(distanceM: 4_000, elevationM: 220),
            PathPoint(distanceM: 6_000, elevationM: 0),
            PathPoint(distanceM: 8_000, elevationM: 220),
            PathPoint(distanceM: 10_000, elevationM: 0)
        ]
        let single = PropagationMath.propagationLoss(
            points: points,
            txAntennaHeightM: 10,
            rxAntennaHeightM: 10,
            frequencyMHz: 900,
            includeProfile: false,
            diffraction: .dominantEdge
        )
        let multi = PropagationMath.propagationLoss(
            points: points,
            txAntennaHeightM: 10,
            rxAntennaHeightM: 10,
            frequencyMHz: 900,
            includeProfile: false,
            diffraction: .multiEdge
        )
        let freeSpace = PropagationMath.freeSpacePathLossDb(distanceM: 10_000, frequencyMHz: 900)
        XCTAssertGreaterThan(multi.pathLossDb, freeSpace)
        XCTAssertGreaterThan(multi.pathLossDb, single.pathLossDb)
        XCTAssertTrue(multi.obstructed)
    }

    func testMultiEdgeLeavesAClearPathOnFreeSpaceOrTwoRay() {
        let points = flatPoints(distance: 10_000, elevation: 0)
        let multi = PropagationMath.propagationLoss(
            points: points,
            txAntennaHeightM: 10,
            rxAntennaHeightM: 10,
            frequencyMHz: 910.525,
            includeProfile: false,
            diffraction: .multiEdge
        )
        let expected = max(
            PropagationMath.freeSpacePathLossDb(distanceM: 10_000, frequencyMHz: 910.525),
            PropagationMath.twoRayLossDb(distanceM: 10_000, txHeightM: 10, rxHeightM: 10)
        )
        XCTAssertEqual(multi.pathLossDb, expected, accuracy: 1)
        XCTAssertFalse(multi.obstructed)
        XCTAssertEqual(multi.knifeEdgeLossDb, 0, accuracy: 0.001)
    }

    func testComparisonReportsMeanMaxAndArea() {
        let primary = CoverageGrid(
            cells: [
                cell(id: 0, rssi: -70, area: 1_000),
                cell(id: 1, rssi: -90, area: 4_000)
            ],
            maxRangeM: 1_000,
            elevationStatus: .cache,
            usedFreeSpaceFallback: false,
            engineName: "ITM (Longley-Rice)"
        )
        let secondary = CoverageGrid(
            cells: [
                cell(id: 0, rssi: -80, area: 1_000),
                cell(id: 1, rssi: -92, area: 4_000)
            ],
            maxRangeM: 1_000,
            elevationStatus: .cache,
            usedFreeSpaceFallback: false,
            engineName: "Simplified"
        )
        let stats = CoverageComparisonMath.compare(primary: primary, secondary: secondary, thresholdDb: 6)
        XCTAssertEqual(stats.meanDeltaDb, 6, accuracy: 0.001)
        XCTAssertEqual(stats.maxAbsDeltaDb, 10, accuracy: 0.001)
        XCTAssertEqual(stats.areaBeyondThresholdM2, 1_000, accuracy: 0.001)
        XCTAssertEqual(stats.comparedCells, 2)
    }

    func testAdaptiveSamplesAreDenserNearTheTransmitter() {
        let total = 9_000.0
        let coarse = stride(from: 0.0, through: total, by: 1_000).map { PathPoint(distanceM: $0, elevationM: 100) }
        let samples = PropagationMath.adaptiveSampleDistances(total: total, coarse: coarse, spacing: 300, maxCount: 160)
        XCTAssertEqual(samples.first ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(samples.last ?? -1, total, accuracy: 0.001)
        let near = zip(samples, samples.dropFirst()).filter { $0.0 <= total * 0.15 }
        let nearGap = near.map { $0.1 - $0.0 }.min() ?? 999
        XCTAssertLessThanOrEqual(nearGap, 101)
        let far = zip(samples, samples.dropFirst()).filter { $0.0 > total * 0.5 }
        let farGap = far.map { $0.1 - $0.0 }.max() ?? 0
        XCTAssertGreaterThan(farGap, nearGap)
    }

    func testWorldCoverURLHasNoSiteParameters() {
        let url = LandCoverService.tileURL(z: 13, x: 1364, y: 2488)
        let text = url.absoluteString
        XCTAssertTrue(text.contains("esa-worldcover-map-10m-2021-v2_map"))
        XCTAssertTrue(text.contains("TILEMATRIX=13"))
        XCTAssertTrue(text.contains("TILECOL=1364"))
        XCTAssertTrue(text.contains("TILEROW=2488"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("dbm"))
        XCTAssertFalse(text.contains("latitude="))
        XCTAssertFalse(text.contains("name="))
    }

    func testClassifierUsesTheOfficialPalette() {
        XCTAssertEqual(LandCoverClassifier.code(red: 0, green: 100, blue: 0), 10)
        XCTAssertEqual(LandCoverClassifier.code(red: 250, green: 0, blue: 0), 50)
        XCTAssertEqual(LandCoverClassifier.code(red: 255, green: 255, blue: 76), 30)
        XCTAssertNil(LandCoverClassifier.code(red: 12, green: 12, blue: 12))
    }

    func testOfflineLandCoverUsesCacheAndWarnsWhenMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinate = Coordinate(latitude: 40, longitude: -105)
        let index = LandCoverService.tileIndex(for: coordinate)
        let file = LandCoverService.cacheURL(root: root, z: index.tile.z, x: index.tile.x, y: index.tile.y)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try treePNG().write(to: file)

        let session = offlineSession()
        let cached = LandCoverService(cacheRoot: root, session: session)
        let hit = try await cached.classes(at: [coordinate])
        XCTAssertEqual(hit.status, .cache)
        XCTAssertEqual(hit.codes.first ?? nil, 10)

        let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missing = LandCoverService(cacheRoot: emptyRoot, session: session)
        let miss = try await missing.classes(at: [coordinate])
        XCTAssertEqual(miss.status, .unavailable)
        XCTAssertNil(miss.codes.first ?? nil)
    }

    func testFineElevationMissFallsBackWithoutDisablingCoarseTiles() {
        XCTAssertEqual(ElevationService.terrainTileError(statusCode: 404, zoom: 12), .missing)
        XCTAssertEqual(ElevationService.terrainTileError(statusCode: 404, zoom: 11), .rejected)
        XCTAssertEqual(ElevationService.terrainTileError(statusCode: 401, zoom: 12), .rejected)
        XCTAssertNil(ElevationService.terrainTileError(statusCode: 200, zoom: 12))
    }

    func testConfidenceDropsWhenSamplesAreCoarseOrTerrainIsPartial() {
        let high = PlanningConfidence.itm(
            sampleSpacingM: 45,
            timePercent: 50,
            locationPercent: 50,
            situationPercent: 50,
            elevationStatus: .cache,
            resolutionReduced: false
        )
        let coarse = PlanningConfidence.itm(
            sampleSpacingM: 400,
            timePercent: 50,
            locationPercent: 50,
            situationPercent: 50,
            elevationStatus: .cache,
            resolutionReduced: false
        )
        let partial = PlanningConfidence.itm(
            sampleSpacingM: 45,
            timePercent: 50,
            locationPercent: 50,
            situationPercent: 50,
            elevationStatus: .partial,
            resolutionReduced: false
        )
        XCTAssertEqual(high, .high)
        XCTAssertEqual(coarse, .low)
        XCTAssertEqual(partial, .medium)
    }

    private func clutterLoss(_ points: [PathPoint], table: ClutterTable) -> ClutterLossResult {
        ClutterMath.loss(
            points: points,
            txAntennaHeightM: 2,
            rxAntennaHeightM: 2,
            frequencyMHz: 900,
            table: table
        )
    }

    /// Tree, then built-up, then grassland. The segment class is the class at its start.
    private func mixedPath(treeM: Double, builtM: Double, openM: Double) -> [PathPoint] {
        let builtStart = treeM
        let openStart = treeM + builtM
        let end = openStart + openM
        return [
            PathPoint(distanceM: 0, elevationM: 100, landCoverCode: 10),
            PathPoint(distanceM: builtStart, elevationM: 100, landCoverCode: 50),
            PathPoint(distanceM: openStart, elevationM: 100, landCoverCode: 30),
            PathPoint(distanceM: end, elevationM: 100, landCoverCode: 30)
        ]
    }

    private func flatPoints(distance: Double, elevation: Double) -> [PathPoint] {
        stride(from: 0.0, through: distance, by: distance / 8).map {
            PathPoint(distanceM: $0, elevationM: elevation)
        }
    }

    private func worstClearance(_ profile: [ProfileSample]) -> Double {
        let total = profile.last?.distanceM ?? 0
        let interior = profile.filter { $0.distanceM > 1 && total - $0.distanceM > 1 }
        return interior.map(\.fresnelClearanceM).min() ?? 0
    }

    private func radioLink(distance: Double, height: Double, frequency: Double) -> LinkRequest {
        let start = Coordinate(latitude: 40, longitude: -105)
        let end = GeoMath.destination(from: start, bearingDeg: 90, distanceM: distance)
        func radio(_ coordinate: Coordinate) -> RadioEndpoint {
            RadioEndpoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                antennaHeightM: height,
                txPowerDbm: 20,
                frequencyMHz: frequency,
                antennaGainDbi: 2,
                cableLossDb: 0
            )
        }
        return LinkRequest(from: radio(start), to: radio(end), sensitivityDbm: -130)
    }

    private func cell(id: Int, rssi: Double, area: Double) -> CoverageCell {
        CoverageCell(
            id: id,
            innerRadiusM: 0,
            outerRadiusM: 1_000,
            startBearingDeg: Double(id) * 10,
            endBearingDeg: Double(id) * 10 + 10,
            rssiDbm: rssi,
            sectorAreaM2: area,
            polygon: []
        )
    }

    private func offlineSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineFailureProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func treePNG() -> Data {
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            pixels[index * 4] = 0
            pixels[index * 4 + 1] = 100
            pixels[index * 4 + 2] = 0
            pixels[index * 4 + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: bitmap
        ), let image = context.makeImage() else {
            return Data()
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

private struct FixedElevation: ElevationProviding {
    var meters: Double

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        ElevationBatch(samples: coordinates.map { _ in ElevationSample(elevationM: meters) }, status: .cache)
    }
}

private struct FixedLandCover: LandCoverProviding {
    var code: Int

    func classes(at coordinates: [Coordinate]) async throws -> LandCoverBatch {
        LandCoverBatch(codes: coordinates.map { _ in code }, status: .cache)
    }
}

private final class OfflineFailureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
