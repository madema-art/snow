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
	check(speed_before > 8.0 and moved > 0.5 and moved <= SnowTuning.TUMBLE_MAX_TRAVEL + 1.0, "visible tumble moves the body visual a limited distance")
	check(still, "during the tumble the physics body has no speed, travel or nitro")
	var t_before := run.elapsed
	while rider.recovery > 0.0:
		await frames(1)
	check(run.elapsed > t_before + 1.0 and rider.position.distance_to(body_at) <= SnowTuning.TUMBLE_MAX_TRAVEL + 1.5, "get-up costs clock time and gains no meaningful ground")
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

	# --- Owner soundtrack player -------------------------------------------
	var music: SnowMusic = game.get_node("Music")
	check(music.player.bus == "Music" and AudioServer.get_bus_index("Music") >= 0, "soundtrack player is routed to the Music bus")
	music.music_dir = "user://test_music_empty/"
	music.scan_and_play()
	check(music.tracks.is_empty() and not music.player.playing, "no soundtrack files: the game runs silently without errors")
	DirAccess.make_dir_recursive_absolute("user://test_music/")
	for name in ["b_second.wav", "a_first.wav"]:
		var f := FileAccess.open("user://test_music/" + name, FileAccess.WRITE)
		f.store_buffer(FileAccess.get_file_as_bytes("res://audio/charge_small.wav")) # FIXTURE file, not music
		f.close()
	music.music_dir = "user://test_music/"
	music.scan_and_play()
	await process_frame
	check(music.tracks.size() == 2 and music.tracks[0].ends_with("a_first.wav") and music.player.playing, "soundtrack files play in filename order")
	music.player.stop()
	music.next_track()
	check(music.current_track().ends_with("b_second.wav"), "playlist advances to the next song")
	music.next_track()
	check(music.current_track().ends_with("a_first.wav"), "playlist loops back to the first song")
	music.player.stop()
	for name in ["b_second.wav", "a_first.wav"]:
		DirAccess.remove_absolute("user://test_music/" + name)
	DirAccess.remove_absolute("user://test_music/")
	for a in ["boost", "steer_left", "steer_right", "jump"]:
		Input.action_release(a)
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	for path in ["user://test_feel_controls.json", "user://test_feel_records.json"]:
		DirAccess.remove_absolute(path)
	print("FEEL TESTS failures=", failures)
	quit(0 if failures == 0 else 1)

## Restart-independent helper: push off from the summit with ordinary input and ride.
func press_and_run(count: int) -> void:
	if run.state == "ready":
		Input.action_press("jump")
		await frames(2)
		Input.action_release("jump")
	await frames(count)
