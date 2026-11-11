class_name SnowControls
extends Node
## Bindings are [kind, index, direction]. Axis directions are individual actions.
## Fixed (never remapped): left stick X steers, left stick forward tucks, back
## brakes, Menu pauses. Everything in DEFAULTS can be remapped.
const DEFAULTS := {
	"jump": ["button", JOY_BUTTON_A, 1], "boost": ["button", JOY_BUTTON_B, 1],
	"brake": ["axis", JOY_AXIS_TRIGGER_LEFT, 1], "tuck": ["axis", JOY_AXIS_TRIGGER_RIGHT, 1],
	"grab": ["button", JOY_BUTTON_X, 1], "spin_left": ["button", JOY_BUTTON_LEFT_SHOULDER, 1],
	"spin_right": ["button", JOY_BUTTON_RIGHT_SHOULDER, 1],
	"look_left": ["axis", JOY_AXIS_RIGHT_X, -1], "look_right": ["axis", JOY_AXIS_RIGHT_X, 1],
	"look_up": ["axis", JOY_AXIS_RIGHT_Y, -1], "look_down": ["axis", JOY_AXIS_RIGHT_Y, 1],
	"restart": ["button", JOY_BUTTON_Y, 1], "recenter": ["button", JOY_BUTTON_RIGHT_STICK, 1],
	"camera_range": ["button", JOY_BUTTON_BACK, 1],
	"flip_forward": ["button", JOY_BUTTON_DPAD_UP, 1], "flip_back": ["button", JOY_BUTTON_DPAD_DOWN, 1]
}
const KEYS := {"jump": KEY_SPACE, "boost": KEY_SHIFT, "brake": KEY_S, "tuck": KEY_W,
	"grab": KEY_G, "spin_left": KEY_Q, "spin_right": KEY_E, "look_left": KEY_LEFT,
	"look_right": KEY_RIGHT, "look_up": KEY_UP, "look_down": KEY_DOWN, "restart": KEY_R, "camera_range": KEY_V,
	"recenter": KEY_C, "flip_forward": KEY_T, "flip_back": KEY_F}
const LABELS := {"jump": "Push off / ollie", "boost": "Nitro", "brake": "Brake / skid", "tuck": "Tuck",
	"grab": "Grab", "spin_left": "Spin left", "spin_right": "Spin right", "look_left": "Camera left",
	"look_right": "Camera right", "look_up": "Camera up", "look_down": "Camera down", "restart": "Restart (hold)", "camera_range": "Camera close / medium / far",
	"recenter": "Recenter camera", "flip_forward": "Front flip", "flip_back": "Back flip"}
var bindings: Dictionary = DEFAULTS.duplicate(true)
var settings_path := "user://snow_controls_v2.json"

func migrate_legacy(legacy_path := "user://snow_controls_v1.json") -> void:
	var old = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	if not old is Dictionary: return
	var completed := complete_bindings(old)
	if completed.is_empty(): return
	bindings = completed
	save_settings()

## Validates the actions a saved mapping contains and gives every action it lacks
## (added in a later version) a conflict-free binding, never disturbing the player's
## own remaps. Returns {} if the saved data is invalid.
func complete_bindings(saved: Dictionary) -> Dictionary:
	var used: Array = []
	var result: Dictionary = {}
	for action in DEFAULTS:
		if not saved.has(action): continue
		if not saved[action] is Array or not valid_binding(saved[action]): return {}
		var b: Array = [saved[action][0], int(saved[action][1]), int(saved[action][2])]
		if b in used: return {}
		used.append(b)
		result[action] = b
	# The View button became the camera-distance control. A mapping saved before
	# that still has the old DEFAULT restart on View: move that default aside.
	# (A restart the player deliberately put elsewhere is left alone.)
	var view: Array = ["button", JOY_BUTTON_BACK, 1]
	if not result.has("camera_range") and result.get("restart") == view:
		used.erase(view)
		result.erase("restart")
	var missing: Array = []
	for action in DEFAULTS:
		if not result.has(action): missing.append(action)
	missing.sort_custom(func(x, y): return x == "camera_range" and y != "camera_range")
	for action in missing:
		var b: Array = DEFAULTS[action].duplicate()
		if b in used:
			var candidates: Array = []
			for index in [3,7,8,11,12,13,14,0,1,2,4,9,10]:
				candidates.append(["button",index,1])
			for axis in [JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y,JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
				candidates.append(["axis",axis,1])
				if axis < JOY_AXIS_TRIGGER_LEFT: candidates.append(["axis",axis,-1])
			for candidate in candidates:
				if not candidate in used:
					b = candidate
					break
		if b in used: return {}
		used.append(b)
		result[action] = b
	return result

func _ready() -> void:
	configure_ui()
	load_settings()
	apply_bindings()

func configure_ui() -> void:
	# Built-in defaults are platform dependent. Explicit fixed pad UI events never remap.
	var ui_buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B, "ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN, "ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT}
	for action in ui_buttons:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		var button := InputEventJoypadButton.new()
		button.button_index = ui_buttons[action]
		InputMap.action_add_event(action, button)
	for pair in [["ui_left", JOY_AXIS_LEFT_X, -1], ["ui_right", JOY_AXIS_LEFT_X, 1], ["ui_up", JOY_AXIS_LEFT_Y, -1], ["ui_down", JOY_AXIS_LEFT_Y, 1]]:
		var axis := InputEventJoypadMotion.new()
		axis.axis = pair[1]
		axis.axis_value = pair[2]
		InputMap.action_add_event(pair[0], axis)

func valid_binding(binding: Array) -> bool:
	if binding.size() != 3 or not (binding[1] is int or binding[1] is float) or not (binding[2] is int or binding[2] is float):
		return false
	if not is_finite(float(binding[1])) or not is_finite(float(binding[2])) or float(binding[1]) != floorf(float(binding[1])):
		return false
	if absf(float(binding[2])) != 1.0: return false
	var index := int(binding[1])
	if binding[0] == "button":
		return index >= 0 and index <= JOY_BUTTON_DPAD_RIGHT and index != JOY_BUTTON_START and index != JOY_BUTTON_GUIDE and binding[2] == 1
	return binding[0] == "axis" and index >= JOY_AXIS_RIGHT_X and index <= JOY_AXIS_TRIGGER_RIGHT and int(binding[2]) in [-1, 1] and (index < JOY_AXIS_TRIGGER_LEFT or int(binding[2]) == 1)

func remap(action: String, binding: Array, persist := true) -> bool:
	if not bindings.has(action) or not valid_binding(binding):
		return false
	var old: Array = bindings[action].duplicate()
	for other in bindings:
		if other != action and bindings[other] == binding:
			bindings[other] = old
	bindings[action] = binding.duplicate()
	apply_bindings()
	if persist:
		save_settings()
	return true

func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		InputMap.action_erase_events(action)
		var binding: Array = bindings[action]
		if binding[0] == "button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(binding[1])
			InputMap.action_add_event(action, button)
		else:
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(binding[1])
			axis.axis_value = float(binding[2])
			InputMap.action_add_event(action, axis)
		var key := InputEventKey.new()
		key.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, key)
	for pair in [["steer_left", KEY_A, -1.0], ["steer_right", KEY_D, 1.0]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.17)
		InputMap.action_erase_events(pair[0])
		var axis := InputEventJoypadMotion.new()
		axis.axis = JOY_AXIS_LEFT_X
		axis.axis_value = pair[2]
		InputMap.action_add_event(pair[0], axis)
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], key)
	# Fixed like steering: push the left stick forward to tuck, pull back to brake.
	for pair in [["lean_forward", -1.0], ["lean_back", 1.0]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], SnowTuning.LEAN_DEADZONE)
		InputMap.action_erase_events(pair[0])
		var axis := InputEventJoypadMotion.new()
		axis.axis = JOY_AXIS_LEFT_Y
		axis.axis_value = pair[1]
		InputMap.action_add_event(pair[0], axis)

func describe(action: String) -> String:
	var b: Array = bindings[action]
	if b[0] == "axis":
		var negative: bool = b[2] < 0
		match int(b[1]):
			JOY_AXIS_RIGHT_X: return "RS left" if negative else "RS right"
			JOY_AXIS_RIGHT_Y: return "RS up" if negative else "RS down"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Axis"
	return {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 7: "LS click", 8: "RS click", 9: "LB", 10: "RB", 11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}.get(int(b[1]), "Button")

func save_settings() -> void:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(bindings))

func load_settings() -> void:
	bindings = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(settings_path):
		if settings_path == "user://snow_controls_v2.json" and FileAccess.file_exists("user://snow_controls_v1.json"):
			migrate_legacy()
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not parsed is Dictionary:
		return
	# Mappings saved by an older version lack newer actions: complete them without
	# touching the player's own choices, then save the upgraded mapping.
	var completed := complete_bindings(parsed)
	if completed.is_empty():
		return
	bindings = completed
	if parsed.size() != DEFAULTS.size():
		save_settings()
