import SwiftUI

struct PathSketchEditor: View {
    @Bindable var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap sites on the map in order. The margin of each hop is the weaker direction. This is a sketch, not a route solver.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if store.sketchSiteIDs.isEmpty {
                        Text("No sites in this path yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.sketchSiteIDs.enumerated()), id: \.offset) { index, id in
                        if let site = store.sites.first(where: { $0.id == id }) {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(site.role.tint.opacity(0.2)))
                                Image(systemName: site.role.symbolName)
                                    .foregroundStyle(site.role.tint)
                                Text(site.name)
                                if !site.isVisible {
                                    Image(systemName: "eye.slash")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Hidden")
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        store.removeSketchSites(at: offsets)
                    }
                    HStack {
                        Button("Remove Last") { store.removeLastSketchSite() }
                            .disabled(store.sketchSiteIDs.isEmpty)
                        Button("Clear") { store.clearSketch() }
                            .disabled(store.sketchSiteIDs.isEmpty)
                    }
                }

                Section("Hops") {
                    Button(store.sketchRunning ? "Analyzing…" : "Analyze Path") {
                        Task { await store.analyzeSketch() }
                    }
                    .disabled(store.sketchRunning || store.sketchSiteIDs.count < 2)
                    .frame(minHeight: 44)
                    if store.sketchRunning {
                        ProgressView()
                            .accessibilityLabel("Analyzing path")
                    }
                    if !store.sketchHops.isEmpty {
                        LabeledContent("Hops", value: "\(store.sketchHops.count)")
                        if let weakest = store.weakestSketchMargin {
                            LabeledContent("Weakest margin", value: FieldFormat.decibels(weakest))
                        }
                        ForEach(store.sketchHops) { hop in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hop.id + 1). \(hop.fromName) → \(hop.toName)")
                                Text("\(FieldFormat.distance(hop.distanceM)) · margin \(FieldFormat.decibels(hop.marginDb))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Save") {
                    TextField("Path name", text: $store.sketchName)
                    Button("Save Path") { store.saveSketch() }
                        .disabled(store.sketchSiteIDs.count < 2)
                        .frame(minHeight: 44)
                }

                if !store.sketches.isEmpty {
                    Section("Saved paths") {
                        ForEach(store.sketches) { sketch in
                            Button {
                                store.loadSketch(sketch)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(sketch.name)
                                    Text("\(sketch.orderedSiteIDs.count) sites")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    store.deleteSketch(sketch)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Long hop")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
    }
}
