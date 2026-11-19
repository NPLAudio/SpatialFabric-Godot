# Audio routing grid (Godot editor)

Open the **SpatialFabric → Routing Grid** dock tab. **Scene Objects** and **Routing CSV** remain separate tabs; no device-group foldouts hide the routing grid. The ordinary per-cue Inspector still edits the same exported properties. No manager or runtime enrollment is required.

## Authoring

The aligned crosspoint matrix has playback-cue rows and interface-group/output-channel columns. It includes all placed playback cues in the current edited scene, including hidden/inactive cues; it does not inspect other open scene tabs or include live-input capture rows. Click an intersection to configure that cue's single endpoint/channel. A green check means **configured**, not playing, online, source-width-compatible, or verified by a stream test. This is not a DSP mixer or multi-send matrix. Clicking an existing check does nothing.

Both axes scroll with independently clipped sticky row and channel/interface headers. Shift + wheel scrolls horizontally. Native scrollbars reach all columns without collapsing groups or channel pagination. At a scroll boundary wheel input is left unconsumed for ancestor handling. Painting visits visible rows/columns only; channel groups use compact spans and binary-search lookup, with five native child controls regardless of cell count. Scene membership/protection is captured once per scene refresh, not per cell.

Click a row label (or choose its path in the cue selector) to use **Audio interface** and **Output channel** dropdowns above the matrix. Duplicate names include exact IDs. Switching interface preserves the current channel, including stored out-of-range channels. Normal Inspector and CSV/manual-ID authoring remain available; the new dropdowns are centralized here rather than injected into the Inspector or generic Scene Objects property editor.

- **Dynamic OS default** writes the empty device ID. It follows the OS at playback time and has unknown capacity; it is never replaced by the currently default physical endpoint.
- **Auto / 0** means corresponding source/output channels.
- **Positive output channels** are 1-based destinations receiving the first source channel. Source width/fit is not inferred.
- Cached interfaces expose their last known channel counts even offline. Unknown IDs expose only Auto and explicitly stored channels. Stored channels outside known capacity are marked `*`; they are not clamped, fabricated, or deleted. Invalid negative legacy values remain displayed but cannot be newly assigned. New assignments and CSV/Inspector channel editing use the native signed 32-bit range (0–2147483647), not the old artificial 256-channel cap.

## Explicit inventory and offline history

Only **Refresh Interfaces** performs static `SFNativePlayer.devices_json()` inventory. The CSV inventory button delegates to this same explicit path. Opening tabs, selecting cues, refreshing scene rows, drawing, Undo and loading history never enumerate, prepare, play, stop or capture. No native player is constructed for enumeration.

The actual Godot wrapper returns `{ok, json, error}`. Its JSON payload is a native **array** of endpoint dictionaries using `id`, `name`, `channels`, `sample_rate` (and unused `is_default`), not Unity managed-device field names. An error envelope, stale success-with-error, malformed/missing fields, duplicate IDs or invalid bounds rejects the entire refresh. Failed refreshes mark history offline for the session, preserve all routes/history, and never persist. A successful refresh that omits a device retains its offline entry and last-seen timestamp; reconnection matches exact IDs, never names. Online means last explicit successful enumeration, not live hotplug monitoring.

History lives in `EditorInterface.get_editor_paths().get_project_settings_dir()/spatialfabric_audio_interfaces_v1.json` (normally `.godot/editor`): per-project editor-user metadata, not `project.godot`, scene data or exported cue references. Schema version 1 stores only exact ID/name, channel count, sample rate and UTC last-seen timestamp. Online state is session-only and always false after load. Persistence uses a temporary file and rename before publishing successful inventory.

Bounds: 256 historical endpoints, 4096 channels/interface, 1024 characters/text field, 2 MiB JSON, sample rate 0–768000 Hz. Control characters, empty physical IDs and fractional numeric fields are rejected. A full history rejects additional endpoints rather than evicting unplugged devices. No implicit history deletion or cache-clear UI is provided.

## Mutation safety and persistence

Every assignment freshly rechecks the stopped editor, current edited-scene membership and existing Scene Object Manager protection, even after a mouse press. Active playback, pending replay/starting requests and retained native-player objects are conservatively protected without polling native workers. The panel never stops a cue to enable an edit. Foreign/unowned transient nodes, external packed-scene content (including editable-instance overrides) and inherited scenes remain read-only here; open the source scene instead. Other stopped local cues remain authorable.

One `EditorUndoRedoManager` action changes only the existing cue's real `device_id` and `output_channel`. It uses that cue's scene history and the editor's normal dirty/persistence behavior; unrelated exports and other cues are untouched. Owned local cue routes survive PackedScene save/reload. This surface deliberately does not author packed-instance overrides. New route IDs/channels are validated, with no invented capacity limit on stored positive routes.

Use **Refresh scene cues** after external Scene Tree additions/removals or Inspector changes; edited-scene changes and editor history changes refresh automatically. No background native polling is installed. Empty scenes retain interface columns. Protected rows are dimmed and selector controls disabled, with protection reasons in row tooltips/status.

## Validation evidence

Godot **4.7.2 stable**, disposable copies only, existing native DLL copied unchanged:

- **149 editor assertions** passed (95 existing + 54 routing), clean import/editor logs and shutdown: `C:/dev/GodotRouting-20261118-reviewed149-bounddraft/{import.log,editor.log,editor-tests.json}`.
- **22 Python tests** passed: `python -m unittest discover -s Tools`.
- **308 runtime assertions**, native required, passed in that same disposable project: `C:/dev/GodotRouting-20261118-reviewed149-bounddraft/{runtime.log,runtime-tests.json}`. The only subsequent copy was the updated `Tests/Godot/routing_tests.gd` overflow fixture (257 is now a valid route; 2147483648 is not), never an original-project import.

Editor coverage includes actual native viewport mouse dispatch to a crosspoint and sticky-row exclusion, real grid GUI signals, dropdown selection signals, one-action Undo/Redo, no-op routing, PackedScene persistence, inactive rows, active/replay/start/foreign/packed guards, mouse-release revalidation, explicit inventory call counts, failed/stale/missing/reconnected inventory, offline reload, schema/bounds/full-history rejection, stored unknown/out-of-range routes, constant-control 10,000 × 4098 presentation, clipping and independent headers. Additional regressions cover UTF-8 byte—not character—inventory limits, a grid-authored channel 7000 surviving an unrelated CSV draft edit and Undo/CSV roundtrip, native int32 overflow rejection, and actual viewport wheel events propagating to an ancestor at the boundary but being consumed when the grid scrolls. CSV snapshot selection explicitly synchronizes hidden SpinBox editable text, preventing Apply from writing a previous cue's unpainted value. Inventory disconnect/reconnect is simulated, not a physical hotplug certification. Headless validation does not establish rendered usability, native dropdown popup keyboard interaction, physical audio playback or microphone behavior.

Re-run editor checks from the source directory (the helper never imports the source project):

```text
python Tools/validate_editor.py --godot C:/Users/davo_/AppData/Local/Temp/GodotExportPortable/Godot_v4.7.2-stable_win64_console.exe --output C:/dev/GodotRouting-new-evidence
```

Choose a fresh output directory. Manual gates remain: graphical readability at small dock sizes, very wide hardware inventories, native popup keyboard/focus behavior, physical unplug/reconnect and hardware streams. Unity and Unreal are outside this Godot implementation's validation scope.
