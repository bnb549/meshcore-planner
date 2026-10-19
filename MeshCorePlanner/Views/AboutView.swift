import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: "\(marketing) (\(build))")
                LabeledContent("Bundle", value: "com.benmonroe.meshcoreplanner")
            }
            Section("What this is") {
                Text("MeshCore Planner places dedicated repeaters so non-relaying companions can reach the network. It estimates coverage, checks a link, and sketches a long hop. It does not talk to a radio, join MQTT, or flash firmware.")
            }
            Section("Credits") {
                Text("The interactive site-planner idea is indebted to the Meshtastic Site Planner concept. The ITM engine is the public-domain NTIA Institute for Telecommunication Sciences Longley-Rice model. The simplified engine is an original approximation: distance, antenna height, earth curvature, and one knife edge. This app does not copy SPLAT!. Results are predictions. Trees and buildings are ignored.")
            }
            Section("Privacy") {
                Text("Sites are stored locally with SwiftData. There is no analytics. Location is used only when you tap My Location, to center the map. Elevation requests send coordinates or tile indexes, never site names or radio settings.")
            }
            Section("License") {
                Text("MIT License. Copyright © 2026 Benjamin Monroe.")
            }
        }
        .navigationTitle("About")
    }

    private var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
    }
}
