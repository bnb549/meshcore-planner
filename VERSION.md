# VERSION

App: MeshCore Planner
Bundle ID: com.benmonroe.meshcoreplanner
Platforms: iOS 17+ / macOS 14+
Xcode: 16+
Swift: 6
Marketing version source of truth: this file + Xcode `MARKETING_VERSION`
Build number source of truth: Xcode `CURRENT_PROJECT_VERSION` (integer, monotonic)

## Current

- Marketing: 0.3.1
- Build: 4
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

### 0.3.0 — 2026-10-19 — build 3

- Added optional ESA WorldCover land-cover clutter. Class attenuation is editable in Settings and is added after ITM or Simplified. Include clutter is off unless the user turns it on, and that restores the 0.2.0 loss.
- Elevation prefers about 30 m terrarium tiles when they exist and falls back to the existing zoom-11 tiles. Offline runs use the cache and say when the resolution was reduced. Paths sample more tightly near the transmitter and near terrain peaks.
- Point-to-point profiles show first-Fresnel clearance in meters. Positive is clear and negative is obstructed, with green, yellow, and red on the profile. The Fresnel zone overlay can be hidden.
- Simplified can sum knife edges across more than one ridge. The single-edge path stays the default. The multi-edge path is an Epstein-Peterson approximation, not ITWOM or a parabolic-equation solver.
- A site can compare ITM, ITM + clutter, Simplified, and Simplified + multi-edge. The inspector shows mean delta, maximum delta, and the area where the two differ by more than a chosen number of dB. The two overlays toggle separately and still follow the site visibility flag.
- ITM runs show a High / Medium / Low confidence badge from the variability percentages and the elevation sample spacing.
- Known limits: No ITWOM, no building footprints, no LiDAR, and no live radio. PlannedSite records and the per-site visibility toggle are unchanged.
- Files introduced: LandCoverService and the clutter attenuation table. ElevationService, both propagation engines, the profile chart, and the comparison section were extended.

### 0.3.1 — 2026-10-19 — build 4

- Tuned land-cover clutter so a suburban path of a few kilometers adds about 5–35 dB instead of climbing past 100 dB. After each segment is computed, that class’s contribution is clamped, and the path is then limited to 35 dB.
- Tree cover now defaults to 0.02 dB/m with a 20 dB path cap. Built-up defaults to 0.01 dB/m with an 18 dB path cap. Other classes keep their 0.3.0 rates and are capped at 24 dB. Tree cover and built-up are the strictest caps.
- Include clutter is still an optional add-on after ITM or Simplified. Turning it off restores the pure engine. Saved clutter tables keep their attenuation rates. New installs, and Reset Clutter Defaults, use the lower rates. An older saved table with no cap stored picks up these caps without replacing the rates.
- Known limits: No ITWOM, no building footprints, no LiDAR, and no live radio. PlannedSite records and the per-site visibility toggle are unchanged.
