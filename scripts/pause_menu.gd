class_name SnowPauseMenu
extends CanvasLayer
var run: SnowRun
var controls: SnowControls
var rider: SnowRider
var camera: SnowCamera
var panel: Control
var title: Label
var clock: Label
var records_label: Label
var mapping_hint: Label
var resume: Button
var mapping_buttons: Dictionary = {}
var capturing := ""
var neutral_axes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	build()
	run.ended.connect(func(): show_menu.call_deferred())

func label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 85
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(action)
	return b

func build() -> void:
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.055, 0.085, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 180)
	center.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 730
	left.add_theme_constant_override("separation", 24)
	columns.add_child(left)
	title = label("SNOW / PAUSED", 64)
	left.add_child(title)
	clock = label("00:00.00", 90)
	left.add_child(clock)
	left.add_child(label("FASTEST COMPLETED RUNS", 30))
	records_label = label("", 35)
	left.add_child(records_label)
	resume = button("Resume", hide_menu)
	left.add_child(resume)
	left.add_child(button("Restart from summit", restart))
	left.add_child(button("Quit", func(): get_tree().quit()))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 1130
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	right.add_child(label("CONTROLLER MAPPING", 46))
	right.add_child(label("Left stick: steering     Menu: pause / resume", 30))
	for action in SnowControls.DEFAULTS:
		var row := HBoxContainer.new()
		var name_label := label(SnowControls.LABELS[action], 32)
		name_label.custom_minimum_size.x = 590
		row.add_child(name_label)
		var b := button("", capture.bind(action))
		b.custom_minimum_size = Vector2(480, 70)
		row.add_child(b)
		right.add_child(row)
		mapping_buttons[action] = b
	mapping_hint = label("Select a binding, then press a button or axis.\nConflicts swap. Menu cancels capture.\nD-pad + A navigate; B returns. View restarts by default.", 28)
	right.add_child(mapping_hint)
	# Explicit cross-column neighbors keep controller navigation predictable.
	var actions := mapping_buttons.keys()
	var left_buttons: Array[Button] = []
	for child in left.get_children():
		if child is Button:
			left_buttons.append(child)
	for b in left_buttons:
		b.focus_neighbor_right = b.get_path_to(mapping_buttons[actions[0]])
	for i in actions.size():
		var b: Button = mapping_buttons[actions[i]]
		b.focus_neighbor_left = b.get_path_to(resume)
		b.focus_neighbor_top = b.get_path_to(mapping_buttons[actions[(i - 1 + actions.size()) % actions.size()]])
		b.focus_neighbor_bottom = b.get_path_to(mapping_buttons[actions[(i + 1) % actions.size()]])
	panel.hide()
	refresh()

func refresh() -> void:
	clock.text = SnowRun.clock_text(run.elapsed)
	title.text = {"finished": "SNOW / FINISHED", "ended": "SNOW / RUN ENDED"}.get(run.state, "SNOW / PAUSED")
	resume.disabled = run.state in ["finished", "ended"]
	records_label.text = "No completed runs yet.\n" if run.records.is_empty() else ""
	for i in run.records.size():
		records_label.text += "%02d     %s\n" % [i + 1, SnowRun.clock_text(run.records[i])]
	for action in mapping_buttons:
		mapping_buttons[action].text = controls.describe(action)

func show_menu() -> void:
	get_tree().paused = true
	panel.show()
	refresh()
	if resume.disabled:
		resume.find_next_valid_focus().grab_focus()
	else:
		resume.grab_focus()

func hide_menu() -> void:
	if run.state in ["finished", "ended"]:
		return
	capturing = ""
	panel.hide()
	get_tree().paused = false

func restart() -> void:
	capturing = ""
	run.restart()
	rider.reset()
	camera.reset()
	panel.hide()
	get_tree().paused = false

func capture(action: String) -> void:
	capturing = action
	neutral_axes.clear()
	for device in Input.get_connected_joypads():
		for axis in range(JOY_AXIS_RIGHT_X, JOY_AXIS_TRIGGER_RIGHT + 1):
			neutral_axes[Vector2i(device, axis)] = absf(Input.get_joy_axis(device, axis)) < 0.3
	mapping_buttons[action].text = "Listening…"
	mapping_hint.text = "Press a controller button or move an axis.\nLeft-stick axes and Menu are reserved.\nMenu cancels capture. Conflicting bindings swap."

func _input(event: InputEvent) -> void:
	var menu: bool = (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START and event.pressed) or (event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed and not event.echo)
	if menu:
		if capturing != "":
			capturing = ""
			refresh()
		elif panel.visible:
			hide_menu()
		else:
			show_menu()
		get_viewport().set_input_as_handled()
		return
	if not panel.visible:
		return
	if capturing != "":
		var binding: Array = []
		if event is InputEventJoypadButton and event.pressed:
			binding = ["button", event.button_index, 1]
		elif event is InputEventJoypadMotion and event.axis >= JOY_AXIS_RIGHT_X:
			var key := Vector2i(event.device, event.axis)
			if absf(event.axis_value) < 0.3:
				neutral_axes[key] = true
			if absf(event.axis_value) > 0.7 and neutral_axes.get(key, true):
				binding = ["axis", event.axis, 1 if event.axis_value > 0 else -1]
		if not binding.is_empty() and controls.remap(capturing, binding):
			capturing = ""
			refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		hide_menu()
		get_viewport().set_input_as_handled()
