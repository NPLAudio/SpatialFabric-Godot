# SpatialFabric for Godot — 0.1 wireframe

**Early development, not a feature-parity port.** Includes an original walkable four-room
blockout, stage/object bindings, a strict bounded OSC codec, explicit exact-bind UDP
transport, read-only scene discovery, ADM XYZ/AED output and shared contract fixtures.
**Direct-device playback is not implemented.** Nothing binds, sends, loads sources or
plays on startup, and there is no Godot mixer fallback.

## SpatialFabric repositories

| Repository | Purpose |
|---|---|
| [SpatialFabric](https://github.com/NPLAudio/SpatialFabric) | Unreal implementation and independent OSC Controller |
| [SpatialFabric-Unity](https://github.com/NPLAudio/SpatialFabric-Unity) | Unity implementation and native audio backend |
| [SpatialFabric-Interop](https://github.com/NPLAudio/SpatialFabric-Interop) | Shared OSC/scene schemas and golden fixtures |
| [AudioLoom](https://github.com/NPLAudio/AudioLoom) | Legacy standalone Unreal playback; private/access-controlled |

This Godot repository is initially local; publishing/remotes are a separate step.
Shared contracts do not transfer platform or hardware certification between engines.

## Open the wireframe

Use Godot **4.7.2 Standard** (GDScript; no .NET requirement). Import root `project.godot`
and run `examples/four_rooms/room_showcase.tscn`. The supported Godot **Compatibility**
renderer keeps this primitive blockout lightweight; this is not Unity's Built-in pipeline.

Click to capture the mouse; **WASD** walks, **Shift** sprints, **Space** jumps, **Esc** releases.
Four enclosed rooms have a continuous hallway/foundation and capsule-width entrances.
Four markers demonstrate binding positions; three animate. Playback rooms are explicitly
labeled placeholders: no sounds, sources or fake play buttons. Network is started only by
calling `SpatialFabricManager.start_networking()` (no UI toggle yet).

The example enables the optional editor dock. Toggle it under
**Project Settings → Plugins → SpatialFabric**; enable it explicitly in other projects.
**Inspect edited scene** reads the local manager only when clicked. For another project,
copy `addons/spatial_fabric/`; the example and Tests are not runtime dependencies.

## Architecture and contracts

- `addons/spatial_fabric/runtime/`: stage, explicit authored object keys/bindings,
  bounded local scene inventory and fail-closed playback/transport boundaries.
- `addons/spatial_fabric/plugin.gd`: explicit read-only editor inspection; no I/O on enable.
- `examples/four_rooms/`: original procedural geometry/visitor; no engine-template assets.
- `Native/`: backend integration plan only; no binary or GDExtension yet.
- `Tests/Fixtures/`: vendored engine-neutral contracts with SHA-256 provenance.
- `Docs/ROADMAP.md`: unimplemented parity work and acceptance gates.

Canonical **front/right/up = Godot -Z/X/Y meters**. Stage dimensions are canonical
front/right/up, normalized against half extents. ADM XYZ is right/front/up and
sphere-limited. Scene-v1 `world_transform.position_cm` remains canonical centimeters.
Godot identity/rotation conventions must never be substituted silently for wire units.

Reserved configuration to coexist with Unreal/Unity: OSC inputs **8300/9200**,
monitor **9201**, ADM **50029**, Custom **9202**. Inputs bind only after
`start_networking()` on loopback by default; remote listening needs `allow_remote_discovery`.
Scene discovery answers `/spatialfabric/scene/query` to the sender IP with the shared
schema-v1 chunking (loopback senders only by default). ADM is opt-in (`adm_enabled`).
Cue bases: `/godot/playback/{mono,stereo,replay}`. Inventory has nine records.
Missing/duplicate keys fail closed and are never repaired by discovery.

## Local validation only

```sh
python -m unittest discover -s Tools -p 'test_*.py'
python Tools/sync_interop.py --check  # maintainer-only; sibling checkout required
python Tools/validate_godot.py --godot '/path/to/godot'
```

The actual Godot gate imports scripts and tests coordinates, fixture-exact OSC,
real loopback discovery/ADM, exclusivity, identity refusal, unavailable audio and
real collision geometry with dummy audio.
Tests use vendored fixtures; ordinary consumers need no sibling repositories.
See `VALIDATION.md` for measured results. **No GitHub Actions files/jobs are used.**
Godot native audio, exports, macOS/Intel/Apple Silicon and physical devices are unvalidated.

MIT; no third-party runtime libraries or source audio included.
