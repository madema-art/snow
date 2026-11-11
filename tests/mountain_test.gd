extends SceneTree
var failures := 0
var game: Node3D
var rider: SnowRider
var run: SnowRun
var camera: SnowCamera
var menu: SnowPauseMenu
# Known geographical route, not checkpoints. Test bot only submits ordinary inputs.
const ROUTE := [Vector2(0,8), Vector2(-320,1250), Vector2(-320,1850), Vector2(-240,2500), Vector2(-150,2900), Vector2(-95,3400), Vector2(200,4070), Vector2(230,4470), Vector2(-310,5310), Vector2(-310,5650), Vector2(-310,6160), Vector2(-310,6500), Vector2(-100,7000), Vector2(0,7440), Vector2(0,7800)]
var obstacles: Array[Vector3] = []
var cautious: bool = "--cautious" in OS.get_cmdline_user_args()
var tricks: bool = "--tricks" in OS.get_cmdline_user_args()
# Trick profile state (inputs only; the bot may READ rider state to time them).
var trick_phase := ""
var trick_timer := 0
var trick_cooldown := 0
var trick_index := 0
var nitro_earned := 0.0
var boost_frames := 0
var tricks_landed := 0
var stall_frames := 0
var frozen := 0

func _initialize() -> void: go.call_deferred()
func check(value: bool, message: String) -> void:
	print("PASS: " if value else "FAIL: ", message)
	if not value: failures += 1
func step() -> void:
	await physics_frame
	await process_frame
func clear_inputs() -> void:
	for action in SnowControls.DEFAULTS: Input.action_release(action)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
func start_run() -> void:
	clear_inputs()
	menu.restart()
	Input.action_press("jump")
	await step()
	await step()
	Input.action_release("jump")
func route_x(distance: float) -> float:
	var z := distance / SnowMountain.DISTANCE_SCALE
	for i in range(1, ROUTE.size()):
		if z <= ROUTE[i].y:
			return lerpf(ROUTE[i-1].x, ROUTE[i].x, clampf((z - ROUTE[i-1].y) / (ROUTE[i].y - ROUTE[i-1].y),0,1))
	return 0

func drive() -> void:
	var lookahead := clampf(25 + rider.speed * 1.1, 35, 70)
	var target := Vector2(route_x(rider.position.z + lookahead), rider.position.z + lookahead)
	var geo_z := rider.position.z / SnowMountain.DISTANCE_SCALE
	var target_speed := 39.0
	if geo_z > 2850 and geo_z < 4650: target_speed = 29
	if geo_z > 4750 and geo_z < 6400: target_speed = 35
	if cautious:
		target_speed = 27.0
		if geo_z > 2850 and geo_z < 4650: target_speed = 21
		if geo_z > 4750 and geo_z < 6400: target_speed = 25
	# Local visible-obstacle avoidance. No warping or changes to rider velocity/heading.
	var nearest := 10000.0
	var relevant := Vector3.ZERO
	for ob in obstacles:
		var dz := ob.y - rider.position.z
		if dz < -ob.z - 2 or dz > lookahead + 20: continue
		var planned_x := lerpf(rider.position.x, target.x, clampf(dz / lookahead, 0, 1))
		if absf(ob.x - planned_x) < ob.z + 3.0 and dz < nearest:
			nearest = dz
			relevant = ob
	if nearest < 10000:
		var side := -1.0 if target.x < relevant.x else 1.0
		target.x = relevant.x + side * (relevant.z + 5)
		target.y = maxf(rider.position.z + 12, relevant.y)
		if nearest < 25: target_speed = minf(target_speed, 22)
	var open_ahead := nearest > lookahead + 10.0
	if tricks:
		drive_tricks(geo_z, open_ahead)
	# Stalled against something: turn the board down the fall line and push (A).
	if rider.speed < 1.0 and rider.recovery <= 0.0 and rider.is_on_floor():
		stall_frames += 1
	else:
		stall_frames = 0
	if stall_frames > 45:
		target = Vector2(rider.position.x + (40.0 if stall_frames % 240 < 120 else -40.0), rider.position.z + 30.0)
		if stall_frames % 30 == 0: Input.action_press("jump")
		elif stall_frames % 30 == 2: Input.action_release("jump")
	var desired := atan2(target.x - rider.position.x, maxf(8,target.y - rider.position.z))
	var error := wrapf(desired - rider.heading, -PI, PI)
	var steer := clampf(-error * 2.8, -1, 1)
	Input.action_press("steer_right", maxf(steer,0))
	Input.action_press("steer_left", maxf(-steer,0))
	var brake := clampf((rider.speed - target_speed) * 0.22 + maxf(0, absf(error) - 0.35) * 0.5,0,0.85)
	Input.action_press("brake", brake)
	Input.action_press("tuck", 1.0 if rider.speed < target_speed - 0.5 and absf(error) < 0.18 else 0.0)

## Ollie + spin/grab on open snow, then spend nitro on clear fast terrain.
func drive_tricks(geo_z: float, open_ahead: bool) -> void:
	trick_cooldown -= 1
	var open_region := geo_z < 1050 or (geo_z > 6550 and geo_z < 7500)
	match trick_phase:
		"":
			Input.action_release("spin_right")
			Input.action_release("grab")
			if open_region and open_ahead and rider.is_on_floor() and rider.recovery <= 0.0 and rider.speed > 16.0 and trick_cooldown <= 0:
				trick_phase = "preload"
				trick_timer = 14
				Input.action_press("jump")
		"preload":
			trick_timer -= 1
			if trick_timer <= 0:
				Input.action_release("jump")
				trick_phase = "air"
				trick_timer = 0
		"air":
			trick_timer += 1
			var kind := trick_index % 3
			if kind != 1 and rider.spin > -PI * 0.92:
				Input.action_press("spin_right")
			else:
				Input.action_release("spin_right")
			if kind != 0 and trick_timer > 4:
				Input.action_press("grab")
			if rider.is_on_floor() and trick_timer > 6 or rider.recovery > 0.0 or trick_timer > 240:
				Input.action_release("spin_right")
				Input.action_release("grab")
				trick_phase = ""
				trick_index += 1
				trick_cooldown = 150
	var boost := rider.nitro > 0.05 and trick_phase == "" and open_ahead and rider.is_on_floor() and (geo_z > 6550 or rider.nitro > 0.35)
	if boost:
		Input.action_press("boost")
		boost_frames += 1
	else:
		Input.action_release("boost")

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	camera = game.get_node("ChaseCamera")
	for child in game.get_children():
		if child is SnowRun: run = child
		if child is SnowPauseMenu: menu = child
		if child is SnowControls:
			child.bindings = SnowControls.DEFAULTS.duplicate(true)
			child.apply_bindings()
		if child is SnowMountain:
			for h in child.all_hazards():
				obstacles.append(Vector3(h.x, h.z, h.w))
	run.records_path = "user://test_massif_records.json"
	run.records.clear()
	rider.sound_event.connect(func(kind: String, _strength: float):
		if kind == "charge":
			nitro_earned += rider.last_reward
			tricks_landed += 1
		if kind in ["crash", "fatal"]: print("FALL ", kind, " reason=",rider.last_crash_reason," p=",rider.position," t=",run.elapsed))
	var old_heading := rider.heading
	var old_velocity := rider.velocity
	for i in 180: camera.orbit_input(1.0/60, Vector2(1,0),false)
	check(absf(camera.orbit) > TAU, "camera continuous full 360 orbit")
	camera.orbit_input(1.0/60,Vector2(1,0),true)
	check(not camera.recentering,"active manual camera input wins over recenter")
	for i in 90: camera.orbit_input(1.0/60,Vector2(0,1),false)
	check(is_equal_approx(camera.lift, SnowCamera.PITCH_MAX), "camera substantial upper pitch range")
	for i in 90: camera.orbit_input(1.0/60,Vector2(0,-1),false)
	check(is_equal_approx(camera.lift, SnowCamera.PITCH_MIN), "camera lower pitch range")
	check(rider.heading == old_heading and rider.velocity == old_velocity, "manual camera never mutates travel")
	var held_yaw := camera.orbit
	for i in 60: camera.orbit_input(1.0/60,Vector2.ZERO,false)
	check(camera.orbit == held_yaw,"manual orbit holds its view during inactivity grace period")
	camera.orbit_input(1.0/60,Vector2.ZERO,true)
	for i in 120: camera.orbit_input(1.0/60,Vector2.ZERO,false)
	check(absf(wrapf(camera.orbit-rider.heading,-PI,PI)) < 0.02 and absf(camera.lift-camera.auto_lift())<0.02,"smooth explicit recenter")
	var obstruction := StaticBody3D.new()
	obstruction.collision_layer = 2
	obstruction.position = rider.position + Vector3(0,2,-5)
	var camera_block := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8,8,1)
	camera_block.shape = box
	obstruction.add_child(camera_block)
	game.add_child(obstruction)
	camera.reset()
	for i in 3: await step()
	check(camera.global_position.z > obstruction.position.z + 0.5,"camera sphere retracts before an actual rock obstruction")
	obstruction.queue_free()
	await step()
	if "--camera-only" in OS.get_cmdline_user_args():
		game.queue_free()
		await process_frame
		OS.delay_msec(100)
		print("CAMERA TESTS failures=",failures)
		quit(0 if failures == 0 else 1)
		return
	await start_run()
	for i in 12000:
		await step()
		if run.state != "running": break
	print("STRAIGHT RESULT state=",run.state," time=",run.elapsed," p=",rider.position)
	check(run.state != "finished" and rider.position.z > 1200*SnowMountain.DISTANCE_SCALE and rider.position.z < 1700*SnowMountain.DISTANCE_SCALE,"straight-line approach fails at physical summit gorge")
	await start_run()
	var crashes := 0
	var max_speed := 0.0
	var distance := 0.0
	var previous := rider.position
	var was_recovering := false
	for i in 36000:
		drive()
		await step()
		if previous.distance_to(rider.position) < 0.0001 and rider.recovery <= 0.0 and rider.speed > 5.0:
			frozen += 1
			if frozen == 30:
				var info := ""
				for c in rider.get_slide_collision_count():
					var hit := rider.get_slide_collision(c)
					info += " [n=%s col=%s meta=%s at=%s]" % [hit.get_normal(), hit.get_collider().name, hit.get_collider().get_meta("hazard", "-"), hit.get_position()]
				print("FROZEN p=", rider.position, " v=", rider.velocity, " floor=", rider.is_on_floor(), " paused=", paused, " state=", run.state, info)
		else:
			frozen = 0
		distance += previous.distance_to(rider.position)
		previous = rider.position
		max_speed = maxf(max_speed,rider.speed)
		if rider.recovery > 0 and not was_recovering: crashes += 1
		was_recovering = rider.recovery > 0
		if i % 1800 == 0: print("CONTROLLED t=",run.elapsed," p=",rider.position," speed=",rider.speed," heading=",rider.heading," recovery=",rider.recovery)
		if run.state != "running": break
	print("CONTROLLED RESULT state=",run.state," time=",run.elapsed," distance=",distance," max_speed=",max_speed," crashes=",crashes," p=",rider.position)
	if tricks:
		print("TRICK RESULT rewarded_landings=", tricks_landed, " nitro_earned=", nitro_earned, " boost_seconds=", boost_frames / 60.0)
		check(tricks_landed >= 4 and nitro_earned > 0.3 and boost_frames > 60, "tricks earn nitro that is then spent on real boosts during a full run")
	check(run.state == "finished", "ordinary steering/braking route completes without teleporting")
	check(run.elapsed >= (330 if cautious else 230) and run.elapsed <= (480 if cautious else 360), "cautious route takes longer" if cautious else "skill-route simulation approximately five minutes")
	check(max_speed > (25 if cautious else 30) and distance > 7800,"real travel distance and expected input-profile speed")
	var finished_time := run.elapsed
	run.finish()
	for i in 8: await process_frame
	check(run.state == "finished" and run.elapsed == finished_time and run.records.size() == 1,"actual finish freezes time and records exactly once")
	clear_inputs()
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	DirAccess.remove_absolute("user://test_massif_records.json")
	print("MASSIF TESTS failures=",failures)
	quit(0 if failures == 0 else 1)



