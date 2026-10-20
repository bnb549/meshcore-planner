# MeshCore Planner

MeshCore Planner is a native planning canvas for MeshCore mesh deployments. Companions do not rebroadcast, so coverage comes from dedicated repeaters sited with terrain in mind. Drop planned sites on a map, apply MeshCore hardware and regional radio presets, estimate coverage, check a point-to-point link, and sketch a long-hop path.

This is a planning tool. It is not a radio companion, a live mesh analyzer, or a firmware flasher.

Coverage can use the Longley-Rice / ITM model or a faster simplified model. Both conform to `PropagationEngine`. The ITM core is the public-domain NTIA ITS implementation. This app does not copy SPLAT!.

## Open the project

Requirements: Xcode 16 or newer, iOS 17+, macOS 14+.

1. Open `MeshCorePlanner.xcodeproj`.
2. Select the MeshCore Planner scheme.
3. Run on an iPhone simulator or My Mac.

The app target is `MeshCorePlanner`, the module is `MeshCorePlanner`, the display name is MeshCore Planner, and the bundle id is `com.benmonroe.meshcoreplanner`. Marketing version 0.3.1 and build 4 are recorded in `VERSION.md` and in the Xcode target.

On macOS the app is sandboxed, with the Hardened Runtime enabled. Outbound network access is used only for elevation tiles and ESA WorldCover land-cover tiles. Location is requested only when you tap My Location, and only to center the map.

## What you can do

- Choose Drop and tap the map to place a repeater. Drag a marker to move it, or edit coordinates in the inspector.
- Hide a site with the visibility toggle. A hidden site stays in the list with an eye-slash icon. Its marker is dimmed and dashed, and its coverage is not drawn. Show All and Hide All are in the list toolbar.
- Apply a hardware preset (TX power and antenna gain) and a regional radio preset (frequency, plus bandwidth, spreading factor, and coding-rate notes).
- Estimate coverage for a reference handheld. Choose ITM (Longley-Rice) or Simplified in Settings or the site inspector, then recompute. Turn on Include clutter to add land-cover loss, or Multi-edge diffraction for the simplified engine. The overlay is colored from stored RSSI, so opacity and the color scale do not resimulate.
- Compare two engines on the same site. The inspector shows the mean and maximum difference in dB, and how much area differs by more than the threshold. Each overlay can be shown or hidden. A hidden site draws neither.
- Analyze a point-to-point link: terrain profile, earth-curvature line of sight, first-Fresnel clearance in meters, and both directions of the link budget. Positive clearance is clear and negative is obstructed. The hop margin is the weaker direction. Compare engines shows the other recipe’s margin and the delta.
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

## Propagation models

Settings and the site inspector choose the engine. The choice is stored in AppStorage. Existing sites keep their coordinates and the visibility toggle. Recompute uses whichever engine is selected and replaces that site’s overlay. ITM is the default when no preference has been saved.

ITM (Longley-Rice) is the NTIA Institute for Telecommunication Sciences Irregular Terrain Model, version 1.3, vendored under `ThirdParty/ITM`. The app calls it through a small reentrant C bridge. Antenna heights are structural heights above local ground. The path uses an elevation profile from `ElevationService`, sampled about every 45–180 m depending on the density setting, and widened on long radials so one radial stays under about 700 points. Coverage and links run off the main thread. A run shows progress and can be cancelled. Fine density is still capped at 50 km.

ITM defaults for MeshCore planning are continental temperate climate, vertical polarization, ground dielectric 15, conductivity 0.005 S/m, surface refractivity 301 N-units, and broadcast variability at 50% time, 50% location, and 50% situation. That 50/50/50 case is a median prediction in the spirit of an F(50,50) curve. Advanced settings can change climate, variability, polarization, the three percentages, and the ground constants. Results are predictions, not a guarantee. ITM itself follows terrain and ignores trees and buildings. A confidence badge (High, Medium, or Low) reflects those variability percentages and how dense the elevation samples are. It is not a statistical map.

Include clutter adds land-cover loss after either engine. The classes are ESA WorldCover 2021 v200 (tree, shrub, grass, crop, built-up, bare, snow, water, wetland, mangrove, moss). Each class has an attenuation in dB/m, a nominal height, and a cap on how many dB that class can add to one path. The loss is charged only while the straight ray is below that height, scaled gently with frequency around 900 MHz, then clamped. Tree cover defaults to 0.02 dB/m and at most 20 dB. Built-up defaults to 0.01 dB/m and at most 18 dB. Those two caps are stricter than the other classes, which stay at their earlier rates and stop at 24 dB each. The whole path then stops at 35 dB. Open water, bare ground, and snow stay at zero. At 900 MHz with antennas near 2 m, a 4 km path that crosses about 600 m of trees and 800 m of houses (the rest grass) adds about 20 dB. A longer mixed path stops at 35 dB instead of climbing past 100 dB. Edit the rates and heights in Settings. Reset Clutter Defaults loads the shipped rates. A table you already saved keeps its rates until you reset. The inspector names the classes that added loss. Turn Include clutter off and recompute to match pure ITM or pure Simplified.

Simplified is the original free-space, antenna-height, and single knife-edge model. For an unobstructed path the loss is the larger of free-space path loss and a flat-earth two-ray loss. If terrain plus 4/3-earth bulge crosses the line between the antennas, the loss is free-space plus one dominant knife-edge. Multi-edge diffraction is optional. It sums Epstein-Peterson knife edges when the profile has more than one obstruction. That is an approximation, not a parabolic-equation model and not ITWOM. The single-edge path stays the fast default. Simplified is also the fallback when elevation is missing or ITM rejects a path. The inspector says when that fallback happened.

Point-to-point analysis draws the terrain profile and the line of sight. It reports first-Fresnel clearance in meters: positive means the terrain is below the zone, negative means the zone is obstructed. Green, yellow, and red mark clear, partial, and blocked samples. The Fresnel zone and the 60% boundary can be turned off on the chart. Compare engines runs a second recipe (ITM, ITM + clutter, Simplified, or Simplified + multi-edge) and shows that margin beside the delta.

Compare coverage runs the same pair on one site. It reports the mean delta, the maximum absolute delta, and the area where one result exceeds the other by more than the chosen threshold. The two overlays toggle independently. Both still honor the site’s visibility flag, so hiding a site hides every overlay.

Elevation prefers AWS terrarium zoom 12, about 30 m at mid-latitudes, where that SRTM-derived tile exists. Otherwise it uses zoom 11, about 70–90 m, then Open-Meteo. Samples are tighter near the transmitter and near terrain peaks when 30 m mode is on. Tiles are cached under Application Support. Offline, cached tiles are reused. If the 30 m tile is missing, the run says the resolution was reduced. With no cache and no live terrain, the overlay falls back to the simplified estimate and a note says so.

Land cover comes from the Terrascope WMTS for ESA WorldCover 2021 v200. The published map is 10 m. This app samples the official colormap at zoom 13, about 15 m at mid-latitudes, and caches the tiles next to the elevation cache. Pixels that do not match the official class colors add no loss. If a tile is missing, clutter is skipped on that part of the path and the run says the land cover is incomplete.

Tile requests carry coordinates or tile indexes only. Site names, power, gain, and notes stay on the device.

## Privacy

Planned sites live in a local SwiftData store. There is no analytics and no telemetry. Location permission is when-in-use, and only after My Location is tapped. The map works if permission is denied; that button is disabled.

## Credits

The idea of an interactive site planner for off-grid mesh repeaters is indebted to the Meshtastic Site Planner concept. The ITM engine is the public-domain NTIA Institute for Telecommunication Sciences Longley-Rice model (ITM 1.3). See `ThirdParty/ITM/LICENSE.md` and `ThirdParty/ITM/NOTICE.md`. Land-cover classes are ESA WorldCover 2021 v200, © ESA WorldCover project / Contains modified Copernicus Sentinel data (2021) processed by the ESA WorldCover consortium. Citation: Zanaga, D. et al. (2022), ESA WorldCover 10 m 2021 v200, https://doi.org/10.5281/zenodo.7254221. The product is CC BY 4.0. The simplified engine, Fresnel clearance display, clutter attenuation table, and multi-edge approximation are original. MeshCore Planner does not copy SPLAT! or other GPL propagation code.

## License

MIT. See `LICENSE`.
