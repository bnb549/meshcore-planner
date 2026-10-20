import Charts
import SwiftUI

struct LinkAnalysisView: View {
    var site: PlannedSite
    @Bindable var store: PlannerStore
    @State private var otherID: UUID?
    @State private var showFresnelZone = true

    var body: some View {
        let others = store.sites.filter { $0.id != site.id }
        if others.isEmpty {
            InspectorNote(text: "Drop another site to check whether this one can hear it. The margin shown is the weaker direction.")
        } else {
            Picker("Other site", selection: $otherID) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(others) { other in
                    Text(other.name).tag(Optional(other.id))
                }
            }
            if let other = others.first(where: { $0.id == otherID }) {
                Toggle("Compare engines", isOn: $store.compareEngines)
                    .accessibilityHint("Runs the comparison engine beside the selected one.")
                if store.compareEngines {
                    Picker("Comparison", selection: $store.comparisonRecipe) {
                        ForEach(EngineRecipe.allCases) { recipe in
                            Text(recipe.title).tag(recipe)
                        }
                    }
                }
                Button(store.linkRunning ? "Analyzing…" : "Analyze Link") {
                    Task { await store.analyzeLink(from: site, to: other) }
                }
                .disabled(store.linkRunning || site.validationError() != nil || other.validationError() != nil)
                .frame(minHeight: 44)
                if store.linkRunning {
                    ProgressView()
                        .accessibilityLabel("Analyzing link")
                }
                if let message = store.linkMessage {
                    InspectorNote(text: message, tint: .red)
                }
                if let result = activeResult {
                    resultBody(result, other: other)
                } else if let cached = store.cachedLink(from: site.id, to: other.id) {
                    cachedBody(cached)
                }
            }
        }
    }

    private var activeResult: LinkResult? {
        guard let otherID, store.linkPair?.0 == site.id, store.linkPair?.1 == otherID else { return nil }
        return store.linkResult
    }

    @ViewBuilder
    private func resultBody(_ result: LinkResult, other: PlannedSite) -> some View {
        InspectorFact(title: "Engine", value: result.engineName)
        InspectorFact(title: "Distance", value: FieldFormat.distance(result.distanceM))
        InspectorFact(title: "Bearing", value: FieldFormat.bearing(result.bearingFromToDeg))
        directionRow(
            title: "\(site.name) → \(other.name)",
            link: result.forward,
            limiting: result.forward.marginDb <= result.reverse.marginDb
        )
        directionRow(
            title: "\(other.name) → \(site.name)",
            link: result.reverse,
            limiting: result.reverse.marginDb < result.forward.marginDb
        )
        InspectorFact(title: "Weakest margin", value: FieldFormat.decibels(result.weakestMarginDb))
        if store.compareEngines, let comparison = store.comparisonResult {
            InspectorFact(title: "\(comparison.engineName) margin", value: FieldFormat.decibels(comparison.weakestMarginDb))
            let delta = result.weakestMarginDb - comparison.weakestMarginDb
            InspectorFact(title: "Margin delta", value: String(format: "%+.1f dB", delta))
            InspectorNote(text: comparison.modelNote)
        }
        if let confidence = result.confidence {
            InspectorFact(title: "Confidence", value: confidence.title)
        }
        InspectorFact(title: "Fresnel clearance", value: PropagationMath.fresnelClearanceLabel(profile: result.profile))
        InspectorFact(
            title: "60% of F1",
            value: result.forward.fresnelClear
                ? String(format: "%.0f%% clear", result.forward.fresnelClearanceRatio * 100)
                : String(format: "Blocked (%.0f%%)", result.forward.fresnelClearanceRatio * 100)
        )
        InspectorNote(text: "Positive clearance means terrain is below the first Fresnel zone. Negative means the zone is obstructed. Green is clear, yellow is partial, red is blocked.")
        if let clutterSummary = result.clutterSummary {
            InspectorNote(text: clutterSummary)
        }
        if let dataNote = result.dataNote {
            InspectorNote(text: dataNote)
        }
        if !result.modelNote.isEmpty {
            InspectorNote(text: result.modelNote)
        }
        if !result.profile.isEmpty {
            Toggle("Fresnel zone", isOn: $showFresnelZone)
                .accessibilityHint("Draws the first Fresnel zone and the 60 percent boundary on the profile.")
            TerrainProfileChart(samples: result.profile, showsFresnelZone: showFresnelZone)
                .frame(height: 180)
                .accessibilityLabel(PropagationMath.fresnelClearanceLabel(profile: result.profile))
        }
    }

    private func directionRow(title: String, link: DirectionalLink, limiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(limiting ? "\(title) · limiting" : title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("EIRP \(FieldFormat.dBm(link.eirpDbm)) · loss \(FieldFormat.decibels(link.pathLossDb)) · received \(FieldFormat.dBm(link.receivedPowerDbm)) · margin \(FieldFormat.decibels(link.marginDb))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func cachedBody(_ link: PlannedLink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InspectorNote(text: "Saved margin \(FieldFormat.decibels(link.weakestMarginDb)) over \(FieldFormat.distance(link.distanceM)).")
            InspectorNote(text: "Run analysis again to draw the terrain profile.")
        }
    }
}

struct TerrainProfileChart: View {
    var samples: [ProfileSample]
    var showsFresnelZone: Bool

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Distance", sample.distanceM / 1_000),
                    y: .value("Meters", sample.terrainWithBulge)
                )
                .foregroundStyle(Color.brown.opacity(0.35))
            }
            ForEach(samples) { sample in
                PointMark(
                    x: .value("Distance", sample.distanceM / 1_000),
                    y: .value("Meters", sample.terrainWithBulge)
                )
                .foregroundStyle(fresnelColor(sample.fresnelBand))
                .symbolSize(28)
            }
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Distance", sample.distanceM / 1_000),
                    y: .value("Meters", sample.losAMSL),
                    series: .value("Series", "Line of sight")
                )
                .foregroundStyle(Color.blue)
            }
            if showsFresnelZone {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Distance", sample.distanceM / 1_000),
                        y: .value("Meters", sample.fresnel1AMSL),
                        series: .value("Series", "First Fresnel")
                    )
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Distance", sample.distanceM / 1_000),
                        y: .value("Meters", sample.fresnel60AMSL),
                        series: .value("Series", "60% Fresnel")
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .chartXAxisLabel("km")
        .chartYAxisLabel("m")
        .chartLegend(position: .bottom)
    }

    private func fresnelColor(_ band: FresnelBand) -> Color {
        switch band {
        case .clear: .green
        case .partial: .yellow
        case .blocked: .red
        }
    }
}
