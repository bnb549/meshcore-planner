# MeshCore Planner

MeshCore Planner is a native planning canvas for MeshCore mesh deployments. Companions do not rebroadcast, so coverage comes from dedicated repeaters sited with terrain in mind. Drop planned sites on a map, apply MeshCore hardware and regional radio presets, estimate coverage, check a point-to-point link, and sketch a long-hop path.

This is a planning tool. It is not a radio companion, a live mesh analyzer, or a firmware flasher.

The propagation engine is an original, practical approximation: free-space path loss, antenna-height geometry, earth curvature, and a single knife-edge when sampled terrain blocks the path. It is not a port of SPLAT! or the Longley-Rice / ITM model. `PropagationEngine` is the seam where a full ITM engine could be added later.

## Open the project

Requirements: Xcode 16 or newer, iOS 17+, macOS 14+.

1. Open `MeshCorePlanner.xcodeproj`.
2. Select the MeshCore Planner scheme.
3. Run on an iPhone simulator or My Mac.

The app target is `MeshCorePlanner`, the module is `MeshCorePlanner`, the display name is MeshCore Planner, and the bundle id is `com.benmonroe.meshcoreplanner`. Marketing version 0.1.0 and build 1 are recorded in `VERSION.md` and in the Xcode target.

On macOS the app is sandboxed, with the Hardened Runtime enabled. Outbound network access is used only for elevation tiles. Location is requested only when you tap My Location, and only to center the map.

## What you can do

- Choose Drop and tap the map to place a repeater. Drag a marker to move it, or edit coordinates in the inspector.
- Hide a site with the visibility toggle. A hidden site stays in the list with an eye-slash icon. Its marker is dimmed and dashed, and its coverage is not drawn. Show All and Hide All are in the list toolbar.
- Apply a hardware preset (TX power and antenna gain) and a regional radio preset (frequency, plus bandwidth, spreading factor, and coding-rate notes).
- Estimate coverage for a reference handheld. The overlay is colored from stored RSSI, so opacity and the color scale do not resimulate.
- Analyze a point-to-point link: terrain profile, earth-curvature line of sight, 60% Fresnel clearance, and both directions of the link budget. The hop margin is the weaker direction.
- Sketch an ordered path across sites and read the hop count and the weakest-link margin. This is not a routing simulation.
- Find a local high point within a search radius, measure a great-circle distance and bearing, and export visible sites plus coverage polygons as GeoJSON.

Sites, saved link summaries, and path sketches are stored on device with SwiftData. Nothing is synced.

## Defaults

| Setting | Default |
| --- | --- |
| Receiver sensitivity | -130 dBm |
| Reference handheld | 1.5 m, 2 dBi, 0 dB cable |
| Maximum simulation range | 30 km, hard cap 50 km |
| New site | Repeater, 10 m antenna, Heltec V3 / V4, US/Canada |

Coverage asks “what can this site deliver to that handheld?” Point-to-point uses each site’s own power, gain, cable loss, and height, in both directions.

### Regional radio presets

| Preset | Frequency | Bandwidth | SF | Coding | Planning sensitivity |
| --- | --- | --- | --- | --- | --- |
| US/Canada | 910.525 MHz | 62.5 kHz | SF7 | CR5 (4/5) | about -129 dBm |
| US/Canada Wide | 910.525 MHz | 250 kHz | SF7 | — | about -123 dBm |
| EU/UK Narrow | 869.618 MHz | 62.5 kHz | SF8 | — | about -132 dBm |

Those sensitivity figures are planning notes, not lab measurements. Choosing a preset does not change the threshold. The coverage threshold stays at the Settings value (default -130 dBm) until you change it or tap Use Suggested Sensitivity.

### Hardware presets

| Preset | Default TX | TX range | Default gain | Gain range |
| --- | --- | --- | --- | --- |
| Heltec V3 / V4 | 22 dBm | 20–22 | 2 dBi | 2 |
| RAK4631 / WisBlock | 22 dBm | 14–22 | 2 dBi | 2 |
| LilyGo T-Beam / T-Echo | 20 dBm | 20 | 2 dBi | 2 |
| Station G2 | 27 dBm | 14–30 | 3 dBi | 2–5 |

Station G2’s upper power is only a planning ceiling. Stay within the rules for the band you are using.

## Propagation model

For an unobstructed path the loss is the larger of free-space path loss and a flat-earth two-ray loss, so low antennas are not given a free-space fantasy. If terrain (plus 4/3-earth bulge) crosses the line between the antennas, the loss is free-space plus one dominant knife-edge. The Fresnel parameter uses the sample with the largest `v`. This is a single-edge model: it does not cascade multiple ridges, and it ignores clutter, atmospheric ducts, and antenna patterns.

`SimplifiedTerrainEngine` conforms to `PropagationEngine`. A later Longley-Rice implementation can replace it without changing the map.

Elevation comes from AWS terrarium tiles (zoom 11, about 70–90 m at mid-latitudes), cached under Application Support. If those tiles are unavailable, the app asks Open-Meteo for elevations and caches those too. Offline, cached tiles are reused. With no cache, the overlay is a free-space estimate and a banner says so.

Tile and elevation requests carry coordinates or tile indexes only. Site names, power, gain, and notes stay on the device.

## Privacy

Planned sites live in a local SwiftData store. There is no analytics and no telemetry. Location permission is when-in-use, and only after My Location is tapped. The map works if permission is denied; that button is disabled.

## Credits

The idea of an interactive site planner for off-grid mesh repeaters is indebted to the Meshtastic Site Planner concept. The terrain-aware radio planning lineage runs through the Longley-Rice / ITM model and John Magliacane’s SPLAT!. MeshCore Planner does not copy that source. The implementation here is a new native approximation.

## License

MIT. See `LICENSE`.
