extends SceneTree
## VISUAL FIXTURE: a turntable for the rider model. The rider's physics is
## switched off and its state fields are set directly so each pose can be shown
## still, from several sides, on the real summit in the real light. Nothing here
## is gameplay evidence. Run under a GL context (Xvfb works):
##   godot --path . --windowed --resolution 1200x900 --rendering-driver opengl3 --script res://tests/rider_studio.gd [-- --night] [-- pose names]
## Writes work/studio/<pose>_<view>[_night].png.
const VIEWS := {
	"back": [Vector3(0.0, 0.9, -3.0), 0.35],
	"front": [Vector3(-3.0, 0.45, 0.35), 0.3],
	"heel": [Vector3(3.0, 0.5, -0.2), 0.3],
	"quarter": [Vector3(-2.2, 0.75, 2.2), 0.3],
	"chase": [Vector3(0.0, 2.1, -5.6), 0.55],
	# Close-ups: offsets from a part of the model rather than from the body.
	"face": [Vector3(-0.75, 0.12, 0.4), "head"],
	"head_back": [Vector3(0.6, 0.25, -0.5), "head"],
	"boots": [Vector3(-0.8, 0.35, 0.9), "boot1"],
}
## pose: [state, speed, steer, yaw_rate, tuck, brake, ground, grab, preload, views]
const POSES := {
	"stand": ["ready", 0.0, 0.0, 0.0, 0.0, 0.0, true, false, 0.0, ["back", "front", "heel", "quarter"]],
	"detail": ["ready", 0.0, 0.0, 0.0, 0.0, 0.0, true, false, 0.0, ["face", "head_back", "boots"]],
	"ride": ["running", 16.0, 0.0, 0.0, 0.0, 0.0, true, false, 0.0, ["back", "front", "chase"]],
	"tuck": ["running", 30.0, 0.0, 0.0, 1.0, 0.0, true, false, 0.0, ["front", "heel", "chase"]],
	"toe": ["running", 20.0, 0.8, -0.55, 0.0, 0.0, true, false, 0.0, ["back", "front"]],
	"heelcarve": ["running", 20.0, -0.8, 0.55, 0.0, 0.0, true, false, 0.0, ["back", "heel"]],
	"brake": ["running", 12.0, 0.0, 0.0, 0.0, 1.0, true, false, 0.0, ["front"]],
	"grab": ["running", 18.0, 0.0, 0.0, 0.0, 0.0, false, true, 0.0, ["front", "back"]],
	"air": ["running", 18.0, 0.0, 0.0, 0.0, 0.0, false, false, 0.0, ["front"]],
}
var game: Node3D
var rider: SnowRider
var cam: Camera3D
var suffix := ""

func _initialize() -> void: go.call_deferred()

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	var chase: Node = game.get_node("ChaseCamera")
	DirAccess.make_dir_recursive_absolute("res://work/studio")
	var wanted: Array = Array(OS.get_cmdline_user_args())
	if "--night" in wanted:
		wanted.erase("--night")
		suffix = "_night"
		rider.run.settings_path = "user://test_studio_settings.json"
		rider.run.set_mode("night")
		game.get_node("Mountain").atmosphere.set_mode("night", true)
	game.get_node("Title").dismiss()
	for i in 3: await process_frame
	chase.process_mode = Node.PROCESS_MODE_DISABLED
	rider.process_mode = Node.PROCESS_MODE_DISABLED
	rider.visual.process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.fov = 40.0
	game.add_child(cam)
	cam.make_current()
	var z := 30.0 * SnowMountain.DISTANCE_SCALE
	rider.position = Vector3(0.0, SnowMountain.height_at(0.0, z) + 0.7, z)
	var up := SnowMountain.normal_at(0.0, z)
	for name in POSES:
		if not wanted.is_empty() and not name in wanted:
			continue
		var p: Array = POSES[name]
		rider.run.state = p[0]
		rider.speed = p[1]
		rider.steer = p[2]
		rider.yaw_rate = p[3]
		rider.tuck_input = p[4]
		rider.brake_input = p[5]
		rider.ground_contact = p[6]
		rider.pop_time = 1.0
		rider.land_time = 10.0
		rider.ollie_preload = p[8]
		if p[7]: Input.action_press("grab")
		else: Input.action_release("grab")
		for i in 90:
			rider.visual.update_pose(1.0 / 60.0, rider.basis_for(up, 0.0), p[6])
		for view in p[9]:
			var v: Array = VIEWS[view]
			var target := rider.global_position + Vector3(0, v[1], 0) if not v[1] is String else (rider.visual.parts[v[1]] as Node3D).global_position
			cam.global_position = (rider.global_position if not v[1] is String else target) + v[0]
			cam.look_at(target, Vector3.UP)
			for i in 3:
				rider.visual.update_pose(1.0 / 60.0, rider.basis_for(up, 0.0), p[6])
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://work/studio/%s_%s%s.png" % [name, view, suffix])
			print("STUDIO ", name, " ", view)
	Input.action_release("grab")
	rider.run.state = "ready"
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("test_studio_settings.json"))
	quit()
