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
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                    LabeledContent("TX power", value: "\(Int(site.txPowerDbm)) dBm")
                } else {
                    Stepper(value: $site.txPowerDbm, in: txRange, step: 1) {
                        Text("TX power \(Int(site.txPowerDbm.rounded())) dBm")
                    }
                    .onChange(of: site.txPowerDbm) { _, _ in store.parametersDidChange(site) }
                }
                if currentHardware?.gainIsFixed == true {
                    LabeledContent("Antenna gain", value: String(format: "%.1f dBi", site.antennaGainDbi))
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
                    LabeledContent("Frequency", value: String(format: "%.3f MHz", radio.frequencyMHz))
                    Text(radio.budgetNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Use Suggested Sensitivity") {
                        store.receiverSensitivityDbm = radio.suggestedSensitivityDbm
                    }
                    .frame(minHeight: 44)
                } else {
                    TextField("Frequency MHz", value: $site.frequencyMHz, format: .number.precision(.fractionLength(3)))
                        .onChange(of: site.frequencyMHz) { _, _ in store.parametersDidChange(site) }
                }
                LabeledContent("Threshold", value: FieldFormat.dBm(store.receiverSensitivityDbm))
            }

            Section("Coverage") {
                if store.runningSiteIDs.contains(site.id) {
                    ProgressView(value: store.progress[site.id] ?? 0) {
                        Text("Estimating coverage")
                    }
                    Button("Cancel") { store.cancelCoverage(for: site.id) }
                        .frame(minHeight: 44)
                } else {
                    Button("Estimate Coverage") { store.estimateCoverage(for: site) }
                        .disabled(site.validationError() != nil)
                        .frame(minHeight: 44)
                }
                if let grid = store.coverage[site.id] {
                    let stats = grid.statistics(sensitivityDbm: store.receiverSensitivityDbm)
                    LabeledContent("Area above threshold", value: FieldFormat.area(stats.areaAboveThresholdM2))
                    LabeledContent("Max usable range", value: FieldFormat.distance(stats.maxUsableRangeM))
                    LabeledContent("Disk covered", value: FieldFormat.percent(stats.percentOfDisk))
                    if grid.usedFreeSpaceFallback {
                        Text("This estimate did not use terrain.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Coverage is this site’s footprint for a handheld at \(String(format: "%.1f", store.receiverHeightM)) m and \(String(format: "%.1f", store.receiverGainDbi)) dBi. Range \(String(format: "%.0f", store.maxRangeKm)) km.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("High point") {
                Slider(value: $highpointRadiusKm, in: 0.2...5) {
                    Text("Search radius")
                }
                LabeledContent("Radius", value: String(format: "%.1f km", highpointRadiusKm))
                Button(store.highpointRunning ? "Searching…" : "Snap to High Point") {
                    Task { await store.findHighpoint(for: site, radiusKm: highpointRadiusKm) }
                }
                .disabled(store.highpointRunning)
                .frame(minHeight: 44)
                if let highpointMessage = store.highpointMessage, store.selectedSiteID == site.id {
                    Text(highpointMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
