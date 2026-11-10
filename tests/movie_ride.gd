extends SceneTree
## Scripted ~32 s ride for Godot's Movie Maker (records the real video AND the real
## audio mix through the game's buses). Ordinary inputs for riding/tricks; ONE
## explicit visual fixture (a tree placed ahead) guarantees a crash on camera.
##   xvfb-run godot --path . --resolution 960x540 --fixed-fps 60 \
##     --write-movie work/movie/ride.avi --script res://tests/movie_ride.gd
var game: Node3D
var rider: SnowRider
var frame := 0
var events: Array[String] = []

func _initialize() -> void: go.call_deferred()

func step(count := 1) -> void:
	for i in count:
		await physics_frame
		frame += 1

func steer_to(x: float) -> void:
	var desired := atan2(x - rider.position.x, 70.0)
	var s := clampf(-(desired - rider.heading) * 2.5, -1, 1)
	Input.action_press("steer_right", maxf(s, 0))
	Input.action_press("steer_left", maxf(-s, 0))

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	rider.sound_event.connect(func(k: String, s: float): print("EVENT t=%.2f %s %.2f" % [frame / 60.0, k, s]))
	await step(90) # summit ambience
	Input.action_press("jump")
	await step(2)
	Input.action_release("jump")
	for i in 420:
		steer_to(160.0)
		Input.action_press("tuck")
		await step()
	Input.action_release("tuck")
	for trick in 3:
		Input.action_press("jump")
		for i in 16:
			steer_to(200.0)
			await step()
		Input.action_release("jump")
		for i in 70:
			if not rider.is_on_floor():
				if rider.spin > -PI * 0.93: Input.action_press("spin_right")
				else: Input.action_release("spin_right")
				if trick == 1: Input.action_press("grab")
			await step()
		Input.action_release("spin_right")
		Input.action_release("grab")
		for i in 60:
			steer_to(200.0)
			await step()
	# Hard carves both ways with spray.
	for i in 150:
		var c := 0.9 if (i / 50) % 2 == 0 else -0.9
		Input.action_press("steer_right", maxf(c, 0))
		Input.action_press("steer_left", maxf(-c, 0))
		await step()
	Input.action_press("boost")
	for i in 260:
		steer_to(240.0)
		await step()
	Input.action_release("boost")
	await step(30)
	Input.action_press("boost") # empty: sputter
	await step(5)
	Input.action_release("boost")
	await step(60)
	Input.action_press("brake")
	await step(70)
	Input.action_release("brake")
	await step(60)
	# FIXTURE: a trunk directly ahead so the crash/tumble/get-up is on camera.
	var tree := StaticBody3D.new()
	tree.collision_layer = 2
	tree.set_meta("hazard", "tree")
	var ahead := rider.position + Vector3(rider.velocity.x, 0, rider.velocity.z).normalized() * 9.0
	tree.position = Vector3(ahead.x, SnowMountain.height_at(ahead.x, ahead.z) + 3.0, ahead.z)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.2
	cylinder.height = 6.0
	shape.shape = cylinder
	tree.add_child(shape)
	game.add_child(tree)
	for i in 300:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		await step()
	for a in ["boost", "steer_left", "steer_right", "tuck", "brake"]:
		Input.action_release(a)
	print("MOVIE DONE frames=", frame)
	quit()
