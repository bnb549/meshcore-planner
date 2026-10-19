import Foundation

nonisolated struct HardwarePreset: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var defaultTxPowerDbm: Double
    var minTxPowerDbm: Double
    var maxTxPowerDbm: Double
    var defaultGainDbi: Double
    var minGainDbi: Double
    var maxGainDbi: Double

    var gainIsFixed: Bool { abs(minGainDbi - maxGainDbi) < 0.01 }
    var powerIsFixed: Bool { abs(minTxPowerDbm - maxTxPowerDbm) < 0.01 }
}

nonisolated struct RadioPreset: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var frequencyMHz: Double
    var bandwidthKHz: Double
    var spreadingFactor: Int
    var codingRate: String?
    /// Planning note only. Coverage uses the sensitivity in Settings until the user applies this.
    var suggestedSensitivityDbm: Double

    var budgetNote: String {
        var parts = ["\(format(bandwidthKHz)) kHz bandwidth", "SF\(spreadingFactor)"]
        if let codingRate {
            parts.append(codingRate)
        }
        let detail = parts.joined(separator: ", ")
        return "\(detail). A typical planning sensitivity for this channel is about \(Int(suggestedSensitivityDbm)) dBm. Coverage uses the sensitivity in Settings until you apply this suggestion."
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

nonisolated enum PresetLibrary {
    static let hardware: [HardwarePreset] = [
        HardwarePreset(
            id: "heltec-v3-v4",
            name: "Heltec V3 / V4",
            defaultTxPowerDbm: 22,
            minTxPowerDbm: 20,
            maxTxPowerDbm: 22,
            defaultGainDbi: 2,
            minGainDbi: 2,
            maxGainDbi: 2
        ),
        HardwarePreset(
            id: "rak4631-wisblock",
            name: "RAK4631 / WisBlock",
            defaultTxPowerDbm: 22,
            minTxPowerDbm: 14,
            maxTxPowerDbm: 22,
            defaultGainDbi: 2,
            minGainDbi: 2,
            maxGainDbi: 2
        ),
        HardwarePreset(
            id: "lilygo-tbeam-techo",
            name: "LilyGo T-Beam / T-Echo",
            defaultTxPowerDbm: 20,
            minTxPowerDbm: 20,
            maxTxPowerDbm: 20,
            defaultGainDbi: 2,
            minGainDbi: 2,
            maxGainDbi: 2
        ),
        HardwarePreset(
            id: "station-g2",
            name: "Station G2",
            defaultTxPowerDbm: 27,
            minTxPowerDbm: 14,
            maxTxPowerDbm: 30,
            defaultGainDbi: 3,
            minGainDbi: 2,
            maxGainDbi: 5
        )
    ]

    static let radio: [RadioPreset] = [
        RadioPreset(
            id: "us-canada",
            name: "US/Canada",
            frequencyMHz: 910.525,
            bandwidthKHz: 62.5,
            spreadingFactor: 7,
            codingRate: "CR5 (4/5)",
            suggestedSensitivityDbm: -129
        ),
        RadioPreset(
            id: "us-canada-wide",
            name: "US/Canada Wide",
            frequencyMHz: 910.525,
            bandwidthKHz: 250,
            spreadingFactor: 7,
            codingRate: nil,
            suggestedSensitivityDbm: -123
        ),
        RadioPreset(
            id: "eu-uk-narrow",
            name: "EU/UK Narrow",
            frequencyMHz: 869.618,
            bandwidthKHz: 62.5,
            spreadingFactor: 8,
            codingRate: nil,
            suggestedSensitivityDbm: -132
        )
    ]

    static func hardware(id: String) -> HardwarePreset? {
        hardware.first { $0.id == id }
    }

    static func radio(id: String) -> RadioPreset? {
        radio.first { $0.id == id }
    }
}
