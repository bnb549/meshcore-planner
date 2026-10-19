# VERSION

App: MeshCore Planner
Bundle ID: com.benmonroe.meshcoreplanner
Platforms: iOS 17+ / macOS 14+
Xcode: 16+
Swift: 6
Marketing version source of truth: this file + Xcode `MARKETING_VERSION`
Build number source of truth: Xcode `CURRENT_PROJECT_VERSION` (integer, monotonic)

## Current

- Marketing: 0.2.0
- Build: 2
- Channel: local
- Date: 2026-10-19
- Git: main

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

### 0.2.0 — 2026-10-19 — build 2

- Added a selectable Longley-Rice / ITM engine next to the existing simplified engine. ITM is the default for a new simulation. Simplified stays available as the fast fallback and is used when elevation is missing or ITM rejects a path.
- Engine choice is a runtime preference in Settings and the site inspector. It is not stored on PlannedSite. Recompute replaces that site’s overlay. Changing the engine does not recompute by itself.
- ITM runs off the main thread, reports progress, and can be cancelled. Density (Fast, Standard, Fine) trades radial count and sample spacing for speed. Runs stay capped at 50 km.
- Point-to-point analysis can compare both engines. The terrain chart draws the line of sight, the first Fresnel zone, and the 60% Fresnel boundary.
- ITM defaults: continental temperate climate, vertical polarization, dielectric 15, conductivity 0.005 S/m, surface refractivity 301, broadcast variability, 50/50/50. That is a median planning prediction in the spirit of F(50,50), not a measurement. Trees and buildings are ignored.
- Known limits: No ITWOM clutter model, no building or tree database, no live radio, and no cloud sync. PlannedSite records and the per-site visibility toggle are unchanged.
- Files introduced: ITMPropagationEngine, ITMBridge, and the public-domain NTIA ITS ITM 1.3 sources under ThirdParty/ITM.
