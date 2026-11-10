extends SceneTree
var failures := 0
func _initialize() -> void: go.call_deferred()
func check(value: bool, message: String) -> void:
	print("PASS: " if value else "FAIL: ", message)
	if not value: failures += 1
func go() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var rider: SnowRider = game.get_node("Rider")
	for child in game.get_children():
		if child is SnowControls:
			child.bindings = SnowControls.DEFAULTS.duplicate(true)
			child.apply_bindings()
	var run := rider.run
	run.records_path = "user://test_terrain_unused.json"
	for i in 2: await physics_frame
	# Local collision fixture, explicitly NOT the whole-run navigation proof.
	var z := 1470 * SnowMountain.DISTANCE_SCALE
	rider.position = Vector3(120,SnowMountain.height_at(120,z)+0.7,z)
	rider.launch_height = rider.position.y
	rider.velocity = Vector3(0,-12,40)
	run.push_off()
	var jumped := false
	var ever_crashed := false
	for i in 300:
		if not jumped and rider.position.z > 1492 * SnowMountain.DISTANCE_SCALE and rider.is_on_floor():
			Input.action_press("jump")
			jumped = true
		else:
			Input.action_release("jump")
		await physics_frame
		await process_frame
		if i == 20: check(rider.speed > 30,"innocuous terrain seams retain high-speed tangent momentum")
		if rider.recovery > 0 or run.state != "running": ever_crashed = true
	check(jumped and not ever_crashed and rider.position.z > 1600*SnowMountain.DISTANCE_SCALE,"actual ollie crosses the narrow gorge spur and lands cleanly")
	check(rider.nitro > 0,"clean shortcut landing awards real stored nitro")
	print("TERRAIN FIXTURE position=",rider.position," charge=",rider.nitro)
	Input.action_release("jump")
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	print("TERRAIN TESTS failures=",failures)
	quit(0 if failures == 0 else 1)
