import Foundation

nonisolated enum FieldFormat {
    static func dBm(_ value: Double) -> String {
        String(format: "%.1f dBm", value)
    }

    static func decibels(_ value: Double) -> String {
        String(format: "%.1f dB", value)
    }

    static func distance(_ meters: Double) -> String {
        if meters < 1_000 {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.2f km", meters / 1_000)
    }

    static func area(_ squareMeters: Double) -> String {
        String(format: "%.2f km²", squareMeters / 1_000_000)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func coordinate(_ value: Double) -> String {
        String(format: "%.5f", value)
    }

    static func bearing(_ degrees: Double) -> String {
        String(format: "%.0f°", degrees)
    }
}
