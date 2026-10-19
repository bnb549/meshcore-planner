# NOTICE

The C++ sources in this directory are the NTIA Institute for Telecommunication Sciences Irregular Terrain Model (ITM), version 1.3. That version is functionally identical to the archived FORTRAN implementation 1.2.2. ITM is the Longley-Rice model.

NTIA developed this software as a work of the United States Government. Under 15 U.S.C. § 105 it is not subject to copyright protection in the United States. The NTIA disclaimer and worldwide permission are in `LICENSE.md`. This app does not use SPLAT! or any other GPL propagation code.

## Changes in this copy — 2026-10-19

Portability only. The numerical model is unchanged.

- `#include` paths no longer use Windows backslashes. Headers are included by name, and the Xcode target adds `ThirdParty/ITM/include` to the header search path.
- `DLLEXPORT` is `extern "C"` when the compiler is not targeting Windows, instead of `__declspec(dllexport)`.

MeshCore Planner calls this code through `ITMBridge`, a small C wrapper. Predictions are not measurements. The model uses terrain profiles and ignores buildings and trees.
