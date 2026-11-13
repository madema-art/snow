extends SceneTree
## Render-cost probe: startup generation time, then per-region draw calls,
## primitives and visible objects for the REAL chase-camera view at the window
## resolution (run with --resolution 3840x2160 for 4K counts). Counts are
## hardware-independent; frame times are only meaningful on the target GPU, so
## the probe labels them with the active renderer/device.
##   godot --path . --resolution 3840x2160 --script res://tests/perf_probe.gd
## [label, azimuth deg from the summit (0 = north), distance from the summit (m)]
const SPOTS := [["Summit", 180.0, 0.0], ["North face", 0.0, 2500.0], ["East forest", 95.0, 5500.0],
	["South snowfields", 180.0, 3000.0], ["West ravines", 260.0, 3500.0], ["South valley", 185.0, 9800.0]]

func _initialize() -> void: go.call_deferred()

func go() -> void:
	var t0 := Time.get_ticks_msec()
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var startup := Time.get_ticks_msec() - t0
	var rider: SnowRider = game.get_node("Rider")
	var camera: SnowCamera = game.get_node("ChaseCamera")
	Engine.max_fps = 0
	print("PERF device=", RenderingServer.get_video_adapter_name(), " driver=", RenderingServer.get_current_rendering_driver_name(), " size=", root.get_visible_rect().size, " startup_ms=", startup)
	for spot in SPOTS:
		rider.reset()
		var top := SnowMountain.spawn_point()
		var az := deg_to_rad(float(spot[1]))
		var p := top + Vector3(sin(az), 0, -cos(az)) * float(spot[2])
		if float(spot[2]) > 0.0:
			game.get_node("Mountain").prepare(p)
			rider.position = Vector3(p.x, SnowMountain.height_at(p.x, p.z) + 0.7, p.z)
			rider.heading = SnowRider.fall_heading(rider.position, 0.0)
			rider.velocity = rider.forward() * 30.0
			rider.speed = 30.0
		camera.reset()
		for i in 12:
			await physics_frame
			await process_frame
		var calls := 0.0
		var prims := 0.0
		var objects := 0.0
		var cpu := 0.0
		var phys := 0.0
		var n := 6
		for i in n:
			await RenderingServer.frame_post_draw
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			await process_frame
		print("PERF region=%s draw_calls=%d primitives=%d objects=%d process_ms=%.2f physics_ms=%.2f" % [spot[0], calls / n, prims / n, objects / n, cpu / n, phys / n])
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	quit()
