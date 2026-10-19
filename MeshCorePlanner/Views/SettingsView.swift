import SwiftUI

struct SettingsView: View {
    @Bindable var store: PlannerStore
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Reference handheld") {
                Text("Coverage is drawn for this receiver. Point-to-point links use each site’s own radio instead. The default threshold is -130 dBm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Stepper(value: $store.receiverSensitivityDbm, in: -150...(-70), step: 1) {
                    Text("Sensitivity \(Int(store.receiverSensitivityDbm.rounded())) dBm")
                }
                Stepper(value: $store.receiverHeightM, in: 0.5...100, step: 0.5) {
                    Text("Height \(String(format: "%.1f m", store.receiverHeightM))")
                }
                Stepper(value: $store.receiverGainDbi, in: -2...10, step: 0.5) {
                    Text("Gain \(String(format: "%.1f dBi", store.receiverGainDbi))")
                }
            }

            Section("Simulation") {
                VStack(alignment: .leading) {
                    Text("Maximum range \(String(format: "%.0f km", store.maxRangeKm))")
                    Slider(value: $store.maxRangeKm, in: 0.5...50, step: 0.5)
                        .accessibilityLabel("Maximum simulation range")
                }
                Text("High-resolution coverage is capped at 50 km.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Map") {
                Picker("Basemap", selection: $store.basemap) {
                    ForEach(Basemap.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Slider(value: $store.overlayOpacity, in: 0.15...0.8) {
                    Text("Coverage opacity")
                }
                Picker("Color scale", selection: $store.colorScale) {
                    ForEach(CoverageColorScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
            }

            Section("Terrain cache") {
                Button("Clear Cached Elevation", role: .destructive) { confirmClear = true }
                    .frame(minHeight: 44)
                Text("Sites stay on this device. Only downloaded elevation tiles are removed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("About") { AboutView() }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear cached elevation?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                Task { await store.clearTerrainCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The next coverage run will download terrain again, or fall back to a free-space estimate while offline.")
        }
    }
}
