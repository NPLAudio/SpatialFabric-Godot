# Parity roadmap

## Implemented surface
- Original walkable four-room geometry, hallway, capsule visitor and moving markers.
- Explicit authored keys, stage normalization, canonical Godot -Z/X/Y mapping and ADM math.
- Read-only bounded local scene-v1 page API and explicit editor inspection.
- Strict bounded OSC codec; explicit exact-bind UDP with transactional rollback.
- Read-only network scene discovery (sender-IP reply, UTF-8 chunking, loopback default).
- Opt-in ADM XYZ/AED/Both output with change filtering and observed `/state` monitor output.
- GDExtension direct-device backend (vendored C ABI), WAV decoder, explicit source
  preparation/device inventory, cue lifecycle with natural-end replay, AudioLoom OSC
  play/stop/loop semantics and real E/Q/L/R/X/N example controls.
- Playback random min/max replay, opt-in runtime startup, derived/custom OSC bases,
  active-only route/source restart and feedback suppression.
- Editor playback manager, draft WAV selection, validated native/legacy-routing CSV,
  real Undo/Redo, scene persistence and playback/live address conflict diagnostics.
- Shared native Windows same-endpoint exclusive/shared negotiation, actual output
  mode and OS-reported output latency diagnostics; see [PARITY.md](PARITY.md).
- Vendored shared schemas/fixtures with SHA-256 provenance and local tests.

- Live input: `SpatialFabricLiveInputCue` (capture device/channel to output device/channel), OSC
  play/stop/gain/state, discovery row, example **I** control.

## Not implemented
1. Multiple keyed output destinations and per-binding output overrides.
2. Query rate limiting/paced multi-page replies beyond the current bounded poll budget.
3. Custom-protocol emission (fixtures already vendored), gain/width/mute/name ADM fields,
   listener following and stable runtime-clone keys.
4. Spatial-object/ADM authoring radar and full additive-world integration beyond
   playback-cue scene authoring. Playback CSV/manager work is tracked separately in
   [playback parity](PARITY.md), not an assertion of spatial-protocol feature parity.
5. macOS Core Audio build/run for Godot and platform-specific packaged/deployment
   qualification, plus physical-hardware acceptance on each claimed platform.

There are no fake network/playback toggles. Missing/duplicate authored keys fail queries
rather than being repaired by discovery. Explicit bindings only; runtime clones are unsupported.
Stage scale must be unit/positive; listener-following and stage flips are not yet supported.
The AudioLoom playback baseline and its software checks are documented separately
in [PARITY.md](PARITY.md). This roadmap does not claim full spatial-protocol parity,
release readiness or hardware certification.

Validation stays local. No GitHub Actions definitions or hosted jobs are used.
