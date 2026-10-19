import Foundation

/// Terrain-aware planner: free-space loss, two-ray height loss on a clear path,
/// and one knife edge when sampled ground blocks the chord. Swap this type for an
/// ITM engine later by conforming to `PropagationEngine`.
nonisolated struct SimplifiedTerrainEngine: PropagationEngine {
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
        let distances = PropagationMath.sampleDistances(total: distance)
        let coordinates = distances.map { sample -> Coordinate in
            if sample <= 0 { return start }
            if abs(sample - distance) < 0.5 { return end }
            return GeoMath.destination(from: start, bearingDeg: bearing, distanceM: sample)
        }
        let batch = try await elevation.elevations(at: coordinates)
        let points = pathPoints(distances: distances, batch: batch)
        let forwardLoss = PropagationMath.propagationLoss(
            points: points,
            txAntennaHeightM: request.from.antennaHeightM,
            rxAntennaHeightM: request.to.antennaHeightM,
            frequencyMHz: request.from.frequencyMHz,
            includeProfile: true
        )
        let reverseLoss = PropagationMath.propagationLoss(
            points: PropagationMath.reversed(points),
            txAntennaHeightM: request.to.antennaHeightM,
            rxAntennaHeightM: request.from.antennaHeightM,
            frequencyMHz: request.to.frequencyMHz,
            includeProfile: false
        )
        return LinkResult(
            distanceM: distance,
            bearingFromToDeg: bearing,
            bearingToFromDeg: GeoMath.bearingDeg(from: end, to: start),
            forward: directional(tx: request.from, rx: request.to, loss: forwardLoss, sensitivity: request.sensitivityDbm),
            reverse: directional(tx: request.to, rx: request.from, loss: reverseLoss, sensitivity: request.sensitivityDbm),
            profile: forwardLoss.profile,
            usedFreeSpaceFallback: forwardLoss.usedFreeSpaceFallback,
            engineName: "Simplified",
            modelNote: forwardLoss.usedFreeSpaceFallback
                ? "No terrain samples. Showing free-space and two-ray loss only."
                : "Simplified model. One knife edge if terrain crosses the line of sight. Trees and buildings are ignored."
        )
    }

    func coverage(
        _ request: CoverageRequest,
        elevation: any ElevationProviding
    ) -> AsyncThrowingStream<CoverageUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let grid = try await Self.compute(request, elevation: elevation) { fraction in
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

    private func directional(
        tx: RadioEndpoint,
        rx: RadioEndpoint,
        loss: LossBreakdown,
        sensitivity: Double
    ) -> DirectionalLink {
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
            pathLossDb: loss.pathLossDb
        )
        return DirectionalLink(
            pathLossDb: loss.pathLossDb,
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
        var cells: [CoverageCell] = []
        cells.reserveCapacity(radials * rings)
        var sawValue = false
        var sawMissing = false
        var sawLive = false
        var sawCache = false
        var cellID = 0

        for radial in 0..<radials {
            try Task.checkCancellation()
            let startBearing = Double(radial) / Double(radials) * 360
            let endBearing = Double(radial + 1) / Double(radials) * 360
            let centerBearing = (startBearing + endBearing) / 2
            var distances = [0.0]
            var cursor = 500.0
            while cursor < maxRange {
                distances.append(cursor)
                cursor += 500
            }
            if distances.last != maxRange {
                distances.append(maxRange)
            }
            let coordinates = distances.map { distance -> Coordinate in
                distance <= 0
                    ? origin
                    : GeoMath.destination(from: origin, bearingDeg: centerBearing, distanceM: distance)
            }
            let batch = try await elevation.elevations(at: coordinates)
            switch batch.status {
            case .live: sawLive = true
            case .cache: sawCache = true
            case .partial:
                sawMissing = true
                sawValue = true
            case .unavailable:
                sawMissing = true
            }
            if batch.samples.contains(where: { $0.elevationM != nil }) { sawValue = true }
            if batch.samples.contains(where: { $0.elevationM == nil }) { sawMissing = true }
            let points = pathPoints(distances: distances, batch: batch)

            for ring in 0..<rings {
                let inner = maxRange * Double(ring) / Double(rings)
                let outer = maxRange * Double(ring + 1) / Double(rings)
                let midpoint = max(50, (inner + outer) / 2)
                var used = points.filter { $0.distanceM <= midpoint + 0.5 }
                if used.last?.distanceM != midpoint {
                    let nearest = points.min { abs($0.distanceM - midpoint) < abs($1.distanceM - midpoint) }
                    used.append(PathPoint(distanceM: midpoint, elevationM: nearest?.elevationM))
                }
                let loss = PropagationMath.propagationLoss(
                    points: used,
                    txAntennaHeightM: request.transmitter.antennaHeightM,
                    rxAntennaHeightM: request.receiverHeightM,
                    frequencyMHz: request.transmitter.frequencyMHz,
                    includeProfile: false
                )
                let rssi = PropagationMath.receivedPowerDbm(
                    txPowerDbm: request.transmitter.txPowerDbm,
                    txGainDbi: request.transmitter.antennaGainDbi,
                    txCableDb: request.transmitter.cableLossDb,
                    rxGainDbi: request.receiverGainDbi,
                    rxCableDb: request.receiverCableLossDb,
                    pathLossDb: loss.pathLossDb
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
            usedFreeSpaceFallback: !sawValue
        )
    }
}

private nonisolated func pathPoints(distances: [Double], batch: ElevationBatch) -> [PathPoint] {
    distances.enumerated().map { index, distance in
        let elevation = index < batch.samples.count ? batch.samples[index].elevationM : nil
        return PathPoint(distanceM: distance, elevationM: elevation)
    }
}
