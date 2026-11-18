# AudioLoom playback parity

The shared [playback contract](https://github.com/NPLAudio/SpatialFabric/blob/main/Specs/Playback-Parity-v1.md)
tracks the AudioLoom baseline, not full spatial-protocol parity or physical-audio
certification. Broader Godot work remains in [ROADMAP.md](ROADMAP.md).

## Closed audited gaps

- Fixed/random min/max replay, one selection per natural end; stop, failure, loop
  and disabling replay cancel pending work. EOF signal subscribers can stop without
  accidentally re-arming playback. Finite long delays are not silently capped.
- `play_on_start` defaults false and runs only in the game, never the editor.
- Blank-derived OSC paths use injectively hex-encoded UTF-8 hierarchy names scoped
  to the authored scene. Explicit nonempty addresses survive unchanged. Rename or
  reparent changes the default; use an explicit path for persistent controllers.
- Duplicate/invalid effective addresses are diagnosed, including playback/live
  collisions in editor validation. Nested commands belong to the most-specific
  registered base; feedback for every registered `/ack` and `/state` is suppressed
  globally before prefix dispatch. Exact duplicates intentionally retain fan-out.
- Active route/source edits stop/join and restart; idle editing never starts audio.
  Restart begins at the start, not the old sample offset. Live-route edits use the
  same active-only rule. Missing configured devices remain fail-closed.
- Shared native Windows exclusive-preferred/shared fallback stays on one endpoint;
  cached OS output-path latency and actual mode are exposed in native status,
  discovery, manager and showcase. Queue occupancy is not OS output latency.
- Editor manager supports source/device/channel/OSC/loop/replay/startup authoring,
  draft-only WAV selection, explicit device inventory and routing CSV import/export.
  Accepted changes use one EditorUndoRedoManager transaction with scene persistence.
  Inspection/CSV preview does not open a stream or enable networking.

## CSV and source identity

Native CSV carries the cue node path, WAV source path, routing and replay/startup
fields. CSV parsing is bounded and handles quotes, newlines, CRLF, BOM and Unicode.
Malformed rows are rejected whole; valid independent rows can still apply. Duplicate
row targets and effective address collisions are rejected rather than guessed.
All accepted properties are one undoable transaction, not an all-file atomic import.
Live cues are included in conflict checks, not exported as playback-cue rows.

Legacy AudioLoom 13-column CSV import requires unique existing cue/WAV/device
mappings. Godot cannot load Unreal SoundWave object references. Unmapped/ambiguous
sources and device labels produce diagnostics; import never invents an asset or
silently substitutes a route. Use explicitly staged WAVs. Whole-PCM decode budgets
and supported rate/layout checks remain; this is not unlimited streaming.

## Fresh local checks

Godot **4.7.2**, Windows x64:

- **308 headless/native checks passed**, with clean import/runtime logs.
- **18 editor authoring assertions passed with clean shutdown**, including actual
  EditorUndoRedoManager, source draft isolation, CSV round-trip/import and
  playback/live collision rejection. The opt-in test plugin uses the normal editor
  loop in a disposable project; no working scene/project settings are changed.
- **22 Python checks passed**; native and interop provenance synchronized.
- Debug/release GDExtension wrappers built against the additive mode/latency APIs.
- Shared native core: **55 silent + 55 fake-COM negotiation/diagnostic checks passed**.

Latest clean runtime gate:
`C:/Users/davo_/AppData/Local/Temp/SpatialFabricGodotChecks-r4b0kq9a/`.
Clean editor gate:
`C:/Users/davo_/AppData/Local/Temp/SpatialFabricGodotEditor-u8qlgo8d/editor-tests.json`.

```text
python Tools/validate_editor.py --godot /path/to/godot
```

The parent process rejects nonzero exits, warnings/errors/leaks and missing required
assertions after editor termination. It does not whitelist shutdown diagnostics.
The CSV fixture stays inside the evidence directory, never the shared `user://` path.
These are machine-local temporary artifacts, not release certificates.

### Current Windows release export

A fresh disposable-copy release export passed headless/windowed self-checks, with
native availability, 10 inventory records, all three retained example WAVs decoded,
and playback/live/network inactive at startup. The windowed screenshot rendered;
explicit ADM loopback verification received 131 three-float XYZ packets across
`/adm/obj/1/xyz` through `/adm/obj/4/xyz`. Dummy audio only. Local notices/ZIP checks passed.

Evidence: `C:/Users/davo_/AppData/Local/Temp/AudioLoom-release-validation-9dlayt1f/`.
Source/copied/exported DLL SHA-256:
`ea11b9471e63f5390bf303e393be7ad0aa538a036ba04fd4873bd53f8d0336c9`.
All 24 expected exports exist, including latency/mode diagnostics. Vendored hashes
match current files; three native files differ from the recorded upstream commit,
so that commit alone does not identify this uncommitted working-tree build.
This is current example-export evidence, not arbitrary migrated-source certification.

The former custom `--editor --script` runner's RID/ObjectDB leaks also reproduced
in an addon-free project. Replacing only that runner architecture resolved them;
no production-addon teardown workaround was needed. Both current editor and runtime
gates have clean logs. No physical playback, microphone capture,
macOS Godot build, packaged sidecar/source migration or acoustic latency qualification
was performed. Loopback UDP and deliberately invalid-device checks are real.
Existing `project.godot` user edits were preserved. See [../VALIDATION.md](../VALIDATION.md)
for commands, historical evidence and remaining deployment boundaries.
