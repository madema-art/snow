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
	var desired := atan2(target.x - rider.position.x, maxf(8,target.y - rider.position.z))
	var error := wrapf(desired - rider.heading, -PI, PI)
	var steer := clampf(-error * 2.8, -1, 1)
	Input.action_press("steer_right", maxf(steer,0))
	Input.action_press("steer_left", maxf(-steer,0))
	var brake := clampf((rider.speed - target_speed) * 0.22 + maxf(0, absf(error) - 0.35) * 0.5,0,0.85)
	Input.action_press("brake", brake)
	Input.action_press("tuck", 1.0 if rider.speed < target_speed - 0.5 and absf(error) < 0.18 else 0.0)

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
			for body in child.get_children():
				if body is StaticBody3D and body.has_meta("hazard"):
					var shape: Shape3D = body.get_child(0).shape
					var radius := 1.0
					if shape is CylinderShape3D: radius = shape.radius
					elif shape is ConvexPolygonShape3D:
						for p in shape.points: radius = maxf(radius, Vector2(p.x,p.z).length())
					obstacles.append(Vector3(body.position.x,body.position.z,radius))
	run.records_path = "user://test_massif_records.json"
	run.records.clear()
	rider.sound_event.connect(func(kind: String, _strength: float):
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
	check(absf(wrapf(camera.orbit-rider.heading,-PI,PI)) < 0.02 and absf(camera.lift-0.32)<0.02,"smooth explicit recenter")
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
		distance += previous.distance_to(rider.position)
		previous = rider.position
		max_speed = maxf(max_speed,rider.speed)
		if rider.recovery > 0 and not was_recovering: crashes += 1
		was_recovering = rider.recovery > 0
		if i % 1800 == 0: print("CONTROLLED t=",run.elapsed," p=",rider.position," speed=",rider.speed," heading=",rider.heading," recovery=",rider.recovery)
		if run.state != "running": break
	print("CONTROLLED RESULT state=",run.state," time=",run.elapsed," distance=",distance," max_speed=",max_speed," crashes=",crashes," p=",rider.position)
	check(run.state == "finished", "ordinary steering/braking route completes without teleporting")
	check(run.elapsed >= (330 if cautious else 260) and run.elapsed <= (480 if cautious else 360), "cautious route takes longer" if cautious else "skill-route simulation approximately five minutes")
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



