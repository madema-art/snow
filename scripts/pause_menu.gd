class_name SnowPauseMenu
extends CanvasLayer
## The ONLY interface in SNOW. Hidden while riding (no HUD of any kind). Shown on
## Menu, on controller disconnect / window focus loss mid-run, and after a finish
## or fatal crash (after a short beat so the moment can be seen). Shows elapsed
## hundredths, the ten fastest completed descents, remapping and
## resume / restart / quit. Fixed controller navigation: D-pad/LS move, A accept,
## B back, Menu toggles or cancels capture.
const ACCENT := Color("ff7a2a")
const INK := Color("eef3f8")
const MUTED := Color("8ea3b8")
var run: SnowRun
var controls: SnowControls
var rider: SnowRider
var camera: SnowCamera
var panel: Control
var title: Label
var status: Label
var clock: Label
var records_label: RichTextLabel
var mapping_hint: Label
var resume: Button
var mapping_buttons: Dictionary = {}
var capturing := ""
var neutral_axes: Dictionary = {}
var pending_show := -1.0
var last_record_rank := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	build()
	run.ended.connect(_on_run_ended)
	Input.joy_connection_changed.connect(_on_joy_changed)

func _on_run_ended() -> void:
	last_record_rank = run.last_rank
	pending_show = 1.6 if run.state == "finished" else 2.6

func _on_joy_changed(_device: int, connected: bool) -> void:
	# Losing the controller mid-descent pauses instead of letting the rider crash.
	if not connected and run.state == "running" and not panel.visible:
		show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and run != null and run.state == "running" and panel != null and not panel.visible:
		show_menu()

func _process(delta: float) -> void:
	if pending_show >= 0.0:
		pending_show -= delta
		if pending_show < 0.0:
			show_menu()
	if panel.visible and not get_tree().paused:
		get_tree().paused = true

func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 40
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.04)
	normal.border_color = Color(1, 1, 1, 0.12)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 34
	normal.content_margin_right = 34
	var focus := normal.duplicate()
	focus.bg_color = Color(ACCENT, 0.9)
	focus.border_color = Color("ffd2a8")
	focus.set_border_width_all(4)
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.12)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(1, 1, 1, 0.015)
	disabled.border_color = Color(1, 1, 1, 0.05)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", focus)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("hover_pressed", "Button", focus)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", Color("1a0d05"))
	theme.set_color("font_pressed_color", "Button", Color("1a0d05"))
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.25))
	theme.set_color("font_color", "Label", INK)
	return theme

func label(text: String, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 96
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 40)
	b.pressed.connect(action)
	return b

func build() -> void:
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = make_theme()
	add_child(panel)
	# Frosted backdrop: the frozen mountain stays visible, softened and darkened.
	var frost := ColorRect.new()
	frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frost_material := ShaderMaterial.new()
	frost_material.shader = preload("res://shaders/pause_frost.gdshader")
	frost.material = frost_material
	panel.add_child(frost)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 300)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 190)
	panel.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 220)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 1180
	left.add_theme_constant_override("separation", 26)
	columns.add_child(left)
	var mark := label("S N O W", 120)
	mark.add_theme_constant_override("outline_size", 0)
	left.add_child(mark)
	title = label("PAUSED", 46, ACCENT)
	left.add_child(title)
	status = label("", 34, MUTED)
	left.add_child(status)
	clock = label("00:00.00", 150)
	left.add_child(clock)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.15)
	rule.custom_minimum_size = Vector2(1180, 3)
	left.add_child(rule)
	left.add_child(label("FASTEST COMPLETED DESCENTS", 34, MUTED))
	records_label = RichTextLabel.new()
	records_label.bbcode_enabled = true
	records_label.fit_content = true
	records_label.scroll_active = false
	records_label.custom_minimum_size = Vector2(1180, 560)
	records_label.add_theme_font_size_override("normal_font_size", 42)
	records_label.add_theme_font_size_override("bold_font_size", 42)
	records_label.add_theme_constant_override("line_separation", 6)
	left.add_child(records_label)
	resume = button("Resume", hide_menu)
	left.add_child(resume)
	left.add_child(button("Restart from summit", restart))
	left.add_child(button("Quit", func(): get_tree().quit()))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 1450
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(label("CONTROLS", 46, ACCENT))
	right.add_child(label("Left stick  steer and carve   ·   Menu  pause / resume   (fixed)", 32, MUTED))
	for action in SnowControls.DEFAULTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 30)
		var name_label := label(SnowControls.LABELS[action], 36)
		name_label.custom_minimum_size.x = 760
		row.add_child(name_label)
		var b := button("", capture.bind(action))
		b.custom_minimum_size = Vector2(620, 78)
		b.add_theme_font_size_override("font_size", 34)
		row.add_child(b)
		right.add_child(row)
		mapping_buttons[action] = b
	mapping_hint = label("", 30, MUTED)
	right.add_child(mapping_hint)
	# Explicit cross-column neighbours keep controller navigation predictable.
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

func default_hint() -> String:
	return "Select a control, then press the new button or move a stick/trigger.\nConflicts swap the two controls. Menu cancels.  D-pad + A navigate · B returns."

func refresh() -> void:
	clock.text = SnowRun.clock_text(run.elapsed)
	title.text = {"finished": "DESCENT COMPLETE", "ended": "RUN ENDED", "ready": "AT THE SUMMIT"}.get(run.state, "PAUSED")
	match run.state:
		"finished":
			status.text = "New fastest descent!" if last_record_rank == 0 else ("Entered the top ten at #%d" % (last_record_rank + 1) if last_record_rank >= 0 else "Not fast enough for the top ten")
		"ended":
			status.text = "A fatal fall. Fatal runs are never recorded."
		"ready":
			status.text = "Push off to start the clock."
		_:
			status.text = "The clock is stopped while paused."
	resume.disabled = run.state in ["finished", "ended"]
	var text := ""
	if run.records.is_empty():
		text = "[color=#8ea3b8]No completed descents yet.[/color]"
	for i in run.records.size():
		var line := "%2d      %s" % [i + 1, SnowRun.clock_text(run.records[i])]
		if i == last_record_rank and run.state == "finished":
			line = "[color=#ff7a2a][b]%s   ◀[/b][/color]" % line
		text += line + "\n"
	records_label.text = text
	for action in mapping_buttons:
		mapping_buttons[action].text = controls.describe(action)
	if capturing == "":
		mapping_hint.text = default_hint()

func show_menu() -> void:
	pending_show = -1.0
	get_tree().paused = true
	panel.show()
	Input.stop_joy_vibration(0)
	for pad in Input.get_connected_joypads():
		Input.stop_joy_vibration(pad)
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
	pending_show = -1.0
	last_record_rank = -1
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
	mapping_buttons[action].text = "Press a button…"
	mapping_hint.text = "Waiting for %s: press a controller button or move the right stick / a trigger.\nLeft stick and Menu are reserved. Menu cancels." % SnowControls.LABELS[action]

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
