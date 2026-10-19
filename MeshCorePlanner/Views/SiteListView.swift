import SwiftUI

enum SiteSort: String, CaseIterable, Identifiable {
    case name
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .distance: "Distance"
        }
    }
}

struct SiteListView: View {
    @Bindable var store: PlannerStore
    var onSelect: (PlannedSite) -> Void

    @State private var query = ""
    @State private var sort: SiteSort = .name
    @State private var pendingDelete: PlannedSite?

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    store.sites.isEmpty ? "No Sites Yet" : "No Matches",
                    systemImage: "mappin.slash",
                    description: Text(store.sites.isEmpty
                        ? "Choose Drop, then tap the map to place the first repeater."
                        : "Try a different name.")
                )
            } else {
                ForEach(filtered) { site in
                    Button {
                        onSelect(site)
                    } label: {
                        row(site)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(site.name), \(site.role.title), \(site.isVisible ? "visible" : "hidden")")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = site
                        }
                    }
                    .contextMenu {
                        Button(site.isVisible ? "Hide" : "Show") {
                            store.setVisible(site, !site.isVisible)
                        }
                        Button("Delete", role: .destructive) {
                            pendingDelete = site
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search sites")
        .navigationTitle("Sites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Show All", systemImage: "eye") { store.setAllVisible(true) }
                    Button("Hide All", systemImage: "eye.slash") { store.setAllVisible(false) }
                    Picker("Sort", selection: $sort) {
                        ForEach(SiteSort.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Show or hide all sites, and sort")
            }
            ToolbarItem(placement: .automatic) {
                ShareLink(item: store.geoJSONPayload(), preview: SharePreview("Visible sites")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export visible sites as GeoJSON")
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this site")?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete Site", role: .destructive) {
                if let pendingDelete {
                    store.deleteSite(pendingDelete)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the site, its saved link analyses, and path sketches that would have fewer than two sites.")
        }
    }

    private var filtered: [PlannedSite] {
        let matched = store.sites.filter { site in
            query.isEmpty || site.name.localizedStandardContains(query)
        }
        switch sort {
        case .name:
            return matched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            return matched.sorted { store.distanceFromCenter($0) < store.distanceFromCenter($1) }
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func row(_ site: PlannedSite) -> some View {
        HStack(spacing: 12) {
            Image(systemName: site.role.symbolName)
                .foregroundStyle(site.role.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name)
                    .font(.body)
                Text("\(site.role.title) · \(FieldFormat.distance(store.distanceFromCenter(site)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.setVisible(site, !site.isVisible)
            } label: {
                Image(systemName: site.isVisible ? "eye" : "eye.slash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(site.isVisible ? "Hide \(site.name)" : "Show \(site.name)")
        }
    }
}
