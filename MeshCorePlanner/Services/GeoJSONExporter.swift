import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct JSONPayload: Transferable, Sendable {
    var filename: String
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { payload in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
            try Data(payload.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum GeoJSONExporter {
    static func featureCollection(
        sites: [PlannedSite],
        grids: [UUID: CoverageGrid],
        sensitivityDbm: Double
    ) -> String {
        var features: [[String: Any]] = []
        for site in sites where site.isVisible {
            features.append(siteFeature(site))
            if let grid = grids[site.id] {
                for cell in grid.cells where cell.rssiDbm >= sensitivityDbm {
                    features.append(coverageFeature(cell, site: site))
                }
            }
        }
        return jsonString(["type": "FeatureCollection", "features": features])
    }

    static func siteJSON(_ site: PlannedSite) -> String {
        jsonString(siteProperties(site))
    }

    static func siteSummary(_ site: PlannedSite) -> String {
        var lines = [
            "MeshCore Planner site",
            "Name: \(site.name)",
            "Role: \(site.role.title)",
            "Latitude: \(FieldFormat.coordinate(site.latitude))",
            "Longitude: \(FieldFormat.coordinate(site.longitude))",
            "Antenna height: \(String(format: "%.1f m", site.antennaHeightM))",
            "TX power: \(String(format: "%.0f dBm", site.txPowerDbm))",
            "Antenna gain: \(String(format: "%.1f dBi", site.antennaGainDbi))",
            "Cable loss: \(String(format: "%.1f dB", site.cableLossDb))",
            "Frequency: \(String(format: "%.3f MHz", site.frequencyMHz))"
        ]
        if let id = site.hardwarePresetID, let preset = PresetLibrary.hardware(id: id) {
            lines.append("Hardware: \(preset.name)")
        }
        if let id = site.radioPresetID, let preset = PresetLibrary.radio(id: id) {
            lines.append("Radio: \(preset.name)")
            lines.append(preset.budgetNote)
        }
        if !site.notes.isEmpty {
            lines.append("Notes: \(site.notes)")
        }
        lines.append("Visible: \(site.isVisible ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    private static func siteFeature(_ site: PlannedSite) -> [String: Any] {
        [
            "type": "Feature",
            "geometry": [
                "type": "Point",
                "coordinates": [site.longitude, site.latitude]
            ],
            "properties": siteProperties(site)
        ]
    }

    private static func siteProperties(_ site: PlannedSite) -> [String: Any] {
        var properties: [String: Any] = [
            "kind": "site",
            "id": site.id.uuidString,
            "name": site.name,
            "role": site.role.rawValue,
            "antennaHeightM": site.antennaHeightM,
            "txPowerDbm": site.txPowerDbm,
            "frequencyMHz": site.frequencyMHz,
            "antennaGainDbi": site.antennaGainDbi,
            "cableLossDb": site.cableLossDb,
            "isVisible": site.isVisible,
            "notes": site.notes
        ]
        if let hardwarePresetID = site.hardwarePresetID {
            properties["hardwarePreset"] = hardwarePresetID
        }
        if let radioPresetID = site.radioPresetID {
            properties["radioPreset"] = radioPresetID
        }
        return properties
    }

    private static func coverageFeature(_ cell: CoverageCell, site: PlannedSite) -> [String: Any] {
        [
            "type": "Feature",
            "geometry": [
                "type": "Polygon",
                "coordinates": [closedRing(cell.polygon)]
            ],
            "properties": [
                "kind": "coverage",
                "siteId": site.id.uuidString,
                "siteName": site.name,
                "rssiDbm": cell.rssiDbm,
                "innerRadiusM": cell.innerRadiusM,
                "outerRadiusM": cell.outerRadiusM
            ]
        ]
    }

    private static func closedRing(_ coordinates: [Coordinate]) -> [[Double]] {
        var ring = coordinates.map { [$0.longitude, $0.latitude] }
        if let first = ring.first, ring.last != first {
            ring.append(first)
        }
        return ring
    }

    private static func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"FeatureCollection\",\"features\":[]}"
        }
        return text
    }
}
