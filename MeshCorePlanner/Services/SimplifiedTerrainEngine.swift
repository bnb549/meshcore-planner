import Foundation

/// Terrain-aware planner: free-space loss, two-ray height loss on a clear path,
/// and one knife edge when sampled ground blocks the chord. Optional multi-edge
/// diffraction sums Epstein-Peterson knife edges. Clutter, when enabled, is added
/// after that loss. Swap this type for an ITM engine by conforming to `PropagationEngine`.
nonisolated struct SimplifiedTerrainEngine: PropagationEngine {
    var options: SimulationOptions

    init(options: SimulationOptions = SimulationOptions()) {
        self.options = options
    }

    func freeSpacePathLossDb(distanceM: Double, frequencyMHz: Double) -> Double {
        PropagationMath.freeSpacePathLossDb(distanceM: distanceM, frequencyMHz: frequencyMHz)
    }

    func link(_ request: LinkRequest, elevation: any ElevationProviding) async throws -> LinkResult {
        try PropagationMath.validate(endpoint: request.from)
        try PropagationMath.validate(endpoint: request.to)
        let start = request.from.coordinate
        let end = request.to.coordinate
        let distance = max(GeoMath.distanceM(from: start, to: end), 1)
        let bearing = GeoMath.bearingDeg(from: start, to: end)
        let sampled = try await samplePath(
            start: start,
            end: end,
            distance: distance,
            bearing: bearing,
            spacing: 250,
            maxCount: 160,
            elevation: elevation
        )
        let diffraction: DiffractionMode = options.multiEdgeDiffraction ? .multiEdge : .dominantEdge
        let forwardGeo = PropagationMath.propagationLoss(
            points: sampled.points,
            txAntennaHeightM: request.from.antennaHeightM,
            rxAntennaHeightM: request.to.antennaHeightM,
            frequencyMHz: request.from.frequencyMHz,
            includeProfile: true,
            diffraction: diffraction
        )
        let reversePoints = PropagationMath.reversed(sampled.points)
        let reverseGeo = PropagationMath.propagationLoss(
            points: reversePoints,
            txAntennaHeightM: request.to.antennaHeightM,
            rxAntennaHeightM: request.from.antennaHeightM,
            frequencyMHz: request.to.frequencyMHz,
            includeProfile: false,
            diffraction: diffraction
        )
        let forwardClutter = clutter(for: sampled.points, txHeight: request.from.antennaHeightM, rxHeight: request.to.antennaHeightM, frequency: request.from.frequencyMHz)
        let reverseClutter = clutter(for: reversePoints, txHeight: request.to.antennaHeightM, rxHeight: request.from.antennaHeightM, frequency: request.to.frequencyMHz)
        let clutterSummary = forwardClutter.lossDb >= reverseClutter.lossDb ? forwardClutter.summary : reverseClutter.summary
        let incomplete = options.includeClutter && (forwardClutter.incomplete || reverseClutter.incomplete || sampled.landCoverIncomplete)
        return LinkResult(
            distanceM: distance,
            bearingFromToDeg: bearing,
            bearingToFromDeg: GeoMath.bearingDeg(from: end, to: start),
            forward: directional(tx: request.from, rx: request.to, loss: forwardGeo, extraLossDb: forwardClutter.lossDb, sensitivity: request.sensitivityDbm),
            reverse: directional(tx: request.to, rx: request.from, loss: reverseGeo, extraLossDb: reverseClutter.lossDb, sensitivity: request.sensitivityDbm),
            profile: forwardGeo.profile,
            usedFreeSpaceFallback: forwardGeo.usedFreeSpaceFallback,
            engineName: EngineTitle.name(model: .simplified, clutter: options.includeClutter, multiEdge: options.multiEdgeDiffraction, fallback: false),
            modelNote: simplifiedNote(fallback: forwardGeo.usedFreeSpaceFallback, clutterSummary: clutterSummary),
            clutterLossDb: max(forwardClutter.lossDb, reverseClutter.lossDb),
            clutterSummary: options.includeClutter ? clutterSummary : nil,
            confidence: nil,
            dataNote: dataNote(reduced: sampled.resolutionReduced, resolutionNote: sampled.resolutionNote, landCoverIncomplete: incomplete)
        )
    }

    func coverage(
        _ request: CoverageRequest,
        elevation: any ElevationProviding
    ) -> AsyncThrowingStream<CoverageUpdate, Error> {
        let options = self.options
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let grid = try await Self.compute(request, options: options, elevation: elevation) { fraction in
                        continuation.yield(.progress(fraction))
                    }
                    continuation.yield(.finished(grid))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func samplePath(
        start: Coordinate,
        end: Coordinate,
        distance: Double,
        bearing: Double,
        spacing: Double,
        maxCount: Int,
        elevation: any ElevationProviding
    ) async throws -> SampledTerrainPath {
        var distances = PropagationMath.sampleDistances(total: distance, spacing: spacing, maxCount: maxCount)
        if options.adaptiveSampling {
            let coarseCoordinates = coordinates(from: start, end: end, bearing: bearing, distances: distances, total: distance)
            let coarseBatch = try await elevation.elevations(at: coarseCoordinates)
            let coarsePoints = zip(distances, coarseBatch.samples).map { distance, sample in
                PathPoint(distanceM: distance, elevationM: sample.elevationM)
            }
            distances = PropagationMath.adaptiveSampleDistances(total: distance, coarse: coarsePoints, spacing: spacing, maxCount: maxCount)
        }
        let coords = coordinates(from: start, end: end, bearing: bearing, distances: distances, total: distance)
        let batch = try await elevation.elevations(at: coords)
        var points = zip(distances, batch.samples).map { distance, sample in
            PathPoint(distanceM: distance, elevationM: sample.elevationM)
        }
        var landCoverIncomplete = false
        if options.includeClutter, let landCover = options.landCover {
            let cover = try await landCover.classes(at: coords)
            for index in points.indices where index < cover.codes.count {
                points[index].landCoverCode = cover.codes[index]
            }
            landCoverIncomplete = cover.status == .unavailable || cover.status == .partial
        }
        return SampledTerrainPath(
            points: points,
            resolutionReduced: batch.resolutionReduced,
            resolutionNote: batch.resolutionNote,
            landCoverIncomplete: landCoverIncomplete
        )
    }

    private func clutter(for points: [PathPoint], txHeight: Double, rxHeight: Double, frequency: Double) -> ClutterLossResult {
        guard options.includeClutter else { return .none }
        return ClutterMath.loss(
            points: points,
            txAntennaHeightM: txHeight,
            rxAntennaHeightM: rxHeight,
            frequencyMHz: frequency,
            table: options.clutterTable
        )
    }

    private func simplifiedNote(fallback: Bool, clutterSummary: String) -> String {
        if fallback && !options.includeClutter && !options.multiEdgeDiffraction {
            return "No terrain samples. Showing free-space and two-ray loss only."
        }
        var parts: [String] = []
        if fallback {
            parts.append("No terrain samples. Showing free-space and two-ray loss only.")
        } else if options.multiEdgeDiffraction {
            parts.append("Simplified model with multi-edge diffraction. Each obstruction is a knife edge between its neighbors. This is an approximation, not a parabolic-equation or ITWOM solution.")
        } else {
            parts.append("Simplified model. One knife edge if terrain crosses the line of sight.")
        }
        if options.includeClutter {
            parts.append(clutterSummary)
        } else {
            parts.append("Trees and buildings are ignored.")
        }
        return parts.joined(separator: " ")
    }

    private func directional(
        tx: RadioEndpoint,
        rx: RadioEndpoint,
        loss: LossBreakdown,
        extraLossDb: Double,
        sensitivity: Double
    ) -> DirectionalLink {
        let pathLoss = loss.pathLossDb + extraLossDb
        let eirp = PropagationMath.eirpDbm(
            txPowerDbm: tx.txPowerDbm,
            gainDbi: tx.antennaGainDbi,
            cableLossDb: tx.cableLossDb
        )
        let received = PropagationMath.receivedPowerDbm(
            txPowerDbm: tx.txPowerDbm,
            txGainDbi: tx.antennaGainDbi,
            txCableDb: tx.cableLossDb,
            rxGainDbi: rx.antennaGainDbi,
            rxCableDb: rx.cableLossDb,
            pathLossDb: pathLoss
        )
        return DirectionalLink(
            pathLossDb: pathLoss,
            receivedPowerDbm: received,
            marginDb: received - sensitivity,
            eirpDbm: eirp,
            knifeEdgeLossDb: loss.knifeEdgeLossDb,
            fresnelClearanceRatio: loss.fresnelClearanceRatio,
            fresnelClear: loss.fresnelClearanceRatio >= 0.6,
            obstructed: loss.obstructed
        )
    }

    private static func compute(
        _ request: CoverageRequest,
        options: SimulationOptions,
        elevation: any ElevationProviding,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CoverageGrid {
        try PropagationMath.validate(endpoint: request.transmitter)
        guard request.receiverHeightM.isFinite, request.receiverHeightM > 0, request.receiverHeightM <= 1_000 else {
            throw PropagationError.invalidHeight
        }
        guard request.receiverGainDbi.isFinite, request.receiverCableLossDb.isFinite, request.sensitivityDbm.isFinite else {
            throw PropagationError.invalidPower
        }
        let maxRange = min(50_000, max(500, request.maxRangeM))
        let radials = max(8, request.radialCount)
        let rings = max(4, request.ringCount)
        let origin = request.transmitter.coordinate
        let sectorAngle = 2 * Double.pi / Double(radials)
        let legacySpacing = !options.adaptiveSampling && !options.multiEdgeDiffraction && !options.includeClutter
        let diffraction: DiffractionMode = options.multiEdgeDiffraction ? .multiEdge : .dominantEdge
        var cells: [CoverageCell] = []
        cells.reserveCapacity(radials * rings)
        var sawValue = false
        var sawMissing = false
        var sawLive = false
        var sawCache = false
        var resolutionReduced = false
        var resolutionNote: String?
        var landCoverIncomplete = false
        var clutterNotes: [String] = []
        var cellID = 0

        for radial in 0..<radials {
            try Task.checkCancellation()
            let startBearing = Double(radial) / Double(radials) * 360
            let endBearing = Double(radial + 1) / Double(radials) * 360
            let centerBearing = (startBearing + endBearing) / 2
            var distances = legacyDistances(maxRange: maxRange, legacy: legacySpacing, spacing: request.sampleSpacingM)
            var coordinates = distances.map { distance -> Coordinate in
                distance <= 0 ? origin : GeoMath.destination(from: origin, bearingDeg: centerBearing, distanceM: distance)
            }
            var batch = try await elevation.elevations(at: coordinates)
            if options.adaptiveSampling {
                let coarse = zip(distances, batch.samples).map { PathPoint(distanceM: $0.0, elevationM: $0.1.elevationM) }
                distances = PropagationMath.adaptiveSampleDistances(
                    total: maxRange,
                    coarse: coarse,
                    spacing: max(request.sampleSpacingM, maxRange / 700),
                    maxCount: 700
                )
                coordinates = distances.map { distance -> Coordinate in
                    distance <= 0 ? origin : GeoMath.destination(from: origin, bearingDeg: centerBearing, distanceM: distance)
                }
                batch = try await elevation.elevations(at: coordinates)
            }
            switch batch.status {
            case .live: sawLive = true
            case .cache: sawCache = true
            case .partial:
                sawMissing = true
                sawValue = true
            case .unavailable:
                sawMissing = true
            }
            if batch.resolutionReduced {
                resolutionReduced = true
                resolutionNote = batch.resolutionNote
            }
            if batch.samples.contains(where: { $0.elevationM != nil }) { sawValue = true }
            if batch.samples.contains(where: { $0.elevationM == nil }) { sawMissing = true }
            var points = zip(distances, batch.samples).map { PathPoint(distanceM: $0.0, elevationM: $0.1.elevationM) }
            if options.includeClutter, let landCover = options.landCover {
                let cover = try await landCover.classes(at: coordinates)
                for index in points.indices where index < cover.codes.count {
                    points[index].landCoverCode = cover.codes[index]
                }
                if cover.status == .unavailable || cover.status == .partial { landCoverIncomplete = true }
            }

            for ring in 0..<rings {
                let inner = maxRange * Double(ring) / Double(rings)
                let outer = maxRange * Double(ring + 1) / Double(rings)
                let midpoint = max(50, (inner + outer) / 2)
                var used = points.filter { $0.distanceM <= midpoint + 0.5 }
                if used.last?.distanceM != midpoint {
                    let nearest = points.min { abs($0.distanceM - midpoint) < abs($1.distanceM - midpoint) }
                    used.append(PathPoint(distanceM: midpoint, elevationM: nearest?.elevationM, landCoverCode: nearest?.landCoverCode))
                }
                let loss = PropagationMath.propagationLoss(
                    points: used,
                    txAntennaHeightM: request.transmitter.antennaHeightM,
                    rxAntennaHeightM: request.receiverHeightM,
                    frequencyMHz: request.transmitter.frequencyMHz,
                    includeProfile: false,
                    diffraction: diffraction
                )
                let clutterLoss = options.includeClutter
                    ? ClutterMath.loss(
                        points: used,
                        txAntennaHeightM: request.transmitter.antennaHeightM,
                        rxAntennaHeightM: request.receiverHeightM,
                        frequencyMHz: request.transmitter.frequencyMHz,
                        table: options.clutterTable
                    )
                    : .none
                if clutterLoss.incomplete { landCoverIncomplete = true }
                if radial == 0, ring == rings / 2, !clutterLoss.summary.isEmpty {
                    clutterNotes.append(clutterLoss.summary)
                }
                let rssi = PropagationMath.receivedPowerDbm(
                    txPowerDbm: request.transmitter.txPowerDbm,
                    txGainDbi: request.transmitter.antennaGainDbi,
                    txCableDb: request.transmitter.cableLossDb,
                    rxGainDbi: request.receiverGainDbi,
                    rxCableDb: request.receiverCableLossDb,
                    pathLossDb: loss.pathLossDb + clutterLoss.lossDb
                )
                let area = 0.5 * (outer * outer - inner * inner) * sectorAngle
                cells.append(CoverageCell(
                    id: cellID,
                    innerRadiusM: inner,
                    outerRadiusM: outer,
                    startBearingDeg: startBearing,
                    endBearingDeg: endBearing,
                    rssiDbm: rssi,
                    sectorAreaM2: area,
                    polygon: PropagationMath.sectorPolygon(
                        center: origin,
                        innerRadiusM: inner,
                        outerRadiusM: outer,
                        startBearingDeg: startBearing,
                        endBearingDeg: endBearing
                    )
                ))
                cellID += 1
            }
            progress(Double(radial + 1) / Double(radials))
        }

        let status: ElevationStatus
        if !sawValue {
            status = .unavailable
        } else if sawMissing {
            status = .partial
        } else if sawLive {
            status = .live
        } else if sawCache {
            status = .cache
        } else {
            status = .cache
        }
        return CoverageGrid(
            cells: cells,
            maxRangeM: maxRange,
            elevationStatus: status,
            usedFreeSpaceFallback: !sawValue,
            engineName: EngineTitle.name(
                model: .simplified,
                clutter: options.includeClutter,
                multiEdge: options.multiEdgeDiffraction,
                fallback: false
            ),
            resolutionReduced: resolutionReduced,
            landCoverIncomplete: landCoverIncomplete,
            confidence: nil,
            clutterSummary: clutterNotes.first,
            dataNote: joinedDataNote(reduced: resolutionReduced, resolutionNote: resolutionNote, landCoverIncomplete: landCoverIncomplete)
        )
    }
}

private nonisolated struct SampledTerrainPath: Sendable {
    var points: [PathPoint]
    var resolutionReduced: Bool
    var resolutionNote: String?
    var landCoverIncomplete: Bool
}

private nonisolated func coordinates(from start: Coordinate, end: Coordinate, bearing: Double, distances: [Double], total: Double) -> [Coordinate] {
    distances.map { sample in
        if sample <= 0 { return start }
        if abs(sample - total) < 0.5 { return end }
        return GeoMath.destination(from: start, bearingDeg: bearing, distanceM: sample)
    }
}

private nonisolated func legacyDistances(maxRange: Double, legacy: Bool, spacing: Double) -> [Double] {
    if legacy {
        var distances = [0.0]
        var cursor = 500.0
        while cursor < maxRange {
            distances.append(cursor)
            cursor += 500
        }
        if distances.last != maxRange {
            distances.append(maxRange)
        }
        return distances
    }
    let step = max(spacing, maxRange / 700)
    return PropagationMath.sampleDistances(total: maxRange, spacing: step, maxCount: 700)
}

private nonisolated func dataNote(reduced: Bool, resolutionNote: String?, landCoverIncomplete: Bool) -> String? {
    joinedDataNote(reduced: reduced, resolutionNote: resolutionNote, landCoverIncomplete: landCoverIncomplete)
}

nonisolated func joinedDataNote(reduced: Bool, resolutionNote: String?, landCoverIncomplete: Bool) -> String? {
    var parts: [String] = []
    if reduced, let resolutionNote, !resolutionNote.isEmpty {
        parts.append(resolutionNote)
    }
    if landCoverIncomplete {
        parts.append("Land cover is incomplete. Clutter was applied only where a class tile was available.")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
}
