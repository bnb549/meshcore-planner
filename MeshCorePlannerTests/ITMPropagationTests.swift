import XCTest
@testable import MeshCorePlanner

final class ITMPropagationTests: XCTestCase {
    func testNTIAReferenceLosses() throws {
        let cases = try referenceCases()
        let profiles = try referenceProfiles()
        XCTAssertEqual(cases.count, 5)
        XCTAssertEqual(profiles.count, cases.count)
        let expected = [207.65, 157.10, 178.53, 183.26, 218.91]
        for index in cases.indices {
            let row = cases[index]
            let profile = profiles[index]
            XCTAssertEqual(profile.count, Int(profile[0]) + 3, "Profile \(index) is not NTIA PFL length")
            let result = ITMBridge.pointToPoint(
                profile: profile,
                txHeightM: row.txHeightM,
                rxHeightM: row.rxHeightM,
                frequencyMHz: row.frequencyMHz,
                climate: row.climate,
                polarization: row.polarization,
                dielectric: row.dielectric,
                conductivity: row.conductivity,
                refractivity: row.refractivity,
                variabilityMode: row.variabilityMode,
                timePercent: row.timePercent,
                locationPercent: row.locationPercent,
                situationPercent: row.situationPercent
            )
            XCTAssertTrue(result.succeeded, "Case \(index) code \(result.errorCode)")
            XCTAssertEqual(result.lossDb, expected[index], accuracy: 0.05, "Case \(index)")
            XCTAssertEqual(result.lossDb, row.expectedLossDb, accuracy: 0.05, "Case \(index) CSV")
        }
    }

    func testFlatPathIsNearFreeSpace() async throws {
        let request = try link(distance: 10_000, height: 30, elevation: FixedElevation(meters: 100))
        let engine = ITMPropagationEngine(parameters: .meshCoreDefault, sampleSpacingM: 100)
        let result = try await engine.link(request.request, elevation: request.elevation)
        let freeSpace = PropagationMath.freeSpacePathLossDb(distanceM: result.distanceM, frequencyMHz: 910.525)
        XCTAssertEqual(result.engineName, "ITM (Longley-Rice)")
        XCTAssertFalse(result.usedFreeSpaceFallback)
        XCTAssertEqual(result.forward.pathLossDb, freeSpace, accuracy: 1.5)
        XCTAssertFalse(result.profile.isEmpty)
        XCTAssertLessThanOrEqual(result.profile[result.profile.count / 2].fresnel1AMSL, result.profile[result.profile.count / 2].losAMSL)
    }

    func testRidgeIncreasesLossAndDiffersFromSimplified() async throws {
        let flat = try link(distance: 10_000, height: 30, elevation: FixedElevation(meters: 100))
        let ridge = try link(distance: 10_000, height: 30, elevation: RidgeElevation(groundM: 100, crestM: 400, halfWidthM: 500))
        let itm = ITMPropagationEngine(parameters: .meshCoreDefault, sampleSpacingM: 100)
        let simplified = SimplifiedTerrainEngine()
        let itmFlat = try await itm.link(flat.request, elevation: flat.elevation)
        let itmRidge = try await itm.link(ridge.request, elevation: ridge.elevation)
        let simpleFlat = try await simplified.link(flat.request, elevation: flat.elevation)
        let simpleRidge = try await simplified.link(ridge.request, elevation: ridge.elevation)
        XCTAssertGreaterThan(itmRidge.forward.pathLossDb, itmFlat.forward.pathLossDb + 10)
        XCTAssertGreaterThan(simpleRidge.forward.pathLossDb, simpleFlat.forward.pathLossDb)
        XCTAssertTrue(simpleRidge.forward.obstructed)
        XCTAssertGreaterThan(abs(itmRidge.forward.pathLossDb - simpleRidge.forward.pathLossDb), 1)
        XCTAssertEqual(itmRidge.engineName, "ITM (Longley-Rice)")
        XCTAssertEqual(simpleRidge.engineName, "Simplified")
    }

    func testMissingElevationFallsBackWithoutThrowing() async throws {
        let request = try link(distance: 10_000, height: 10, elevation: FixedElevation(meters: nil))
        let engine = ITMPropagationEngine()
        let result = try await engine.link(request.request, elevation: request.elevation)
        XCTAssertTrue(result.usedFreeSpaceFallback)
        XCTAssertEqual(result.engineName, "Simplified")
        XCTAssertTrue(result.forward.pathLossDb.isFinite)

        let coverage = CoverageRequest(
            transmitter: radio(height: 10),
            maxRangeM: 2_000,
            receiverHeightM: 1.5,
            receiverGainDbi: 2,
            sensitivityDbm: -130,
            radialCount: 8,
            ringCount: 4,
            sampleSpacingM: 180
        )
        let grid = try await finishedGrid(engine.coverage(coverage, elevation: FixedElevation(meters: nil)))
        XCTAssertEqual(grid.engineName, "Simplified")
        XCTAssertTrue(grid.usedFreeSpaceFallback)
        XCTAssertFalse(grid.cells.isEmpty)
    }

    func testCoverageUsesITMWhenTerrainExists() async throws {
        let engine = ITMPropagationEngine(parameters: .meshCoreDefault, sampleSpacingM: 180)
        let request = CoverageRequest(
            transmitter: radio(height: 10),
            maxRangeM: 2_000,
            receiverHeightM: 1.5,
            receiverGainDbi: 2,
            sensitivityDbm: -130,
            radialCount: 8,
            ringCount: 4,
            sampleSpacingM: 180
        )
        let grid = try await finishedGrid(engine.coverage(request, elevation: FixedElevation(meters: 100)))
        XCTAssertEqual(grid.engineName, "ITM (Longley-Rice)")
        XCTAssertFalse(grid.usedFreeSpaceFallback)
        XCTAssertEqual(grid.cells.count, 32)
    }

    func testCoverageCancelStopsTheRun() async throws {
        let engine = ITMPropagationEngine(sampleSpacingM: 90)
        let request = CoverageRequest(
            transmitter: radio(height: 10),
            maxRangeM: 20_000,
            receiverHeightM: 1.5,
            receiverGainDbi: 2,
            sensitivityDbm: -130,
            radialCount: 36,
            ringCount: 24,
            sampleSpacingM: 90
        )
        let probe = CancelProbe()
        let stream = engine.coverage(request, elevation: HoldingElevation(probe: probe))
        let task = Task {
            for try await update in stream {
                probe.note(update)
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let started = Date()
        task.cancel()
        _ = try? await task.value
        try await Task.sleep(for: .milliseconds(400))
        let text = probe.snapshot()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, text)
        XCTAssertTrue(text.contains("sleep threw"), text)
        XCTAssertFalse(text.contains("slept"), text)
        XCTAssertFalse(text.contains("finished"), text)
    }

    private func link(
        distance: Double,
        height: Double,
        elevation: any ElevationProviding
    ) throws -> (request: LinkRequest, elevation: any ElevationProviding) {
        let start = Coordinate(latitude: 40, longitude: -105)
        let end = GeoMath.destination(from: start, bearingDeg: 90, distanceM: distance)
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
                txPowerDbm: 22,
                frequencyMHz: 910.525,
                antennaGainDbi: 2,
                cableLossDb: 0
            ),
            sensitivityDbm: -130
        )
        return (request, elevation)
    }

    private func radio(height: Double) -> RadioEndpoint {
        RadioEndpoint(
            latitude: 40,
            longitude: -105,
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

    private func referenceCases() throws -> [ReferenceCase] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/p2p.csv")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
        return try lines.map { line in
            let values = line.split(separator: ",").compactMap { Double($0) }
            guard values.count == 13 else { throw ParseError() }
            return ReferenceCase(
                txHeightM: values[0],
                rxHeightM: values[1],
                dielectric: values[2],
                conductivity: values[3],
                refractivity: values[4],
                frequencyMHz: values[5],
                polarization: Int32(values[6]),
                climate: Int32(values[7]),
                timePercent: values[8],
                locationPercent: values[9],
                situationPercent: values[10],
                variabilityMode: Int32(values[11]),
                expectedLossDb: values[12]
            )
        }
    }

    private func referenceProfiles() throws -> [[Double]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/pfls.csv")
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
        return lines.map { line in
            line.split(separator: ",").compactMap { Double($0) }
        }
    }
}

private struct ReferenceCase {
    var txHeightM: Double
    var rxHeightM: Double
    var dielectric: Double
    var conductivity: Double
    var refractivity: Double
    var frequencyMHz: Double
    var polarization: Int32
    var climate: Int32
    var timePercent: Double
    var locationPercent: Double
    var situationPercent: Double
    var variabilityMode: Int32
    var expectedLossDb: Double
}

private struct ParseError: Error {}

private struct FixedElevation: ElevationProviding {
    var meters: Double?

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        let samples = coordinates.map { _ in ElevationSample(elevationM: meters) }
        let status: ElevationStatus = meters == nil ? .unavailable : .cache
        return ElevationBatch(samples: samples, status: status)
    }
}

private struct RidgeElevation: ElevationProviding {
    var groundM: Double
    var crestM: Double
    var halfWidthM: Double

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        guard let first = coordinates.first, let last = coordinates.last else {
            return ElevationBatch(samples: [], status: .unavailable)
        }
        let midpoint = GeoMath.destination(
            from: first,
            bearingDeg: GeoMath.bearingDeg(from: first, to: last),
            distanceM: GeoMath.distanceM(from: first, to: last) / 2
        )
        let samples = coordinates.map { coordinate in
            let elevation = GeoMath.distanceM(from: coordinate, to: midpoint) <= halfWidthM ? crestM : groundM
            return ElevationSample(elevationM: elevation)
        }
        return ElevationBatch(samples: samples, status: .cache)
    }
}

private final class CancelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func note(_ update: CoverageUpdate) {
        lock.lock()
        switch update {
        case .progress(let fraction): lines.append("progress \(fraction)")
        case .finished: lines.append("finished cells")
        }
        lock.unlock()
    }

    func mark(_ text: String) {
        lock.lock()
        lines.append(text)
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: ", ")
    }
}

private struct HoldingElevation: ElevationProviding {
    var probe: CancelProbe

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        probe.mark("elevations \(coordinates.count) cancelled \(Task.isCancelled)")
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            probe.mark("sleep threw")
            throw error
        }
        probe.mark("slept")
        let samples = coordinates.map { _ in ElevationSample(elevationM: 100.0) }
        return ElevationBatch(samples: samples, status: .cache)
    }
}
