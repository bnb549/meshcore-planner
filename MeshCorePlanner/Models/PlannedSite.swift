import Foundation
import SwiftData

nonisolated enum SiteRole: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case repeater
    case companion
    case roomServer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repeater: "Repeater"
        case .companion: "Companion"
        case .roomServer: "Room Server"
        }
    }

    var symbolName: String {
        switch self {
        case .repeater: "antenna.radiowaves.left.and.right"
        case .companion: "iphone"
        case .roomServer: "server.rack"
        }
    }
}

@Model
final class PlannedSite {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var antennaHeightM: Double
    var txPowerDbm: Double
    var frequencyMHz: Double
    var antennaGainDbi: Double
    var cableLossDb: Double
    var roleRaw: String
    var isVisible: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var hardwarePresetID: String?
    var radioPresetID: String?

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        antennaHeightM: Double = 10,
        txPowerDbm: Double = 22,
        frequencyMHz: Double = 910.525,
        antennaGainDbi: Double = 2,
        cableLossDb: Double = 0,
        role: SiteRole = .repeater,
        isVisible: Bool = true,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        hardwarePresetID: String? = "heltec-v3-v4",
        radioPresetID: String? = "us-canada"
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.antennaHeightM = antennaHeightM
        self.txPowerDbm = txPowerDbm
        self.frequencyMHz = frequencyMHz
        self.antennaGainDbi = antennaGainDbi
        self.cableLossDb = cableLossDb
        self.roleRaw = role.rawValue
        self.isVisible = isVisible
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hardwarePresetID = hardwarePresetID
        self.radioPresetID = radioPresetID
    }

    var role: SiteRole {
        get { SiteRole(rawValue: roleRaw) ?? .repeater }
        set { roleRaw = newValue.rawValue }
    }

    var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    func radioEndpoint() -> RadioEndpoint {
        RadioEndpoint(
            latitude: latitude,
            longitude: longitude,
            antennaHeightM: antennaHeightM,
            txPowerDbm: txPowerDbm,
            frequencyMHz: frequencyMHz,
            antennaGainDbi: antennaGainDbi,
            cableLossDb: cableLossDb
        )
    }

    func apply(hardware preset: HardwarePreset) {
        txPowerDbm = preset.defaultTxPowerDbm
        antennaGainDbi = preset.defaultGainDbi
        hardwarePresetID = preset.id
        updatedAt = .now
    }

    func apply(radio preset: RadioPreset) {
        frequencyMHz = preset.frequencyMHz
        radioPresetID = preset.id
        updatedAt = .now
    }

    /// Drops a preset id when the stored numbers leave that preset.
    /// Hardware stays attached while TX and gain remain inside the allowed range.
    /// A radio preset stays attached only while the frequency still matches.
    func reconcilePresetIDs() {
        if let hardwarePresetID, let preset = PresetLibrary.hardware(id: hardwarePresetID) {
            let txAllowed = txPowerDbm >= preset.minTxPowerDbm && txPowerDbm <= preset.maxTxPowerDbm
            let gainAllowed = antennaGainDbi >= preset.minGainDbi && antennaGainDbi <= preset.maxGainDbi
            if !txAllowed || !gainAllowed {
                self.hardwarePresetID = nil
            }
        }
        if let radioPresetID, let preset = PresetLibrary.radio(id: radioPresetID) {
            if abs(frequencyMHz - preset.frequencyMHz) > 0.000_5 {
                self.radioPresetID = nil
            }
        }
    }

    func validationError() -> PropagationError? {
        do {
            try PropagationMath.validate(endpoint: radioEndpoint())
            return nil
        } catch let error as PropagationError {
            return error
        } catch {
            return nil
        }
    }
}
