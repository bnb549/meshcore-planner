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
                Picker("Propagation", selection: $store.propagationModel) {
                    ForEach(PropagationModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .accessibilityLabel("Propagation engine")
                Picker("Density", selection: $store.simulationQuality) {
                    ForEach(SimulationQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .accessibilityLabel("Coverage density")
                VStack(alignment: .leading) {
                    Text("Maximum range \(String(format: "%.0f km", store.maxRangeKm))")
                    Slider(value: $store.maxRangeKm, in: 0.5...50, step: 0.5)
                        .accessibilityLabel("Maximum simulation range")
                }
                Text("ITM is the default. Simplified is the fast fallback when terrain is missing. Fine density uses closer samples and stays capped at 50 km. Recompute a site after changing the engine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("ITM assumptions") {
                Picker("Climate", selection: $store.itmClimate) {
                    ForEach(ITMClimate.allCases) { climate in
                        Text(climate.title).tag(climate)
                    }
                }
                Picker("Variability", selection: $store.itmVariability) {
                    ForEach(ITMVariability.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Vertical polarization", isOn: $store.itmPolarizationVertical)
                    .accessibilityHint("LoRa planning uses vertical polarization.")
                Stepper(value: $store.itmTimePercent, in: 1...99, step: 1) {
                    Text("Time \(Int(store.itmTimePercent.rounded()))%")
                }
                Stepper(value: $store.itmLocationPercent, in: 1...99, step: 1) {
                    Text("Location \(Int(store.itmLocationPercent.rounded()))%")
                }
                Stepper(value: $store.itmSituationPercent, in: 1...99, step: 1) {
                    Text("Situation \(Int(store.itmSituationPercent.rounded()))%")
                }
                Stepper(value: $store.itmDielectric, in: 2...80, step: 1) {
                    Text("Dielectric \(Int(store.itmDielectric.rounded()))")
                }
                Stepper(value: $store.itmConductivity, in: 0.001...0.05, step: 0.001) {
                    Text("Conductivity \(String(format: "%.3f S/m", store.itmConductivity))")
                }
                Stepper(value: $store.itmRefractivity, in: 250...400, step: 1) {
                    Text("Refractivity \(Int(store.itmRefractivity.rounded())) N")
                }
                Text("The default 50/50/50 broadcast case is a median prediction, in the spirit of an F(50,50) curve. ITM ignores buildings and trees. It is not a guarantee.")
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
