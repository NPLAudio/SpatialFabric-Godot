# Local validation

Status: **early development, not feature parity.** No GitHub Actions, remote, release or
export templates. Validation is local and silent: no physical audio has been played.

## Measured (Windows x64, official Godot 4.7.2.stable.ed1daf0bf)

- **9 Python checks**: layout, fixture/native-source/audio SHA-256 provenance, no sockets
  outside the explicit transport, no `AudioStreamPlayer`/mixer use, no Actions files.
- Real headless editor import with the plugin and the GDExtension loaded: clean, with
  the gate failing on any Godot `ERROR`, `WARNING`, parse or Unicode message.
- **98 Godot checks with the native library** (earlier gate: 86/71 before live input) (native checks are then
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
- Real Forward+ (Vulkan) renders of hall, spatial room and a playback room were
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

## Live input (silent)

Included in the 98: observed live start/end/failure from synthetic statuses, bounded gain,
OSC gain semantics, read-only discovery row, explicit input inventory, and a live start on
intentionally invalid devices that fails (`no default fallback`) with no live state. The
vendored native core's 48 silent checks cover the bridge (mapping, resampling, xruns, gain).
**No real microphone or line input was opened.**

## Playback commands and look (local)

Reproduced "playback commands do not work": OSC `/play` on a cue nobody had prepared was refused ("Source is not prepared"), and
nothing in the example prepared cues except the E key; my earlier harness pre-prepared them and hid it. `try_play()` now prepares on
demand (preparing opens no device; tests keep every start on an invalid device). Also found by the export self-check: the **exported**
player could not read its own cue WAVs (Godot drops raw files that have an import); the three cue files are now "keep (no import)"
so they ship as-is, and the self-check fails if any cue source does not decode. **107 Godot checks** pass. Visual overhaul reviewed
in real renders. Not verified: audible output (no sound was played).

## Controller connectivity (local)

Reproduced "Godot sends nothing to the controller": the shipped example sent **zero** packets after N (ADM was never enabled) and,
once enabled, sent to `50018` while the controller listens on `50018`/`9002`/`9001`. Fixed: N enables ADM, a matching controller
profile ships, unchanged positions refresh every second (static objects were otherwise invisible to a late-starting receiver).
Verified with the controller's own receivers and tracker against the running engine: all four objects (873 packets in 10 s)
arrive on the profile's ports. **105 Godot checks** pass. Not verified: a human-operated GUI session with the full controller window.

## Release export (local)

Windows x64 release export with the official 4.7.2 templates: the exported build's own self-check passed headless and windowed
(release native library loaded, 10-record inventory, nothing listening/playing/live at startup), a screenshot was rendered from
the export, and a fresh extraction of the ZIP re-passed with matching SHA-256s. Unsigned; macOS/Linux/web are not exported; no
physical audio was played. The project gate (98 checks) was re-run on a clean copy because an editor was open on the project.

## Not measured / not implemented

- **Physical input or output of any kind** (real capture, latency, drift, feedback handling): channel isolation, fidelity, latency, exclusive mode,
  hot-unplug, audible loop/EOF/replay. Needs a human on real hardware.
- macOS/Linux Godot runtime, Core Audio, exports, other Godot versions.
- Custom protocol output, multiple keyed destinations, per-binding overrides, listener
  following, runtime-clone identity, CSV workflows, authoring panels/radar/Undo,
  query rate limiting. The editor dock has had import-level but no interactive UI test.
- The keyboard controls (E/Q/L/R/X/N) are implemented but exercised only through their
  underlying APIs and a render, not by synthetic key events.
- Other repositories' results are not Godot evidence.
