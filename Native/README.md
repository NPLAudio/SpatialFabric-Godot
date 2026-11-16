# Direct-device backend boundary — not implemented

No native library, GDExtension, device enumeration or audio worker is supplied yet.
PlaybackCue fails closed. Godot AudioStreamPlayer/mixer output is not a fallback.

A future adapter must provide explicit device refresh, exact endpoint routing,
immutable bounded PCM, resampling/channel mapping, observed worker state, cancellation,
drain and device-loss cleanup. Evaluate a Godot GDExtension wrapper around the existing
engine-neutral C ABI in the Unity repository; do not create a dependency on Unity
assemblies or move engine code into SpatialFabric-Interop. Source reuse needs an explicit
version/hash/license boundary and independent Godot build/lifetime tests.

Windows WASAPI and macOS Core Audio are planned, not Godot platform support claims.
Neither Unreal's user-reported Apple Silicon result nor Unity's native tests certify Godot.
