import XCTest
@testable import MeshCorePlanner

final class PropagationTests: XCTestCase {
    func testFreeSpaceAtOneKilometer() {
        let loss = PropagationMath.freeSpacePathLossDb(distanceM: 1_000, frequencyMHz: 910.525)
        XCTAssertEqual(loss, 91.62, accuracy: 0.05)
    }

    func testDoublingDistanceAddsSixDecibels() {
        let near = PropagationMath.freeSpacePathLossDb(distanceM: 1_000, frequencyMHz: 910.525)
        let far = PropagationMath.freeSpacePathLossDb(distanceM: 2_000, frequencyMHz: 910.525)
        XCTAssertEqual(far - near, 6.02, accuracy: 0.05)
    }

    func testKnifeEdgeAtGrazingIsAboutSixDecibels() {
        XCTAssertEqual(PropagationMath.knifeEdgeLossDb(v: 0), 6, accuracy: 0.5)
        XCTAssertEqual(PropagationMath.knifeEdgeLossDb(v: -1), 0, accuracy: 0.001)
    }

    func testClearPathMatchesFreeSpaceOrTwoRay() async throws {
        let engine = SimplifiedTerrainEngine()
        let request = linkRequest(height: 10, distance: 5_000, elevation: 0)
        let result = try await engine.link(request.request, elevation: request.elevation)
        let expected = max(
            PropagationMath.freeSpacePathLossDb(distanceM: 5_000, frequencyMHz: 910.525),
            PropagationMath.twoRayLossDb(distanceM: 5_000, txHeightM: 10, rxHeightM: 10)
        )
        XCTAssertEqual(result.forward.pathLossDb, expected, accuracy: 1)
        XCTAssertFalse(result.forward.obstructed)
        XCTAssertEqual(
            result.forward.marginDb,
            result.forward.receivedPowerDbm - (-130),
            accuracy: 0.001
        )
    }

    func testRidgeAddsKnifeEdgeLoss() async throws {
        let engine = SimplifiedTerrainEngine()
        let flat = linkRequest(height: 10, distance: 10_000, elevation: 0)
        let ridge = linkRequest(height: 10, distance: 10_000, elevation: 200)
        let clear = try await engine.link(flat.request, elevation: flat.elevation)
        let blocked = try await engine.link(ridge.request, elevation: ridge.elevation)
        XCTAssertGreaterThan(blocked.forward.pathLossDb, clear.forward.pathLossDb + 6)
        XCTAssertTrue(blocked.forward.obstructed)
        XCTAssertGreaterThan(blocked.forward.knifeEdgeLossDb, 6)
    }

    func testZeroHeightDoesNotSampleElevation() async {
        let engine = SimplifiedTerrainEngine()
        var from = sampleEndpoint(latitude: 40, longitude: -105, height: 0)
        from.antennaHeightM = 0
        let request = LinkRequest(
            from: from,
            to: sampleEndpoint(latitude: 40.05, longitude: -105, height: 10),
            sensitivityDbm: -130
        )
        do {
            _ = try await engine.link(request, elevation: ExplodingElevation())
            XCTFail("Expected a height error")
        } catch let error as PropagationError {
            XCTAssertEqual(error, .invalidHeight)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testInvalidCoordinateDoesNotSampleElevation() async {
        let engine = SimplifiedTerrainEngine()
        let request = LinkRequest(
            from: sampleEndpoint(latitude: 120, longitude: -105, height: 10),
            to: sampleEndpoint(latitude: 40, longitude: -105, height: 10),
            sensitivityDbm: -130
        )
        do {
            _ = try await engine.link(request, elevation: ExplodingElevation())
            XCTFail("Expected a coordinate error")
        } catch let error as PropagationError {
            XCTAssertEqual(error, .invalidCoordinate)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCoverageAreaFillsTheDiskAndThresholdSplitsRange() async throws {
        let engine = SimplifiedTerrainEngine()
        let request = CoverageRequest(
            transmitter: sampleEndpoint(latitude: 40, longitude: -105, height: 10),
            maxRangeM: 10_000,
            receiverHeightM: 1.5,
            receiverGainDbi: 2,
            sensitivityDbm: -80
        )
        let grid = try await finishedGrid(engine.coverage(request, elevation: ScriptedElevation { _ in 0 }))
        let area = grid.cells.reduce(0.0) { $0 + $1.sectorAreaM2 }
        XCTAssertEqual(area, grid.diskAreaM2, accuracy: grid.diskAreaM2 * 0.001)
        let above = grid.cells.filter { $0.rssiDbm >= -80 }
        let below = grid.cells.filter { $0.rssiDbm < -80 }
        XCTAssertFalse(above.isEmpty)
        XCTAssertFalse(below.isEmpty)
        let stats = grid.statistics(sensitivityDbm: -80)
        XCTAssertGreaterThan(stats.areaAboveThresholdM2, 0)
        XCTAssertLessThan(stats.percentOfDisk, 100)
        XCTAssertGreaterThan(stats.percentOfDisk, 0)
        XCTAssertLessThan(stats.maxUsableRangeM, grid.maxRangeM)
        let everything = grid.statistics(sensitivityDbm: -200)
        XCTAssertEqual(everything.percentOfDisk, 100, accuracy: 0.1)
    }

    func testTerrariumURLHasNoSiteParameters() {
        let url = ElevationService.terrariumURL(z: 11, x: 123, y: 456)
        XCTAssertEqual(
            url.absoluteString,
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/11/123/456.png"
        )
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("dbm"))
        XCTAssertFalse(url.absoluteString.contains("name="))
        XCTAssertFalse(url.absoluteString.contains("latitude="))
    }

    func testRegionalAndHardwarePresets() throws {
        let us = try XCTUnwrap(PresetLibrary.radio(id: "us-canada"))
        XCTAssertEqual(us.frequencyMHz, 910.525, accuracy: 0.0001)
        XCTAssertEqual(us.bandwidthKHz, 62.5, accuracy: 0.01)
        XCTAssertEqual(us.spreadingFactor, 7)
        XCTAssertEqual(us.suggestedSensitivityDbm, -129)

        let wide = try XCTUnwrap(PresetLibrary.radio(id: "us-canada-wide"))
        XCTAssertEqual(wide.frequencyMHz, 910.525, accuracy: 0.0001)
        XCTAssertEqual(wide.bandwidthKHz, 250, accuracy: 0.01)
        XCTAssertEqual(wide.spreadingFactor, 7)

        let eu = try XCTUnwrap(PresetLibrary.radio(id: "eu-uk-narrow"))
        XCTAssertEqual(eu.frequencyMHz, 869.618, accuracy: 0.0001)
        XCTAssertEqual(eu.bandwidthKHz, 62.5, accuracy: 0.01)
        XCTAssertEqual(eu.spreadingFactor, 8)
        XCTAssertEqual(eu.suggestedSensitivityDbm, -132)

        let heltec = try XCTUnwrap(PresetLibrary.hardware(id: "heltec-v3-v4"))
        XCTAssertEqual(heltec.defaultTxPowerDbm, 22)
        XCTAssertEqual(heltec.defaultGainDbi, 2)
        XCTAssertEqual(heltec.minTxPowerDbm, 20)
        XCTAssertEqual(heltec.maxTxPowerDbm, 22)

        let rak = try XCTUnwrap(PresetLibrary.hardware(id: "rak4631-wisblock"))
        XCTAssertEqual(rak.minTxPowerDbm, 14)
        XCTAssertEqual(rak.maxTxPowerDbm, 22)
        XCTAssertEqual(rak.defaultGainDbi, 2)

        let lily = try XCTUnwrap(PresetLibrary.hardware(id: "lilygo-tbeam-techo"))
        XCTAssertEqual(lily.defaultTxPowerDbm, 20)
        XCTAssertEqual(lily.defaultGainDbi, 2)

        let station = try XCTUnwrap(PresetLibrary.hardware(id: "station-g2"))
        XCTAssertEqual(station.defaultTxPowerDbm, 27)
        XCTAssertEqual(station.maxTxPowerDbm, 30)
        XCTAssertEqual(station.minGainDbi, 2)
        XCTAssertEqual(station.maxGainDbi, 5)
    }

    private func linkRequest(height: Double, distance: Double, elevation: Double) -> (request: LinkRequest, elevation: ScriptedElevation) {
        let start = Coordinate(latitude: 40, longitude: -105)
        let end = GeoMath.destination(from: start, bearingDeg: 90, distanceM: distance)
        let midpoint = GeoMath.destination(from: start, bearingDeg: 90, distanceM: distance / 2)
        let scripted = ScriptedElevation { coordinate in
            if elevation == 0 { return 0 }
            return GeoMath.distanceM(from: coordinate, to: midpoint) < 400 ? elevation : 0
        }
        let request = LinkRequest(
            from: RadioEndpoint(
                latitude: start.latitude,
                longitude: start.longitude,
                antennaHeightM: height,
                txPowerDbm: 22,
                frequencyMHz: 910.525,
                antennaGainDbi: 2,
                cableLossDb: 0
            ),
            to: RadioEndpoint(
                latitude: end.latitude,
                longitude: end.longitude,
                antennaHeightM: height,
                txPowerDbm: 14,
                frequencyMHz: 910.525,
                antennaGainDbi: 2,
                cableLossDb: 0
            ),
            sensitivityDbm: -130
        )
        return (request, scripted)
    }

    private func sampleEndpoint(latitude: Double, longitude: Double, height: Double) -> RadioEndpoint {
        RadioEndpoint(
            latitude: latitude,
            longitude: longitude,
            antennaHeightM: height,
            txPowerDbm: 22,
            frequencyMHz: 910.525,
            antennaGainDbi: 2,
            cableLossDb: 0
        )
    }

    private func finishedGrid(_ stream: AsyncThrowingStream<CoverageUpdate, Error>) async throws -> CoverageGrid {
        var grid: CoverageGrid?
        for try await update in stream {
            if case .finished(let value) = update {
                grid = value
            }
        }
        return try XCTUnwrap(grid)
    }
}

private struct ScriptedElevation: ElevationProviding {
    var resolver: @Sendable (Coordinate) -> Double?

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        let samples = coordinates.map { ElevationSample(elevationM: resolver($0)) }
        let any = samples.contains { $0.elevationM != nil }
        let missing = samples.contains { $0.elevationM == nil }
        let status: ElevationStatus = !any ? .unavailable : (missing ? .partial : .cache)
        return ElevationBatch(samples: samples, status: status)
    }
}

private struct ExplodingElevation: ElevationProviding {
    struct Called: Error {}

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        throw Called()
    }
}
