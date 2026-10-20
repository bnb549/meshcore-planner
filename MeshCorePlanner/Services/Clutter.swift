import CoreGraphics
import Foundation
import ImageIO

// MARK: - Clutter table

/// One ESA WorldCover class and the through-clutter loss charged while the ray is inside it.
nonisolated struct ClutterClassSetting: Codable, Equatable, Identifiable, Sendable {
    var code: Int
    var name: String
    var attenuationDbPerMeter: Double
    var heightM: Double
    /// Maximum dB this class can add on one path, after the frequency scale.
    var maxLossDb: Double

    var id: Int { code }

    private enum CodingKeys: String, CodingKey {
        case code, name, attenuationDbPerMeter, heightM, maxLossDb
    }

    init(code: Int, name: String, attenuationDbPerMeter: Double, heightM: Double, maxLossDb: Double) {
        self.code = code
        self.name = name
        self.attenuationDbPerMeter = attenuationDbPerMeter
        self.heightM = heightM
        self.maxLossDb = maxLossDb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(Int.self, forKey: .code)
        self.code = code
        name = try container.decode(String.self, forKey: .name)
        attenuationDbPerMeter = try container.decode(Double.self, forKey: .attenuationDbPerMeter)
        heightM = try container.decode(Double.self, forKey: .heightM)
        // Older saved tables have no cap. Keep their rates and fill the shipped cap.
        maxLossDb = try container.decodeIfPresent(Double.self, forKey: .maxLossDb)
            ?? ClutterTable.defaultMaxLossDb(for: code)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encode(attenuationDbPerMeter, forKey: .attenuationDbPerMeter)
        try container.encode(heightM, forKey: .heightM)
        try container.encode(maxLossDb, forKey: .maxLossDb)
    }
}

/// User-editable attenuation. A ray above `heightM` is not charged.
/// Bare ground, snow, and water add nothing.
///
/// 0.3.1 planning caps, applied after each segment and again to the path:
/// tree cover 0.02 dB/m and at most 20 dB; built-up 0.01 dB/m and at most 18 dB.
/// Those two caps are stricter than every other class (24 dB). The path then
/// stops at 35 dB. Other class rates are the 0.3.0 values. At 900 MHz, 2 m
/// antennas, and flat ground, 600 m of trees plus 800 m of built-up (a 4 km
/// path, the rest grass) adds 20 dB. A longer mixed path stops at 35 dB.
nonisolated struct ClutterTable: Codable, Equatable, Sendable {
    var classes: [ClutterClassSetting]

    /// Ceiling on the sum of every class on one path.
    static let maxTotalLossDb = 35.0

    /// Tree cover and built-up are the strictest. Every other class uses 24 dB.
    static func defaultMaxLossDb(for code: Int) -> Double {
        switch code {
        case 10: return 20
        case 50: return 18
        default: return 24
        }
    }

    static let meshCoreDefault = ClutterTable(classes: [
        ClutterClassSetting(code: 10, name: "Tree cover", attenuationDbPerMeter: 0.02, heightM: 15, maxLossDb: defaultMaxLossDb(for: 10)),
        ClutterClassSetting(code: 20, name: "Shrubland", attenuationDbPerMeter: 0.08, heightM: 2, maxLossDb: defaultMaxLossDb(for: 20)),
        ClutterClassSetting(code: 30, name: "Grassland", attenuationDbPerMeter: 0.01, heightM: 0.5, maxLossDb: defaultMaxLossDb(for: 30)),
        ClutterClassSetting(code: 40, name: "Cropland", attenuationDbPerMeter: 0.02, heightM: 1, maxLossDb: defaultMaxLossDb(for: 40)),
        ClutterClassSetting(code: 50, name: "Built-up", attenuationDbPerMeter: 0.01, heightM: 10, maxLossDb: defaultMaxLossDb(for: 50)),
        ClutterClassSetting(code: 60, name: "Bare or sparse", attenuationDbPerMeter: 0, heightM: 0, maxLossDb: defaultMaxLossDb(for: 60)),
        ClutterClassSetting(code: 70, name: "Snow and ice", attenuationDbPerMeter: 0, heightM: 0, maxLossDb: defaultMaxLossDb(for: 70)),
        ClutterClassSetting(code: 80, name: "Open water", attenuationDbPerMeter: 0, heightM: 0, maxLossDb: defaultMaxLossDb(for: 80)),
        ClutterClassSetting(code: 90, name: "Herbaceous wetland", attenuationDbPerMeter: 0.05, heightM: 1, maxLossDb: defaultMaxLossDb(for: 90)),
        ClutterClassSetting(code: 95, name: "Mangrove", attenuationDbPerMeter: 0.35, heightM: 12, maxLossDb: defaultMaxLossDb(for: 95)),
        ClutterClassSetting(code: 100, name: "Moss and lichen", attenuationDbPerMeter: 0.02, heightM: 0.3, maxLossDb: defaultMaxLossDb(for: 100))
    ])

    func setting(for code: Int) -> ClutterClassSetting? {
        classes.first { $0.code == code }
    }

    func mergingMissingDefaults() -> ClutterTable {
        var merged = classes
        for item in Self.meshCoreDefault.classes where !merged.contains(where: { $0.code == item.code }) {
            merged.append(item)
        }
        merged.sort { $0.code < $1.code }
        return ClutterTable(classes: merged)
    }

    func fingerprint() -> String {
        classes
            .sorted { $0.code < $1.code }
            .map { String(format: "%d:%.3f:%.1f:%.1f", $0.code, $0.attenuationDbPerMeter, $0.heightM, $0.maxLossDb) }
            .joined(separator: ",")
    }
}

nonisolated struct ClutterLossResult: Sendable, Equatable {
    var lossDb: Double
    var summary: String
    var incomplete: Bool

    static let none = ClutterLossResult(lossDb: 0, summary: "", incomplete: false)
}

nonisolated enum ClutterMath {
    /// Weissberger-style frequency tilt. The table is normalized at 900 MHz.
    static func frequencyScale(frequencyMHz: Double) -> Double {
        let gigahertz = max(frequencyMHz, 1) / 1_000
        return pow(gigahertz / 0.9, 0.284)
    }

    /// Additive loss for the portion of the path where the straight ray is below the class height.
    /// Each segment is clamped to the remaining per-class cap and the remaining 35 dB path cap before it is added.
    /// Missing class or elevation on a segment adds nothing and marks the result incomplete.
    static func loss(
        points: [PathPoint],
        txAntennaHeightM: Double,
        rxAntennaHeightM: Double,
        frequencyMHz: Double,
        table: ClutterTable
    ) -> ClutterLossResult {
        guard points.count >= 2 else {
            return ClutterLossResult(lossDb: 0, summary: "No land-cover samples on this path.", incomplete: true)
        }
        let total = max(points.last?.distanceM ?? 1, 1)
        let scale = frequencyScale(frequencyMHz: frequencyMHz)
        let txGround = points.first?.elevationM ?? 0
        let rxGround = points.last?.elevationM ?? 0
        let hTx = txGround + txAntennaHeightM
        let hRx = rxGround + rxAntennaHeightM
        var lossDb = 0.0
        var charged: [Int: (distance: Double, loss: Double)] = [:]
        var incomplete = false
        var sawClass = false

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let length = end.distanceM - start.distanceM
            guard length > 0.5 else { continue }
            guard let code = start.landCoverCode ?? end.landCoverCode else {
                incomplete = true
                continue
            }
            sawClass = true
            guard let setting = table.setting(for: code),
                  setting.attenuationDbPerMeter > 0,
                  setting.heightM > 0 else { continue }
            guard let startGround = start.elevationM, let endGround = end.elevationM else {
                incomplete = true
                continue
            }
            let mid = (start.distanceM + end.distanceM) / 2
            let chord = hTx + (hRx - hTx) * (mid / total)
            let aboveGround = chord - (startGround + endGround) / 2
            guard aboveGround < setting.heightM else { continue }
            let raw = setting.attenuationDbPerMeter * scale * length
            let already = charged[code]?.loss ?? 0
            let classRoom = max(0, setting.maxLossDb - already)
            let pathRoom = max(0, ClutterTable.maxTotalLossDb - lossDb)
            let segmentLoss = min(raw, min(classRoom, pathRoom))
            lossDb += segmentLoss
            var entry = charged[code] ?? (0, 0)
            entry.distance += length
            entry.loss += segmentLoss
            charged[code] = entry
        }

        if !sawClass { incomplete = true }
        let parts = charged.keys.sorted().compactMap { code -> String? in
            guard let setting = table.setting(for: code), let entry = charged[code], entry.loss > 0 else { return nil }
            return "\(setting.name.lowercased()) \(Int(entry.distance.rounded())) m"
        }
        let summary: String
        if lossDb > 0 {
            let list = parts.joined(separator: ", ")
            if lossDb >= ClutterTable.maxTotalLossDb - 0.05 {
                summary = String(format: "Clutter added %.1f dB from %@. That is the %.0f dB path cap.", lossDb, list, ClutterTable.maxTotalLossDb)
            } else {
                summary = String(format: "Clutter added %.1f dB from %@.", lossDb, list)
            }
        } else if incomplete {
            summary = "Land cover is incomplete. No clutter loss was added where the class was unknown."
        } else {
            summary = "Land cover was sampled. The ray stays above the clutter, so no extra loss was added."
        }
        return ClutterLossResult(lossDb: lossDb, summary: summary, incomplete: incomplete)
    }
}

// MARK: - Recipes, confidence, comparison

nonisolated enum EngineRecipe: String, CaseIterable, Identifiable, Sendable {
    case itm
    case itmClutter
    case simplified
    case simplifiedMultiEdge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itm: "ITM"
        case .itmClutter: "ITM + clutter"
        case .simplified: "Simplified"
        case .simplifiedMultiEdge: "Simplified + multi-edge"
        }
    }

    var model: PropagationModel {
        switch self {
        case .itm, .itmClutter: .itm
        case .simplified, .simplifiedMultiEdge: .simplified
        }
    }

    var includeClutter: Bool { self == .itmClutter }
    var multiEdge: Bool { self == .simplifiedMultiEdge }
}

nonisolated enum EngineTitle {
    static func name(model: PropagationModel, clutter: Bool, multiEdge: Bool, fallback: Bool) -> String {
        if fallback {
            return clutter ? "Simplified + clutter" : "Simplified"
        }
        switch model {
        case .itm:
            return clutter ? "ITM + clutter" : "ITM (Longley-Rice)"
        case .simplified:
            if multiEdge && clutter { return "Simplified + multi-edge + clutter" }
            if multiEdge { return "Simplified + multi-edge" }
            if clutter { return "Simplified + clutter" }
            return "Simplified"
        }
    }
}

/// A coarse cue for an ITM run. Not a statistical coverage map.
nonisolated enum PlanningConfidence: String, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    static func itm(
        sampleSpacingM: Double,
        timePercent: Double,
        locationPercent: Double,
        situationPercent: Double,
        elevationStatus: ElevationStatus,
        resolutionReduced: Bool
    ) -> PlanningConfidence {
        var rank = 1
        if sampleSpacingM <= 90 {
            rank = 2
        } else if sampleSpacingM > 180 {
            rank = 0
        }
        let nearMedian = abs(timePercent - 50) <= 10
            && abs(locationPercent - 50) <= 10
            && abs(situationPercent - 50) <= 10
        if !nearMedian { rank -= 1 }
        if elevationStatus == .partial || elevationStatus == .unavailable || resolutionReduced {
            rank -= 1
        }
        switch rank {
        case 2...: return .high
        case 1: return .medium
        default: return .low
        }
    }
}

nonisolated struct SimulationOptions: Sendable {
    var includeClutter: Bool = false
    var clutterTable: ClutterTable = .meshCoreDefault
    var multiEdgeDiffraction: Bool = false
    var adaptiveSampling: Bool = false
    var landCover: (any LandCoverProviding)? = nil
}

nonisolated struct CoverageComparison: Sendable, Equatable {
    var primaryName: String
    var secondaryName: String
    var meanDeltaDb: Double
    var maxAbsDeltaDb: Double
    var areaBeyondThresholdM2: Double
    var thresholdDb: Double
    var comparedCells: Int
}

nonisolated enum CoverageComparisonMath {
    /// Primary RSSI minus comparison RSSI. Cells match on id, then on ring geometry.
    static func compare(primary: CoverageGrid, secondary: CoverageGrid, thresholdDb: Double) -> CoverageComparison {
        let threshold = max(0, thresholdDb)
        var sum = 0.0
        var maxAbs = 0.0
        var area = 0.0
        var count = 0
        let byID = Dictionary(uniqueKeysWithValues: secondary.cells.map { ($0.id, $0) })
        for cell in primary.cells {
            let other = byID[cell.id] ?? secondary.cells.first { candidate in
                abs(candidate.innerRadiusM - cell.innerRadiusM) < 1
                    && abs(candidate.startBearingDeg - cell.startBearingDeg) < 0.1
            }
            guard let other else { continue }
            let delta = cell.rssiDbm - other.rssiDbm
            sum += delta
            maxAbs = max(maxAbs, abs(delta))
            if abs(delta) > threshold { area += cell.sectorAreaM2 }
            count += 1
        }
        return CoverageComparison(
            primaryName: primary.engineName,
            secondaryName: secondary.engineName,
            meanDeltaDb: count > 0 ? sum / Double(count) : 0,
            maxAbsDeltaDb: maxAbs,
            areaBeyondThresholdM2: area,
            thresholdDb: threshold,
            comparedCells: count
        )
    }
}

// MARK: - Land cover

nonisolated struct LandCoverBatch: Sendable {
    var codes: [Int?]
    var status: ElevationStatus
}

nonisolated protocol LandCoverProviding: Sendable {
    func classes(at coordinates: [Coordinate]) async throws -> LandCoverBatch
}

/// Maps an ESA WorldCover colormap pixel to a class code. Unknown colors add no loss.
nonisolated enum LandCoverClassifier {
    static let palette: [(code: Int, red: UInt8, green: UInt8, blue: UInt8)] = [
        (10, 0, 100, 0),
        (20, 255, 187, 34),
        (30, 255, 255, 76),
        (40, 240, 150, 255),
        (50, 250, 0, 0),
        (60, 180, 180, 180),
        (70, 240, 240, 240),
        (80, 0, 100, 200),
        (90, 0, 150, 160),
        (95, 0, 207, 117),
        (100, 250, 230, 160)
    ]

    static func code(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) -> Int? {
        guard alpha >= 16 else { return nil }
        var bestCode: Int?
        var bestDistance = Int.max
        for entry in palette {
            let distance = abs(Int(red) - Int(entry.red))
                + abs(Int(green) - Int(entry.green))
                + abs(Int(blue) - Int(entry.blue))
            if distance < bestDistance {
                bestDistance = distance
                bestCode = entry.code
            }
        }
        guard bestDistance <= 36 else { return nil }
        return bestCode
    }
}

/// Fetches ESA WorldCover 2021 v200 colormap tiles and caches them locally.
/// Requests contain tile indexes only. Do not add site names, power, or radio settings.
/// The published map is 10 m. Tiles are sampled at web-mercator zoom 13, about 15 m at mid-latitudes.
actor LandCoverService: LandCoverProviding {
    static let tileZoom = 13

    private let session: URLSession
    private let cacheRoot: URL
    private var memoryTiles: [TileIndex: DecodedLandCover] = [:]

    init(cacheRoot: URL? = nil, session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.httpCookieAcceptPolicy = .never
        self.session = session ?? URLSession(configuration: configuration)
        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.cacheRoot = base.appendingPathComponent("MeshCorePlannerCache", isDirectory: true)
        }
    }

    /// Public WMTS URL. The query is the layer, tile matrix, column, and row. Nothing else about the site.
    static func tileURL(z: Int, x: Int, y: Int) -> URL {
        var components = URLComponents(string: "https://wmts.terrascope.be/wmts")!
        components.queryItems = [
            URLQueryItem(name: "SERVICE", value: "WMTS"),
            URLQueryItem(name: "REQUEST", value: "GetTile"),
            URLQueryItem(name: "VERSION", value: "1.0.0"),
            URLQueryItem(name: "LAYER", value: "esa-worldcover-map-10m-2021-v2_map"),
            URLQueryItem(name: "STYLE", value: "default"),
            URLQueryItem(name: "FORMAT", value: "image/png"),
            URLQueryItem(name: "TILEMATRIXSET", value: "EPSG:3857"),
            URLQueryItem(name: "TILEMATRIX", value: String(z)),
            URLQueryItem(name: "TILEROW", value: String(y)),
            URLQueryItem(name: "TILECOL", value: String(x)),
            URLQueryItem(name: "TIME", value: "2021-01-01")
        ]
        return components.url!
    }

    static func tileIndex(for coordinate: Coordinate, zoom: Int = tileZoom) -> (tile: TileIndex, x: Int, y: Int) {
        LandCoverIndex.pixel(for: coordinate, zoom: zoom)
    }

    func clearCache() {
        memoryTiles.removeAll()
        let folder = cacheRoot.appendingPathComponent("LandCoverTiles", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    func classes(at coordinates: [Coordinate]) async throws -> LandCoverBatch {
        try Task.checkCancellation()
        if coordinates.isEmpty {
            return LandCoverBatch(codes: [], status: .cache)
        }
        var codes = [Int?](repeating: nil, count: coordinates.count)
        var sawLive = false
        var sawCache = false
        let zoom = Self.tileZoom
        var grouped: [TileIndex: [(Int, Int, Int)]] = [:]
        for (index, coordinate) in coordinates.enumerated() {
            let pixel = LandCoverIndex.pixel(for: coordinate, zoom: zoom)
            grouped[pixel.tile, default: []].append((index, pixel.x, pixel.y))
        }
        for (tile, pixels) in grouped {
            try Task.checkCancellation()
            let decoded: DecodedLandCover
            let fromCache: Bool
            do {
                let loaded = try await loadTile(tile)
                decoded = loaded.tile
                fromCache = loaded.fromCache
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            if fromCache { sawCache = true } else { sawLive = true }
            for (index, px, py) in pixels {
                let x = min(decoded.width - 1, max(0, px * decoded.width / 256))
                let y = min(decoded.height - 1, max(0, py * decoded.height / 256))
                let offset = (y * decoded.width + x) * 4
                guard offset + 3 < decoded.pixels.count else { continue }
                codes[index] = LandCoverClassifier.code(
                    red: decoded.pixels[offset],
                    green: decoded.pixels[offset + 1],
                    blue: decoded.pixels[offset + 2],
                    alpha: decoded.pixels[offset + 3]
                )
            }
        }
        let any = codes.contains { $0 != nil }
        let missing = codes.contains { $0 == nil }
        let status: ElevationStatus
        if !any {
            status = .unavailable
        } else if missing {
            status = .partial
        } else if sawLive {
            status = .live
        } else if sawCache {
            status = .cache
        } else {
            status = .cache
        }
        return LandCoverBatch(codes: codes, status: status)
    }

    private func loadTile(_ tile: TileIndex) async throws -> (tile: DecodedLandCover, fromCache: Bool) {
        if let cached = memoryTiles[tile] {
            return (cached, true)
        }
        let file = cacheFile(tile)
        if let data = try? Data(contentsOf: file), let decoded = Self.decode(data) {
            memoryTiles[tile] = decoded
            return (decoded, true)
        }
        let url = Self.tileURL(z: tile.z, x: tile.x, y: tile.y)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LandCoverTileFailure.failed
        }
        guard let decoded = Self.decode(data) else { throw LandCoverTileFailure.failed }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        memoryTiles[tile] = decoded
        return (decoded, false)
    }

    static func cacheURL(root: URL, z: Int, x: Int, y: Int) -> URL {
        root
            .appendingPathComponent("LandCoverTiles", isDirectory: true)
            .appendingPathComponent("\(z)", isDirectory: true)
            .appendingPathComponent("\(x)", isDirectory: true)
            .appendingPathComponent("\(y).png")
    }

    private func cacheFile(_ tile: TileIndex) -> URL {
        Self.cacheURL(root: cacheRoot, z: tile.z, x: tile.x, y: tile.y)
    }

    private static func decode(_ data: Data) -> DecodedLandCover? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmap
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        return DecodedLandCover(width: width, height: height, pixels: pixels)
    }
}

private nonisolated struct DecodedLandCover: Sendable {
    var width: Int
    var height: Int
    var pixels: [UInt8]
}

private nonisolated enum LandCoverTileFailure: Error {
    case failed
}

private nonisolated enum LandCoverIndex {
    static func pixel(for coordinate: Coordinate, zoom: Int) -> (tile: TileIndex, x: Int, y: Int) {
        let clampedLatitude = min(85.051_128_78, max(-85.051_128_78, coordinate.latitude))
        let n = Double(1 << zoom)
        let xFloat = (coordinate.longitude + 180) / 360 * n
        let latitudeRadians = clampedLatitude * .pi / 180
        let yFloat = (1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / .pi) / 2 * n
        let limit = (1 << zoom) - 1
        var tileX = Int(floor(xFloat))
        tileX = (tileX % (limit + 1) + (limit + 1)) % (limit + 1)
        let tileY = min(limit, max(0, Int(floor(yFloat))))
        let pixelX = min(255, max(0, Int((xFloat - floor(xFloat)) * 256)))
        let pixelY = min(255, max(0, Int((yFloat - floor(yFloat)) * 256)))
        return (TileIndex(z: zoom, x: tileX, y: tileY), pixelX, pixelY)
    }
}
