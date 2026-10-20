import Foundation
import CoreGraphics
import ImageIO

nonisolated enum ElevationResolutionPreference: String, CaseIterable, Identifiable, Sendable {
    case prefer30m
    case coarse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prefer30m: "30 m when available"
        case .coarse: "About 90 m"
        }
    }
}

nonisolated enum TerrainTileOutcome: Equatable, Sendable {
    case missing
    case rejected
    case failed
}

/// Fetches SRTM-derived elevation and caches it locally.
/// Requests contain tile indexes or sample coordinates only. Do not add site names, power, or radio settings.
/// Zoom 12 is about 30 m at mid-latitudes. Zoom 11, about 70–90 m, is the fallback.
actor ElevationService: ElevationProviding {
    static let terrainZoom = 11
    static let preferredZoom = 12

    private let session: URLSession
    private let cacheRoot: URL
    private var memoryTiles: [TileIndex: DecodedTile] = [:]
    private var pointCache: [String: Double] = [:]
    private var loadedPointCache = false
    private var terrariumDisabled = false
    private var preference: ElevationResolutionPreference = .prefer30m

    /// A 404 on a finer zoom is a miss. A 404 on zoom 11, or an auth failure, disables terrarium for this process.
    static func terrainTileError(statusCode: Int, zoom: Int) -> TerrainTileOutcome? {
        guard !(200...299).contains(statusCode) else { return nil }
        if statusCode == 404, zoom > terrainZoom { return .missing }
        if statusCode == 401 || statusCode == 403 || statusCode == 404 || statusCode == 410 { return .rejected }
        return .failed
    }

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

    /// Public tile URL. The path is `terrarium/{z}/{x}/{y}.png` and nothing else.
    static func terrariumURL(z: Int, x: Int, y: Int) -> URL {
        URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(z)/\(x)/\(y).png")!
    }

    func setPreference(_ preference: ElevationResolutionPreference) {
        self.preference = preference
    }

    func clearCache() {
        memoryTiles.removeAll()
        pointCache.removeAll()
        loadedPointCache = true
        terrariumDisabled = false
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    func elevations(at coordinates: [Coordinate]) async throws -> ElevationBatch {
        try Task.checkCancellation()
        if coordinates.isEmpty {
            return ElevationBatch(samples: [], status: .cache)
        }
        var values = Array<Double?>(repeating: nil, count: coordinates.count)
        var sawLive = false
        var fineFilled = Set<Int>()

        if !terrariumDisabled {
            let zoom = preference == .prefer30m ? Self.preferredZoom : Self.terrainZoom
            let outcome = try await fillFromTerrarium(coordinates, zoom: zoom, into: &values, filled: &fineFilled)
            sawLive = outcome.sawLive
            if outcome.rejected {
                terrariumDisabled = true
                values = Array(repeating: nil, count: coordinates.count)
                fineFilled.removeAll()
                sawLive = false
            } else if preference == .prefer30m {
                let missing = values.indices.filter { values[$0] == nil }
                if !missing.isEmpty && !terrariumDisabled {
                    var ignored = Set<Int>()
                    let fallback = try await fillFromTerrarium(
                        coordinates,
                        zoom: Self.terrainZoom,
                        only: missing,
                        into: &values,
                        filled: &ignored
                    )
                    if fallback.sawLive { sawLive = true }
                    if fallback.rejected {
                        terrariumDisabled = true
                    }
                }
            }
        }

        let missing = values.indices.filter { values[$0] == nil }
        if !missing.isEmpty {
            let outcome = try await fillFromOpenMeteo(coordinates, indexes: Array(missing), into: &values)
            if outcome.sawLive { sawLive = true }
        }

        let anyValue = values.contains { $0 != nil }
        let anyMissing = values.contains { $0 == nil }
        let status: ElevationStatus
        if !anyValue {
            status = .unavailable
        } else if anyMissing {
            status = .partial
        } else if sawLive {
            status = .live
        } else {
            status = .cache
        }
        let wantsFine = preference == .prefer30m
        let anyCoarse = wantsFine && values.indices.contains { values[$0] != nil && !fineFilled.contains($0) }
        let note = anyCoarse
            ? "30 m elevation was unavailable for part of this path. Coarser cached or zoom-11 terrain was used."
            : nil
        return ElevationBatch(
            samples: values.map { ElevationSample(elevationM: $0) },
            status: status,
            resolutionReduced: anyCoarse,
            resolutionNote: note
        )
    }

    private struct FillOutcome {
        var sawLive = false
        var sawCache = false
        var rejected = false
    }

    private func fillFromTerrarium(
        _ coordinates: [Coordinate],
        zoom: Int,
        only indexes: [Int]? = nil,
        into values: inout [Double?],
        filled: inout Set<Int>
    ) async throws -> FillOutcome {
        var outcome = FillOutcome()
        let target = indexes ?? Array(coordinates.indices)
        var grouped: [TileIndex: [(Int, Int, Int)]] = [:]
        for index in target where values[index] == nil && coordinates.indices.contains(index) {
            let pixel = TerrainIndex.pixel(for: coordinates[index], zoom: zoom)
            grouped[pixel.tile, default: []].append((index, pixel.x, pixel.y))
        }
        for (tile, pixels) in grouped {
            try Task.checkCancellation()
            let decoded: DecodedTile
            let fromCache: Bool
            do {
                let loaded = try await loadTile(tile)
                decoded = loaded.tile
                fromCache = loaded.fromCache
            } catch TileFailure.missing {
                continue
            } catch TileFailure.rejected {
                outcome.rejected = true
                return outcome
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            if fromCache { outcome.sawCache = true } else { outcome.sawLive = true }
            for (index, px, py) in pixels {
                let x = min(decoded.width - 1, max(0, px * decoded.width / 256))
                let y = min(decoded.height - 1, max(0, py * decoded.height / 256))
                values[index] = Double(decoded.elevations[y * decoded.width + x])
                filled.insert(index)
            }
        }
        return outcome
    }

    private func loadTile(_ tile: TileIndex) async throws -> (tile: DecodedTile, fromCache: Bool) {
        if let cached = memoryTiles[tile] {
            return (cached, true)
        }
        let file = tileFile(tile)
        if let data = try? Data(contentsOf: file), let decoded = Self.decodeTerrarium(data) {
            memoryTiles[tile] = decoded
            return (decoded, true)
        }
        let url = Self.terrariumURL(z: tile.z, x: tile.x, y: tile.y)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse,
           let failure = Self.terrainTileError(statusCode: http.statusCode, zoom: tile.z) {
            switch failure {
            case .missing: throw TileFailure.missing
            case .rejected: throw TileFailure.rejected
            case .failed: throw TileFailure.failed
            }
        }
        guard let decoded = Self.decodeTerrarium(data) else { throw TileFailure.failed }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        memoryTiles[tile] = decoded
        return (decoded, false)
    }

    private func fillFromOpenMeteo(
        _ coordinates: [Coordinate],
        indexes: [Int],
        into values: inout [Double?]
    ) async throws -> FillOutcome {
        try loadPointCacheIfNeeded()
        var outcome = FillOutcome()
        var unresolved: [Int] = []
        for index in indexes {
            let key = Self.pointKey(coordinates[index])
            if let cached = pointCache[key] {
                values[index] = cached
                outcome.sawCache = true
            } else {
                unresolved.append(index)
            }
        }
        var cursor = 0
        while cursor < unresolved.count {
            try Task.checkCancellation()
            let end = min(cursor + 100, unresolved.count)
            let slice = Array(unresolved[cursor..<end])
            cursor = end
            let fetched = try await requestOpenMeteo(coordinates: slice.map { coordinates[$0] })
            if let fetched {
                outcome.sawLive = true
                for (offset, index) in slice.enumerated() where offset < fetched.count {
                    let elevation = fetched[offset]
                    values[index] = elevation
                    pointCache[Self.pointKey(coordinates[index])] = elevation
                }
                persistPointCache()
            }
        }
        return outcome
    }

    /// Anonymous elevation query. The query items are latitude and longitude only.
    private func requestOpenMeteo(coordinates: [Coordinate]) async throws -> [Double]? {
        guard !coordinates.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: coordinates.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: coordinates.map { String($0.longitude) }.joined(separator: ","))
        ]
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(OpenMeteoElevation.self, from: data)
            return decoded.elevation
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func tileFile(_ tile: TileIndex) -> URL {
        cacheRoot
            .appendingPathComponent("TerrainTiles", isDirectory: true)
            .appendingPathComponent("\(tile.z)", isDirectory: true)
            .appendingPathComponent("\(tile.x)", isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
    }

    private func loadPointCacheIfNeeded() throws {
        guard !loadedPointCache else { return }
        loadedPointCache = true
        let url = cacheRoot.appendingPathComponent("elevation-points.json")
        guard let data = try? Data(contentsOf: url) else { return }
        pointCache = (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    private func persistPointCache() {
        let url = cacheRoot.appendingPathComponent("elevation-points.json")
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(pointCache) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func pointKey(_ coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }

    static func decodeTerrarium(_ data: Data) -> DecodedTile? {
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
            let bitmap = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
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
        var elevations = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let red = Float(pixels[index * 4])
            let green = Float(pixels[index * 4 + 1])
            let blue = Float(pixels[index * 4 + 2])
            elevations[index] = (red * 256 + green + blue / 256) - 32_768
        }
        return DecodedTile(width: width, height: height, elevations: elevations)
    }
}

private nonisolated enum TileFailure: Error {
    case missing
    case rejected
    case failed
}

nonisolated struct TileIndex: Hashable, Sendable {
    var z: Int
    var x: Int
    var y: Int
}

nonisolated struct DecodedTile: Sendable {
    var width: Int
    var height: Int
    var elevations: [Float]
}

private nonisolated struct OpenMeteoElevation: Decodable, Sendable {
    var elevation: [Double]
}

private nonisolated enum TerrainIndex {
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
