import Charts
import SwiftUI

struct LinkAnalysisView: View {
    var site: PlannedSite
    @Bindable var store: PlannerStore
    @State private var otherID: UUID?

    var body: some View {
        let others = store.sites.filter { $0.id != site.id }
        if others.isEmpty {
            Text("Drop another site to check whether this one can hear it. The margin shown is the weaker direction.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Picker("Other site", selection: $otherID) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(others) { other in
                    Text(other.name).tag(Optional(other.id))
                }
            }
            if let other = others.first(where: { $0.id == otherID }) {
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
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
        LabeledContent("Distance", value: FieldFormat.distance(result.distanceM))
        LabeledContent("Bearing", value: FieldFormat.bearing(result.bearingFromToDeg))
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
        LabeledContent("Weakest margin", value: FieldFormat.decibels(result.weakestMarginDb))
        LabeledContent(
            "Fresnel clearance",
            value: result.forward.fresnelClear
                ? String(format: "%.0f%% of F1", result.forward.fresnelClearanceRatio * 100)
                : String(format: "Blocked (%.0f%% of F1)", result.forward.fresnelClearanceRatio * 100)
        )
        if result.usedFreeSpaceFallback {
            Text("Terrain was unavailable, so this profile is a free-space estimate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if !result.profile.isEmpty {
            TerrainProfileChart(samples: result.profile)
                .frame(height: 180)
                .accessibilityLabel(result.forward.fresnelClear
                    ? "Terrain profile, first Fresnel zone is at least 60 percent clear"
                    : "Terrain profile, first Fresnel zone is obstructed")
        }
    }

    private func directionRow(title: String, link: DirectionalLink, limiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(limiting ? "\(title) · limiting" : title)
                .font(.subheadline.weight(.semibold))
            Text("EIRP \(FieldFormat.dBm(link.eirpDbm)) · loss \(FieldFormat.decibels(link.pathLossDb)) · received \(FieldFormat.dBm(link.receivedPowerDbm)) · margin \(FieldFormat.decibels(link.marginDb))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func cachedBody(_ link: PlannedLink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved margin \(FieldFormat.decibels(link.weakestMarginDb)) over \(FieldFormat.distance(link.distanceM)).")
                .font(.footnote)
            Text("Run analysis again to draw the terrain profile.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct TerrainProfileChart: View {
    var samples: [ProfileSample]

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Distance", sample.distanceM / 1_000),
                    y: .value("Meters", sample.terrainWithBulge)
                )
                .foregroundStyle(Color.brown.opacity(0.45))
            }
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Distance", sample.distanceM / 1_000),
                    y: .value("Meters", sample.losAMSL),
                    series: .value("Series", "Line of sight")
                )
                .foregroundStyle(Color.blue)
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
        .chartXAxisLabel("km")
        .chartYAxisLabel("m")
        .chartLegend(position: .bottom)
    }
}
