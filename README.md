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
In a playback room: **E** prepare (first use) and request playback, **Q** stop, **L** loop,
**R** auto-replay. **X** stops all cues. **N** starts/stops OSC networking. The HUD shows
the observed state; "playing" means the native worker actually started, not that a request
was made. **E uses the system default output device and makes sound.** Rooms: spatial
motion (four objects, three animated), warm percussion (output 1), stereo groove
(matching L/R, loop), glass/mechanical (output 2, 2.5 s replay) using the same original
procedural WAVs as the Unreal/Unity examples. Visual walls do not spatialize or isolate PCM.

The editor dock is enabled in the example (Project Settings → Plugins → SpatialFabric);
**Inspect edited scene** reads the manager only when clicked. For another project copy
`addons/spatial_fabric/`; the example and tests are not runtime dependencies.

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

Ports (chosen to coexist with Unreal/Unity): inputs **8300/9200**, monitor **9201**,
ADM **50029**, Custom **9202** (Custom output is not implemented). Inputs bind only after
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
