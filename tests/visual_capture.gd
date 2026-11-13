extends SceneTree
## VISUAL FIXTURE (not a navigation proof): places the stationary rider at
## representative mountain views, drives the real chase camera and saves PNGs to
## res://work/shots/. Run windowed under a real GL context (Xvfb works):
##   godot --path . --windowed --resolution 1600x900 --script res://tests/visual_capture.gd [-- shot names]
## Speed shots set a display-only velocity while the run is still "ready", so the
## rider does not move; camera framing/FOV react exactly as when riding.
## Shots on the 360-degree mountain: [azimuth deg from the summit (0 = north),
## distance from the summit (m), board heading ("fall" = down the fall line, or
## degrees), camera look yaw relative to the board, lift (rad, <1) or display speed].
const SHOTS := {
	"summit": [0.0, 0.0, 180.0, 0.0, 0.0],
	"summit_north": [0.0, 0.0, 0.0, 0.0, 0.0],
	"summit_east": [0.0, 0.0, 90.0, 0.0, 0.0],
	"summit_west": [0.0, 0.0, 270.0, 0.0, 0.0],
	"summit_high": [0.0, 0.0, 135.0, 0.0, 0.62],
	"north_face": [350.0, 1300.0, "fall", 0.0, 26.0],
	"north_cliffs": [10.0, 2600.0, "fall", 0.6, 0.3],
	"east_forest": [95.0, 5200.0, "fall", 0.0, 22.0],
	"south_snowfields": [180.0, 2600.0, "fall", 0.0, 30.0],
	"southwest": [225.0, 3600.0, "fall", 0.0, 28.0],
	"west_ravine": [260.0, 3200.0, "fall", 0.0, 26.0],
	"northwest": [315.0, 3000.0, "fall", 0.0, 24.0],
	"valley_south": [185.0, 9800.0, "fall", PI, 0.15],
	"look_up_from_valley": [120.0, 9000.0, "fall", PI, -0.1],
	"tree_close": [95.0, 5600.0, "fall", 0.0, 0.1],
	"rider_close": [0.0, 0.0, 180.0, 1.45, 0.12],
	"nitro": [180.0, 4200.0, "fall", -0.5, 0.05],
	"pause": [0.0, 0.0, 180.0, 0.0, 0.0],
	"sky_moon": [0.0, 0.0, 112.0, 0.0, -0.22],
	"sky_aurora": [0.0, 0.0, 0.0, 0.0, -0.2],
	"sky_up": [0.0, 0.0, 200.0, 0.0, -0.34],
	"snow_close": [180.0, 600.0, "fall", 0.5, 0.42],
	"slope_night": [150.0, 2200.0, "fall", 0.0, 28.0],
	"ride_carve": [],
	"ride_nitro": [],
	"ride_plume": [],
	"ride_tumble": [],
}
var game: Node3D
var rider: SnowRider
var camera: SnowCamera
var suffix := ""

func _initialize() -> void: go.call_deferred()

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	camera = game.get_node("ChaseCamera")
	DirAccess.make_dir_recursive_absolute("res://work/shots")
	var wanted: Array = Array(OS.get_cmdline_user_args())
	# "--night" renders every requested shot in Night Mode (files get a _night suffix).
	if "--night" in wanted:
		wanted.erase("--night")
		suffix = "_night"
		rider.run.settings_path = "user://test_capture_settings.json"
		rider.run.set_mode("night")
		game.get_node("Mountain").atmosphere.set_mode("night", true)
	game.get_node("Title").dismiss()
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
	for i in 60 * 8:
		var desired := SnowRider.fall_heading(rider.position + rider.forward() * 40.0, rider.heading) * 0.7 + rider.heading * 0.3
		var steer := clampf(-wrapf(desired - rider.heading, -PI, PI) * 2.5, -1, 1)
		Input.action_press("steer_right", maxf(steer, 0))
		Input.action_press("steer_left", maxf(-steer, 0))
		Input.action_press("tuck", 1.0)
		await physics_frame
	RenderingServer.render_loop_enabled = true
	Input.action_release("tuck")
	if name == "ride_nitro":
		rider.nitro = 1.0 # VISUAL FIXTURE ONLY: never done in navigation proofs.
		Input.action_press("boost")
	if name == "ride_plume" or name == "ride_tumble":
		rider.velocity = rider.velocity.normalized() * 27.0 # VISUAL FIXTURE: speed for the shot
	if name == "ride_plume":
		for i in 45:
			Input.action_press("steer_left", 0.8)
			await physics_frame
			await process_frame
	if name == "ride_tumble":
		await physics_frame
		rider.crash(22.0) # VISUAL FIXTURE: a fall on camera
		for i in 22:
			await physics_frame
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/shots/ride_tumble_a.png")
		for i in 45:
			await physics_frame
			await process_frame
	for i in (22 if name == "ride_carve" else (0 if name in ["ride_plume", "ride_tumble"] else 40)):
		var carve := 0.85 if name == "ride_carve" else 0.0
		Input.action_press("steer_right", carve)
		Input.action_release("steer_left")
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/shots/%s%s.png" % [name, suffix])
	print("SHOT ", name, " speed=", rider.speed, " state=", run.state, " p=", rider.position)
	for a in ["boost", "steer_right", "steer_left", "tuck"]:
		Input.action_release(a)
	run.restart()

## Board heading (radians, +Z = 0) that faces a compass azimuth (0 = north).
static func compass_heading(azimuth_deg: float) -> float:
	var a := deg_to_rad(azimuth_deg)
	return atan2(sin(a), -cos(a))

func shot(name: String, s: Array) -> void:
	if name.begins_with("ride_"):
		await ride(name)
		return
	rider.reset()
	var top := SnowMountain.spawn_point()
	var az := deg_to_rad(float(s[0]))
	var x: float = top.x + sin(az) * float(s[1])
	var z: float = top.z - cos(az) * float(s[1])
	if float(s[1]) > 0.0:
		rider.position = Vector3(x, SnowMountain.height_at(x, z) + 0.7, z)
		rider.mountain.prepare(rider.position)
	rider.grounded_normal = SnowMountain.normal_at(rider.position.x, rider.position.z)
	rider.heading = SnowRider.fall_heading(rider.position, 0.0) if s[2] is String else compass_heading(float(s[2]))
	var speed: float = s[4] if s[4] > 1.0 else 0.0
	rider.velocity = rider.forward() * speed
	rider.speed = speed
	if name == "snow_close":
		camera.distance = 3.0
	if name == "nitro":
		rider.nitro = 0.95
		rider.visual.refresh_charge(0.95)
	if name == "rider_carve":
		rider.steer = 0.9
		rider.yaw_rate = -0.7
		rider.speed = 25.0
	camera.reset()
	camera.look_yaw = s[3]
	if absf(s[4]) > 0.0 and absf(s[4]) < 1.0:
		camera.lift = s[4]
	camera.idle = 0.0
	if name == "rider_close":
		camera.distance = 3.2
	for i in 28:
		if name in ["rider_close", "rider_carve", "nitro", "tree_close", "snow_close"]:
			camera.distance = 3.4
		await physics_frame
		await process_frame
	if name == "pause":
		for child in game.get_children():
			if child is SnowPauseMenu:
				child.show_menu()
				child.mode_button.grab_focus()
		for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/shots/%s%s.png" % [name, suffix])
	print("SHOT ", name, " cam=", camera.global_position, " fps=", Engine.get_frames_per_second())
	if name == "pause":
		for child in game.get_children():
			if child is SnowPauseMenu: child.hide_menu()
