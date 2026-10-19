# VERSION

App: MeshCore Planner
Bundle ID: com.benmonroe.meshcoreplanner
Platforms: iOS 17+ / macOS 14+
Xcode: 16+
Swift: 6
Marketing version source of truth: this file + Xcode `MARKETING_VERSION`
Build number source of truth: Xcode `CURRENT_PROJECT_VERSION` (integer, monotonic)

## Current

- Marketing: 0.1.0
- Build: 1
- Channel: local
- Date: 2026-10-18
- Git: uninitialized

## SemVer rules

- MAJOR: breaking UI/data/file-format changes, or dropped OS support
- MINOR: user-visible features that stay backward compatible
- PATCH: fixes, polish, performance, copy
- Build number: increment on every archive / TestFlight upload, even if marketing version is unchanged

## History

### 0.1.0 — 2026-10-18 — build 1

- Initial scaffold from Grok Build prompt.
- Added: Multiplatform SwiftUI MapKit site planner focused on MeshCore repeater placement for non-relaying companions. Persistent PlannedSite storage (SwiftData) with per-site visibility toggle. MeshCore hardware and regional radio presets. Terrain-aware coverage estimation (simplified propagation engine with elevation sampling). Point-to-point link analysis and basic long-hop path sketching. Find highpoint, measure tool, coverage statistics.
- Known limits: Propagation model is a practical terrain-aware approximation (distance + height + sampled elevation / knife-edge style), not a full Longley-Rice/ITM port. Terrain data requires network (SRTM-derived) with local caching; offline only after tiles are cached. No real-time radio, no MQTT, no firmware flashing. Exports are basic (GeoJSON of sites + coverage contours).
- Files introduced: VERSION.md, README.md, MeshCorePlanner app target, PlannedSite SwiftData model, PropagationEngine, map overlays.
