# Central Scene Object Manager

The existing **SpatialFabric** editor dock has **Scene Objects**, **Routing Grid** and **Routing CSV** tabs. [Audio Routing Grid](AudioRoutingMatrix.md) documents the separate aligned crosspoint matrix, centralized interface/channel dropdowns, explicit inventory and offline editor-user history. This is an in-editor scene configuration surface, not a network router or a property-link system. Opening it does not prepare audio, enumerate devices, capture a microphone, start listeners, or enroll objects in a runtime manager.

## Workflow

1. Open the scene you want to author. **Scene Objects** lists the current edited scene root and placed descendants, including ordinary `Node`, hidden and nonspatial nodes with no SF configuration. Editor/internal and unowned transient nodes are excluded.
2. Filter by node path, engine type or SF type. Ctrl/Shift-select multiple rows, or select parents in the Scene Tree and click **Use Scene Tree selection**. Filtering does not discard an existing selection; clear the filter to see every selected row. **Refresh all placed nodes** updates the list after Scene Tree changes.
3. Choose an SF type. **Add typed SF child to selected nodes** explicitly adds that functionality to each selected parent. Existing matching functionality on the node or a direct child is reused; repeated Add does not create duplicates. The original node's script is never replaced.
4. Choose an exported SF property. Controls are generated from the actual component's export metadata, not a parallel settings model. Mixed values are explicitly marked; simply opening a property or pressing Apply preserves them. Author a value, then **Apply authored SF property to selection**. Each bulk operation is one scene Undo/Redo transaction. Missing functionality, protected targets or invalid values reject the entire edit with reasons; editing never adds functionality implicitly. The property key stays selected after Apply and history refreshes.
5. **Inspect first SF component** opens the real node in Godot's normal Inspector (including its native export hints). Central editing deliberately exposes only that SF type's script exports, not engine properties such as transforms or visibility. Save the scene normally to persist owned children and properties.

## Central property controls

- **Booleans:** checkbox with an explicit mixed indicator; clicking authors a definite value.
- **Enums:** exported labels such as **XYZ / AED / Both**, not numeric codes.
- **Numbers:** SpinBoxes use exported bounds/steps. Apply validates finite numbers, whole integers and ranges across every target before starting a transaction. Raw typed input remains authoritative even if SpinBox normalizes its display on focus loss. `or_greater` / `or_lesser` are honored; replay delays above one hour remain valid. Replay minimum must not exceed each target's maximum. Ports/channels use their real export limits, and stage dimensions must be finite and positive.
- **Vectors:** numeric X/Y/Z/W fields. Editing one axis of a mixed vector preserves each target's other axes.
- **Strings:** plain text. `source_path` also has a file picker with the exported WAV filter; picking a file changes only the draft. Empty paths are allowed; nonempty source paths must be WAV paths. OSC bases retain their literal-path validation. To author an empty string over mixed values, type and clear the string before Apply.
- **NodePath / Array[NodePath]:** select destination nodes in the Scene Tree, then click the property's **Use Scene Tree selection** control (the single-path control uses the first selected node). This does not change the dock's authored target set. **Clear paths** drafts an empty path/array. Apply computes relative paths separately from each real SF component, preserves typed arrays and rejects stale/out-of-scene destinations atomically. No handwritten NodePath constructors are required.

Normal SF exports require no code syntax. Only uncommon complex exports use an explicitly labeled advanced Variant fallback. Applying one property leaves all other properties unchanged. The Scene Objects tab scrolls vertically to keep Apply and status reachable in shorter docks.

**Remove selected SF functionality** is explicit and undoable. It removes the chosen matching SF component, not the selected ordinary parent. The edited root and SF nodes containing children cannot be removed here; use the normal Scene Tree for subtree operations. Removal Undo restores parent, owner and sibling position. Creation/removal use EditorUndoRedoManager scene histories and reference tracking so detached nodes survive Undo/Redo and are released when their history is discarded.

## Supported types

| Choice | Real typed child | Configuration |
| --- | --- | --- |
| Playback | `SpatialFabricPlaybackCue` | Source, output, loop/replay and OSC identity exports; inactive defaults, `play_on_start = false`. |
| Live input | `SpatialFabricLiveInputCue` | Capture/output routing and gain exports; no session or microphone starts. |
| Spatial object | `SpatialFabricObject` | Object identity/label and bound transform. For a Node3D parent, new children explicitly bind `..`; otherwise the component has its own independent 3D pose. |
| Stage | `SpatialFabricStage` | Persistent key and canonical dimensions in meters. |
| Manager | `SpatialFabricManager` | Explicit paths, ports and network/ADM configuration; no listener starts. |

All types can be added beneath an ordinary Node. Node3D-based components beneath nonspatial parents do not acquire a guessed transform binding. No attachment modifies any existing manager's `object_paths`, `cue_paths`, `live_paths` or `stage_path`. Runtime enrollment and starting audio/networking remain separate explicit operations. Authoring `play_on_start` changes future runtime behavior, never editor playback.

## Safety and limitations

- External packed-scene content remains listed but read-only here, including instance roots and editable-instance overrides. Open its source scene to configure it. Inherited scenes are conservatively entirely read-only in this surface, including local overrides. Reasons appear in row tooltips and selection/operation messages. Existing Routing CSV mutations use the same protection check.
- Selection addresses the node itself if it is the chosen SF type, otherwise its first direct matching child. It does not recursively guess a component beneath other parents. If older authored content already has duplicate components, select those component rows individually to inspect/edit them.
- This remains SF configuration authoring, not a complete replacement for every Inspector widget. Node references use the current Scene Tree selection, not a separate hierarchical picker; the array control replaces/clears the array rather than reordering individual rows. The existing Routing CSV tab retains its routing-policy validation; its explicit Refresh Interfaces button shares the Routing Grid inventory/cache path. Routing Grid provides human-friendly route selectors without replacing generic SF-property or Inspector authoring. None of the tabs starts streams/listeners.
- Use Refresh after adding/deleting/reparenting through other editor tools. History and edited-scene changes refresh automatically. Pending drafts are bound to the scene, selected node/real-component sets, SF type and property. Compatible refreshes retain the draft, including unrelated history; incompatible changes cancel it with a visible message, never applying it to a different target. Apply remains explicit. Filtering is debounced and uses cached rows without packing the scene or rebuilding the typed editor. Scene membership and inheritance protection are cached once per refresh/operation (including Routing CSV protection), not recalculated per row.

## Regression evidence

Run from the project directory (the runner copies the project; it never imports or runs the source project):

```text
python Tools/validate_editor.py --godot C:/Users/davo_/AppData/Local/Temp/GodotExportPortable/Godot_v4.7.2-stable_win64_console.exe --output C:/dev/GodotSceneManager-polished-20261118-final95
python -m unittest discover -s Tools
```

2026-11-18, Godot **4.7.2 stable**: **95 editor assertions passed**, clean headless import/editor logs and shutdown; **22 Python tests passed** (including 4 runner tests). Evidence: `C:/dev/GodotSceneManager-polished-20261118-final95/{import.log,editor.log,editor-tests.json}`. Choose a fresh output directory for another run; existing evidence is never replaced.

Coverage includes real typed-control construction/signals and conversion helpers: mixed checkboxes, enum labels, numeric/range/finite rejection, raw drafts surviving simulated native normalization/focus-loss signals, numeric step signals, both range-extension flags, over-one-hour replay and per-target min/max validation, file picker callbacks, single/array NodePath selection/clear and per-component resolution, stale node rejection, partial mixed-vector edits, invalid dimensions, retained property/draft during refresh/history, target/scene-bound draft cancellation, cached/debounced filtering with hash-indexed selection membership, vertical scrolling, and reversed `[C, B, A]` removal/Undo restoring original `[A, B, C, D]` sibling order through redo.

Existing attachment/lifetime/ownership, save/reload persistence, protected packed/inherited/unsaved scenes and no audio/capture/network startup or implicit enrollment assertions remain covered. Persistence uses the editor's no-preview save API to avoid dummy-renderer thumbnail errors. Headless Scene Objects tests do not establish actual mouse/keyboard focus, native file-dialog interaction, visual layout usability or hardware audio acceptance; those manual gates remain outstanding. The subsequent routing implementation passed **149 total editor assertions**, **22 Python tests** and **308 native-required runtime assertions**; [routing evidence and exact scope](AudioRoutingMatrix.md#validation-evidence) includes native viewport crosspoint mouse dispatch, without claiming physical audio or graphical UX certification.
