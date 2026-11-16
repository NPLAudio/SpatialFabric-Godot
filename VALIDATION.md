# Local wireframe validation

Status: **starter scaffold only**, not a complete Godot port. No GitHub Actions.
No GitHub remote, release, export templates or native binaries are configured.

## Measured

Windows x64, official Godot **4.7.2.stable.ed1daf0bf**, portable test executable:

- **6 Python source/provenance/layout checks passed**.
- Vendored Interop fixture bytes and SHA-256 provenance match the shared source.
- Real headless Godot editor import with the example's plugin enabled: passed,
  no script/parse errors. Dummy audio driver used for validation.
- **57 real Godot checks passed** (the original 31 plus fixture-exact OSC decode/re-encode/rejection, bundles, bounds, exclusive bind with rollback, real UDP paged scene query, ignored invalid requests, ADM XYZ/AED over UDP, socket release). Original 31:: canonical -Z/X/Y and ADM mapping, sphere limiting,
  rotated/invalid stages, nine-record local inventory, paging/bounds, duplicate-key
  refusal without mutation, unavailable native/network paths, four floor probes,
  four clear door capsules, actual visitor crossings through all four doors and
  blocking at a solid wall.
- A fresh source-only consumer copy (no `.godot` cache, `.git` or sibling repository)
  independently passed **31 Godot + 6 Python checks** after a clean import.
- **Two actual OpenGL Compatibility renders captured and reviewed** (hall / spatial
  room), NVIDIA RTX 4070 Ti SUPER. Geometry, original visitor camera, markers, labels
  and honest wireframe HUD rendered. No source audio or OSC was sent.

Evidence on the development machine: `%TEMP%/SpatialFabricGodot-srlq0ntq/`:
`Final/{import.log,tests.log,tests.json}`, `Screenshots/{hall,spatial}.png`, `render.log`.
Fresh-consumer evidence: `%TEMP%/SpatialFabricGodotConsumer-skavr0t7/Evidence/`.
The temporary portable Godot executable is not part of this repository.

Reproduce:

```sh
python -m unittest discover -s Tools -p 'test_*.py'
python Tools/validate_godot.py --godot '/path/to/godot'
godot --audio-driver Dummy --path . --script res://Tests/Godot/render_wireframe.gd -- /absolute/external/screenshots
```

## Not measured / not implemented

No Custom emitter, multi-destination routing, monitor state, native PCM/device
backend, source preparation, observed native lifecycle, replay, CSV, runtime-clone
identity or full authoring workflow exists yet. Audio fails closed. Network is explicit-start; only loopback is tested.
The editor dock's manual Inspect click has not had interactive UI automation; import
and the underlying local API are tested. No standalone exports, older Godot versions,
Mac/Linux Godot runtime or physical audio are validated. Other repositories' results
are not Godot evidence. See `Docs/ROADMAP.md` before advertising support or parity.
