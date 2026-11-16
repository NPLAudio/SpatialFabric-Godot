# Parity roadmap

## Present in this scaffold
- Original walkable four-room geometry, hallway, capsule visitor and moving markers.
- Explicit authored keys, stage normalization, canonical Godot -Z/X/Y mapping and ADM math.
- Read-only bounded local scene-v1 page API and explicit editor inspection.
- Strict bounded OSC codec; explicit exact-bind UDP with transactional rollback.
- Read-only network scene discovery (sender-IP reply, UTF-8 chunking, loopback default).
- Opt-in ADM XYZ/AED/Both output with change filtering and observed `/state` monitor output.
- GDExtension direct-device backend (vendored C ABI), WAV decoder, explicit source
  preparation/device inventory, cue lifecycle with natural-end replay, AudioLoom OSC
  play/stop/loop semantics and real E/Q/L/R/X/N example controls.
- Vendored shared schemas/fixtures with SHA-256 provenance and local tests.

- Live input: `SpatialFabricLiveInputCue` (capture device/channel to output device/channel), OSC
  play/stop/gain/state, discovery row, example **I** control.

## Not implemented
1. Multiple keyed output destinations and per-binding output overrides.
2. Query rate limiting/paced multi-page replies beyond the current bounded poll budget.
3. Custom-protocol emission (fixtures already vendored), gain/width/mute/name ADM fields,
   listener following and stable runtime-clone keys.
4. Transactional CSV workflows and editor-side source import.
5. Full authoring panels/radar, Undo, scene persistence/additive-world integration.
6. macOS Core Audio build/run for Godot, exports/templates and physical-hardware
   acceptance on each claimed platform.

There are no fake network/playback toggles. Missing/duplicate authored keys fail queries
rather than being repaired by discovery. Explicit bindings only; runtime clones are unsupported.
Stage scale must be unit/positive; listener-following and stage flips are not yet supported.
Do not call this feature parity, release readiness or hardware certification.

Validation stays local. No GitHub Actions definitions or hosted jobs are used.
