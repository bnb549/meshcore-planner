import MapKit
import SwiftUI

struct MapCanvasView: View {
    @Bindable var store: PlannerStore
    var showsSiteListButton: Bool
    var onShowSites: () -> Void
    var onShowSettings: () -> Void
    var onSelectSite: (PlannedSite) -> Void

    @State private var showDisplay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MapReader { proxy in
            Map(position: $store.cameraPosition) {
                ForEach(drawnPolygons) { polygon in
                    MapPolygon(coordinates: polygon.coordinates)
                        .foregroundStyle(polygon.color.opacity(store.overlayOpacity))
                }
                if let measureLine {
                    MapPolyline(coordinates: measureLine, contourStyle: .geodesic)
                        .stroke(.white, lineWidth: 3)
                    if store.measurePoints.count == 2 {
                        Annotation("Measure", coordinate: midpoint(store.measurePoints[0], store.measurePoints[1])) {
                            Text(store.measureSummary ?? "")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                if sketchLine.count >= 2 {
                    MapPolyline(coordinates: sketchLine, contourStyle: .geodesic)
                        .stroke(.white, lineWidth: 3)
                }
                ForEach(store.sketchHops) { hop in
                    Annotation("Hop \(hop.id + 1)", coordinate: mapCoordinate(hop.midpoint)) {
                        Text("\(hop.id + 1)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Hop \(hop.id + 1), margin \(FieldFormat.dBm(hop.marginDb))")
                    }
                }
                ForEach(store.sites) { site in
                    Annotation(site.name, coordinate: mapCoordinate(site.coordinate), anchor: .bottom) {
                        SiteMarker(
                            site: site,
                            selected: store.selectedSiteID == site.id,
                            mapSize: store.mapSize,
                            latitudeDelta: store.latitudeDelta,
                            longitudeDelta: store.longitudeDelta,
                            onSelect: { onSelectSite(site) },
                            onMove: { coordinate, commit in
                                store.moveSite(site, to: coordinate, commit: commit)
                            }
                        )
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .simultaneousGesture(tapGesture(proxy))
            .simultaneousGesture(longPressGesture(proxy))
            .onMapCameraChange(frequency: .onEnd) { context in
                store.noteRegion(context.region)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { store.updateMapSize(geometry.size) }
                        .onChange(of: geometry.size) { _, size in
                            store.updateMapSize(size)
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Drop repeater at map center")) {
            store.dropSite(at: store.mapCenter)
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: store.overlayOpacity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
    }

    private var bottomChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.sites.isEmpty {
                emptyCard
            }
            if let banner = store.elevationBanner {
                statusLine(banner, systemImage: "exclamationmark.triangle")
            }
            if let summary = store.measureSummary, store.mapTool == .measure {
                statusLine(summary, systemImage: "ruler")
            }
            if let highpoint = store.highpointMessage {
                statusLine(highpoint, systemImage: "mountain.2")
            }
            if let message = store.simulationMessage {
                statusLine(message, systemImage: "info.circle")
            }
            if let progress = store.activeProgress {
                HStack(spacing: 12) {
                    ProgressView(value: progress.fraction)
                        .accessibilityLabel("Coverage progress")
                        .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                    Button("Cancel") { store.cancelCoverage(for: progress.id) }
                        .frame(minHeight: 44)
                }
            }
            if store.sites.contains(where: { $0.isVisible && store.coverage[$0.id] != nil }) {
                CoverageLegend(scale: store.colorScale, sensitivity: store.receiverSensitivityDbm)
            }
            toolRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Drop the first repeater", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            Text("Long-press the map to place a site. Companions do not relay, so coverage comes from dedicated repeaters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Drop at map center") {
                store.dropSite(at: store.mapCenter)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .combine)
    }

    private var toolRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapTool.allCases) { tool in
                    Button {
                        store.mapTool = tool
                        if tool != .measure { store.measurePoints = [] }
                    } label: {
                        Image(systemName: tool.symbolName)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(store.mapTool == tool ? Color.accentColor : Color.primary)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(store.mapTool == tool ? .isSelected : [])
                }
                Button(action: store.requestMyLocation) {
                    Image(systemName: "location")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(store.locationDenied)
                .accessibilityLabel("My Location")
                .accessibilityHint(store.locationDenied ? "Location permission is off. The map still works." : "Drops a repeater at your current location.")
                Menu {
                    Picker("Basemap", selection: $store.basemap) {
                        ForEach(Basemap.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                } label: {
                    Image(systemName: "map")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Basemap, \(store.basemap.title)")
                Button { showDisplay = true } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Coverage display")
                .popover(isPresented: $showDisplay) {
                    displayControls
                }
                if showsSiteListButton {
                    Button(action: onShowSites) {
                        Image(systemName: "list.bullet")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Sites")
                }
                Button(action: onShowSettings) {
                    Image(systemName: "gearshape")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Settings")
                ShareLink(item: store.geoJSONPayload(), preview: SharePreview("Visible sites")) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Export visible sites as GeoJSON")
            }
            .padding(.vertical, 2)
        }
    }

    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coverage display")
                .font(.headline)
            Text("Opacity and colors use the stored signal levels.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Slider(value: $store.overlayOpacity, in: 0.15...0.8) {
                Text("Opacity")
            }
            .accessibilityLabel("Coverage opacity")
            Picker("Colors", selection: $store.colorScale) {
                ForEach(CoverageColorScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            CoverageLegend(scale: store.colorScale, sensitivity: store.receiverSensitivityDbm)
        }
        .padding()
        .frame(minWidth: 280)
    }

    private var mapStyle: MapStyle {
        switch store.basemap {
        case .standard: .standard(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        }
    }

    private var drawnPolygons: [DrawnPolygon] {
        store.sites.filter(\.isVisible).flatMap { site in
            guard let grid = store.coverage[site.id] else { return [DrawnPolygon]() }
            return grid.cells.compactMap { cell in
                guard cell.rssiDbm >= store.receiverSensitivityDbm else { return nil }
                return DrawnPolygon(
                    id: "\(site.id.uuidString)-\(cell.id)",
                    coordinates: cell.polygon.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    },
                    color: CoverageStyle.color(
                        rssi: cell.rssiDbm,
                        sensitivity: store.receiverSensitivityDbm,
                        scale: store.colorScale
                    )
                )
            }
        }
    }

    private var measureLine: [CLLocationCoordinate2D]? {
        guard store.measurePoints.count == 2 else { return nil }
        return store.measurePoints.map(mapCoordinate)
    }

    private var sketchLine: [CLLocationCoordinate2D] {
        store.sketchSiteIDs.compactMap { id in
            store.sites.first { $0.id == id }.map { mapCoordinate($0.coordinate) }
        }
    }

    private func tapGesture(_ proxy: MapProxy) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let converted = proxy.convert(value.location, from: .local) else { return }
            let coordinate = Coordinate(latitude: converted.latitude, longitude: converted.longitude)
            switch store.mapTool {
            case .drop:
                store.dropSite(at: coordinate)
            case .measure:
                store.addMeasurePoint(coordinate)
            case .pan, .sketch:
                break
            }
        }
    }

    private func longPressGesture(_ proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard store.mapTool != .drop else { return }
                guard case .second(true, let drag) = value, let location = drag?.location,
                      let converted = proxy.convert(location, from: .local) else { return }
                store.dropSite(at: Coordinate(latitude: converted.latitude, longitude: converted.longitude))
            }
    }

    private func mapCoordinate(_ coordinate: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func midpoint(_ start: Coordinate, _ end: Coordinate) -> CLLocationCoordinate2D {
        let distance = GeoMath.distanceM(from: start, to: end)
        let bearing = GeoMath.bearingDeg(from: start, to: end)
        return mapCoordinate(GeoMath.destination(from: start, bearingDeg: bearing, distanceM: distance / 2))
    }

    private func statusLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}

private struct DrawnPolygon: Identifiable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
    var color: Color
}

enum CoverageStyle {
    static func color(rssi: Double, sensitivity: Double, scale: CoverageColorScale) -> Color {
        let strong = -80.0
        let span = strong - sensitivity
        let amount = span == 0 ? 1 : min(1, max(0, (rssi - sensitivity) / span))
        switch scale {
        case .coverage:
            return Color(hue: 0.08 + 0.28 * amount, saturation: 0.72, brightness: 0.9)
        case .heat:
            return Color(hue: 0.62 * (1 - amount), saturation: 0.78, brightness: 0.95)
        }
    }
}

struct CoverageLegend: View {
    var scale: CoverageColorScale
    var sensitivity: Double

    var body: some View {
        HStack(spacing: 10) {
            swatch("Strong", rssi: -80)
            swatch("Fair", rssi: (sensitivity + -80) / 2)
            swatch("Marginal", rssi: sensitivity)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coverage colors from strong to marginal at \(Int(sensitivity)) dBm")
    }

    private func swatch(_ title: String, rssi: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(CoverageStyle.color(rssi: rssi, sensitivity: sensitivity, scale: scale))
                .frame(width: 14, height: 14)
            Text(title)
        }
    }
}

struct SiteMarker: View {
    var site: PlannedSite
    var selected: Bool
    var mapSize: CGSize
    var latitudeDelta: Double
    var longitudeDelta: Double
    var onSelect: () -> Void
    var onMove: (Coordinate, Bool) -> Void

    @State private var dragOrigin: Coordinate?

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: site.role.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(site.isVisible ? site.role.tint : Color.gray.opacity(0.55)))
                .overlay {
                    Circle().strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: site.isVisible ? [] : [4, 3])
                    )
                    .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 3)
                        .padding(-4)
                }
            Text(site.name)
                .font(.caption2)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .opacity(site.isVisible ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(site.name), \(site.role.title)")
        .accessibilityValue(site.isVisible ? "Visible" : "Hidden")
        .accessibilityHint("Selects the site. Drag to move it.")
        .accessibilityAddTraits(.isButton)
        .onTapGesture(perform: onSelect)
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard mapSize.width > 1, mapSize.height > 1, latitudeDelta > 0, longitudeDelta > 0 else { return }
                if dragOrigin == nil { dragOrigin = site.coordinate }
                guard let dragOrigin else { return }
                onMove(shifted(from: dragOrigin, by: value.translation), false)
            }
            .onEnded { value in
                guard let dragOrigin else { return }
                onMove(shifted(from: dragOrigin, by: value.translation), true)
                self.dragOrigin = nil
            }
    }

    private func shifted(from origin: Coordinate, by translation: CGSize) -> Coordinate {
        let latitude = origin.latitude - Double(translation.height) / mapSize.height * latitudeDelta
        let longitude = origin.longitude + Double(translation.width) / mapSize.width * longitudeDelta
        return Coordinate(latitude: latitude, longitude: GeoMath.normalizeLongitude(longitude))
    }
}

extension SiteRole {
    var tint: Color {
        switch self {
        case .repeater: .orange
        case .companion: .teal
        case .roomServer: .indigo
        }
    }
}
