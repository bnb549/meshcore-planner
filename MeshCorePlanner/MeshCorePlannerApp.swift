import SwiftData
import SwiftUI

@main
struct MeshCorePlannerApp: App {
    @State private var store: PlannerStore

    init() {
        do {
            let schema = Schema([PlannedSite.self, PlannedLink.self, PathSketch.self])
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let store = PlannerStore(modelContext: container.mainContext, container: container)
            _store = State(initialValue: store)
        } catch {
            fatalError("Could not open the MeshCore Planner store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
        .modelContainer(store.container)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: store)
        }
        #endif
    }
}
