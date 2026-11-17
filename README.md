# SpatialFabric for Godot — 0.2 early development

**Not a feature-parity port yet.** Includes an original walkable four-room example with
real playback controls, stage/object bindings, a strict bounded OSC codec, explicit
exact-bind UDP, read-only scene discovery, ADM XYZ/AED output, AudioLoom play/stop/loop
control with observed `/state`, and a **direct-device audio backend** (GDExtension over the
Unity repo's C ABI). Custom-protocol output and multi-destination routing are not implemented.
Nothing binds, sends, loads a source or plays on startup, and there is no Godot mixer fallback.
**Windows is tested silently only; no physical audio has been verified.** See `VALIDATION.md`.

## SpatialFabric repositories

| Repository | Purpose |
|---|---|
| [SpatialFabric](https://github.com/NPLAudio/SpatialFabric) | Unreal implementation and independent OSC Controller |
| [SpatialFabric-Unity](https://github.com/NPLAudio/SpatialFabric-Unity) | Unity implementation and native audio backend |
| [SpatialFabric-Interop](https://github.com/NPLAudio/SpatialFabric-Interop) | Shared OSC/scene schemas and golden fixtures |
| [AudioLoom](https://github.com/NPLAudio/AudioLoom) | Legacy standalone Unreal playback; private/access-controlled |

This Godot repository is local so far; publishing is a separate step. Shared contracts do
not transfer platform or hardware certification between engines.

## Run the example

Use Godot **4.7.2 Standard** (GDScript; no .NET). Build the native library first for audio
(`python Tools/build_native.py`, editor closed; see `Native/README.md`), then import
`project.godot` and run `examples/four_rooms/room_showcase.tscn`. Without the library the
example still runs and cues report that native audio is not loaded.

Click to capture the mouse; **WASD** walk, **Shift** sprint, **Space** jump, **Esc** release.
In a playback room: **E** requests playback (Play prepares the cue's WAV on demand, which opens no device), **Q** stop, **L** loop,
**R** auto-replay. **X** stops all cues. **I** starts/stops **live input** (default microphone/line
in to the default output; see below). **N** starts/stops OSC networking. The HUD shows
the observed state; "playing" means the native worker actually started, not that a request
was made. **E uses the system default output device and makes sound.** Rooms: spatial
motion (four objects, three animated), warm percussion (output 1), stereo groove
(matching L/R, loop), glass/mechanical (output 2, 2.5 s replay) using the same original
procedural WAVs as the Unreal/Unity examples. Visual walls do not spatialize or isolate PCM.

The editor dock is enabled in the example (Project Settings → Plugins → SpatialFabric);
**Inspect edited scene** reads the manager only when clicked. For another project copy
`addons/spatial_fabric/`; the example and tests are not runtime dependencies.

## Live input (microphone / line in)

`SpatialFabricLiveInputCue` routes a **selected capture device and channel** to a **selected output
device and channel** through the same native path as `SpatialFabricPlaybackCue`; there is no
`AudioStreamMicrophone`/AudioServer use. Selection mirrors output: explicit `refresh_input_devices()`,
exact configured IDs with **no default fallback**, input channel `0` = all / `1..N` = one input,
output channel `0` = corresponding / `1..N` = one output, exclusive mode for the output only.
Nothing opens a microphone until an explicit `try_start()` (the example's **I** key, or OSC
`/godot/live/input/play`, which may trigger an OS permission prompt). Also `/stop`, `/gain`
(float 0..4), observed `/state`, and a read-only `live_input` discovery record.
`is_live()` means the worker really started. Latency is a bounded ring (about twice `buffer_ms`) with a
drift servo; underruns/overruns and an input peak are reported. **Mic to nearby speakers feeds back:**
use headphones or low gain. macOS exports need a microphone usage description; macOS capture is unbuilt.
**No test has ever opened a real microphone; physical latency/quality is unverified.**

## Rendering and look

The example uses the **Forward+ renderer (needs Vulkan)**: lit PBR materials with a polished tiled floor, a shadow-casting light
in every room, glowing door frames and stage outline, emissive OSC objects that light their surroundings in their own colour,
and a `WorldEnvironment` (ambient light, filmic tone mapping, glow, SSAO, light fog, 4x MSAA). On hardware without Vulkan, switch
Project Settings > Rendering > Renderer to *Compatibility*: the scene still runs but loses SSAO/glow and looks flatter.

## Connect the OSC Controller

Godot uses the same default ports as the Unreal plugin, so the controller's defaults already match; load
`examples/four_rooms/OSCControllerProfile.json` (also shipped as `profiles/spatialfabric-godot.json`) only to get the Godot cue bases
(`/godot/...`) and the live-input cue, then **Start all receivers**. Only one engine app can own the input ports at a time. Press **N** in the example: it starts OSC listening
(inputs `8100`/`9000`) **and turns ADM output on** (xyz to `50018`, observed `/state` to `9001`); the HUD names these ports.
Outside the example, `start_networking()` alone sends nothing until you set `adm_enabled = true`. Unchanged positions are
re-sent every `adm_refresh_seconds` (default 1 s) so a controller that starts later still learns every object, static ones
included. Custom-protocol output (`9002`) is not implemented. If the controller still shows nothing, run the OSC Controller's
**Debugger / test bed** on the same ports, or check the ports in the HUD against the controller's receiver list.

## Release export (Windows x64)

`export_presets.cfg` defines a *Windows Desktop* release export. With Godot 4.7.2 plus its Windows export templates (a self-contained
portable editor works) and the **release** native library (`python Tools/build_native.py --targets template_release`), run
`python Tools/export_windows.py --godot <console exe> --output <new empty dir>`. It exports, verifies that only the release DLL
ships, runs the built-in headless self-check (`game.exe -- --sf-selfcheck report.json [--sf-shot view.png]`), takes a windowed
screenshot, and writes a ZIP, checksums and manifest. Keep the `.exe`, `.pck` and `.dll` together. **Unsigned**, Windows only, and
**E plays through the default output device**; **I** opens the default microphone.

## Architecture and contracts

- `addons/spatial_fabric/runtime/`: stage, object bindings, manager, OSC codec/transport,
  scene query, WAV decoder, playback control and cue.
- `addons/spatial_fabric/*.gdextension`: native backend (not hot-reloadable).
- `examples/four_rooms/`: original procedural geometry, visitor and WAVs; no template assets.
- `Native/`: GDExtension source, vendored C ABI, build notes. `Tests/Fixtures/`: vendored
  engine-neutral contracts with SHA-256 provenance. `Docs/ROADMAP.md`: remaining work.

Canonical **front/right/up = Godot -Z/X/Y meters**. Stage dimensions are canonical
front/right/up, normalized against half extents. ADM XYZ is right/front/up and sphere-limited.
Scene-v1 `world_transform.position_cm` remains canonical centimeters.

Ports (identical to the Unreal plugin defaults): inputs **8100/9000**, monitor **9001**,
ADM **50018**, Custom **9002** (Custom output is not implemented). Inputs bind only after
`start_networking()`, on loopback unless `allow_remote_discovery` is set. Discovery answers
`/spatialfabric/scene/query` to the sender IP with the shared schema-v1 chunking. ADM is
opt-in (`adm_enabled`). Cue bases `/godot/playback/{mono,stereo,replay}` accept `/play`,
`/stop`, `/loop` with AudioLoom's numeric semantics and report observed `/state` to the
monitor port. Missing or duplicate authored keys fail closed and are never repaired by discovery.

## Local validation only

```sh
python -m unittest discover -s Tools -p 'test_*.py'
python Tools/build_native.py
python Tools/validate_godot.py --godot '/path/to/godot' --require-native
```

Ordinary consumers need no sibling repositories. **No GitHub Actions are used.**
macOS Core Audio for Godot, exports, other Godot versions and every physical-audio
property are unvalidated.

MIT. Third-party build input: godot-cpp (MIT), fetched at build time, not vendored.
