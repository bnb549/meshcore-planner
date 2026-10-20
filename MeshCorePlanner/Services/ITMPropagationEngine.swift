import Foundation

nonisolated enum PropagationModel: String, CaseIterable, Identifiable, Sendable {
    case itm
    case simplified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itm: "ITM (Longley-Rice)"
        case .simplified: "Simplified"
        }
    }
}

nonisolated enum SimulationQuality: String, CaseIterable, Identifiable, Sendable {
    case fast
    case standard
    case fine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .standard: "Standard"
        case .fine: "Fine"
        }
    }

    var radialCount: Int {
        switch self {
        case .fast: 24
        case .standard: 36
        case .fine: 48
        }
    }

    var ringCount: Int {
        switch self {
        case .fast: 12
        case .standard: 24
        case .fine: 32
        }
    }

    /// Ground sample spacing along a path. Long radials are widened so one radial stays under about 700 points.
    var sampleSpacingM: Double {
        switch self {
        case .fast: 180
        case .standard: 90
        case .fine: 45
        }
    }
}

nonisolated enum ITMClimate: Int, CaseIterable, Identifiable, Sendable {
    case equatorial = 1
    case continentalSubtropical = 2
    case maritimeSubtropical = 3
    case desert = 4
    case continentalTemperate = 5
    case maritimeTemperateLand = 6
    case maritimeTemperateSea = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .equatorial: "Equatorial"
        case .continentalSubtropical: "Continental subtropical"
        case .maritimeSubtropical: "Maritime subtropical"
        case .desert: "Desert"
        case .continentalTemperate: "Continental temperate"
        case .maritimeTemperateLand: "Maritime temperate, land"
        case .maritimeTemperateSea: "Maritime temperate, sea"
        }
    }
}

nonisolated enum ITMVariability: Int, CaseIterable, Identifiable, Sendable {
    case singleMessage = 0
    case accidental = 1
    case mobile = 2
    case broadcast = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .singleMessage: "Single message"
        case .accidental: "Accidental"
        case .mobile: "Mobile"
        case .broadcast: "Broadcast"
        }
    }
}

/// Defaults follow a median MeshCore planning case: vertical polarization, mixed ground, continental temperate climate.
nonisolated struct ITMParameters: Sendable, Equatable {
    var climate: ITMClimate
    var polarizationVertical: Bool
    var dielectric: Double
    var conductivity: Double
    var refractivity: Double
    var variability: ITMVariability
    var timePercent: Double
    var locationPercent: Double
    var situationPercent: Double

    static let meshCoreDefault = ITMParameters(
        climate: .continentalTemperate,
        polarizationVertical: true,
        dielectric: 15,
        conductivity: 0.005,
        refractivity: 301,
        variability: .broadcast,
        timePercent: 50,
        locationPercent: 50,
        situationPercent: 50
    )

    var polarization: Int { polarizationVertical ? 1 : 0 }

    var clamped: ITMParameters {
        var copy = self
        copy.dielectric = min(80, max(1.1, dielectric))
        copy.conductivity = min(1, max(0.0001, conductivity))
        copy.refractivity = min(400, max(250, refractivity))
        copy.timePercent = min(99, max(1, timePercent))
        copy.locationPercent = min(99, max(1, locationPercent))
        copy.situationPercent = min(99, max(1, situationPercent))
        return copy
    }
}

nonisolated enum ITMBridge {
    struct PathLoss: Sendable {
        var lossDb: Double
        var errorCode: Int32
        var warnings: Int32
        var propagationMode: Int32
        var freeSpaceLossDb: Double

        var succeeded: Bool { errorCode == 0 || errorCode == 1 }

        var modeTitle: String {
            switch propagationMode {
            case 1: "line of sight"
            case 2: "diffraction"
            case 3: "troposcatter"
            default: "predicted"
            }
        }
    }

    static func pointToPoint(
        profile: [Double],
        txHeightM: Double,
        rxHeightM: Double,
        frequencyMHz: Double,
        parameters: ITMParameters
    ) -> PathLoss {
        let parameters = parameters.clamped
        return pointToPoint(
            profile: profile,
            txHeightM: txHeightM,
            rxHeightM: rxHeightM,
            frequencyMHz: frequencyMHz,
            climate: Int32(parameters.climate.rawValue),
            polarization: Int32(parameters.polarization),
            dielectric: parameters.dielectric,
            conductivity: parameters.conductivity,
            refractivity: parameters.refractivity,
            variabilityMode: Int32(parameters.variability.rawValue),
            timePercent: parameters.timePercent,
            locationPercent: parameters.locationPercent,
            situationPercent: parameters.situationPercent
        )
    }

    /// `variabilityMode` is the NTIA `mdvar` code. Reference cases use values outside the Settings picker, such as 12.
    static func pointToPoint(
        profile: [Double],
        txHeightM: Double,
        rxHeightM: Double,
        frequencyMHz: Double,
        climate: Int32,
        polarization: Int32,
        dielectric: Double,
        conductivity: Double,
        refractivity: Double,
        variabilityMode: Int32,
        timePercent: Double,
        locationPercent: Double,
        situationPercent: Double
    ) -> PathLoss {
        var output = ITMPathLoss(
            lossDb: 0,
            errorCode: 0,
            warnings: 0,
            propagationMode: 0,
            freeSpaceLossDb: 0
        )
        let code = profile.withUnsafeBufferPointer { buffer in
            itm_point_to_point(
                buffer.baseAddress,
                Int32(buffer.count),
                txHeightM,
                rxHeightM,
                frequencyMHz,
                climate,
                polarization,
                dielectric,
                conductivity,
                refractivity,
                variabilityMode,
                timePercent,
                locationPercent,
                situationPercent,
                &output
            )
        }
        return PathLoss(
            lossDb: output.lossDb,
            errorCode: code,
            warnings: output.warnings,
            propagationMode: output.propagationMode,
            freeSpaceLossDb: output.freeSpaceLossDb
        )
    }
}

/// Longley-Rice point-to-point loss over an elevation profile.
/// The CPU work runs off the main actor. Missing terrain uses `SimplifiedTerrainEngine`.
nonisolated struct ITMPropagationEngine: PropagationEngine {
    var parameters: ITMParameters
    var sampleSpacingM: Double
    var options: SimulationOptions

    init(
        parameters: ITMParameters = .meshCoreDefault,
        sampleSpacingM: Double = SimulationQuality.standard.sampleSpacingM,
        options: SimulationOptions = SimulationOptions()
    ) {
        self.parameters = parameters
        self.sampleSpacingM = sampleSpacingM
        self.options = options
    }

    func freeSpacePathLossDb(distanceM: Double, frequencyMHz: Double) -> Double {
        PropagationMath.freeSpacePathLossDb(distanceM: distanceM, frequencyMHz: frequencyMHz)
    }

    func link(_ request: LinkRequest, elevation: any ElevationProviding) async throws -> LinkResult {
        try PropagationMath.validate(endpoint: request.from)
        try PropagationMath.validate(endpoint: request.to)
        let sampled = try await sampleLink(request, elevation: elevation)
        let parameters = self.parameters
        let options = self.options
        return await Task.detached {
            Self.assembleLink(request, sampled: sampled, parameters: parameters, options: options)
        }.value
    }

    func coverage(
        _ request: CoverageRequest,
        elevation: any ElevationProviding
    ) -> AsyncThrowingStream<CoverageUpdate, Error> {
        let parameters = self.parameters
        let options = self.options
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let grid = try await Self.compute(request, parameters: parameters, options: options, elevation: elevation) { fraction in
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

    private func sampleLink(_ request: LinkRequest, elevation: any ElevationProviding) async throws -> SampledPath {
        let start = request.from.coordinate
        let end = request.to.coordinate
        let distance = max(GeoMath.distanceM(from: start, to: end), 1)
        let bearing = GeoMath.bearingDeg(from: start, to: end)
        var distances = PropagationMath.sampleDistances(total: distance, spacing: sampleSpacingM, maxCount: 700)
        if options.adaptiveSampling {
            let coarseCoordinates = distances.map { sample -> Coordinate in
                if sample <= 0 { return start }
                if abs(sample - distance) < 0.5 { return end }
                return GeoMath.destination(from: start, bearingDeg: bearing, distanceM: sample)
            }
            let coarseBatch = try await elevation.elevations(at: coarseCoordinates)
            let coarsePoints = zip(distances, coarseBatch.samples).map { sampleDistance, sample in
                PathPoint(distanceM: sampleDistance, elevationM: sample.elevationM)
            }
            distances = PropagationMath.adaptiveSampleDistances(
                total: distance,
                coarse: coarsePoints,
                spacing: sampleSpacingM,
                maxCount: 700
            )
        }
        let coordinates = distances.map { sample -> Coordinate in
            if sample <= 0 { return start }
            if abs(sample - distance) < 0.5 { return end }
            return GeoMath.destination(from: start, bearingDeg: bearing, distanceM: sample)
        }
        let batch = try await elevation.elevations(at: coordinates)
        var points = zip(distances, batch.samples).map { sampleDistance, sample in
            PathPoint(distanceM: sampleDistance, elevationM: sample.elevationM)
        }
        var landCoverIncomplete = false
        if options.includeClutter, let landCover = options.landCover {
            let cover = try await landCover.classes(at: coordinates)
            for index in points.indices where index < cover.codes.count {
                points[index].landCoverCode = cover.codes[index]
            }
            landCoverIncomplete = cover.status == .unavailable || cover.status == .partial
        }
        return SampledPath(
            distanceM: distance,
            bearingFromToDeg: bearing,
            bearingToFromDeg: GeoMath.bearingDeg(from: end, to: start),
            points: points,
            elevationStatus: batch.status,
            resolutionReduced: batch.resolutionReduced,
            resolutionNote: batch.resolutionNote,
            landCoverIncomplete: landCoverIncomplete
        )
    }

    private static func assembleLink(
        _ request: LinkRequest,
        sampled: SampledPath,
        parameters: ITMParameters,
        options: SimulationOptions
    ) -> LinkResult {
        let forwardGeo = PropagationMath.propagationLoss(
            points: sampled.points,
            txAntennaHeightM: request.from.antennaHeightM,
            rxAntennaHeightM: request.to.antennaHeightM,
            frequencyMHz: request.from.frequencyMHz,
            includeProfile: true
        )
        let reverseGeo = PropagationMath.propagationLoss(
            points: PropagationMath.reversed(sampled.points),
            txAntennaHeightM: request.to.antennaHeightM,
            rxAntennaHeightM: request.from.antennaHeightM,
            frequencyMHz: request.to.frequencyMHz,
            includeProfile: false
        )
        let forwardITM = itmLoss(
            points: sampled.points,
            txHeightM: request.from.antennaHeightM,
            rxHeightM: request.to.antennaHeightM,
            frequencyMHz: request.from.frequencyMHz,
            parameters: parameters
        )
        let reverseITM = itmLoss(
            points: PropagationMath.reversed(sampled.points),
            txHeightM: request.to.antennaHeightM,
            rxHeightM: request.from.antennaHeightM,
            frequencyMHz: request.to.frequencyMHz,
            parameters: parameters
        )
        let usedFallback = forwardITM == nil || reverseITM == nil
        let forwardClutter = itmClutter(points: sampled.points, txHeight: request.from.antennaHeightM, rxHeight: request.to.antennaHeightM, frequency: request.from.frequencyMHz, options: options)
        let reverseClutter = itmClutter(points: PropagationMath.reversed(sampled.points), txHeight: request.to.antennaHeightM, rxHeight: request.from.antennaHeightM, frequency: request.to.frequencyMHz, options: options)
        let forwardLoss = (forwardITM?.lossDb ?? forwardGeo.pathLossDb) + forwardClutter.lossDb
        let reverseLoss = (reverseITM?.lossDb ?? reverseGeo.pathLossDb) + reverseClutter.lossDb
        let mode = forwardITM?.modeTitle ?? "simplified"
        let clutterSummary = forwardClutter.lossDb >= reverseClutter.lossDb ? forwardClutter.summary : reverseClutter.summary
        let note = itmNote(parameters: parameters, mode: mode, fallback: usedFallback, clutter: options.includeClutter, clutterSummary: clutterSummary)
        let incomplete = options.includeClutter && (forwardClutter.incomplete || reverseClutter.incomplete || sampled.landCoverIncomplete)
        let confidence = usedFallback ? nil : PlanningConfidence.itm(
            sampleSpacingM: sampled.distanceM / Double(max(sampled.points.count - 1, 1)),
            timePercent: parameters.timePercent,
            locationPercent: parameters.locationPercent,
            situationPercent: parameters.situationPercent,
            elevationStatus: sampled.elevationStatus,
            resolutionReduced: sampled.resolutionReduced
        )
        return LinkResult(
            distanceM: sampled.distanceM,
            bearingFromToDeg: sampled.bearingFromToDeg,
            bearingToFromDeg: sampled.bearingToFromDeg,
            forward: directional(tx: request.from, rx: request.to, breakdown: forwardGeo, pathLossDb: forwardLoss, sensitivity: request.sensitivityDbm),
            reverse: directional(tx: request.to, rx: request.from, breakdown: reverseGeo, pathLossDb: reverseLoss, sensitivity: request.sensitivityDbm),
            profile: forwardGeo.profile,
            usedFreeSpaceFallback: usedFallback || forwardGeo.usedFreeSpaceFallback && forwardITM == nil,
            engineName: EngineTitle.name(model: .itm, clutter: options.includeClutter, multiEdge: false, fallback: usedFallback),
            modelNote: note,
            clutterLossDb: max(forwardClutter.lossDb, reverseClutter.lossDb),
            clutterSummary: options.includeClutter ? clutterSummary : nil,
            confidence: confidence,
            dataNote: joinedDataNote(reduced: sampled.resolutionReduced, resolutionNote: sampled.resolutionNote, landCoverIncomplete: incomplete)
        )
    }

    private static func compute(
        _ request: CoverageRequest,
        parameters: ITMParameters,
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
        let spacing = max(request.sampleSpacingM, maxRange / 700)
        let origin = request.transmitter.coordinate
        let sectorAngle = 2 * Double.pi / Double(radials)
        var cells: [CoverageCell] = []
        cells.reserveCapacity(radials * rings)
        var sawValue = false
        var sawMissing = false
        var sawLive = false
        var sawCache = false
        var itmCells = 0
        var cellID = 0
        var resolutionReduced = false
        var resolutionNote: String?
        var landCoverIncomplete = false
        var clutterSummary: String?

        for radial in 0..<radials {
            try Task.checkCancellation()
            let startBearing = Double(radial) / Double(radials) * 360
            let endBearing = Double(radial + 1) / Double(radials) * 360
            let centerBearing = (startBearing + endBearing) / 2
            var distances = PropagationMath.sampleDistances(total: maxRange, spacing: spacing, maxCount: 700)
            if options.adaptiveSampling {
                let coarseCoordinates = distances.map { distance -> Coordinate in
                    distance <= 0 ? origin : GeoMath.destination(from: origin, bearingDeg: centerBearing, distanceM: distance)
                }
                let coarseBatch = try await elevation.elevations(at: coarseCoordinates)
                let coarsePoints = zip(distances, coarseBatch.samples).map { PathPoint(distanceM: $0.0, elevationM: $0.1.elevationM) }
                distances = PropagationMath.adaptiveSampleDistances(total: maxRange, coarse: coarsePoints, spacing: spacing, maxCount: 700)
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
            if batch.resolutionReduced {
                resolutionReduced = true
                resolutionNote = batch.resolutionNote
            }
            if batch.samples.contains(where: { $0.elevationM != nil }) { sawValue = true }
            if batch.samples.contains(where: { $0.elevationM == nil }) { sawMissing = true }
            var points = zip(distances, batch.samples).map { distance, sample in
                PathPoint(distanceM: distance, elevationM: sample.elevationM)
            }
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
                let prefix = prefixPoints(points, through: midpoint)
                let itm = itmLoss(
                    points: prefix,
                    txHeightM: request.transmitter.antennaHeightM,
                    rxHeightM: request.receiverHeightM,
                    frequencyMHz: request.transmitter.frequencyMHz,
                    parameters: parameters
                )
                let geometric = PropagationMath.propagationLoss(
                    points: prefix,
                    txAntennaHeightM: request.transmitter.antennaHeightM,
                    rxAntennaHeightM: request.receiverHeightM,
                    frequencyMHz: request.transmitter.frequencyMHz,
                    includeProfile: false
                )
                if itm == nil {
                    // This ring stays on the simplified loss. Other rings can still use ITM.
                } else {
                    itmCells += 1
                }
                let clutterLoss = itmClutter(
                    points: prefix,
                    txHeight: request.transmitter.antennaHeightM,
                    rxHeight: request.receiverHeightM,
                    frequency: request.transmitter.frequencyMHz,
                    options: options
                )
                if clutterLoss.incomplete { landCoverIncomplete = true }
                if clutterSummary == nil, clutterLoss.lossDb > 0 { clutterSummary = clutterLoss.summary }
                let pathLoss = (itm?.lossDb ?? geometric.pathLossDb) + clutterLoss.lossDb
                let rssi = PropagationMath.receivedPowerDbm(
                    txPowerDbm: request.transmitter.txPowerDbm,
                    txGainDbi: request.transmitter.antennaGainDbi,
                    txCableDb: request.transmitter.cableLossDb,
                    rxGainDbi: request.receiverGainDbi,
                    rxCableDb: request.receiverCableLossDb,
                    pathLossDb: pathLoss
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
        let fallback = itmCells == 0
        return CoverageGrid(
            cells: cells,
            maxRangeM: maxRange,
            elevationStatus: status,
            usedFreeSpaceFallback: fallback,
            engineName: EngineTitle.name(model: .itm, clutter: options.includeClutter, multiEdge: false, fallback: fallback),
            resolutionReduced: resolutionReduced,
            landCoverIncomplete: landCoverIncomplete,
            confidence: fallback ? nil : PlanningConfidence.itm(
                sampleSpacingM: spacing,
                timePercent: parameters.timePercent,
                locationPercent: parameters.locationPercent,
                situationPercent: parameters.situationPercent,
                elevationStatus: status,
                resolutionReduced: resolutionReduced
            ),
            clutterSummary: options.includeClutter ? clutterSummary : nil,
            dataNote: joinedDataNote(reduced: resolutionReduced, resolutionNote: resolutionNote, landCoverIncomplete: landCoverIncomplete)
        )
    }
}

private nonisolated struct SampledPath: Sendable {
    var distanceM: Double
    var bearingFromToDeg: Double
    var bearingToFromDeg: Double
    var points: [PathPoint]
    var elevationStatus: ElevationStatus
    var resolutionReduced: Bool
    var resolutionNote: String?
    var landCoverIncomplete: Bool
}

private nonisolated func itmClutter(
    points: [PathPoint],
    txHeight: Double,
    rxHeight: Double,
    frequency: Double,
    options: SimulationOptions
) -> ClutterLossResult {
    guard options.includeClutter else { return .none }
    return ClutterMath.loss(
        points: points,
        txAntennaHeightM: txHeight,
        rxAntennaHeightM: rxHeight,
        frequencyMHz: frequency,
        table: options.clutterTable
    )
}

private nonisolated func itmNote(
    parameters: ITMParameters,
    mode: String,
    fallback: Bool,
    clutter: Bool,
    clutterSummary: String
) -> String {
    if fallback {
        var text = "Terrain was missing or ITM rejected the path, so this result uses the simplified model."
        if clutter { text += " \(clutterSummary)" }
        return text
    }
    var text = "ITM (Longley-Rice), \(mode), \(parameters.variability.title.lowercased()), \(Int(parameters.timePercent))/\(Int(parameters.locationPercent))/\(Int(parameters.situationPercent)). A prediction, not a measurement."
    if clutter {
        text += " \(clutterSummary)"
    } else {
        text += " Trees and buildings are ignored."
    }
    return text
}

private nonisolated func prefixPoints(_ points: [PathPoint], through distance: Double) -> [PathPoint] {
    let kept = points.filter { $0.distanceM <= distance + 0.5 }
    guard let last = kept.last else { return points }
    if abs(last.distanceM - distance) < 0.5 || kept.count < 2 {
        if kept.count >= 2 { return kept }
        let nearest = points.min { abs($0.distanceM - distance) < abs($1.distanceM - distance) }
        return [
            PathPoint(distanceM: 0, elevationM: points.first?.elevationM, landCoverCode: points.first?.landCoverCode),
            PathPoint(distanceM: distance, elevationM: nearest?.elevationM, landCoverCode: nearest?.landCoverCode)
        ]
    }
    return kept + [PathPoint(distanceM: distance, elevationM: last.elevationM, landCoverCode: last.landCoverCode)]
}

private nonisolated func filledGround(_ points: [PathPoint]) -> [Double]? {
    let known = points.enumerated().compactMap { index, point -> (Int, Double)? in
        guard let elevation = point.elevationM else { return nil }
        return (index, elevation)
    }
    guard known.count >= 2, let first = known.first, let last = known.last else { return nil }
    var values = Array(repeating: first.1, count: points.count)
    for index in 0..<first.0 { values[index] = first.1 }
    for index in last.0..<points.count { values[index] = last.1 }
    for pair in zip(known, known.dropFirst()) {
        let span = pair.1.0 - pair.0.0
        guard span > 0 else { continue }
        for index in pair.0.0...pair.1.0 {
            let fraction = Double(index - pair.0.0) / Double(span)
            values[index] = pair.0.1 + (pair.1.1 - pair.0.1) * fraction
        }
    }
    return values
}

private nonisolated func itmLoss(
    points: [PathPoint],
    txHeightM: Double,
    rxHeightM: Double,
    frequencyMHz: Double,
    parameters: ITMParameters
) -> ITMBridge.PathLoss? {
    guard let ground = filledGround(points), ground.count >= 2 else { return nil }
    let total = max(points.last?.distanceM ?? 1, 1)
    let spacing = total / Double(ground.count - 1)
    var profile = [Double(ground.count - 1), spacing]
    profile.append(contentsOf: ground)
    let result = ITMBridge.pointToPoint(
        profile: profile,
        txHeightM: txHeightM,
        rxHeightM: rxHeightM,
        frequencyMHz: frequencyMHz,
        parameters: parameters
    )
    guard result.succeeded, result.lossDb.isFinite else { return nil }
    return result
}

private nonisolated func directional(
    tx: RadioEndpoint,
    rx: RadioEndpoint,
    breakdown: LossBreakdown,
    pathLossDb: Double,
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
        pathLossDb: pathLossDb
    )
    return DirectionalLink(
        pathLossDb: pathLossDb,
        receivedPowerDbm: received,
        marginDb: received - sensitivity,
        eirpDbm: eirp,
        knifeEdgeLossDb: breakdown.knifeEdgeLossDb,
        fresnelClearanceRatio: breakdown.fresnelClearanceRatio,
        fresnelClear: breakdown.fresnelClearanceRatio >= 0.6,
        obstructed: breakdown.obstructed
    )
}
