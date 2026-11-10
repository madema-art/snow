extends SceneTree
## Integration tests run the real CharacterBody on real generated collision meshes.
var failures := 0
var game: Node3D
var rider: SnowRider
var run: SnowRun
var controls: SnowControls
var menu: SnowPauseMenu

func _initialize() -> void:
	go.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func press(action: String, count := 2) -> void:
	Input.action_press(action)
	await frames(count)
	Input.action_release(action)
	await frames(1)

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for child in game.get_children():
		if child is SnowRider: rider = child
		if child is SnowRun: run = child
		if child is SnowControls: controls = child
		if child is SnowPauseMenu: menu = child
	run.records_path = "user://test_records.json"
	run.records.clear()
	controls.settings_path = "user://test_controls.json"
	controls.bindings = SnowControls.DEFAULTS.duplicate(true)
	controls.apply_bindings()
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 3840 and ProjectSettings.get_setting("display/window/size/viewport_height") == 2160 and ProjectSettings.get_setting("display/window/size/mode") == 3 and ProjectSettings.get_setting("display/window/vsync/vsync_mode") == 1, "4K fullscreen / VSync configuration")
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "separate SFX and reserved Music buses")
	var drift_event := InputEventJoypadMotion.new()
	drift_event.axis = JOY_AXIS_RIGHT_X
	drift_event.axis_value = 0.1
	Input.parse_input_event(drift_event)
	check(Input.get_vector("look_left","look_right","look_up","look_down",0.18) == Vector2.ZERO, "right-stick deadzone rejects small analog drift")
	drift_event = drift_event.duplicate()
	drift_event.axis_value = 0
	Input.parse_input_event(drift_event)
	var start := rider.position
	await frames(30)
	check(run.elapsed == 0 and rider.position == start, "stationary opening / clock before push-off")
	await press("jump")
	await frames(120)
	check(run.state == "running" and run.elapsed > 1.9 and rider.position.z > 12, "push-off starts actual downhill physics and clock")
	await press("jump")
	await frames(8)
	check(not rider.is_on_floor(), "ollie separates from collision surface")
	var yaw_before := rider.heading
	var horizontal_before := Vector2(rider.velocity.x, rider.velocity.z)
	var camera: SnowCamera = game.get_node("ChaseCamera")
	var orbit_before := camera.orbit
	Input.action_press("look_right")
	Input.action_press("look_up")
	await frames(8)
	Input.action_release("look_right")
	Input.action_release("look_up")
	check(rider.heading == yaw_before and rider.spin == 0 and rider.flip == 0 and absf(horizontal_before.angle_to(Vector2(rider.velocity.x,rider.velocity.z))) < 0.0005, "airborne right stick never steers, redirects or performs tricks")
	check(absf(camera.orbit - orbit_before) > 0.1, "free camera responds in actual airborne physics")
	var air_position := rider.position
	var time_before := run.elapsed
	menu.show_menu()
	for i in 20:
		await process_frame
	check(run.elapsed == time_before and rider.position == air_position, "midair pause freezes timer and simulation")
	menu.hide_menu()
	await frames(100)
	check(rider.nitro > 0.0 and rider.recovery == 0.0, "clean jump landing stores nitro")
	var stored := rider.nitro
	await press("boost", 6)
	check(rider.nitro < stored, "variable burst consumes stored nitro")
	rider.nitro = 0
	rider.air_time = 1
	rider.landed(6)
	var simple_reward := rider.nitro
	rider.nitro = 0
	rider.air_time = 1
	rider.spin = TAU
	rider.grabbed = 0.5
	rider.landed(6)
	check(rider.nitro > simple_reward, "landed spin and grab reward more than a simple jump")
	rider.spin = PI * 0.5
	rider.landed(8)
	check(rider.recovery > 0 and rider.nitro == 0 and rider.velocity == Vector3.ZERO, "incomplete sideways landing catches edge and clears nitro")
	rider.nitro = 0.7
	rider.velocity = Vector3(0, 0, 30)
	rider.crash(16)
	check(rider.nitro == 0 and rider.velocity == Vector3.ZERO and rider.speed == 0, "crash clears ALL charge and momentum immediately")
	check(rider.visual.board_material.emission_energy_multiplier == 0, "crash immediately darkens board")
	time_before = run.elapsed
	await frames(30)
	check(run.elapsed > time_before and rider.velocity == Vector3.ZERO, "recovery costs time without sliding momentum")
	check(controls.remap("boost", ["button", JOY_BUTTON_A, 1]), "remap accepts controller binding")
	check(controls.bindings.jump == ["button", JOY_BUTTON_B, 1], "conflict swaps previous binding")
	check(not controls.remap("boost", ["button", JOY_BUTTON_START, 1]), "Menu remains reserved")
	check(not controls.remap("boost", ["axis", JOY_AXIS_LEFT_X, 1]), "left stick remains reserved")
	controls.save_settings()
	controls.bindings = {}
	controls.load_settings()
	check(controls.bindings.boost == ["button", JOY_BUTTON_A, 1], "remap persists through disk reload")
	check(not controls.valid_binding(["button", 0, {}]) and not controls.valid_binding(["axis", 2.5, 1]), "malformed binding values rejected safely")
	var legacy: Dictionary = SnowControls.DEFAULTS.duplicate(true)
	for action in ["recenter","flip_forward","flip_back"]: legacy.erase(action)
	legacy.boost = ["button",JOY_BUTTON_RIGHT_STICK,1]
	var legacy_file := FileAccess.open("user://test_legacy.json",FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	controls.migrate_legacy("user://test_legacy.json")
	check(controls.bindings.boost == ["button",JOY_BUTTON_RIGHT_STICK,1] and controls.bindings.recenter != controls.bindings.boost and controls.bindings.size() == SnowControls.DEFAULTS.size(), "legacy remaps survive adding camera and flip actions without conflicts")
	var available_buttons := [0,1,2,3,4,7,8,9,10,11,12,13,14]
	var legacy_index := 0
	for action in legacy:
		legacy[action] = ["button",available_buttons[legacy_index],1]
		legacy_index += 1
	legacy_file = FileAccess.open("user://test_legacy.json",FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	controls.migrate_legacy("user://test_legacy.json")
	var unique: Array = []
	var legacy_kept := true
	for action in controls.bindings:
		if not controls.bindings[action] in unique: unique.append(controls.bindings[action])
		if legacy.has(action) and controls.bindings[action] != legacy[action]: legacy_kept = false
	check(legacy_kept and unique.size() == SnowControls.DEFAULTS.size(),"migration preserves a nearly full button map using free axes for new actions")
	controls.bindings = SnowControls.DEFAULTS.duplicate(true)
	controls.apply_bindings()
	# Real fixed Menu events still work after arbitrary gameplay remaps.
	var menu_event := InputEventJoypadButton.new()
	menu_event.button_index = JOY_BUTTON_START
	menu_event.pressed = true
	menu._input(menu_event)
	check(paused and menu.panel.visible, "fixed controller Menu opens pause after remap")
	menu.capture("boost")
	var b_event := InputEventJoypadButton.new()
	b_event.button_index = JOY_BUTTON_Y
	b_event.pressed = true
	menu._input(b_event)
	check(controls.bindings.boost == ["button", JOY_BUTTON_Y, 1] and menu.capturing == "", "pause capture consumes controller button and saves remap")
	var fixed_accept := false
	for event in InputMap.action_get_events("ui_accept"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
			fixed_accept = true
	check(fixed_accept, "pause accept remains A independently of gameplay remaps")
	menu.resume.grab_focus()
	var right_event := InputEventJoypadButton.new()
	right_event.button_index = JOY_BUTTON_DPAD_RIGHT
	right_event.pressed = true
	Input.parse_input_event(right_event)
	await process_frame
	check(root.gui_get_focus_owner() == menu.mapping_buttons.jump, "synthetic fixed D-pad reaches controller mappings")
	right_event.pressed = false
	Input.parse_input_event(right_event)
	menu._input(menu_event)
	check(not paused, "fixed Menu resumes from pause")
	controls.bindings = SnowControls.DEFAULTS.duplicate(true)
	controls.apply_bindings()
	run.records.clear()
	for i in range(12, 0, -1):
		run.restart()
		run.push_off()
		run.elapsed = 60 + i
		run.finish()
	# Finish signal opens the menu deferred; flush before restarting.
	await process_frame
	run.load_records()
	check(run.records.size() == 10 and run.records[0] == 61 and run.records[9] == 70, "ten fastest finishes persist sorted")
	check(SnowRun.clock_text(61.239) == "01:01.24", "hundredth-second formatting")
	menu.restart()
	check(run.elapsed == 0 and rider.nitro == 0 and rider.position == start, "quick restart resets clock, charge and summit")
	# Compare real physics on the same short stretch, preserving all collisions.
	await press("jump")
	await frames(180)
	var normal_speed := rider.speed
	Input.action_press("brake")
	await frames(60)
	Input.action_release("brake")
	check(rider.speed < normal_speed * 0.7, "braking dissipates downhill momentum")
	await frames(120)
	var x_before := rider.position.x
	await press("steer_right", 35)
	check(rider.position.x < x_before - 0.4 and rider.heading < -0.2, "right steering carves toward camera screen-right")
	# An actual high-speed head-on collision against a controlled tree collider.
	rider.crash(2)
	var minor_recovery := rider.recovery_length
	rider.nitro = 0.7
	rider.velocity = Vector3(20,0,20)
	rider.crash(40)
	check(rider.recovery_length > minor_recovery + 3 and rider.nitro == 0 and rider.velocity == Vector3.ZERO, "major falls have longer recovery and still clear all charge/momentum")
	menu.restart()
	run.push_off()
	var tree := StaticBody3D.new()
	tree.collision_layer = 2
	tree.set_meta("hazard", "tree")
	tree.position = Vector3(0, SnowMountain.height_at(0, 70) + 3, 70)
	var shape := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.6
	trunk.height = 6
	shape.shape = trunk
	tree.add_child(shape)
	game.add_child(tree)
	rider.position = Vector3(0, SnowMountain.height_at(0, 65) + 0.72, 65)
	rider.velocity = Vector3(0, -6, 40)
	rider.nitro = 0.8
	await frames(20)
	print("TREE CHECK state=", run.state, " recovery=", rider.recovery, " p=", rider.position, " v=", rider.velocity)
	check(run.state == "ended" and rider.velocity == Vector3.ZERO and rider.nitro == 0, "high-speed direct tree collision ends run without retaining charge or speed")
	menu.restart()
	run.push_off()
	rider.position = Vector3(0, SnowMountain.height_at(0, 65) + 0.72, 65)
	rider.velocity = Vector3(0, -3, 15)
	rider.nitro = 0.5
	await frames(35)
	check(run.state == "running" and rider.recovery > 0 and rider.nitro == 0 and rider.velocity == Vector3.ZERO, "moderate actual tree collision enters nonfatal recovery")
	await frames(300)
	check(run.state == "running" and rider.recovery == 0 and rider.position.z > 65, "nonfatal get-up resumes without false fatal drop")
	tree.queue_free()
	menu.restart()
	check(rider.steer == 0 and rider.heading == 0 and rider.spin == 0 and rider.flip == 0, "restart clears steering and all trick rotations")
	run.push_off()
	rider.nitro = 0.5
	rider.position = Vector3(0, SnowMountain.height_at(0, 100) + 100, 100)
	rider.launch_height = rider.position.y
	await frames(180)
	check(run.state == "ended" and rider.nitro == 0, "actual 100 m physical fall ends run")
	menu.restart()
	# Full mountain navigation and finish timing live in mountain_test.gd.
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	for path in ["user://test_records.json", "user://test_controls.json", "user://test_legacy.json"]:
		DirAccess.remove_absolute(path)
	print("TESTS COMPLETE: ", failures, " failures")
	quit(0 if failures == 0 else 1)
