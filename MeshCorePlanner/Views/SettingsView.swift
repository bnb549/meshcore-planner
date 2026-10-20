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
                Toggle("Include clutter", isOn: $store.includeClutter)
                    .accessibilityHint("Adds land-cover loss after ITM or Simplified. Off adds nothing. Recompute to apply it.")
                Toggle("Multi-edge diffraction", isOn: $store.multiEdgeDiffraction)
                    .accessibilityHint("Simplified engine only. Sums knife edges across more than one ridge.")
                Picker("Elevation", selection: $store.elevationResolution) {
                    ForEach(ElevationResolutionPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .accessibilityLabel("Elevation resolution")
                InspectorNote(text: "ITM is the default. Simplified is the fast fallback when terrain is missing. Fine density uses closer samples and stays capped at 50 km. 30 m terrain is used when the tile service has it, and about 90 m otherwise. Recompute after changing the engine, clutter, or diffraction. Turning those off does not recompute by itself.")
            }

            Section("Land-cover clutter") {
                InspectorNote(text: "Defaults are a capped planning excess near 900 MHz. A ray above the class height is not charged. Tree cover starts at 0.02 dB/m and stops at 20 dB on a path. Built-up starts at 0.01 dB/m and stops at 18 dB. Other classes keep their earlier rates and stop at 24 dB. The whole path stops at 35 dB. Open water, bare ground, and snow stay at zero. Raise a rate if you want that class to reach its cap on a shorter path. Reset Clutter Defaults loads these rates. A table you already saved stays as you saved it until you reset.")
                ForEach($store.clutterTable.classes) { $entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.body)
                        Stepper(value: $entry.attenuationDbPerMeter, in: 0...2, step: 0.01) {
                            Text(String(format: "%.2f dB/m", entry.attenuationDbPerMeter))
                        }
                        .accessibilityLabel("\(entry.name) attenuation")
                        Stepper(value: $entry.heightM, in: 0...40, step: 0.5) {
                            Text(String(format: "Height %.1f m", entry.heightM))
                        }
                        .accessibilityLabel("\(entry.name) height")
                    }
                }
                Button("Reset Clutter Defaults") { store.resetClutterTable() }
                    .frame(minHeight: 44)
            }

            Section("Engine comparison") {
                Picker("Comparison", selection: $store.comparisonRecipe) {
                    ForEach(EngineRecipe.allCases) { recipe in
                        Text(recipe.title).tag(recipe)
                    }
                }
                Stepper(value: $store.comparisonThresholdDb, in: 1...30, step: 1) {
                    Text("Delta area threshold \(Int(store.comparisonThresholdDb.rounded())) dB")
                }
                Toggle("Show site overlay", isOn: $store.showPrimaryOverlay)
                Toggle("Show comparison overlay", isOn: $store.showComparisonOverlay)
                InspectorNote(text: "Compare from a site to run ITM, ITM + clutter, Simplified, or Simplified + multi-edge on the same coverage. The mean and maximum are the difference in dB. Hidden sites draw neither overlay.")
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
                InspectorNote(text: "The default 50/50/50 broadcast case is a median prediction, in the spirit of an F(50,50) curve. ITM itself ignores buildings and trees. Include clutter to add land-cover loss after that prediction. The confidence badge reads the variability percentages and how dense the elevation samples are. It is not a guarantee.")
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
                Button("Clear Cached Terrain", role: .destructive) { confirmClear = true }
                    .frame(minHeight: 44)
                InspectorNote(text: "Sites stay on this device. This removes downloaded elevation and land-cover tiles. The next run uses whatever is still cached, or warns when the finer data is missing.")
            }

            Section {
                NavigationLink("About") { AboutView() }
            }
        }
        .navigationTitle("Settings")
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .confirmationDialog("Clear cached terrain and land cover?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                Task { await store.clearTerrainCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The next coverage run will download elevation and land cover again, or use whatever tiles are still on this device.")
        }
    }
}
