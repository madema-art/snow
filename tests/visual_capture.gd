extends SceneTree
## VISUAL FIXTURE (not a navigation proof): places the stationary rider at
## representative mountain views, drives the real chase camera and saves PNGs to
## res://work/shots/. Run windowed under a real GL context (Xvfb works):
##   godot --path . --windowed --resolution 1600x900 --script res://tests/visual_capture.gd [-- shot names]
## Speed shots set a display-only velocity while the run is still "ready", so the
## rider does not move; camera framing/FOV react exactly as when riding.
const SHOTS := {
	"summit": [0.0, 30.0, 0.0, 0.0, 0.0],
	"summit_look_back": [0.0, 30.0, 0.0, PI, 0.15],
	"summit_fast": [-120.0, 900.0, 0.0, 0.0, 34.0],
	"cliffs_gorge_approach": [-60.0, 1650.0, 0.0, 0.0, 30.0],
	"cliffs_gorge_side": [-300.0, 1790.0, 0.0, 1.25, 0.35],
	"cliffs_buttress": [-180.0, 2650.0, 0.0, 0.0, 26.0],
	"forest": [-170.0, 3700.0, 0.0, 0.0, 24.0],
	"forest_escarpment": [-40.0, 4950.0, 0.0, 0.0, 22.0],
	"broken": [-300.0, 6300.0, 0.0, 0.0, 30.0],
	"broken_cut": [100.0, 6460.0, 0.0, 0.0, 26.0],
	"final": [-40.0, 6950.0, 0.0, 0.0, 38.0],
	"finish": [0.0, 7480.0, 0.0, 0.0, 20.0],
	"tree_close": [-150.0, 3520.0, 0.0, 0.0, 0.1],
	"rider_close": [0.0, 30.0, 0.0, -1.35, 0.1],
	"rider_carve": [-120.0, 900.0, 0.0, -0.9, 0.12],
	"nitro": [-80.0, 6700.0, 0.0, -0.5, 0.05],
	"pause": [0.0, 30.0, 0.0, 0.0, 0.0],
	"ride_carve": [],
	"ride_nitro": [],
}
var game: Node3D
var rider: SnowRider
var camera: SnowCamera

func _initialize() -> void: go.call_deferred()

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	camera = game.get_node("ChaseCamera")
	DirAccess.make_dir_recursive_absolute("res://work/shots")
	var wanted: Array = OS.get_cmdline_user_args()
	for name in SHOTS:
		if not wanted.is_empty() and not name in wanted:
			continue
		await shot(name, SHOTS[name])
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	quit()

## Real riding: ordinary push-off and steering inputs, rendering paused while the
## simulation runs so software GL stays fast, then frames are rendered live.
func ride(name: String) -> void:
	rider.reset()
	camera.reset()
	var run := rider.run
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	RenderingServer.render_loop_enabled = false
	var target_x := -150.0
	for i in 60 * 22:
		var desired := atan2(target_x - rider.position.x, 60.0)
		var steer := clampf(-(desired - rider.heading) * 2.5, -1, 1)
		Input.action_press("steer_right", maxf(steer, 0))
		Input.action_press("steer_left", maxf(-steer, 0))
		Input.action_press("tuck", 1.0)
		await physics_frame
	RenderingServer.render_loop_enabled = true
	Input.action_release("tuck")
	if name == "ride_nitro":
		rider.nitro = 1.0 # VISUAL FIXTURE ONLY: never done in navigation proofs.
		Input.action_press("boost")
	for i in 40:
		var carve := 0.85 if name == "ride_carve" else 0.0
		Input.action_press("steer_right", carve)
		Input.action_release("steer_left")
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/shots/%s.png" % name)
	print("SHOT ", name, " speed=", rider.speed, " state=", run.state, " p=", rider.position)
	for a in ["boost", "steer_right", "steer_left", "tuck"]:
		Input.action_release(a)
	run.restart()

func shot(name: String, s: Array) -> void:
	if name.begins_with("ride"):
		await ride(name)
		return
	var x: float = s[0]
	var z: float = s[1] * SnowMountain.DISTANCE_SCALE
	rider.reset()
	rider.position = Vector3(x, SnowMountain.height_at(x, z) + 0.7, z)
	rider.grounded_normal = SnowMountain.normal_at(x, z)
	rider.heading = s[2]
	var speed: float = s[4] if s[4] > 1.0 else 0.0
	rider.velocity = Vector3(sin(rider.heading), 0, cos(rider.heading)) * speed
	rider.speed = speed
	if name == "nitro":
		rider.nitro = 0.95
		rider.visual.refresh_charge(0.95)
	if name == "rider_carve":
		rider.steer = 0.9
		rider.yaw_rate = -0.7
		rider.speed = 25.0
	camera.reset()
	camera.look_yaw = s[3]
	if s[4] > 0.0 and s[4] < 1.0:
		camera.lift = s[4]
	camera.idle = 0.0
	if name == "rider_close":
		camera.distance = 3.2
	for i in 50:
		if name in ["rider_close", "rider_carve", "nitro", "tree_close"]:
			camera.distance = 3.4
		await physics_frame
		await process_frame
	if name == "pause":
		for child in game.get_children():
			if child is SnowPauseMenu: child.show_menu()
		for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/shots/%s.png" % name)
	print("SHOT ", name, " cam=", camera.global_position, " fps=", Engine.get_frames_per_second())
	if name == "pause":
		for child in game.get_children():
			if child is SnowPauseMenu: child.hide_menu()
