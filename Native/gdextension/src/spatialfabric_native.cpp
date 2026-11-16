// SpatialFabric Godot GDExtension: thin wrappers over the vendored direct-device C ABI.
// No Godot AudioServer/mixer use. Device inventory and starts are explicit calls. MIT.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vector>
#include "spatialfabric_audio.h"

using namespace godot;

class SFNativeBuffer : public RefCounted {
    GDCLASS(SFNativeBuffer, RefCounted)
    sf_buffer* buffer = nullptr;
    String error;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("create", "interleaved_samples", "channels", "sample_rate"), &SFNativeBuffer::create);
        ClassDB::bind_method(D_METHOD("is_valid"), &SFNativeBuffer::is_valid);
        ClassDB::bind_method(D_METHOD("get_error"), &SFNativeBuffer::get_error);
        ClassDB::bind_method(D_METHOD("render", "frames", "output_channels", "output_rate", "output_channel", "loop", "position"), &SFNativeBuffer::render);
    }
public:
    sf_buffer* raw() const { return buffer; }
    ~SFNativeBuffer() { if (buffer) sf_buffer_destroy(buffer); }
    // Copies PCM into an immutable native allocation; the caller's array is not retained.
    bool create(const PackedFloat32Array& samples, int32_t channels, int32_t rate) {
        if (buffer) { sf_buffer_destroy(buffer); buffer = nullptr; }
        char message[512] = {0};
        buffer = sf_buffer_create(samples.ptr(), samples.size(), channels, rate, message, sizeof(message));
        error = buffer ? String() : String::utf8(message);
        return buffer != nullptr;
    }
    bool is_valid() const { return buffer != nullptr; }
    String get_error() const { return error; }
    // Offline deterministic render for tests. Never touches an OS audio device.
    Dictionary render(int32_t frames, int32_t output_channels, int32_t output_rate, int32_t output_channel, bool loop, double position) {
        Dictionary result;
        if (!buffer || frames < 1 || frames > 1048576 || output_channels < 1 || output_channels > 64) { result["frames_written"] = -1; return result; }
        std::vector<float> out((size_t)frames * (size_t)output_channels, 0.0f);
        double cursor = position;
        int32_t written = sf_buffer_render(buffer, out.data(), frames, output_channels, output_rate, output_channel, loop ? 1 : 0, &cursor);
        PackedFloat32Array samples;
        samples.resize((int64_t)out.size());
        for (size_t i = 0; i < out.size(); ++i) samples[(int64_t)i] = out[i];
        result["frames_written"] = written;
        result["samples"] = samples;
        result["position"] = cursor;
        return result;
    }
};

class SFNativePlayer : public RefCounted {
    GDCLASS(SFNativePlayer, RefCounted)
    sf_player* player = nullptr;
    Ref<SFNativeBuffer> retained; // keeps the shared native buffer alive for the worker
protected:
    static void _bind_methods() {
        ClassDB::bind_static_method("SFNativePlayer", D_METHOD("abi_version"), &SFNativePlayer::abi_version);
        ClassDB::bind_static_method("SFNativePlayer", D_METHOD("devices_json"), &SFNativePlayer::devices_json);
        ClassDB::bind_method(D_METHOD("start", "buffer", "device_id", "output_channel", "exclusive", "buffer_ms", "loop"), &SFNativePlayer::start);
        ClassDB::bind_method(D_METHOD("set_loop", "loop"), &SFNativePlayer::set_loop);
        ClassDB::bind_method(D_METHOD("status"), &SFNativePlayer::status);
        ClassDB::bind_method(D_METHOD("stop"), &SFNativePlayer::stop);
    }
public:
    SFNativePlayer() { player = sf_player_create(); }
    ~SFNativePlayer() { if (player) { sf_player_stop(player); sf_player_destroy(player); } }
    static int64_t abi_version() { return sf_audio_abi_version(); }
    // Explicit inventory only; Godot callers must never invoke this implicitly.
    static Dictionary devices_json() {
        Dictionary result;
        char error[512] = {0};
        int32_t need = sf_devices_json(nullptr, 0, error, sizeof(error));
        if (need <= 0) { result["ok"] = false; result["error"] = String::utf8(error); return result; }
        std::vector<char> text((size_t)need + 1, 0);
        int32_t got = sf_devices_json(text.data(), need, error, sizeof(error));
        result["ok"] = got > 0;
        result["json"] = got > 0 ? String::utf8(text.data()) : String();
        result["error"] = got > 0 ? String() : String::utf8(error);
        return result;
    }
    // A request, not an acknowledgement: poll status() for the real worker state.
    int64_t start(const Ref<SFNativeBuffer>& buffer, const String& device_id, int32_t output_channel, bool exclusive, int32_t buffer_ms, bool loop) {
        if (!player || buffer.is_null() || !buffer->is_valid()) return 1; // ERR_UNAVAILABLE-like generic failure
        retained = buffer;
        CharString id = device_id.utf8();
        return sf_player_start(player, buffer->raw(), id.get_data(), output_channel, exclusive ? 1 : 0, buffer_ms, loop ? 1 : 0);
    }
    void set_loop(bool loop) { if (player) sf_player_loop(player, loop ? 1 : 0); }
    Dictionary status() const {
        Dictionary result;
        sf_status s = {};
        if (player) sf_player_status(player, &s);
        result["state"] = s.state; result["reason"] = s.reason;
        result["output_channels"] = s.output_channels; result["output_rate"] = s.output_rate;
        result["exclusive_active"] = s.exclusive_active != 0; result["buffer_frames"] = s.buffer_frames;
        result["started_sequence"] = (int64_t)s.started_sequence; result["ended_sequence"] = (int64_t)s.ended_sequence;
        result["rendered_frames"] = (int64_t)s.rendered_frames; result["error"] = String::utf8(s.error_utf8);
        return result;
    }
    void stop() { if (player) sf_player_stop(player); }
};

void initialize_spatialfabric_native(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    GDREGISTER_CLASS(SFNativeBuffer);
    GDREGISTER_CLASS(SFNativePlayer);
}
void uninitialize_spatialfabric_native(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT spatialfabric_native_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization* init) {
    GDExtensionBinding::InitObject object(get_proc, library, init);
    object.register_initializer(initialize_spatialfabric_native);
    object.register_terminator(uninitialize_spatialfabric_native);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
}
