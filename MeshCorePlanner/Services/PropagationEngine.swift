import Foundation

// MARK: - Geometry

nonisolated struct Coordinate: Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
}

nonisolated enum GeoMath {
    static let earthRadiusM = 6_371_000.0

    static func distanceM(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusM * c
    }

    static func bearingDeg(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func destination(from start: Coordinate, bearingDeg: Double, distanceM: Double) -> Coordinate {
        let angular = distanceM / earthRadiusM
        let theta = bearingDeg * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(
            sin(theta) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return Coordinate(
            latitude: lat2 * 180 / .pi,
            longitude: normalizeLongitude(lon2 * 180 / .pi)
        )
    }

    static func normalizeLongitude(_ value: Double) -> Double {
        var longitude = value
        while longitude > 180 { longitude -= 360 }
        while longitude < -180 { longitude += 360 }
        return longitude
    }
}

// MARK: - Errors and requests

nonisolated enum PropagationError: Error, Equatable, LocalizedError {
    case invalidCoordinate
    case invalidHeight
    case invalidFrequency
    case invalidPower

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            "Latitude must be between -90 and 90, and longitude between -180 and 180."
        case .invalidHeight:
            "Antenna height must be greater than 0 m and at most 1000 m."
        case .invalidFrequency:
            "Frequency must be greater than 0."
        case .invalidPower:
            "TX power, gain, and cable loss must be real numbers."
        }
    }
}

nonisolated struct RadioEndpoint: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var antennaHeightM: Double
    var txPowerDbm: Double
    var frequencyMHz: Double
    var antennaGainDbi: Double
    var cableLossDb: Double

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

nonisolated struct LinkRequest: Sendable {
    var from: RadioEndpoint
    var to: RadioEndpoint
    var sensitivityDbm: Double
}

nonisolated struct CoverageRequest: Sendable {
    var transmitter: RadioEndpoint
    var maxRangeM: Double
    var receiverHeightM: Double
    var receiverGainDbi: Double
    var receiverCableLossDb: Double
    var sensitivityDbm: Double
    var radialCount: Int
    var ringCount: Int
    var sampleSpacingM: Double

    init(
        transmitter: RadioEndpoint,
        maxRangeM: Double,
        receiverHeightM: Double,
        receiverGainDbi: Double,
        receiverCableLossDb: Double = 0,
        sensitivityDbm: Double,
        radialCount: Int = 36,
        ringCount: Int = 24,
        sampleSpacingM: Double = 500
    ) {
        self.transmitter = transmitter
        self.maxRangeM = maxRangeM
        self.receiverHeightM = receiverHeightM
        self.receiverGainDbi = receiverGainDbi
        self.receiverCableLossDb = receiverCableLossDb
        self.sensitivityDbm = sensitivityDbm
        self.radialCount = radialCount
        self.ringCount = ringCount
        self.sampleSpacingM = sampleSpacingM
    }
}

// MARK: - Results

nonisolated enum FresnelBand: Sendable, Equatable {
    case clear
    case partial
    case blocked

    var title: String {
        switch self {
        case .clear: "Clear"
        case .partial: "Partial"
        case .blocked: "Obstructed"
        }
    }
}

nonisolated struct ProfileSample: Sendable, Identifiable {
    var id: Int
    var distanceM: Double
    var terrainAMSL: Double
    var terrainWithBulge: Double
    var losAMSL: Double
    var fresnel60AMSL: Double
    var fresnel1AMSL: Double
    var protrusionM: Double

    /// Distance from the terrain to the bottom of the first Fresnel zone.
    /// Positive means the zone is clear. Negative means terrain enters the zone.
    var fresnelClearanceM: Double { fresnel1AMSL - terrainWithBulge }

    var fresnelBand: FresnelBand {
        if fresnelClearanceM >= -0.05 { return .clear }
        if terrainWithBulge <= fresnel60AMSL + 0.05 { return .partial }
        return .blocked
    }
}

nonisolated struct DirectionalLink: Sendable {
    var pathLossDb: Double
    var receivedPowerDbm: Double
    var marginDb: Double
    var eirpDbm: Double
    var knifeEdgeLossDb: Double
    var fresnelClearanceRatio: Double
    var fresnelClear: Bool
    var obstructed: Bool
}

nonisolated struct LinkResult: Sendable {
    var distanceM: Double
    var bearingFromToDeg: Double
    var bearingToFromDeg: Double
    var forward: DirectionalLink
    var reverse: DirectionalLink
    var profile: [ProfileSample]
    var usedFreeSpaceFallback: Bool
    var engineName: String
    var modelNote: String
    var clutterLossDb: Double = 0
    var clutterSummary: String? = nil
    var confidence: PlanningConfidence? = nil
    var dataNote: String? = nil

    var weakestMarginDb: Double { min(forward.marginDb, reverse.marginDb) }
}

nonisolated struct CoverageCell: Sendable, Identifiable {
    var id: Int
    var innerRadiusM: Double
    var outerRadiusM: Double
    var startBearingDeg: Double
    var endBearingDeg: Double
    var rssiDbm: Double
    var sectorAreaM2: Double
    var polygon: [Coordinate]
}

nonisolated struct CoverageStats: Sendable {
    var areaAboveThresholdM2: Double
    var maxUsableRangeM: Double
    var percentOfDisk: Double
    var diskAreaM2: Double
}

nonisolated struct CoverageGrid: Sendable {
    var cells: [CoverageCell]
    var maxRangeM: Double
    var elevationStatus: ElevationStatus
    var usedFreeSpaceFallback: Bool
    var engineName: String = "Simplified"
    var resolutionReduced: Bool = false
    var landCoverIncomplete: Bool = false
    var confidence: PlanningConfidence? = nil
    var clutterSummary: String? = nil
    var dataNote: String? = nil

    var diskAreaM2: Double { .pi * maxRangeM * maxRangeM }

    func statistics(sensitivityDbm: Double) -> CoverageStats {
        let above = cells.filter { $0.rssiDbm >= sensitivityDbm }
        let area = above.reduce(0.0) { $0 + $1.sectorAreaM2 }
        let farthest = above.map(\.outerRadiusM).max() ?? 0
        let percent = diskAreaM2 > 0 ? (area / diskAreaM2) * 100 : 0
        return CoverageStats(
            areaAboveThresholdM2: area,
            maxUsableRangeM: farthest,
            percentOfDisk: percent,
            diskAreaM2: diskAreaM2
        )
    }
}

nonisolated enum CoverageUpdate: Sendable {
    case progress(Double)
    case finished(CoverageGrid)
}

nonisolated struct PathPoint: Sendable {
    var distanceM: Double
    var elevationM: Double?
    var landCoverCode: Int? = nil
}

nonisolated struct LossBreakdown: Sendable {
    var pathLossDb: Double
    var knifeEdgeLossDb: Double
    var fresnelClearanceRatio: Double
    var obstructed: Bool
    var usedFreeSpaceFallback: Bool
    var profile: [ProfileSample]
}

// MARK: - Elevation

nonisolated struct ElevationSample: Sendable {
    var elevationM: Double?
}

nonisolated enum ElevationStatus: Sendable, Equatable {
    case live
    case cache
    case partial
    case unavailable
}

nonisolated struct ElevationBatch: Sendable {
    var samples: [ElevationSample]
    var status: ElevationStatus
    var resolutionReduced: Bool = false
    var resolutionNote: String? = nil
}

nonisolated protocol ElevationProviding: Sendable {
    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch
}

nonisolated protocol PropagationEngine: Sendable {
    func freeSpacePathLossDb(distanceM: Double, frequencyMHz: Double) -> Double
    func link(_ request: LinkRequest, elevation: any ElevationProviding) async throws -> LinkResult
    func coverage(_ request: CoverageRequest, elevation: any ElevationProviding) -> AsyncThrowingStream<CoverageUpdate, Error>
}

// MARK: - Math

nonisolated enum DiffractionMode: Sendable {
    /// One knife edge at the worst sample, and only when that sample crosses the line of sight.
    case dominantEdge
    /// Epstein-Peterson sum of knife edges at successive obstructions.
    case multiEdge
}

/// Original planning formulas. Not derived from SPLAT! or ITM source.
nonisolated enum PropagationMath {
    static let kFactor = 4.0 / 3.0

    static func freeSpacePathLossDb(distanceM: Double, frequencyMHz: Double) -> Double {
        let kilometers = max(distanceM, 1) / 1_000
        return 20 * log10(kilometers) + 20 * log10(frequencyMHz) + 32.44
    }

    static func wavelengthM(frequencyMHz: Double) -> Double {
        299.792458 / frequencyMHz
    }

    /// First Fresnel zone radius. r = sqrt(λ · d1 · d2 / (d1 + d2)).
    static func firstFresnelRadiusM(distance1M: Double, distance2M: Double, frequencyMHz: Double) -> Double {
        let total = distance1M + distance2M
        guard distance1M > 0, distance2M > 0, frequencyMHz > 0, total > 0 else { return 0 }
        let lambda = wavelengthM(frequencyMHz: frequencyMHz)
        return sqrt(lambda * distance1M * distance2M / total)
    }

    static func twoRayLossDb(distanceM: Double, txHeightM: Double, rxHeightM: Double) -> Double {
        let tx = max(txHeightM, 0.5)
        let rx = max(rxHeightM, 0.5)
        return 40 * log10(max(distanceM, 1)) - 20 * log10(tx) - 20 * log10(rx)
    }

    /// ITU-R single knife-edge approximation. About 6 dB at v = 0, and 0 below v = -0.78.
    static func knifeEdgeLossDb(v: Double) -> Double {
        guard v > -0.78 else { return 0 }
        let term = sqrt((v - 0.1) * (v - 0.1) + 1) + v - 0.1
        guard term > 0 else { return 0 }
        return 6.9 + 20 * log10(term)
    }

    static func earthBulgeM(d1: Double, d2: Double) -> Double {
        d1 * d2 / (2 * kFactor * GeoMath.earthRadiusM)
    }

    static func eirpDbm(txPowerDbm: Double, gainDbi: Double, cableLossDb: Double) -> Double {
        txPowerDbm + gainDbi - cableLossDb
    }

    static func receivedPowerDbm(
        txPowerDbm: Double,
        txGainDbi: Double,
        txCableDb: Double,
        rxGainDbi: Double,
        rxCableDb: Double,
        pathLossDb: Double
    ) -> Double {
        eirpDbm(txPowerDbm: txPowerDbm, gainDbi: txGainDbi, cableLossDb: txCableDb)
            + rxGainDbi
            - rxCableDb
            - pathLossDb
    }

    static func validate(endpoint: RadioEndpoint) throws {
        guard endpoint.latitude.isFinite, endpoint.longitude.isFinite,
              endpoint.latitude >= -90, endpoint.latitude <= 90,
              endpoint.longitude >= -180, endpoint.longitude <= 180 else {
            throw PropagationError.invalidCoordinate
        }
        guard endpoint.antennaHeightM.isFinite, endpoint.antennaHeightM > 0, endpoint.antennaHeightM <= 1_000 else {
            throw PropagationError.invalidHeight
        }
        guard endpoint.frequencyMHz.isFinite, endpoint.frequencyMHz > 0 else {
            throw PropagationError.invalidFrequency
        }
        guard endpoint.txPowerDbm.isFinite, endpoint.antennaGainDbi.isFinite, endpoint.cableLossDb.isFinite else {
            throw PropagationError.invalidPower
        }
    }

    static func sampleDistances(total: Double, spacing: Double = 250, maxCount: Int = 160) -> [Double] {
        let safe = max(total, 1)
        let steps = max(2, min(maxCount, Int((safe / spacing).rounded(.up))))
        return (0...steps).map { safe * Double($0) / Double(steps) }
    }

    static func reversed(_ points: [PathPoint]) -> [PathPoint] {
        guard let total = points.last?.distanceM else { return points }
        return points.reversed().map {
            PathPoint(distanceM: total - $0.distanceM, elevationM: $0.elevationM, landCoverCode: $0.landCoverCode)
        }
    }

    /// Denser samples in the first 15% of the path and around terrain peaks. Coarser elsewhere.
    /// `sampleDistances` is unchanged. Callers opt into this when a finer profile is useful.
    static func adaptiveSampleDistances(
        total: Double,
        coarse: [PathPoint],
        spacing: Double,
        maxCount: Int
    ) -> [Double] {
        let safe = max(total, 1)
        let step = max(spacing, 1)
        let fine = max(step / 3, 1)
        let nearLimit = safe * 0.15
        var raw: [Double] = [0, safe]
        var cursor = fine
        while cursor < nearLimit {
            raw.append(cursor)
            cursor += fine
        }
        if nearLimit > 0, nearLimit < safe { raw.append(nearLimit) }
        cursor = nearLimit + step
        while cursor < safe {
            raw.append(cursor)
            cursor += step
        }
        var peakDistances: [Double] = []
        if coarse.count >= 3 {
            for index in 1..<(coarse.count - 1) {
                guard let mid = coarse[index].elevationM,
                      let left = coarse[index - 1].elevationM,
                      let right = coarse[index + 1].elevationM,
                      mid + 0.01 >= left, mid + 0.01 >= right,
                      mid >= left + 8 || mid >= right + 8 else { continue }
                let peak = min(safe, max(0, coarse[index].distanceM))
                peakDistances.append(peak)
                raw.append(peak)
                raw.append(max(0, peak - step / 4))
                raw.append(min(safe, peak + step / 4))
            }
        }
        var unique = Array(Set(raw.map { ($0 * 2).rounded() / 2 })).sorted()
        if unique.first != 0 { unique.insert(0, at: 0) }
        if let last = unique.last, abs(last - safe) > 0.5 {
            unique.append(safe)
        } else if let last = unique.indices.last, abs(unique[last] - safe) <= 0.5 {
            unique[last] = safe
        }
        let limit = max(maxCount, 2)
        guard unique.count > limit else { return unique }
        func isProtected(_ distance: Double) -> Bool {
            if distance <= 0.5 || abs(distance - safe) <= 0.5 || distance <= nearLimit + 0.5 { return true }
            return peakDistances.contains { abs($0 - distance) <= step / 3 }
        }
        var keep = unique
        while keep.count > limit {
            var removeAt: Int?
            var smallestGap = Double.greatestFiniteMagnitude
            for index in 1..<(keep.count - 1) where !isProtected(keep[index]) {
                let gap = keep[index] - keep[index - 1]
                if gap < smallestGap {
                    smallestGap = gap
                    removeAt = index
                }
            }
            guard let removeAt else { break }
            keep.remove(at: removeAt)
        }
        return keep
    }

    static func fresnelClearanceLabel(profile: [ProfileSample]) -> String {
        guard let total = profile.last?.distanceM else { return "No profile" }
        let interior = profile.filter { $0.distanceM > 1 && total - $0.distanceM > 1 }
        let relevant = interior.isEmpty ? profile : interior
        guard let worst = relevant.min(by: { $0.fresnelClearanceM < $1.fresnelClearanceM }) else { return "No profile" }
        return String(format: "%@ %+.0f m", worst.fresnelBand.title, worst.fresnelClearanceM)
    }

    /// Loss along an ordered path. The first point is the transmitter ground and the last is the receiver ground.
    /// A path whose terrain stays below the line of sight uses max(FSPL, two-ray).
    /// Terrain that meets or crosses that line uses FSPL plus one knife edge, without two-ray.
    /// Fresnel clearance is still reported when the ray is clear.
    /// `multiEdge` sums Epstein-Peterson knife edges. The default remains one dominant edge.
    static func propagationLoss(
        points: [PathPoint],
        txAntennaHeightM: Double,
        rxAntennaHeightM: Double,
        frequencyMHz: Double,
        includeProfile: Bool,
        diffraction: DiffractionMode = .dominantEdge
    ) -> LossBreakdown {
        let total = max(points.last?.distanceM ?? 1, 1)
        let frequency = max(frequencyMHz, 0.001)
        let lambda = wavelengthM(frequencyMHz: frequency)
        let fspl = freeSpacePathLossDb(distanceM: total, frequencyMHz: frequency)
        let twoRay = twoRayLossDb(distanceM: total, txHeightM: txAntennaHeightM, rxHeightM: rxAntennaHeightM)
        let txGround = points.first?.elevationM ?? 0
        let rxGround = points.last?.elevationM ?? 0
        let hTx = txGround + txAntennaHeightM
        let hRx = rxGround + rxAntennaHeightM

        var maxV = -Double.greatestFiniteMagnitude
        var minClearance = Double.greatestFiniteMagnitude
        var usableObstacles = 0
        var profile: [ProfileSample] = []
        var effectiveHeights = [Double?](repeating: nil, count: points.count)
        var vValues = [Double](repeating: -.greatestFiniteMagnitude, count: points.count)

        for (index, point) in points.enumerated() {
            let d1 = point.distanceM
            let d2 = max(total - d1, 0)
            let bulge = earthBulgeM(d1: d1, d2: d2)
            let chord = hTx + (hRx - hTx) * (d1 / total)
            let hasElevation = point.elevationM != nil
            let ground = point.elevationM ?? 0
            let protrusion = (ground + bulge) - chord
            let fresnelRadius = (d1 > 1 && d2 > 1)
                ? firstFresnelRadiusM(distance1M: d1, distance2M: d2, frequencyMHz: frequency)
                : 0
            if hasElevation, d1 > 1, d2 > 1 {
                usableObstacles += 1
                let v = protrusion * sqrt((2 * total) / (lambda * d1 * d2))
                effectiveHeights[index] = ground + bulge
                vValues[index] = v
                maxV = max(maxV, v)
                if fresnelRadius > 0 {
                    minClearance = min(minClearance, -protrusion / fresnelRadius)
                }
            }
            if includeProfile {
                profile.append(ProfileSample(
                    id: index,
                    distanceM: d1,
                    terrainAMSL: ground,
                    terrainWithBulge: ground + bulge,
                    losAMSL: chord,
                    fresnel60AMSL: chord - 0.6 * fresnelRadius,
                    fresnel1AMSL: chord - fresnelRadius,
                    protrusionM: hasElevation ? protrusion : 0
                ))
            }
        }

        let fallback = usableObstacles == 0
        // v > 0 means the sampled ground meets the line of sight. Fresnel intrusion
        // below that line stays on the two-ray model; the clearance ratio still reports it.
        let dominantObstructed = !fallback && maxV > 0
        let obstructed: Bool
        let knife: Double
        if diffraction == .multiEdge && !fallback {
            let multi = multiEdgeLossDb(
                points: points,
                effectiveHeights: effectiveHeights,
                vValues: vValues,
                txHeightM: hTx,
                rxHeightM: hRx,
                total: total,
                lambda: lambda
            )
            obstructed = multi.edgeCount > 0
            knife = obstructed ? multi.lossDb : 0
        } else {
            obstructed = dominantObstructed
            knife = obstructed ? knifeEdgeLossDb(v: maxV) : 0
        }
        let loss = obstructed ? fspl + knife : max(fspl, twoRay)
        let clearance = minClearance == .greatestFiniteMagnitude ? 1 : minClearance
        return LossBreakdown(
            pathLossDb: loss,
            knifeEdgeLossDb: knife,
            fresnelClearanceRatio: clearance,
            obstructed: obstructed,
            usedFreeSpaceFallback: fallback,
            profile: profile
        )
    }

    static func sectorPolygon(
        center: Coordinate,
        innerRadiusM: Double,
        outerRadiusM: Double,
        startBearingDeg: Double,
        endBearingDeg: Double
    ) -> [Coordinate] {
        let steps = 4
        let outer = (0...steps).map { step in
            let bearing = startBearingDeg + (endBearingDeg - startBearingDeg) * Double(step) / Double(steps)
            return GeoMath.destination(from: center, bearingDeg: bearing, distanceM: outerRadiusM)
        }
        if innerRadiusM < 1 {
            return [center] + outer
        }
        let inner = (0...steps).reversed().map { step in
            let bearing = startBearingDeg + (endBearingDeg - startBearingDeg) * Double(step) / Double(steps)
            return GeoMath.destination(from: center, bearingDeg: bearing, distanceM: innerRadiusM)
        }
        return outer + inner
    }

    /// Epstein-Peterson: each obstruction is a knife edge between the previous and next terminal.
    /// Losses are summed. This is not a parabolic-equation or ITWOM solution.
    private static func multiEdgeLossDb(
        points: [PathPoint],
        effectiveHeights: [Double?],
        vValues: [Double],
        txHeightM: Double,
        rxHeightM: Double,
        total: Double,
        lambda: Double
    ) -> (lossDb: Double, edgeCount: Int) {
        guard points.count >= 3, lambda > 0 else { return (0, 0) }
        var indexes: [Int] = []
        for index in 1..<(points.count - 1) {
            guard let height = effectiveHeights[index], vValues[index] > 0 else { continue }
            let left = effectiveHeights[index - 1] ?? height
            let right = effectiveHeights[index + 1] ?? height
            if height + 0.05 >= left && height + 0.05 >= right {
                indexes.append(index)
            }
        }
        if let worst = vValues.enumerated().max(by: { $0.element < $1.element }),
           worst.element > 0,
           worst.offset > 0,
           worst.offset < points.count - 1,
           !indexes.contains(worst.offset) {
            indexes.append(worst.offset)
            indexes.sort()
        }
        guard !indexes.isEmpty else { return (0, 0) }

        struct Terminal {
            var distanceM: Double
            var heightM: Double
        }
        var terminals = [Terminal(distanceM: 0, heightM: txHeightM)]
        for index in indexes {
            guard let height = effectiveHeights[index] else { continue }
            let distance = points[index].distanceM
            if let previous = terminals.last, abs(distance - previous.distanceM) < 1 { continue }
            terminals.append(Terminal(distanceM: distance, heightM: height))
        }
        if let previous = terminals.last, abs(total - previous.distanceM) < 1 {
            terminals.removeLast()
        }
        terminals.append(Terminal(distanceM: total, heightM: rxHeightM))
        guard terminals.count >= 3 else { return (0, 0) }

        var loss = 0.0
        var edges = 0
        for index in 1..<(terminals.count - 1) {
            let previous = terminals[index - 1]
            let edge = terminals[index]
            let next = terminals[index + 1]
            let d1 = edge.distanceM - previous.distanceM
            let d2 = next.distanceM - edge.distanceM
            guard d1 > 1, d2 > 1 else { continue }
            let span = d1 + d2
            let line = previous.heightM + (next.heightM - previous.heightM) * (d1 / span)
            let clearance = edge.heightM - line
            let v = clearance * sqrt((2 * span) / (lambda * d1 * d2))
            let edgeLoss = knifeEdgeLossDb(v: v)
            if edgeLoss > 0 {
                loss += edgeLoss
                edges += 1
            }
        }
        return (loss, edges)
    }
}
