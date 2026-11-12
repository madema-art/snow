extends SceneTree
## Pass-3 systems on the real scene: trick economy and anti-farming, landing
## quality, nitro empty/partial use, crash tumble isolation, travel-relative free
## camera, results timing, disconnect auto-pause and record rank. Some checks set
## state directly (explicit FIXTURES); none of them is a navigation proof.
##   godot --headless --path . --fixed-fps 60 --script res://tests/feel_test.gd
var failures := 0
var game: Node3D
var rider: SnowRider
var run: SnowRun
var camera: SnowCamera
var menu: SnowPauseMenu
var controls: SnowControls
var events: Array[String] = []

func _initialize() -> void: go.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	camera = game.get_node("ChaseCamera")
	for child in game.get_children():
		if child is SnowRun: run = child
		if child is SnowPauseMenu: menu = child
		if child is SnowControls: controls = child
	controls.settings_path = "user://test_feel_controls.json"
	controls.bindings = SnowControls.DEFAULTS.duplicate(true)
	controls.apply_bindings()
	run.records_path = "user://test_feel_records.json"
	run.records.clear()
	rider.sound_event.connect(func(kind: String, _s: float): events.append(kind))
	await frames(2)

	# --- Trick economy -------------------------------------------------------
	var flat := rider.trick_reward(0.45, 1.0, 0, 0, 0.0, 1.0)
	check(flat == 0.0, "a tiny flat ollie pays no nitro")
	var plain := rider.trick_reward(1.2, 3.0, 0, 0, 0.0, 1.0)
	rider.fatigue.clear()
	var spin360 := rider.trick_reward(1.2, 3.0, 2, 0, 0.0, 1.0)
	rider.fatigue.clear()
	var spin720 := rider.trick_reward(1.8, 3.0, 4, 0, 0.0, 1.0)
	rider.fatigue.clear()
	var flip := rider.trick_reward(1.8, 3.0, 0, 1, 0.0, 1.0)
	rider.fatigue.clear()
	var combo := rider.trick_reward(1.8, 3.0, 2, 1, 0.8, 1.0)
	rider.fatigue.clear()
	check(plain > 0.0 and spin360 > plain and spin720 > spin360 and flip > spin360, "harder tricks earn more nitro (plain < 360 < 720, flip > 360)")
	check(combo > flip + spin360 * 0.9, "combining spin, flip and grab multiplies the reward")
	var big_drop := rider.trick_reward(1.2, 20.0, 0, 0, 0.0, 1.0)
	rider.fatigue.clear()
	check(big_drop > plain, "a bigger, more dangerous drop pays more than a small hop")
	var sketchy := rider.trick_reward(1.2, 3.0, 2, 0, 0.0, 0.3)
	rider.fatigue.clear()
	check(sketchy < spin360 * 0.8, "landing quality scales the reward")
	var first := rider.trick_reward(1.2, 3.0, 2, 0, 0.0, 1.0)
	var second := rider.trick_reward(1.2, 3.0, 2, 0, 0.0, 1.0)
	var third := rider.trick_reward(1.2, 3.0, 2, 0, 0.0, 1.0)
	var different := rider.trick_reward(1.2, 3.0, 0, 0, 0.6, 1.0)
	check(second < first * 0.6 and third < second and different > third, "repeating one trick fatigues it; a different trick does not")
	rider.fatigue.clear()
	var spam := 0.0
	for i in 20:
		spam += rider.trick_reward(1.0, 2.0, 1 + i % 2, 0, 0.5 * (i % 3), 1.0)
	check(spam < 1.2, "twenty rapid back-to-back tricks cannot fill the board more than about once (%.2f)" % spam)
	rider.fatigue.clear()
	rider.fatigue["s2 f0 g0"] = 1.0
	await press_and_run(0)
	check(rider.fatigue.get("s2 f0 g0", 0.0) < 1.0, "trick fatigue recovers over riding time")
	check(spin720 <= SnowTuning.REWARD_CAP and combo <= SnowTuning.REWARD_CAP, "single landing reward is capped")

	# --- Landing evaluation on the real body --------------------------------
	menu.restart()
	run.push_off()
	rider.velocity = Vector3(0, -2, 20)
	rider.heading = 0.0
	rider.air_time = 1.2
	rider.spin = PI * 1.02
	rider.launch_height = rider.position.y + 3.0
	rider.nitro = 0.0
	var switch_before := rider.switch_stance
	rider.landed(6.0)
	check(rider.recovery == 0.0 and rider.nitro > 0.0 and rider.switch_stance != switch_before, "clean 180 rides away switch and earns charge")
	rider.velocity = Vector3(16, -2, 10) # board pointing downhill, travelling 58 degrees across it
	rider.heading = 0.0
	rider.air_time = 1.0
	rider.landed(6.0)
	check(rider.recovery > 0.0 and rider.nitro == 0.0, "landing badly misaligned with travel catches an edge and wipes nitro")

	# --- Nitro: partial use, depletion and empty sputter --------------------
	menu.restart()
	await press_and_run(40)
	rider.nitro = 0.5 # FIXTURE
	events.clear()
	Input.action_press("boost")
	await frames(30)
	Input.action_release("boost")
	await frames(2)
	check(rider.nitro > 0.3 and rider.nitro < 0.5 and "boost" in events and "boost_release" in events, "partial boost spends some charge and keeps the rest")
	Input.action_press("boost")
	await frames(150)
	Input.action_release("boost")
	await frames(2)
	check(rider.nitro == 0.0 and "deplete" in events, "holding boost depletes the board with its own sound")
	events.clear()
	Input.action_press("boost")
	await frames(3)
	Input.action_release("boost")
	await frames(2)
	check("empty" in events and not rider.boosting, "pressing boost with an empty board sputters and gives no thrust")

	# --- Nitro never adds grip ----------------------------------------------
	var lateral_loss := []
	for boost in [false, true]:
		menu.restart()
		await press_and_run(90)
		rider.heading = 0.0
		rider.velocity = Vector3(6.0, rider.velocity.y, 22.0) # sideways slide FIXTURE
		rider.nitro = 1.0 if boost else 0.0
		if boost: Input.action_press("boost")
		await frames(1)
		Input.action_release("boost")
		lateral_loss.append(absf(rider.velocity.x))
	check(absf(lateral_loss[0] - lateral_loss[1]) < 0.05, "boost adds forward thrust only, never extra edge grip")

	# --- Crash: tumble is presentation only ---------------------------------
	menu.restart()
	await press_and_run(120)
	var body_at := rider.position
	rider.nitro = 0.8
	var speed_before := rider.speed
	rider.crash(18.0)
	check(rider.nitro == 0.0 and rider.velocity == Vector3.ZERO and rider.speed == 0.0, "crash wipes nitro and momentum instantly")
	check(rider.visual.board_material.emission_energy_multiplier == 0.0, "board goes dark the instant of a fall")
	var moved := 0.0
	var still := true
	for i in 40:
		await frames(1)
		moved = maxf(moved, rider.tumble_pos.distance_to(body_at))
		if rider.position.distance_to(body_at) > 0.01 or rider.velocity != Vector3.ZERO or rider.speed != 0.0 or rider.nitro != 0.0:
			still = false
	check(speed_before > 8.0 and moved > 0.5, "the fallen body is thrown and tumbles away from the crash point")
	check(still, "during the tumble the physics body has no speed, travel or nitro")
	var t_before := run.elapsed
	while rider.recovery > 0.0:
		await frames(1)
	check(run.elapsed > t_before + 1.0 and rider.position.distance_to(rider.tumble_pos) < 15.0, "get-up costs clock time and happens where the tumble came to rest")
	check(not rider.visual.top_level and rider.recovery == 0.0, "rider is back on the board after recovery")
	check(rider.crash_tier() == 1, "severity 18 is a moderate crash tier")

	# --- Camera: free look is relative to travel and never steers ------------
	menu.restart()
	await press_and_run(150)
	camera.idle = 0.0
	for i in 40:
		camera.orbit_input(1.0 / 60.0, Vector2(1, 0), false)
	for i in 30:
		camera.orbit_input(1.0 / 60.0, Vector2.ZERO, false)
	var held := camera.look_yaw
	var heading_before := rider.heading
	Input.action_press("steer_left", 0.8)
	await frames(60)
	Input.action_release("steer_left")
	check(absf(camera.look_yaw - held) < 0.001 and absf(rider.heading - heading_before) > 0.1, "manual look offset holds while the rider carves (no auto-follow fight)")
	check(absf(wrapf(camera.orbit - (camera.follow_yaw + camera.look_yaw), -PI, PI)) < 0.001, "camera yaw = travel direction + player look offset")
	for i in 300:
		camera.orbit_input(1.0 / 60.0, Vector2.ZERO, false)
	print("settle look_yaw=", camera.look_yaw, " idle=", camera.idle, " state=", run.state, " rec=", rider.recovery)
	check(absf(wrapf(camera.look_yaw, -PI, PI)) < 0.05, "after the inactivity delay the view settles back behind the rider")
	camera.look_yaw = PI
	camera.idle = 0.0
	var before_look := rider.velocity
	await frames(1)
	check(rider.velocity.angle_to(before_look) < 0.2, "looking straight back while riding does not redirect the rider")

	# --- Results: fatal beat, disconnect pause, record rank -------------------
	menu.restart()
	run.push_off()
	rider.position.y += 120.0 # FIXTURE: a real 120 m free fall onto real terrain
	rider.launch_height = rider.position.y
	await frames(200)
	check(run.state == "ended" and not paused, "fatal fall ends the run but the moment plays out before results")
	await frames(200)
	check(paused and menu.panel.visible and menu.resume.disabled, "results appear after the beat; Resume is unavailable")
	menu.restart()
	await press_and_run(10)
	menu._on_joy_changed(0, false)
	check(paused and menu.panel.visible, "controller disconnect mid-run pauses immediately")
	menu.hide_menu()
	check(not paused, "resume after reconnect continues the run")
	run.records = [100.0, 120.0]
	run.state = "running"
	run.elapsed = 110.0
	run.finish()
	check(run.last_rank == 1 and run.records == [100.0, 110.0, 120.0], "finish reports its top-ten rank")
	check(controls.describe("look_left") == "RS left" and controls.describe("brake") == "LT", "readable binding names in the menu")

	# --- Pass 4: standing push, records version, playtest mix rules ----------
	menu.restart()
	await press_and_run(40)
	Input.action_press("brake")
	await frames(240)
	Input.action_release("brake")
	rider.velocity = Vector3.ZERO # FIXTURE: a dead stop on the slope
	await frames(1)
	var stop_speed := rider.speed
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(4)
	check(stop_speed < 1.0 and rider.speed > 2.0 and rider.air_time < 0.3, "A pushes off again from a near standstill (no one stays stuck)")
	var fresh_run := SnowRun.new()
	check(fresh_run.records_path.ends_with("snow_records_massif_v3.json") and SnowMountain.COURSE_ID == "massif_v3", "reshaped mountain keeps its own records file")
	fresh_run.free()
	check(is_equal_approx(SnowMusic.track_gain_db("x/Heavier Half-time Beat Cover.mp3"), 4.0) and SnowMusic.track_gain_db("x/Alpine Shift (Take 2) (Remix).mp3") < -1.5 and SnowMusic.track_gain_db("x/Some New Song.mp3") == 0.0, "songs are level-matched; unknown songs play at the default level")
	var loudest_bed := 0.0
	for loop_name in SnowAudio.LOOPS:
		if loop_name != "nitro_loop": loudest_bed = maxf(loudest_bed, SnowAudio.LOOPS[loop_name][1])
	check(not SnowAudio.LOOPS.has("wind_whistle") and loudest_bed <= 0.5 and SnowMusic.MUSIC_BUS_DB >= -4.0 and SnowMusic.DUCK_DB >= -3.0, "playtest mix rules hold: no whistle layer, quiet beds, music leads")
	# --- Pass 5: momentum tumbles ---------------------------------------------
	var slow_fall := await tumble_fixture(10.0, 8.0)
	var fast_fall := await tumble_fixture(30.0, 20.0)
	print("TUMBLE slow=", slow_fall, " fast=", fast_fall)
	check(fast_fall.travel > slow_fall.travel * 1.8 and fast_fall.travel > 12.0, "a faster crash tumbles much farther (%.1f m vs %.1f m): momentum physics" % [fast_fall.travel, slow_fall.travel])
	check(fast_fall.frozen and slow_fall.frozen, "riding speed, velocity and nitro stay at zero for the whole tumble")
	check(fast_fall.travel / fast_fall.time < 30.0 * 0.6 and fast_fall.time > 1.5, "the tumble is far slower than riding and costs seconds (%.1f s)" % fast_fall.time)
	check(fast_fall.impacts >= 2 and fast_fall.impacts > slow_fall.impacts - 1, "the body bounces and rolls: %d separate impacts" % fast_fall.impacts)
	check(fast_fall.groan and fast_fall.stood, "it comes to rest with a groan and the rider stands up there")
	var audio: SnowAudio
	for child in game.get_children():
		if child is SnowAudio: audio = child
	menu.restart()
	await press_and_run(60)
	rider.crash(20.0)
	check(audio.voice.playing and audio.voice.stream == audio.streams["grunt_hit_1"], "the first hit knocks a grunt out of the rider")
	events.clear()
	audio.voice_cooldown = 0.0
	rider.sound_event.emit("tumble", 0.6)
	check(audio.voice.playing and audio.voice.stream != audio.streams["grunt_hit_1"], "rolling impacts add their own grunts")
	# A tumble that goes over a real drop is fatal (FIXTURE: placed above the gorge lip).
	menu.restart()
	run.push_off()
	var lip_z := 1452.0 * SnowMountain.DISTANCE_SCALE
	rider.position = Vector3(0, SnowMountain.height_at(0, lip_z) + 0.72, lip_z)
	rider.velocity = Vector3(0, -8, 26)
	await frames(2)
	rider.crash(10.0)
	check(run.state == "running", "a fall near the gorge starts as an ordinary fall")
	await frames(420)
	check(run.state == "ended" and rider.last_crash_reason == "tumbled off a drop", "tumbling over the gorge lip is a fatal fall, by physics not by zone")

	# --- Pass 5: deep lean, plume and over-lean --------------------------------
	menu.restart()
	await press_and_run(60)
	rider.velocity = Vector3(0, -9, 28) # FIXTURE: at speed on the summit face
	await frames(2)
	Input.action_press("steer_right", 0.75)
	await frames(150)
	check(rider.recovery == 0.0 and rider.over_lean == 0.0 and rider.plume > 0.5 and rider.plume_side > 0.0, "a committed carve throws a plume and never tips the rider (plume %.2f)" % rider.plume)
	Input.action_release("steer_right")
	menu.restart()
	await press_and_run(60)
	rider.velocity = Vector3(0, -9, 30)
	await frames(2)
	Input.action_press("steer_left", 1.0)
	var lock_frames := 0
	var max_plume := 0.0
	var warned := false
	while rider.recovery == 0.0 and lock_frames < 400:
		await frames(1)
		lock_frames += 1
		max_plume = maxf(max_plume, rider.plume)
		if rider.over_lean > 0.5: warned = true
	Input.action_release("steer_left")
	check(rider.recovery > 0.0 and rider.last_crash_reason == "over-lean" and lock_frames > 60 and lock_frames < 240, "leaning too far for too long washes the edge out into a tumble (after %.2f s)" % (lock_frames / 60.0))
	check(max_plume > 0.8 and warned, "full lean throws the biggest plume and builds a warning first")
	check(rider.nitro == 0.0 and rider.velocity == Vector3.ZERO, "an over-lean fall wipes speed and nitro like any other fall")
	menu.restart()
	await press_and_run(60)
	rider.velocity = Vector3(0, -9, 30)
	await frames(2)
	Input.action_press("steer_left", 1.0)
	Input.action_press("brake", 1.0)
	await frames(200)
	Input.action_release("steer_left")
	Input.action_release("brake")
	check(rider.recovery == 0.0 and rider.last_crash_reason != "over-lean", "a braking skid turn at full lock stays upright")

	# --- Pass 5: left stick forward/back, restart hold, camera range, mapping upgrade
	menu.restart()
	await press_and_run(90)
	var ls := InputEventJoypadMotion.new()
	ls.axis = JOY_AXIS_LEFT_Y
	ls.axis_value = -1.0
	Input.parse_input_event(ls)
	await frames(3)
	check(rider.tuck_input > 0.9 and rider.brake_input == 0.0, "left stick forward crouches into a tuck")
	ls = ls.duplicate()
	ls.axis_value = -0.2
	Input.parse_input_event(ls)
	await frames(3)
	check(rider.tuck_input == 0.0, "small stick drift neither tucks nor brakes")
	var speed_at := rider.speed
	ls = ls.duplicate()
	ls.axis_value = 1.0
	Input.parse_input_event(ls)
	await frames(60)
	check(rider.brake_input > 0.9 and rider.speed < speed_at, "pulling the left stick back brakes")
	ls = ls.duplicate()
	ls.axis_value = 0.0
	Input.parse_input_event(ls)
	await frames(2)
	Input.action_press("restart")
	await frames(6)
	Input.action_release("restart")
	await frames(2)
	check(run.state == "running", "a tap on restart does nothing")
	Input.action_press("restart")
	await frames(30)
	Input.action_release("restart")
	check(run.state == "ready" and run.elapsed == 0.0, "holding restart returns to the summit")
	camera.range_path = "user://test_feel_camera.json"
	camera.range_index = 1
	await frames(90)
	var mid_view := camera.distance
	Input.action_press("camera_range")
	await frames(2)
	Input.action_release("camera_range")
	await frames(120)
	var far_view := camera.distance
	Input.action_press("camera_range")
	await frames(2)
	Input.action_release("camera_range")
	await frames(120)
	var near_view := camera.distance
	check(camera.range_index == 0 and far_view > mid_view * 1.3 and near_view < mid_view * 0.85, "View cycles the camera medium -> far -> close (%.1f / %.1f / %.1f m)" % [mid_view, far_view, near_view])
	camera.range_index = 2
	camera.load_range()
	check(camera.range_index == 0, "the chosen camera distance is remembered")
	Input.action_press("camera_range")
	await frames(2)
	Input.action_release("camera_range")
	check(camera.range_index == 1 and run.state == "ready", "the View button no longer restarts the run")
	DirAccess.remove_absolute("user://test_feel_camera.json")
	var old_map: Dictionary = SnowControls.DEFAULTS.duplicate(true)
	old_map.erase("camera_range")
	old_map["restart"] = ["button", JOY_BUTTON_BACK, 1] # the pass-4 default
	old_map["boost"] = ["button", JOY_BUTTON_DPAD_LEFT, 1] # a deliberate player remap
	var old_file := FileAccess.open("user://test_feel_controls.json", FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_map))
	old_file.close()
	controls.load_settings()
	check(controls.bindings.size() == SnowControls.DEFAULTS.size() and controls.bindings.camera_range == ["button", JOY_BUTTON_BACK, 1] and controls.bindings.restart == ["button", JOY_BUTTON_Y, 1] and controls.bindings.boost == ["button", JOY_BUTTON_DPAD_LEFT, 1], "older saved mapping upgrades: View becomes camera, restart moves to Y, player remaps kept")
	old_map["restart"] = ["button", JOY_BUTTON_DPAD_RIGHT, 1] # the player had moved restart themselves
	old_file = FileAccess.open("user://test_feel_controls.json", FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_map))
	old_file.close()
	controls.load_settings()
	check(controls.bindings.restart == ["button", JOY_BUTTON_DPAD_RIGHT, 1] and controls.bindings.camera_range == ["button", JOY_BUTTON_BACK, 1], "a restart the player remapped themselves is left where they put it")
	controls.bindings = SnowControls.DEFAULTS.duplicate(true)
	controls.apply_bindings()

	# --- Pass 6: Day / Night ----------------------------------------------------
	var atmosphere: SnowAtmosphere = game.get_node("Mountain").atmosphere
	var soundtrack: SnowMusic = game.get_node("Music")
	run.settings_path = "user://test_feel_settings.json"
	menu.restart()
	check(run.mode == "day" and atmosphere.mode == "day" and SnowAtmosphere.night_amount == 0.0, "a fresh install starts in Day")
	var day_exposure := atmosphere.environment.tonemap_exposure
	menu.show_menu()
	check(not menu.mode_button.disabled and "Day" in menu.mode_button.text and "DAY" in menu.records_title.text, "at the summit the pause menu offers the time of day")
	var song_before := soundtrack.current
	var songs_before := soundtrack.history.size()
	menu.mode_button.pressed.emit() # A on the selector
	check(run.mode == "night" and atmosphere.mode == "night" and "Night" in menu.mode_button.text and "NIGHT" in menu.records_title.text, "choosing Night applies at once and switches to the Night leaderboard")
	for i in 130:
		await process_frame
	check(paused and is_equal_approx(SnowAtmosphere.night_amount, 1.0) and atmosphere.environment.tonemap_exposure > day_exposure and (atmosphere.sun.basis.z).dot(SnowAtmosphere.MOON_DIRECTION.normalized()) > 0.99, "the world cross-fades to moonlight behind the paused menu")
	check(soundtrack.current == song_before and soundtrack.history.size() == songs_before, "changing the time of day never restarts or skips the music")
	var saved_mode = JSON.parse_string(FileAccess.get_file_as_string("user://test_feel_settings.json"))
	var fresh := SnowRun.new()
	fresh.settings_path = run.settings_path
	fresh.load_settings()
	check(saved_mode is Dictionary and saved_mode.get("mode") == "night" and fresh.mode == "night", "the chosen time of day is remembered for the next launch")
	fresh.free()
	menu.hide_menu()
	await press_and_run(30)
	check(not run.set_mode("day") and run.mode == "night", "the time of day cannot be changed during a timed descent")
	menu.show_menu()
	menu.mode_button.pressed.emit()
	check(menu.mode_button.disabled and "locked" in menu.mode_button.text and run.mode == "night" and atmosphere.mode == "night", "the selector is locked while the clock is running")
	menu.hide_menu()
	check(not game.get_node("Title").visible, "the launch title is gone once the rider has pushed off")
	var drawn := false
	for layer in game.get_children():
		if layer is CanvasLayer:
			for item in layer.get_children():
				if item is CanvasItem and item.is_visible_in_tree(): drawn = true
	check(not drawn, "no HUD: nothing at all is drawn over the game during a descent, day or night")
	var day_times: Array = run.by_mode["day"].duplicate()
	run.records.clear()
	run.elapsed = 222.0
	run.finish()
	check(run.by_mode["night"] == [222.0] and run.by_mode["day"] == day_times and FileAccess.file_exists("user://test_feel_records_night.json"), "a night finish is recorded on the Night leaderboard only")
	check(run.set_mode("day") and run.mode == "day" and not 222.0 in run.records, "after the run the time of day can be changed again")
	menu.refresh()
	check("DAY" in menu.records_title.text and not "03:42.00" in menu.records_label.text, "the menu shows the leaderboard of the selected time of day")
	run.set_mode("night")
	menu.refresh()
	check("NIGHT" in menu.records_title.text and "03:42.00" in menu.records_label.text, "switching back shows the Night times again")
	run.load_records()
	check(run.by_mode["night"] == [222.0] and not 222.0 in run.by_mode["day"], "Day and Night top tens persist in separate files")
	menu.restart()
	run.set_mode("day")
	atmosphere.set_mode("day", true)
	check(SnowAtmosphere.night_amount == 0.0 and is_equal_approx(atmosphere.environment.tonemap_exposure, day_exposure) and (atmosphere.sun.basis.z).dot(SnowAtmosphere.SUN_DIRECTION.normalized()) > 0.99, "Day returns exactly to its own lighting")
	check(ProjectSettings.get_setting("application/boot_splash/image") == "res://branding/splash.png" and FileAccess.file_exists("res://branding/snow.ico") and FileAccess.file_exists("res://branding/icon_256.png"), "branded boot splash and icon are in place")

	# --- Soundtrack manager (real files in res://assets/music/) ------------
	var music: SnowMusic = game.get_node("Music")
	var opener := music.music_dir.path_join(SnowMusic.OPENING_TRACK)
	check(music.tracks.size() >= 7 and music.players[0].bus == "Music" and music.players[1].bus == "Music", "soundtrack auto-discovers %d songs, routed only to the Music bus" % music.tracks.size())
	check(not music.history.is_empty() and music.history[0] == opener and music.players[music.active].playing, "every launch opens with 'Alpine Shift (Take 2) (Remix).mp3'")
	music.start() # a second "launch"
	check(music.history[0] == opener, "the opener is fixed, not random")
	var first_cycle: Array[String] = []
	for i in music.tracks.size() - 1:
		music.advance()
		first_cycle.append(music.current)
	var unique_first: Array[String] = []
	for t in first_cycle:
		if not t in unique_first: unique_first.append(t)
	check(unique_first.size() == music.tracks.size() - 1 and not opener in first_cycle, "after the opener, every OTHER song plays once before any repeat")
	check(music.fading, "song changes crossfade")
	for i in 200:
		await process_frame
	check(not music.fading and not music.players[1 - music.active].playing, "crossfade completes and the outgoing song stops")
	# Simulate many later cycles (playlist logic only) to check the bag rules.
	var sequence: Array[String] = [music.current]
	var cycles_ok := true
	for c in 25:
		var cycle_items: Array[String] = []
		for i in music.tracks.size():
			var name := music.next_track_name()
			music.current = name
			cycle_items.append(name)
			sequence.append(name)
		var seen: Array[String] = []
		for t in cycle_items:
			if not t in seen: seen.append(t)
		if seen.size() != music.tracks.size(): cycles_ok = false
	var repeats := 0
	for i in range(1, sequence.size()):
		if sequence[i] == sequence[i - 1]: repeats += 1
	check(cycles_ok, "later cycles reshuffle ALL songs, opener included, each once per cycle")
	check(repeats == 0, "no song ever plays twice in a row, across 25 cycle boundaries")
	# Pause / resume / restart / results behaviour on the real menu.
	menu.restart()
	await press_and_run(30)
	var playing_track := music.current
	var history_size := music.history.size()
	menu.show_menu()
	check(music.paused and music.players[music.active].stream_paused, "pausing the game pauses the soundtrack")
	var paused_at := music.players[music.active].get_playback_position()
	for i in 20: await process_frame
	check(absf(music.players[music.active].get_playback_position() - paused_at) < 0.05, "paused music holds its position")
	menu.hide_menu()
	check(not music.paused and not music.players[music.active].stream_paused and music.current == playing_track, "resume continues the same song from the same place")
	menu.restart()
	await press_and_run(10)
	check(music.current == playing_track and music.history.size() == history_size, "restarting a descent never restarts or skips the soundtrack")
	run.state = "running"
	run.finish()
	await frames(150)
	check(menu.panel.visible and not music.paused, "results after a finish keep the music playing")
	menu.restart()
	var before_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	rider.sound_event.emit("crash", 0.8)
	for i in 20: await process_frame
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < before_db - 2.0, "music ducks gently under a crash")
	# Fallbacks: opener missing, and no music at all.
	DirAccess.make_dir_recursive_absolute("user://test_music/")
	var sample := FileAccess.get_file_as_bytes("res://assets/music/Powder Rush (Take 1).mp3")
	var test_copies := ["Song A.mp3", "Song B.mp3", "notes.txt"]
	for name in test_copies:
		var f := FileAccess.open("user://test_music/" + name, FileAccess.WRITE)
		f.store_buffer(sample) # FIXTURE copies of an owner track
		f.close()
	music.music_dir = "user://test_music/"
	music.start()
	check(music.tracks.size() == 2 and music.players[music.active].playing and music.history[0].get_file() in ["Song A.mp3", "Song B.mp3"], "missing opener falls back to another song; non-audio files ignored")
	music.music_dir = "user://test_music_none/"
	music.start()
	music.advance()
	check(music.tracks.is_empty() and not music.players[0].playing and not music.players[1].playing, "no music installed: silent, no errors")
	for name in test_copies:
		DirAccess.remove_absolute("user://test_music/" + name)
	DirAccess.remove_absolute("user://test_music/")
	for a in ["boost", "steer_left", "steer_right", "jump"]:
		Input.action_release(a)
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	for path in ["user://test_feel_controls.json", "user://test_feel_records.json", "user://test_feel_records_night.json", "user://test_feel_settings.json"]:
		DirAccess.remove_absolute(path)
	print("FEEL TESTS failures=", failures)
	quit(0 if failures == 0 else 1)

## FIXTURE: ride off the summit, set a downhill speed, fall, and measure the tumble.
func tumble_fixture(ride_speed: float, severity: float) -> Dictionary:
	menu.restart()
	await press_and_run(60)
	rider.velocity = Vector3(0, -ride_speed * 0.3, ride_speed)
	await frames(2)
	events.clear()
	rider.nitro = 0.6
	var from := rider.position
	rider.crash(severity)
	var frozen := true
	var ticks := 0
	while not rider.tumble_resting and ticks < 900:
		await frames(1)
		ticks += 1
		if rider.velocity != Vector3.ZERO or rider.speed != 0.0 or rider.nitro != 0.0 or rider.position.distance_to(from) > 0.01:
			frozen = false
	var rest := rider.tumble_pos
	var impacts := events.count("tumble")
	var groan := "groan" in events
	while rider.recovery > 0.0 and ticks < 2000:
		await frames(1)
		ticks += 1
	return {"travel": Vector2(rest.x - from.x, rest.z - from.z).length(), "time": rider.tumble_time, "impacts": impacts, "groan": groan, "frozen": frozen, "stood": rider.recovery == 0.0 and rider.position.distance_to(rest) < 15.0}

## Restart-independent helper: push off from the summit with ordinary input and ride.
func press_and_run(count: int) -> void:
	if run.state == "ready":
		Input.action_press("jump")
		await frames(2)
		Input.action_release("jump")
	await frames(count)
