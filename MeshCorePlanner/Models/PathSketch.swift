import Foundation
import SwiftData

@Model
final class PathSketch {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    /// JSON array of UUID strings. A primitive array is unreliable in the iOS 17 SwiftData store.
    var orderedSiteIDsJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        orderedSiteIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.orderedSiteIDsJSON = PathSketch.encode(orderedSiteIDs)
    }

    var orderedSiteIDs: [UUID] {
        get { PathSketch.decode(orderedSiteIDsJSON) }
        set {
            orderedSiteIDsJSON = PathSketch.encode(newValue)
            updatedAt = .now
        }
    }

    private static func encode(_ ids: [UUID]) -> String {
        let values = ids.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func decode(_ json: String) -> [UUID] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values.compactMap(UUID.init(uuidString:))
    }
}
