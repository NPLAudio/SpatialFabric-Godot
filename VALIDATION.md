# Local validation

Status: **early development, not feature parity.** No GitHub Actions, remote, release or
export templates. Validation is local and silent: no physical audio has been played.

## Measured (Windows x64, official Godot 4.7.2.stable.ed1daf0bf)

- **9 Python checks**: layout, fixture/native-source/audio SHA-256 provenance, no sockets
  outside the explicit transport, no `AudioStreamPlayer`/mixer use, no Actions files.
- Real headless editor import with the plugin and the GDExtension loaded: clean, with
  the gate failing on any Godot `ERROR`, `WARNING`, parse or Unicode message.
- **86 Godot checks with the native library; 71 without it** (native checks are then
  skipped, never faked). `--require-native` makes a missing library a failure. Covered:
  - Coordinates, ADM XYZ/AED, stage validity, nine-record inventory, paging bounds and
    duplicate-key refusal without discovery repair.
  - OSC fixture-exact decode and byte-exact re-encode, malformed rejection, bundles,
    UTF-8 and bounds.
  - Real loopback UDP: exclusive bind with transactional rollback, paged scene query
    reassembly, invalid request ignored, ADM XYZ/AED packets, socket release.
  - WAV decoder on the three original cues (1/2/1 channels, 48 kHz) and bad input.
  - AudioLoom play/loop trigger semantics, including first-float-before-first-int.
  - Cue lifecycle from synthetic native statuses: observed start, natural-end replay,
    stop cancels, short clips between polls kept, device failure never replays.
  - Native: ABI v1, immutable PCM copy, channel routing, zero-tailed EOF, non-finite and
    empty PCM rejection, explicit non-playing device inventory, an **invalid device that
    fails without ever reporting Playing**, and OSC play to it with no `/state` emitted.
  - Door capsules/crossings and wall blocking with real physics; room-to-cue mapping.
- Real OpenGL Compatibility renders of hall, spatial room and a playback room were
  reviewed (RTX 4070 Ti SUPER): geometry, per-room signs and live HUD.
- Build: `Tools/build_native.py` produced debug and release DLLs from a clean godot-cpp
  clone (`godot-4.5-stable`); the extension loads in Godot 4.7.2.

Evidence directory (development machine): `%TEMP%/SpatialFabricGodot-srlq0ntq/`
(`Cue5/`, `NoNative/`, `Screens4/`). The portable Godot executable is not in the repo.

```sh
python -m unittest discover -s Tools -p 'test_*.py'
python Tools/build_native.py
python Tools/validate_godot.py --godot /path/to/godot --require-native
godot --audio-driver Dummy --path . --script res://Tests/Godot/render_wireframe.gd -- /absolute/screens
```

## Not measured / not implemented

- **Physical output of any kind**: channel isolation, fidelity, latency, exclusive mode,
  hot-unplug, audible loop/EOF/replay. Needs a human on real hardware.
- macOS/Linux Godot runtime, Core Audio, exports, other Godot versions.
- Custom protocol output, multiple keyed destinations, per-binding overrides, listener
  following, runtime-clone identity, CSV workflows, authoring panels/radar/Undo,
  query rate limiting. The editor dock has had import-level but no interactive UI test.
- The keyboard controls (E/Q/L/R/X/N) are implemented but exercised only through their
  underlying APIs and a render, not by synthetic key events.
- Other repositories' results are not Godot evidence.
