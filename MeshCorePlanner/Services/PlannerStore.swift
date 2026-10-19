import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData
import SwiftUI

nonisolated enum Basemap: String, CaseIterable, Identifiable, Hashable, Sendable {
    case standard
    case hybrid
    case imagery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Hybrid"
        case .imagery: "Imagery"
        }
    }
}

nonisolated enum CoverageColorScale: String, CaseIterable, Identifiable, Hashable, Sendable {
    case coverage
    case heat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coverage: "Coverage"
        case .heat: "Heat"
        }
    }
}

nonisolated enum MapTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pan
    case drop
    case measure
    case sketch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan: "Pan"
        case .drop: "Drop"
        case .measure: "Measure"
        case .sketch: "Path"
        }
    }

    var symbolName: String {
        switch self {
        case .pan: "hand.draw"
        case .drop: "plus.circle"
        case .measure: "ruler"
        case .sketch: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct HopResult: Identifiable {
    var id: Int
    var fromID: UUID
    var toID: UUID
    var fromName: String
    var toName: String
    var distanceM: Double
    var marginDb: Double
    var from: Coordinate
    var to: Coordinate

    var midpoint: Coordinate {
        let bearing = GeoMath.bearingDeg(from: from, to: to)
        return GeoMath.destination(from: from, bearingDeg: bearing, distanceM: distanceM / 2)
    }
}

@MainActor
@Observable
final class PlannerStore {
    let container: ModelContainer
    private let modelContext: ModelContext
    let elevation: ElevationService
    private let injectedEngine: (any PropagationEngine)?

    var sites: [PlannedSite] = []
    var links: [PlannedLink] = []
    var sketches: [PathSketch] = []

    var selectedSiteID: UUID?
    var coverage: [UUID: CoverageGrid] = [:]
    private var coverageFingerprints: [UUID: String] = [:]
    var progress: [UUID: Double] = [:]
    var runningSiteIDs: Set<UUID> = []
    private var coverageTasks: [UUID: Task<Void, Never>] = [:]
    private var editRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var settingsRefreshTask: Task<Void, Never>?

    var simulationMessage: String?
    var highpointMessage: String?
    var highpointRunning = false
    var linkResult: LinkResult?
    var comparisonResult: LinkResult?
    var compareEngines = false
    var linkPair: (UUID, UUID)?
    var linkRunning = false
    var linkMessage: String?

    var mapTool: MapTool = .pan
    var measurePoints: [Coordinate] = []
    var sketchSiteIDs: [UUID] = []
    var sketchHops: [HopResult] = []
    var sketchRunning = false
    var sketchName = "Long hop"

    var cameraPosition: MapCameraPosition
    var mapCenter: Coordinate
    var latitudeDelta: Double
    var longitudeDelta: Double
    var mapSize: CGSize = CGSize(width: 400, height: 700)
    var locationDenied: Bool
    var showsUserLocation = false

    var receiverSensitivityDbm: Double {
        didSet { persist(receiverSensitivityDbm, SettingsKey.sensitivity) }
    }

    var maxRangeKm: Double {
        didSet {
            persist(maxRangeKm, SettingsKey.maxRange)
            scheduleSettingsRefresh()
        }
    }

    var receiverHeightM: Double {
        didSet {
            persist(receiverHeightM, SettingsKey.height)
            scheduleSettingsRefresh()
        }
    }

    var receiverGainDbi: Double {
        didSet {
            persist(receiverGainDbi, SettingsKey.gain)
            scheduleSettingsRefresh()
        }
    }

    var basemap: Basemap {
        didSet { UserDefaults.standard.set(basemap.rawValue, forKey: SettingsKey.basemap) }
    }

    var overlayOpacity: Double {
        didSet { persist(overlayOpacity, SettingsKey.opacity) }
    }

    var colorScale: CoverageColorScale {
        didSet { UserDefaults.standard.set(colorScale.rawValue, forKey: SettingsKey.colorScale) }
    }

    var propagationModel: PropagationModel {
        didSet { UserDefaults.standard.set(propagationModel.rawValue, forKey: SettingsKey.model) }
    }

    var simulationQuality: SimulationQuality {
        didSet { UserDefaults.standard.set(simulationQuality.rawValue, forKey: SettingsKey.quality) }
    }

    var itmClimate: ITMClimate {
        didSet { UserDefaults.standard.set(itmClimate.rawValue, forKey: SettingsKey.climate) }
    }

    var itmVariability: ITMVariability {
        didSet { UserDefaults.standard.set(itmVariability.rawValue, forKey: SettingsKey.variability) }
    }

    var itmPolarizationVertical: Bool {
        didSet { UserDefaults.standard.set(itmPolarizationVertical, forKey: SettingsKey.polarization) }
    }

    var itmTimePercent: Double {
        didSet { persist(itmTimePercent, SettingsKey.time) }
    }

    var itmLocationPercent: Double {
        didSet { persist(itmLocationPercent, SettingsKey.location) }
    }

    var itmSituationPercent: Double {
        didSet { persist(itmSituationPercent, SettingsKey.situation) }
    }

    var itmDielectric: Double {
        didSet { persist(itmDielectric, SettingsKey.dielectric) }
    }

    var itmConductivity: Double {
        didSet { persist(itmConductivity, SettingsKey.conductivity) }
    }

    var itmRefractivity: Double {
        didSet { persist(itmRefractivity, SettingsKey.refractivity) }
    }

    private let locationClient = LocationClient()

    init(modelContext: ModelContext, container: ModelContainer, elevation: ElevationService = ElevationService(), engine: (any PropagationEngine)? = nil) {
        self.modelContext = modelContext
        self.container = container
        self.elevation = elevation
        self.injectedEngine = engine

        let defaults = UserDefaults.standard
        let sensitivity = defaults.object(forKey: SettingsKey.sensitivity) as? Double ?? -130
        let range = defaults.object(forKey: SettingsKey.maxRange) as? Double ?? 30
        let height = defaults.object(forKey: SettingsKey.height) as? Double ?? 1.5
        let gain = defaults.object(forKey: SettingsKey.gain) as? Double ?? 2
        let opacity = defaults.object(forKey: SettingsKey.opacity) as? Double ?? 0.45
        let latitude = defaults.object(forKey: SettingsKey.latitude) as? Double ?? 39.7392
        let longitude = defaults.object(forKey: SettingsKey.longitude) as? Double ?? -104.9903
        let spanLat = defaults.object(forKey: SettingsKey.spanLatitude) as? Double ?? 0.45
        let spanLon = defaults.object(forKey: SettingsKey.spanLongitude) as? Double ?? 0.45
        receiverSensitivityDbm = sensitivity
        maxRangeKm = range
        receiverHeightM = height
        receiverGainDbi = gain
        overlayOpacity = opacity
        basemap = Basemap(rawValue: defaults.string(forKey: SettingsKey.basemap) ?? "") ?? .standard
        colorScale = CoverageColorScale(rawValue: defaults.string(forKey: SettingsKey.colorScale) ?? "") ?? .coverage
        propagationModel = PropagationModel(rawValue: defaults.string(forKey: SettingsKey.model) ?? "") ?? .itm
        simulationQuality = SimulationQuality(rawValue: defaults.string(forKey: SettingsKey.quality) ?? "") ?? .standard
        itmClimate = ITMClimate(rawValue: defaults.integer(forKey: SettingsKey.climate)) ?? .continentalTemperate
        itmVariability = ITMVariability(rawValue: defaults.object(forKey: SettingsKey.variability) as? Int ?? ITMVariability.broadcast.rawValue) ?? .broadcast
        itmPolarizationVertical = defaults.object(forKey: SettingsKey.polarization) as? Bool ?? true
        itmTimePercent = defaults.object(forKey: SettingsKey.time) as? Double ?? 50
        itmLocationPercent = defaults.object(forKey: SettingsKey.location) as? Double ?? 50
        itmSituationPercent = defaults.object(forKey: SettingsKey.situation) as? Double ?? 50
        itmDielectric = defaults.object(forKey: SettingsKey.dielectric) as? Double ?? 15
        itmConductivity = defaults.object(forKey: SettingsKey.conductivity) as? Double ?? 0.005
        itmRefractivity = defaults.object(forKey: SettingsKey.refractivity) as? Double ?? 301
        mapCenter = Coordinate(latitude: latitude, longitude: longitude)
        latitudeDelta = spanLat
        longitudeDelta = spanLon
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        ))
        locationDenied = locationClient.isDenied
        locationClient.onLocation = { [weak self] latitude, longitude in
            guard let self else { return }
            self.showsUserLocation = true
            self.centerMap(on: Coordinate(latitude: latitude, longitude: longitude))
        }
        locationClient.onAuthorizationChange = { [weak self] denied in
            self?.locationDenied = denied
        }
        reload()
    }

    var selectedSite: PlannedSite? {
        guard let selectedSiteID else { return nil }
        return sites.first { $0.id == selectedSiteID }
    }

    var elevationBanner: String? {
        let visible = sites.filter(\.isVisible)
        let statuses = visible.compactMap { coverage[$0.id]?.elevationStatus }
        if statuses.contains(.unavailable) {
            return "No terrain data. Showing a free-space estimate."
        }
        if statuses.contains(.partial) {
            return "Some elevation is unavailable. Those samples ignore terrain."
        }
        return nil
    }

    var activeProgress: (id: UUID, fraction: Double)? {
        if let selectedSiteID, let fraction = progress[selectedSiteID] {
            return (selectedSiteID, fraction)
        }
        guard let first = progress.first else { return nil }
        return (first.key, first.value)
    }

    var weakestSketchMargin: Double? {
        sketchHops.map(\.marginDb).min()
    }

    func reload() {
        sites = (try? modelContext.fetch(FetchDescriptor<PlannedSite>())) ?? []
        links = (try? modelContext.fetch(FetchDescriptor<PlannedLink>())) ?? []
        sketches = (try? modelContext.fetch(FetchDescriptor<PathSketch>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))) ?? []
    }

    func dropSite(at coordinate: Coordinate) {
        let index = sites.filter { $0.role == .repeater }.count + 1
        let site = PlannedSite(name: "Repeater \(index)", latitude: coordinate.latitude, longitude: coordinate.longitude)
        modelContext.insert(site)
        save()
        reload()
        selectedSiteID = site.id
        simulationMessage = nil
        highpointMessage = nil
    }

    func requestMyLocation() {
        guard !locationDenied else { return }
        locationClient.requestCurrentLocation()
    }

    func centerMap(on coordinate: Coordinate) {
        mapCenter = coordinate
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }

    func moveSite(_ site: PlannedSite, to coordinate: Coordinate, commit: Bool) {
        site.latitude = coordinate.latitude
        site.longitude = coordinate.longitude
        if commit {
            parametersDidChange(site)
        }
    }

    func setVisible(_ site: PlannedSite, _ visible: Bool) {
        site.isVisible = visible
        site.updatedAt = .now
        save()
        if visible, coverage[site.id] != nil, coverageFingerprints[site.id] != fingerprint(for: site) {
            estimateCoverage(for: site)
        }
    }

    func setAllVisible(_ visible: Bool) {
        for site in sites {
            site.isVisible = visible
            site.updatedAt = .now
        }
        save()
        if visible {
            for site in sites where coverage[site.id] != nil && coverageFingerprints[site.id] != fingerprint(for: site) {
                estimateCoverage(for: site)
            }
        }
    }

    func deleteSite(_ site: PlannedSite) {
        let id = site.id
        coverageTasks[id]?.cancel()
        coverageTasks[id] = nil
        runningSiteIDs.remove(id)
        progress[id] = nil
        coverage[id] = nil
        coverageFingerprints[id] = nil
        for link in links where link.fromSiteID == id || link.toSiteID == id {
            modelContext.delete(link)
        }
        for sketch in sketches {
            var ids = sketch.orderedSiteIDs
            let original = ids
            ids.removeAll { $0 == id }
            if ids.count < 2 {
                modelContext.delete(sketch)
            } else if ids != original {
                sketch.orderedSiteIDs = ids
            }
        }
        sketchSiteIDs.removeAll { $0 == id }
        sketchHops.removeAll { $0.fromID == id || $0.toID == id }
        if selectedSiteID == id { selectedSiteID = nil }
        if linkPair?.0 == id || linkPair?.1 == id {
            linkPair = nil
            linkResult = nil
        }
        modelContext.delete(site)
        save()
        reload()
    }

    func touch(_ site: PlannedSite) {
        site.updatedAt = .now
        save()
    }

    func parametersDidChange(_ site: PlannedSite) {
        site.reconcilePresetIDs()
        site.updatedAt = .now
        save()
        let id = site.id
        guard coverage[id] != nil else { return }
        editRefreshTasks[id]?.cancel()
        editRefreshTasks[id] = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let site = self.sites.first(where: { $0.id == id }) else { return }
            self.estimateCoverage(for: site)
        }
    }

    func estimateCoverage(for site: PlannedSite) {
        if let error = site.validationError() {
            simulationMessage = error.localizedDescription
            return
        }
        simulationMessage = nil
        let id = site.id
        let fingerprint = fingerprint(for: site)
        let request = coverageRequest(for: site)
        coverageTasks[id]?.cancel()
        runningSiteIDs.insert(id)
        progress[id] = 0
        let engine = selectedEngine()
        let elevation = self.elevation
        coverageTasks[id] = Task {
            let stream = engine.coverage(request, elevation: elevation)
            do {
                for try await update in stream {
                    if Task.isCancelled { return }
                    switch update {
                    case .progress(let fraction):
                        self.progress[id] = fraction
                    case .finished(let grid):
                        guard let current = self.sites.first(where: { $0.id == id }),
                              self.fingerprint(for: current) == fingerprint else { return }
                        self.coverage[id] = grid
                        self.coverageFingerprints[id] = fingerprint
                        self.progress[id] = nil
                        self.runningSiteIDs.remove(id)
                    }
                }
            } catch is CancellationError {
                self.progress[id] = nil
                self.runningSiteIDs.remove(id)
            } catch {
                self.progress[id] = nil
                self.runningSiteIDs.remove(id)
                self.simulationMessage = error.localizedDescription
            }
        }
    }

    func cancelCoverage(for id: UUID) {
        coverageTasks[id]?.cancel()
        coverageTasks[id] = nil
        progress[id] = nil
        runningSiteIDs.remove(id)
    }

    func analyzeLink(from: PlannedSite, to: PlannedSite) async {
        if let error = from.validationError() ?? to.validationError() {
            linkMessage = error.localizedDescription
            return
        }
        linkRunning = true
        linkMessage = nil
        comparisonResult = nil
        linkPair = (from.id, to.id)
        defer { linkRunning = false }
        let request = LinkRequest(from: from.radioEndpoint(), to: to.radioEndpoint(), sensitivityDbm: receiverSensitivityDbm)
        let primary = selectedEngine()
        let secondary = compareEngines ? alternateEngine() : nil
        do {
            let result = try await primary.link(request, elevation: elevation)
            linkResult = result
            if let secondary {
                comparisonResult = try await secondary.link(request, elevation: elevation)
            }
            upsertLink(from: from, to: to, result: result)
        } catch is CancellationError {
            return
        } catch {
            linkMessage = error.localizedDescription
        }
    }

    func cachedLink(from: UUID, to: UUID) -> PlannedLink? {
        links.first { link in
            (link.fromSiteID == from && link.toSiteID == to) || (link.fromSiteID == to && link.toSiteID == from)
        }
    }

    func findHighpoint(for site: PlannedSite, radiusKm: Double) async {
        guard site.latitude.isFinite, site.longitude.isFinite else {
            highpointMessage = PropagationError.invalidCoordinate.localizedDescription
            return
        }
        let radius = min(5_000, max(200, radiusKm * 1_000))
        var step = max(90, radius / 12)
        var coordinates = highpointSamples(around: site.coordinate, radius: radius, step: step)
        while coordinates.count > 400 {
            step *= 1.25
            coordinates = highpointSamples(around: site.coordinate, radius: radius, step: step)
        }
        highpointRunning = true
        highpointMessage = nil
        defer { highpointRunning = false }
        do {
            let batch = try await elevation.elevations(at: coordinates)
            let ranked = zip(coordinates, batch.samples).compactMap { coordinate, sample -> (Coordinate, Double)? in
                guard let elevation = sample.elevationM else { return nil }
                return (coordinate, elevation)
            }
            guard let best = ranked.max(by: { $0.1 < $1.1 }) else {
                highpointMessage = "No elevation data in that radius."
                return
            }
            let origin = site.coordinate
            let moved = GeoMath.distanceM(from: origin, to: best.0)
            let originElevation = zip(coordinates, batch.samples).min { lhs, rhs in
                GeoMath.distanceM(from: lhs.0, to: origin) < GeoMath.distanceM(from: rhs.0, to: origin)
            }?.1.elevationM
            site.coordinate = best.0
            parametersDidChange(site)
            if let originElevation {
                let gain = best.1 - originElevation
                highpointMessage = "Snapped \(FieldFormat.distance(moved)) to \(Int(best.1.rounded())) m ground (\(gain >= 0 ? "+" : "")\(Int(gain.rounded())) m)."
            } else {
                highpointMessage = "Snapped \(FieldFormat.distance(moved)) to \(Int(best.1.rounded())) m ground."
            }
        } catch is CancellationError {
            return
        } catch {
            highpointMessage = error.localizedDescription
        }
    }

    func addMeasurePoint(_ coordinate: Coordinate) {
        if measurePoints.count >= 2 {
            measurePoints.removeAll()
        }
        measurePoints.append(coordinate)
    }

    var measureSummary: String? {
        guard measurePoints.count == 2 else { return nil }
        let distance = GeoMath.distanceM(from: measurePoints[0], to: measurePoints[1])
        let bearing = GeoMath.bearingDeg(from: measurePoints[0], to: measurePoints[1])
        return "\(FieldFormat.distance(distance))  ·  \(FieldFormat.bearing(bearing))"
    }

    func appendSketchSite(_ site: PlannedSite) {
        guard sketchSiteIDs.last != site.id else { return }
        sketchSiteIDs.append(site.id)
        sketchHops = []
    }

    func removeLastSketchSite() {
        guard !sketchSiteIDs.isEmpty else { return }
        var ids = sketchSiteIDs
        ids.removeLast()
        sketchSiteIDs = ids
        sketchHops = []
    }

    func removeSketchSites(at offsets: IndexSet) {
        var ids = sketchSiteIDs
        for index in offsets.sorted(by: >) where ids.indices.contains(index) {
            ids.remove(at: index)
        }
        sketchSiteIDs = ids
        sketchHops = []
    }

    func clearSketch() {
        sketchSiteIDs = []
        sketchHops = []
    }

    func analyzeSketch() async {
        let ordered = sketchSiteIDs.compactMap { id in sites.first { $0.id == id } }
        guard ordered.count >= 2 else { return }
        sketchRunning = true
        defer { sketchRunning = false }
        var hops: [HopResult] = []
        for index in ordered.indices.dropLast() {
            let from = ordered[index]
            let to = ordered[index + 1]
            if let error = from.validationError() ?? to.validationError() {
                simulationMessage = error.localizedDescription
                return
            }
            let request = LinkRequest(from: from.radioEndpoint(), to: to.radioEndpoint(), sensitivityDbm: receiverSensitivityDbm)
            let engine = selectedEngine()
            do {
                let result = try await engine.link(request, elevation: elevation)
                hops.append(HopResult(
                    id: index,
                    fromID: from.id,
                    toID: to.id,
                    fromName: from.name,
                    toName: to.name,
                    distanceM: result.distanceM,
                    marginDb: result.weakestMarginDb,
                    from: from.coordinate,
                    to: to.coordinate
                ))
                upsertLink(from: from, to: to, result: result)
            } catch is CancellationError {
                return
            } catch {
                simulationMessage = error.localizedDescription
                return
            }
        }
        sketchHops = hops
    }

    func saveSketch() {
        let ids = sketchSiteIDs
        guard ids.count >= 2 else { return }
        let name = sketchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sketch = PathSketch(name: name.isEmpty ? "Long hop" : name, orderedSiteIDs: ids)
        modelContext.insert(sketch)
        save()
        reload()
    }

    func loadSketch(_ sketch: PathSketch) {
        sketchSiteIDs = sketch.orderedSiteIDs
        sketchName = sketch.name
        sketchHops = []
        mapTool = .sketch
    }

    func deleteSketch(_ sketch: PathSketch) {
        modelContext.delete(sketch)
        save()
        reload()
    }

    func clearTerrainCache() async {
        await elevation.clearCache()
    }

    func noteRegion(_ region: MKCoordinateRegion) {
        mapCenter = Coordinate(latitude: region.center.latitude, longitude: region.center.longitude)
        latitudeDelta = region.span.latitudeDelta
        longitudeDelta = region.span.longitudeDelta
        let defaults = UserDefaults.standard
        defaults.set(region.center.latitude, forKey: SettingsKey.latitude)
        defaults.set(region.center.longitude, forKey: SettingsKey.longitude)
        defaults.set(region.span.latitudeDelta, forKey: SettingsKey.spanLatitude)
        defaults.set(region.span.longitudeDelta, forKey: SettingsKey.spanLongitude)
    }

    func updateMapSize(_ size: CGSize) {
        guard abs(size.width - mapSize.width) > 1 || abs(size.height - mapSize.height) > 1 else { return }
        mapSize = size
    }

    func distanceFromCenter(_ site: PlannedSite) -> Double {
        GeoMath.distanceM(from: mapCenter, to: site.coordinate)
    }

    func coverageFingerprintsMatch(_ site: PlannedSite) -> Bool {
        coverageFingerprints[site.id] == fingerprint(for: site)
    }

    func fingerprint(for site: PlannedSite) -> String {
        [
            String(format: "%.5f", site.latitude),
            String(format: "%.5f", site.longitude),
            String(format: "%.2f", site.antennaHeightM),
            String(format: "%.2f", site.txPowerDbm),
            String(format: "%.2f", site.antennaGainDbi),
            String(format: "%.2f", site.cableLossDb),
            String(format: "%.3f", site.frequencyMHz),
            String(format: "%.2f", receiverHeightM),
            String(format: "%.2f", receiverGainDbi),
            String(format: "%.2f", maxRangeKm),
            propagationModel.rawValue,
            simulationQuality.rawValue,
            String(itmClimate.rawValue),
            String(itmVariability.rawValue),
            itmPolarizationVertical ? "V" : "H",
            String(format: "%.0f", itmTimePercent),
            String(format: "%.0f", itmLocationPercent),
            String(format: "%.0f", itmSituationPercent),
            String(format: "%.2f", itmDielectric),
            String(format: "%.4f", itmConductivity),
            String(format: "%.0f", itmRefractivity)
        ].joined(separator: "|")
    }

    func geoJSONPayload() -> JSONPayload {
        JSONPayload(
            filename: "meshcore-planner.geojson",
            text: GeoJSONExporter.featureCollection(
                sites: sites,
                grids: coverage,
                sensitivityDbm: receiverSensitivityDbm
            )
        )
    }

    private func coverageRequest(for site: PlannedSite) -> CoverageRequest {
        CoverageRequest(
            transmitter: site.radioEndpoint(),
            maxRangeM: maxRangeKm * 1_000,
            receiverHeightM: receiverHeightM,
            receiverGainDbi: receiverGainDbi,
            receiverCableLossDb: 0,
            sensitivityDbm: receiverSensitivityDbm,
            radialCount: simulationQuality.radialCount,
            ringCount: simulationQuality.ringCount,
            sampleSpacingM: simulationQuality.sampleSpacingM
        )
    }

    private func currentITMParameters() -> ITMParameters {
        ITMParameters(
            climate: itmClimate,
            polarizationVertical: itmPolarizationVertical,
            dielectric: itmDielectric,
            conductivity: itmConductivity,
            refractivity: itmRefractivity,
            variability: itmVariability,
            timePercent: itmTimePercent,
            locationPercent: itmLocationPercent,
            situationPercent: itmSituationPercent
        )
    }

    private func makeEngine(_ model: PropagationModel) -> any PropagationEngine {
        switch model {
        case .itm:
            ITMPropagationEngine(parameters: currentITMParameters(), sampleSpacingM: simulationQuality.sampleSpacingM)
        case .simplified:
            SimplifiedTerrainEngine()
        }
    }

    private func selectedEngine() -> any PropagationEngine {
        if let injectedEngine { return injectedEngine }
        return makeEngine(propagationModel)
    }

    private func alternateEngine() -> any PropagationEngine {
        makeEngine(propagationModel == .itm ? .simplified : .itm)
    }

    private func scheduleSettingsRefresh() {
        settingsRefreshTask?.cancel()
        settingsRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            for site in self.sites where self.coverage[site.id] != nil {
                self.estimateCoverage(for: site)
            }
        }
    }

    private func upsertLink(from: PlannedSite, to: PlannedSite, result: LinkResult) {
        let record = links.first { link in
            (link.fromSiteID == from.id && link.toSiteID == to.id) || (link.fromSiteID == to.id && link.toSiteID == from.id)
        } ?? {
            let created = PlannedLink(
                name: "\(from.name) – \(to.name)",
                fromSiteID: from.id,
                toSiteID: to.id,
                distanceM: result.distanceM,
                bearingFromToDeg: result.bearingFromToDeg,
                bearingToFromDeg: result.bearingToFromDeg,
                forwardPathLossDb: result.forward.pathLossDb,
                reversePathLossDb: result.reverse.pathLossDb,
                forwardReceivedDbm: result.forward.receivedPowerDbm,
                reverseReceivedDbm: result.reverse.receivedPowerDbm,
                forwardMarginDb: result.forward.marginDb,
                reverseMarginDb: result.reverse.marginDb,
                fresnelClearanceRatio: result.forward.fresnelClearanceRatio,
                fresnelClear: result.forward.fresnelClear,
                usedFreeSpaceFallback: result.usedFreeSpaceFallback
            )
            modelContext.insert(created)
            return created
        }()
        record.update(from: result, fromSite: from, toSite: to)
        save()
        reload()
    }

    private func highpointSamples(around center: Coordinate, radius: Double, step: Double) -> [Coordinate] {
        var samples = [center]
        var north = -radius
        while north <= radius + 0.1 {
            var east = -radius
            while east <= radius + 0.1 {
                if east * east + north * north <= radius * radius {
                    let distance = hypot(east, north)
                    if distance >= 1 {
                        let bearing = atan2(east, north) * 180 / .pi
                        samples.append(GeoMath.destination(from: center, bearingDeg: bearing, distanceM: distance))
                    }
                }
                east += step
            }
            north += step
        }
        return samples
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            simulationMessage = "Could not save. \(error.localizedDescription)"
        }
    }

    private func persist(_ value: Double, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

private enum SettingsKey {
    static let sensitivity = "receiverSensitivityDbm"
    static let maxRange = "maxRangeKm"
    static let height = "receiverHeightM"
    static let gain = "receiverGainDbi"
    static let basemap = "basemap"
    static let opacity = "coverageOpacity"
    static let colorScale = "coverageColorScale"
    static let latitude = "mapLatitude"
    static let longitude = "mapLongitude"
    static let spanLatitude = "mapSpanLatitude"
    static let spanLongitude = "mapSpanLongitude"
    static let model = "propagationModel"
    static let quality = "simulationQuality"
    static let climate = "itmClimate"
    static let variability = "itmVariability"
    static let polarization = "itmPolarizationVertical"
    static let time = "itmTimePercent"
    static let location = "itmLocationPercent"
    static let situation = "itmSituationPercent"
    static let dielectric = "itmDielectric"
    static let conductivity = "itmConductivity"
    static let refractivity = "itmRefractivity"
}
