import Foundation
import SwiftData

/// Cached scalar result of a point-to-point analysis.
/// The terrain profile is recomputed when elevation is available.
@Model
final class PlannedLink {
    var id: UUID
    var name: String
    var fromSiteID: UUID
    var toSiteID: UUID
    var createdAt: Date
    var updatedAt: Date
    var distanceM: Double
    var bearingFromToDeg: Double
    var bearingToFromDeg: Double
    var forwardPathLossDb: Double
    var reversePathLossDb: Double
    var forwardReceivedDbm: Double
    var reverseReceivedDbm: Double
    var forwardMarginDb: Double
    var reverseMarginDb: Double
    var fresnelClearanceRatio: Double
    var fresnelClear: Bool
    var usedFreeSpaceFallback: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fromSiteID: UUID,
        toSiteID: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        distanceM: Double,
        bearingFromToDeg: Double,
        bearingToFromDeg: Double,
        forwardPathLossDb: Double,
        reversePathLossDb: Double,
        forwardReceivedDbm: Double,
        reverseReceivedDbm: Double,
        forwardMarginDb: Double,
        reverseMarginDb: Double,
        fresnelClearanceRatio: Double,
        fresnelClear: Bool,
        usedFreeSpaceFallback: Bool
    ) {
        self.id = id
        self.name = name
        self.fromSiteID = fromSiteID
        self.toSiteID = toSiteID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.distanceM = distanceM
        self.bearingFromToDeg = bearingFromToDeg
        self.bearingToFromDeg = bearingToFromDeg
        self.forwardPathLossDb = forwardPathLossDb
        self.reversePathLossDb = reversePathLossDb
        self.forwardReceivedDbm = forwardReceivedDbm
        self.reverseReceivedDbm = reverseReceivedDbm
        self.forwardMarginDb = forwardMarginDb
        self.reverseMarginDb = reverseMarginDb
        self.fresnelClearanceRatio = fresnelClearanceRatio
        self.fresnelClear = fresnelClear
        self.usedFreeSpaceFallback = usedFreeSpaceFallback
    }

    var weakestMarginDb: Double { min(forwardMarginDb, reverseMarginDb) }

    func update(from result: LinkResult, fromSite: PlannedSite, toSite: PlannedSite) {
        name = "\(fromSite.name) – \(toSite.name)"
        fromSiteID = fromSite.id
        toSiteID = toSite.id
        distanceM = result.distanceM
        bearingFromToDeg = result.bearingFromToDeg
        bearingToFromDeg = result.bearingToFromDeg
        forwardPathLossDb = result.forward.pathLossDb
        reversePathLossDb = result.reverse.pathLossDb
        forwardReceivedDbm = result.forward.receivedPowerDbm
        reverseReceivedDbm = result.reverse.receivedPowerDbm
        forwardMarginDb = result.forward.marginDb
        reverseMarginDb = result.reverse.marginDb
        fresnelClearanceRatio = result.forward.fresnelClearanceRatio
        fresnelClear = result.forward.fresnelClear
        usedFreeSpaceFallback = result.usedFreeSpaceFallback
        updatedAt = .now
    }
}
