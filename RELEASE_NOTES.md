# SpatialFabric Godot 0.2.0

First GitHub release of the Godot integration and four-room showcase, for Godot 4.7.2.

## Changes

- Standard OSC `/ack` results and `/status`, with actual observed playing/stopped
  state, synchronous/asynchronous start failures and bounded command handling.
- Correct native start return handling; Play prepares PCM on demand. Cue WAVs ship
  in release exports without lossy import conversion.
- Lifecycle subscriptions track late-added, removed and freed cue nodes while OSC
  is active. Seven golden packets and 34 shared command decisions are covered.
- Forward+ four-room walking example with explicit playback, live-input and network
  controls. No audio or listeners are started automatically.

## Downloads

- `SpatialFabric-Godot-0.2.0-CompleteSource.zip`: source project, vendored native
  sources, documentation and tests. Build native libraries for your target platform.
- `SpatialFabric-Godot-0.2.0-Windows-x64.zip`: editor-ready project with Windows debug
  and release native libraries.
- `SpatialFabricRoomShowcase-Godot-0.2.0-Windows-x64.zip`: standalone release export.
  Extract every file together; the `.pck` and native `.dll` are required. Keep the
  bundled `LICENSE` and `LICENSES/` directory (Godot engine/third-party, godot-cpp
  and native audio notices) with the application.

For source builds see `README.md`. For controller use, explicitly enable OSC and use
`examples/four_rooms/OSCControllerProfile.json` in this project. The controller
bundle also provides `profiles/spatialfabric-godot.json`; its canonical source is
[`Apps/OSCController/profiles/spatialfabric-godot.json`](https://github.com/NPLAudio/SpatialFabric/blob/main/Apps/OSCController/profiles/spatialfabric-godot.json)
in the SpatialFabric hub. Shared ports: input 8100/9000,
monitor 9001, ADM 50018, Custom 9002. Multiple engines need distinct configured ports.

## Verification / limits

205 Godot checks passed with the rebuilt Windows debug native library; an earlier
no-extension gate passed 176 checks. Nine Python checks and fixture provenance passed.
An earlier Windows release export passed headless/windowed self-checks, a rendered
screenshot and real ADM UDP verification, without audio playback. That evidence does
not certify the latest source or updated notice packaging; a fresh export is required
before publishing the runtime archive. See `VALIDATION.md` and build manifests for exact scope. The operator reported the interactive issues resolved.

OSC acknowledgement delivery is best effort and unauthenticated. A received play is
not proof of audible output. Automated tests did not open real capture or produce
physical sound. This release provides unsigned Windows x64 binaries only; hardware,
latency and other platforms are not certified. Keep an independent mute and use
headphones before intentionally enabling live input. Preserve bundled licenses.
