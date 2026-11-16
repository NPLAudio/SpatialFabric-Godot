# Direct-device backend (GDExtension)

`gdextension/` wraps the engine-neutral C ABI v1 vendored from SpatialFabric-Unity
(`vendor/sf_audio`, SHA-256 provenance in `PROVENANCE.json`) as two classes:

- `SFNativeBuffer`: copies finite interleaved float PCM (<=64M samples) into an
  immutable native allocation; offline `render()` for tests, never opens a device.
- `SFNativePlayer`: explicit `devices_json()` inventory, `start()` request, observed
  `status()` (state, reason, start/end sequences), `set_loop()`, `stop()`.

Godot's AudioServer/mixer is never used and there is no fallback: without the library
(or on an unsupported OS) cues report the failure and nothing plays. The extension is
`reloadable = false`; hot reload crashed the editor on shutdown during development.

## Build (editor closed)

```sh
python -m pip install scons
python Tools/build_native.py       # Windows x64, or macOS universal
python Tools/sync_native.py --check
```

godot-cpp is cloned at tag `godot-4.5-stable` into the ignored `Native/.deps`
(compatibility_minimum 4.5; loaded successfully by Godot 4.7.2). Binaries go to the
ignored `addons/spatial_fabric/bin/`. `.gdignore` keeps Godot from importing build
objects. Update vendored source only with `python Tools/sync_native.py` from a
reviewed SpatialFabric-Unity commit, then rebuild and rerun every gate.

## Status

- Windows x64 (WASAPI): built (debug + release) and exercised **silently** by the
  Godot tests: offline channel routing/EOF, PCM rejection, explicit inventory, an invalid
  device that fails without ever reporting Playing, and the cue/OSC lifecycle.
- macOS (Core Audio): source is included through the vendored core but has **not**
  been built or run for Godot. No Mac claim is made for Godot.
- Physical channel mapping, fidelity, latency, exclusive mode, hot-unplug and audible
  natural-end replay have **not** been tested; the same acceptance list as Unity
  (`SpatialFabric-Unity/Docs/HARDWARE_ACCEPTANCE.md`) applies and needs a human at real hardware.
- Exports/templates: not built. An exported game needs the matching template DLL.
