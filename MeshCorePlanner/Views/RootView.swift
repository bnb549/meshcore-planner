import SwiftUI

struct RootView: View {
    @Bindable var store: PlannerStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showList = false
    @State private var showSettings = false
    @State private var showInspector = false

    var body: some View {
        Group {
            if sizeClass == .compact {
                phoneLayout
            } else {
                splitLayout
            }
        }
        .sheet(isPresented: sketchPresented) {
            PathSketchEditor(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(store: store)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var phoneLayout: some View {
        NavigationStack {
            MapCanvasView(
                store: store,
                showsSiteListButton: true,
                onShowSites: { showList = true },
                onShowSettings: { showSettings = true },
                onSelectSite: selectOnPhone
            )
            .navigationTitle("MeshCore Planner")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $showList) {
            NavigationStack {
                SiteListView(store: store) { site in
                    store.selectedSiteID = site.id
                    showList = false
                    showInspector = true
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                if let site = store.selectedSite {
                    SiteInspectorView(site: site, store: store)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: store.selectedSiteID) { _, id in
            if id == nil { showInspector = false }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            SiteListView(store: store) { site in
                store.selectedSiteID = site.id
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } content: {
            MapCanvasView(
                store: store,
                showsSiteListButton: false,
                onShowSites: {},
                onShowSettings: { showSettings = true },
                onSelectSite: { site in store.selectedSiteID = site.id }
            )
        } detail: {
            if let site = store.selectedSite {
                SiteInspectorView(site: site, store: store)
                    .id(site.id)
            } else {
                ContentUnavailableView(
                    "No Site Selected",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Choose a site or long-press the map to drop a repeater.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sketchPresented: Binding<Bool> {
        Binding(
            get: { store.mapTool == .sketch },
            set: { presented in
                if !presented, store.mapTool == .sketch {
                    store.mapTool = .pan
                }
            }
        )
    }

    private func selectOnPhone(_ site: PlannedSite) {
        store.selectedSiteID = site.id
        showList = false
        showInspector = true
    }
}
