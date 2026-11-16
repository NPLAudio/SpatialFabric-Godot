# Wireframe / parity roadmap

## Present in this scaffold
- Original walkable four-room geometry, hallway, capsule visitor and moving markers.
- Explicit authored keys, stage normalization, canonical Godot -Z/X/Y mapping and ADM math.
- Read-only bounded local scene-v1 page API and explicit editor inspection.
- Strict bounded OSC codec; explicit exact-bind UDP with transactional rollback.
- Read-only network scene discovery (sender-IP reply, UTF-8 chunking, loopback default).
- Opt-in ADM XYZ/AED/Both output with change filtering; fail-closed native audio.
- Vendored shared schemas/fixtures with SHA-256 provenance and local tests.

## Not implemented
1. Multiple keyed output destinations, per-binding output overrides and monitor `/state`.
2. Query rate limiting/paced multi-page replies beyond the current bounded poll budget.
3. Custom-protocol emission (fixtures already vendored), gain/width/mute/name ADM fields, listener following, target overrides and stable runtime-clone keys.
4. Native device/PCM preparation and worker lifecycle, real observed state, loop/replay,
   routing, source import and transactional CSV workflows.
5. Full authoring panels/radar, Undo, scene persistence/additive-world integration.
6. Native deployment/export/player/hardware acceptance on each claimed platform.

The wireframe has no fake network/playback toggles. Exported ports/source paths are
configuration only. The local inventory deliberately reports listening/playing false
and backend unavailable. Missing/duplicate authored keys fail queries rather than
being repaired by discovery. Explicit bindings only; runtime clones are unsupported.
Stage scale must be unit/positive; listener-following and stage flips are not yet supported.
Do not call this feature parity, release readiness or hardware certification.

Validation stays local. No GitHub Actions definitions or hosted jobs are used.
