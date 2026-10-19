import SwiftUI

struct SiteInspectorView: View {
    @Bindable var site: PlannedSite
    @Bindable var store: PlannerStore
    @State private var confirmDelete = false
    @State private var highpointRadiusKm = 1.0

    var body: some View {
        Form {
            Section("Site") {
                TextField("Name", text: $site.name)
                    .onChange(of: site.name) { _, _ in store.touch(site) }
                Picker("Role", selection: roleBinding) {
                    ForEach(SiteRole.allCases) { role in
                        Label(role.title, systemImage: role.symbolName).tag(role)
                    }
                }
                Toggle(isOn: visibilityBinding) {
                    Label(site.isVisible ? "Shown on map" : "Hidden on map", systemImage: site.isVisible ? "eye" : "eye.slash")
                }
                .accessibilityLabel("Coverage visibility for \(site.name)")
                TextField("Notes", text: $site.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: site.notes) { _, _ in store.touch(site) }
            }

            Section("Location") {
                TextField("Latitude", value: $site.latitude, format: .number.precision(.fractionLength(5)))
                    .onChange(of: site.latitude) { _, _ in store.parametersDidChange(site) }
                TextField("Longitude", value: $site.longitude, format: .number.precision(.fractionLength(5)))
                    .onChange(of: site.longitude) { _, _ in store.parametersDidChange(site) }
                TextField("Antenna height (m)", value: $site.antennaHeightM, format: .number.precision(.fractionLength(1)))
                    .onChange(of: site.antennaHeightM) { _, _ in store.parametersDidChange(site) }
                if let error = site.validationError() {
                    InspectorNote(text: error.localizedDescription, tint: .red)
                }
            }

            Section("Hardware") {
                Picker("Preset", selection: hardwareBinding) {
                    Text("Custom").tag(Optional<String>.none)
                    ForEach(PresetLibrary.hardware) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                if currentHardware?.powerIsFixed == true {
                    InspectorFact(title: "TX power", value: "\(Int(site.txPowerDbm)) dBm")
                } else {
                    Stepper(value: $site.txPowerDbm, in: txRange, step: 1) {
                        Text("TX power \(Int(site.txPowerDbm.rounded())) dBm")
                    }
                    .onChange(of: site.txPowerDbm) { _, _ in store.parametersDidChange(site) }
                }
                if currentHardware?.gainIsFixed == true {
                    InspectorFact(title: "Antenna gain", value: String(format: "%.1f dBi", site.antennaGainDbi))
                } else {
                    Stepper(value: $site.antennaGainDbi, in: gainRange, step: 0.5) {
                        Text("Antenna gain \(String(format: "%.1f dBi", site.antennaGainDbi))")
                    }
                    .onChange(of: site.antennaGainDbi) { _, _ in store.parametersDidChange(site) }
                }
                Stepper(value: $site.cableLossDb, in: 0...15, step: 0.5) {
                    Text("Cable loss \(String(format: "%.1f dB", site.cableLossDb))")
                }
                .onChange(of: site.cableLossDb) { _, _ in store.parametersDidChange(site) }
            }

            Section("Radio") {
                Picker("Region", selection: radioBinding) {
                    Text("Custom").tag(Optional<String>.none)
                    ForEach(PresetLibrary.radio) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                if let radio = currentRadio {
                    InspectorFact(title: "Frequency", value: String(format: "%.3f MHz", radio.frequencyMHz))
                    InspectorNote(text: radio.budgetNote)
                    Button("Use Suggested Sensitivity") {
                        store.receiverSensitivityDbm = radio.suggestedSensitivityDbm
                    }
                    .frame(minHeight: 44)
                } else {
                    TextField("Frequency MHz", value: $site.frequencyMHz, format: .number.precision(.fractionLength(3)))
                        .onChange(of: site.frequencyMHz) { _, _ in store.parametersDidChange(site) }
                }
                InspectorFact(title: "Threshold", value: FieldFormat.dBm(store.receiverSensitivityDbm))
            }

            Section("Coverage") {
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
                if store.runningSiteIDs.contains(site.id) {
                    ProgressView(value: store.progress[site.id] ?? 0) {
                        Text("Estimating coverage")
                    }
                    Button("Cancel") { store.cancelCoverage(for: site.id) }
                        .frame(minHeight: 44)
                } else {
                    Button(store.coverage[site.id] == nil ? "Estimate Coverage" : "Recompute") {
                        store.estimateCoverage(for: site)
                    }
                    .disabled(site.validationError() != nil)
                    .frame(minHeight: 44)
                    .accessibilityHint("Runs the selected propagation engine and replaces this site’s overlay.")
                }
                if let grid = store.coverage[site.id] {
                    let stats = grid.statistics(sensitivityDbm: store.receiverSensitivityDbm)
                    InspectorFact(title: "Engine", value: grid.engineName)
                    InspectorFact(title: "Area above threshold", value: FieldFormat.area(stats.areaAboveThresholdM2))
                    InspectorFact(title: "Max usable range", value: FieldFormat.distance(stats.maxUsableRangeM))
                    InspectorFact(title: "Disk covered", value: FieldFormat.percent(stats.percentOfDisk))
                    if store.coverageFingerprintsMatch(site) == false {
                        InspectorNote(text: "This overlay is out of date. Recompute to apply the current engine and settings.")
                    }
                    if grid.usedFreeSpaceFallback {
                        InspectorNote(text: "Terrain was missing or rejected, so this overlay uses the simplified model.")
                    }
                }
                InspectorNote(text: "Coverage is this site’s footprint for a handheld at \(String(format: "%.1f", store.receiverHeightM)) m and \(String(format: "%.1f", store.receiverGainDbi)) dBi. Range \(String(format: "%.0f", store.maxRangeKm)) km.")
            }

            Section("High point") {
                Slider(value: $highpointRadiusKm, in: 0.2...5) {
                    Text("Search radius")
                }
                InspectorFact(title: "Radius", value: String(format: "%.1f km", highpointRadiusKm))
                Button(store.highpointRunning ? "Searching…" : "Snap to High Point") {
                    Task { await store.findHighpoint(for: site, radiusKm: highpointRadiusKm) }
                }
                .disabled(store.highpointRunning)
                .frame(minHeight: 44)
                if let highpointMessage = store.highpointMessage, store.selectedSiteID == site.id {
                    InspectorNote(text: highpointMessage)
                }
            }

            Section("Link") {
                LinkAnalysisView(site: site, store: store)
            }

            Section("Share") {
                ShareLink(item: GeoJSONExporter.siteSummary(site), preview: SharePreview(site.name)) {
                    Label("Share Summary", systemImage: "text.alignleft")
                }
                ShareLink(
                    item: JSONPayload(filename: "\(site.name).json", text: GeoJSONExporter.siteJSON(site)),
                    preview: SharePreview(site.name)
                ) {
                    Label("Share JSON", systemImage: "curlybraces")
                }
            }

            Section {
                Button("Delete Site", role: .destructive) { confirmDelete = true }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle(site.name)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .confirmationDialog("Delete \(site.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Site", role: .destructive) { store.deleteSite(site) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the site and any saved analyses that depend on it.")
        }
    }

    private var currentHardware: HardwarePreset? {
        site.hardwarePresetID.flatMap(PresetLibrary.hardware(id:))
    }

    private var currentRadio: RadioPreset? {
        site.radioPresetID.flatMap(PresetLibrary.radio(id:))
    }

    private var txRange: ClosedRange<Double> {
        if let currentHardware { return currentHardware.minTxPowerDbm...currentHardware.maxTxPowerDbm }
        return 0...30
    }

    private var gainRange: ClosedRange<Double> {
        if let currentHardware { return currentHardware.minGainDbi...currentHardware.maxGainDbi }
        return 0...15
    }

    private var roleBinding: Binding<SiteRole> {
        Binding(
            get: { site.role },
            set: {
                site.role = $0
                store.touch(site)
            }
        )
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { site.isVisible },
            set: { store.setVisible(site, $0) }
        )
    }

    private var hardwareBinding: Binding<String?> {
        Binding(
            get: { site.hardwarePresetID },
            set: { newValue in
                if let newValue, let preset = PresetLibrary.hardware(id: newValue) {
                    site.apply(hardware: preset)
                } else {
                    site.hardwarePresetID = nil
                }
                store.parametersDidChange(site)
            }
        )
    }

    private var radioBinding: Binding<String?> {
        Binding(
            get: { site.radioPresetID },
            set: { newValue in
                if let newValue, let preset = PresetLibrary.radio(id: newValue) {
                    site.apply(radio: preset)
                } else {
                    site.radioPresetID = nil
                }
                store.parametersDidChange(site)
            }
        )
    }
}

/// A label and value that share the full inspector row and wrap on word boundaries.
struct InspectorFact: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Explanatory copy that uses the whole inspector width instead of the form’s label column.
struct InspectorNote: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
