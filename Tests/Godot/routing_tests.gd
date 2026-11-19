extends SceneTree
## Standalone: godot --headless --path . --script Tests/Godot/routing_tests.gd
## Main runner: preload("res://Tests/Godot/routing_tests.gd").run(tree, check)
## Pure tests: no native extension, device, audio or network calls.

const Policy = preload("res://addons/spatial_fabric/editor/routing_policy.gd")
var _failures := 0
var _checks := 0

class AuthoredCue extends Node:
	var source_path := "res://audio/Bell.wav"
	var device_id := "opaque-id"
	var output_channel := 2
	var exclusive := false
	var buffer_ms := 20
	var osc_base := "/test/bell"
	var loop := false
	var auto_replay := true
	var replay_delay_seconds := 2.5
	var random_replay_delay := true
	var replay_delay_min := 1.0
	var replay_delay_max := 3.0
	var play_on_start := false

func _initialize() -> void:
	call_deferred("_standalone")

func _standalone() -> void:
	run(self, _check)
	print("Routing tests: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(label)

static func _legacy(values: Array) -> String:
	var fields := PackedStringArray()
	for value in values:
		fields.append(Policy._quote(str(value)))
	return ",".join(Policy.LEGACY_COLUMNS) + "\n" + ",".join(fields) + "\n"

static func run(tree: SceneTree, check: Callable) -> void:
	var cue := AuthoredCue.new()
	cue.name = "RoutingTestCue"
	tree.root.add_child(cue)
	var row := Policy.snapshot(cue)
	check.call(row.node_path == str(cue.get_path()) and row.random_replay_delay and not row.play_on_start, "snapshot copies node path and opt-in fields")
	check.call(Policy.validate(row).is_empty(), "authored row validates")
	var before := row.duplicate(true)
	Policy.validate(row)
	check.call(row == before and cue.source_path == row.source_path, "validation does not mutate row or cue")
	cue.free()

	var quoted := row.duplicate(true)
	quoted.source_path = "res://audio/日本,\"Bell\"\nline\rbreak.wav"
	quoted.device_id = "device, \"quoted\"\r\nsecond line"
	quoted.replay_delay_seconds = 1.23456789012345
	var csv := Policy.export_csv([quoted, row])
	var imported := Policy.import_csv(csv)
	check.call(not csv.is_empty() and imported.errors.is_empty() and imported.rows == [quoted, row], "CSV roundtrip commas quotes CR LF Unicode and types")
	check.call(Policy.import_csv(String.chr(0xfeff) + Policy.export_csv([row]).replace("\n", "\r\n")).rows == [row], "BOM and CRLF import")
	check.call(Policy.import_csv(Policy.export_csv([row]).trim_suffix("\n")).rows == [row], "CSV final record needs no newline")
	check.call(Policy.import_csv(Policy.export_csv([])).rows.is_empty(), "empty export imports as zero rows")
	var blank := row.duplicate(true)
	blank.source_path = ""
	blank.device_id = ""
	check.call(Policy.validate(blank).is_empty(), "unassigned source and default device accepted")

	for key in Policy.COLUMNS:
		var missing := row.duplicate(true)
		missing.erase(key)
		check.call(not Policy.validate(missing).is_empty(), "required field / " + key)
	for pair in [["output_channel", -1], ["output_channel", 2147483648], ["output_channel", 1.5], ["buffer_ms", 4], ["buffer_ms", 501], ["exclusive", 1], ["play_on_start", "false"], ["replay_delay_seconds", NAN], ["replay_delay_max", INF], ["replay_delay_min", -1], ["node_path", ""], ["node_path", "Cue:property"], ["source_path", "res://bell.mp3"], ["osc_base", "relative"], ["osc_base", "/bad path"], ["osc_base", "/bad/*"], ["osc_base", "/bad/"], ["device_id", "x".repeat(Policy.MAX_FIELD + 1)]]:
		var invalid := row.duplicate(true)
		invalid[pair[0]] = pair[1]
		check.call(not Policy.validate(invalid).is_empty(), "reject invalid / " + str(pair))
	var long_delay := row.duplicate(true)
	long_delay.replay_delay_seconds = 7200.0
	long_delay.replay_delay_max = 10800.0
	check.call(Policy.validate(long_delay).is_empty(), "finite long replay delays retain AudioLoom scheduling range")
	var reversed := row.duplicate(true)
	reversed.replay_delay_min = 4.0
	check.call(not Policy.validate(reversed).is_empty() and Policy.export_csv([row, reversed]).is_empty(), "reversed delay and whole invalid export rejected")

	var header := ",".join(Policy.COLUMNS) + "\n"
	var good_line := Policy.export_csv([row]).trim_prefix(header)
	var bad_line := good_line.replace(",2,", ",not-an-int,")
	var partial := Policy.import_csv(header + good_line + bad_line + "short,row\n" + good_line)
	check.call(partial.rows == [row, row] and partial.errors.size() == 2, "bad and short native rows never partially imported; good rows preserved")
	check.call(partial.errors[0].row == 3 and partial.errors[1].row == 4, "native diagnostics have logical CSV row indexes")
	var bad_bool := good_line.replace(",false,", ",maybe,")
	check.call(Policy.import_csv(header + bad_bool).rows.is_empty(), "invalid boolean is not silently coerced")
	var multiline_bad := Policy.import_csv(Policy.export_csv([quoted]) + "short,row\n")
	check.call(multiline_bad.errors[0].row == 3, "multiline quoted record counts once in indexes")
	for text in ["", "wrong,header\n", header + "\"unterminated", header + "\"closed\"junk\n", header + "unquoted\"quote\n", "x".repeat(Policy.MAX_BYTES + 1), header + "x".repeat(Policy.MAX_FIELD + 1)]:
		var rejected := Policy.import_csv(text)
		check.call(rejected.rows.is_empty() and not rejected.errors.is_empty(), "reject malformed/bounded CSV / " + str(text.length()))
	var too_many: Array = []
	too_many.resize(Policy.MAX_ROWS + 1)
	too_many.fill(row)
	check.call(Policy.export_csv(too_many).is_empty(), "export row bound")
	check.call(not Policy.import_csv(header + good_line.repeat(Policy.MAX_ROWS + 1)).errors.is_empty(), "import row bound")
	check.call(not Policy.import_csv(header + ("a,".repeat(Policy.COLUMNS.size())) + "a\n").errors.is_empty(), "column count bound")

	var legacy_values := ["Actor_1", "Actor Label", "AudioLoomComponent_1", "0", "/Game/Audio/Bell.Bell", "Speakers", "4", "", "/legacy/bell", "/legacy/bell/play", "/legacy/bell/stop", "/legacy/bell/loop", "/legacy/bell/state"]
	var legacy_csv := _legacy(legacy_values)
	var unmapped := Policy.import_csv(legacy_csv)
	check.call(unmapped.rows.is_empty() and unmapped.errors[0].row == 2 and unmapped.errors[0].message.contains("source basename 'bell'") and unmapped.errors[0].message.contains("device label"), "legacy unmapped source and device report meaningful matching hints")
	var candidate := row.duplicate(true)
	candidate.device_label = "Speakers"
	var migrated := Policy.import_csv(legacy_csv, [candidate])
	check.call(migrated.rows.size() == 1 and migrated.rows[0].output_channel == 4 and migrated.rows[0].osc_base == "/legacy/bell" and migrated.rows[0].device_id == "opaque-id", "legacy resolves source file basename and label to opaque device ID")
	check.call(migrated.rows[0].random_replay_delay and not migrated.rows[0].play_on_start and candidate.output_channel == 2, "legacy preserves candidate-only fields without mutation")
	check.call(migrated.errors[0].severity == "warning" and migrated.errors[0].message.contains("ActorName") and migrated.errors[0].message.contains("OscPlay"), "legacy unmapped identity and derived fields explicitly reported")
	check.call(Policy.import_csv(legacy_csv, [candidate, candidate]).rows.is_empty(), "ambiguous legacy candidates fail closed")
	check.call(Policy.import_csv(legacy_csv, [row]).rows.is_empty(), "legacy device ID is not guessed as native device ID")
	var exact_device := legacy_values.duplicate()
	exact_device[5] = row.device_id
	check.call(Policy.import_csv(_legacy(exact_device), [row]).rows.size() == 1, "legacy exact already-authored native device ID is meaningful")
	var legacy_partial := legacy_csv.trim_suffix("\n").get_slice("\n", 1).get_slice(",/legacy/bell/loop", 0)
	check.call(Policy.import_csv(",".join(Policy.LEGACY_COLUMNS) + "\n" + legacy_partial + "\n", [candidate]).rows.is_empty(), "partial legacy row rejected entirely")
	var invalid_legacy := legacy_values.duplicate()
	invalid_legacy[6] = "-1"
	check.call(Policy.import_csv(_legacy(invalid_legacy), [candidate]).rows.is_empty(), "invalid legacy channel never partially applied")
	invalid_legacy = legacy_values.duplicate()
	invalid_legacy[7] = "bad osc"
	check.call(Policy.import_csv(_legacy(invalid_legacy), [candidate]).rows.is_empty(), "invalid legacy OSC never partially applied")
	invalid_legacy[7] = "/override"
	check.call(Policy.import_csv(_legacy(invalid_legacy), [candidate]).rows[0].osc_base == "/override", "legacy override takes precedence over derived base")
