extends SceneTree
func _initialize() -> void: go.call_deferred()
func go() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var rider: SnowRider = game.get_node("Rider")
	var camera: SnowCamera = game.get_node("ChaseCamera")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(3840,2160)
	viewport.world_3d = root.world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(viewport)
	var bench_camera := Camera3D.new()
	viewport.add_child(bench_camera)
	bench_camera.current = true
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	# Bench-only overrides; shipped settings stay fullscreen/VSync/60.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mountain: SnowMountain = game.get_node("Mountain")
	var top := SnowMountain.spawn_point()
	# Summit, then the north, east, south and west faces (azimuth, distance).
	for spot in [[0.0, 0.0], [0.0, 2500.0], [95.0, 5500.0], [180.0, 3000.0], [260.0, 3500.0]]:
		var a := deg_to_rad(spot[0])
		var p := top + Vector3(sin(a), 0, -cos(a)) * float(spot[1])
		mountain.prepare(p)
		var x := p.x
		var z := p.z
		rider.position = Vector3(x, SnowMountain.height_at(x,z)+0.7,z)
		rider.grounded_normal = SnowMountain.normal_at(x,z)
		rider.heading = SnowRider.fall_heading(rider.position, 0.0)
		camera.reset()
		for i in 40:
			await process_frame
			bench_camera.global_transform = camera.global_transform
			bench_camera.fov = camera.fov
			bench_camera.far = camera.far
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://work/pass3_%d.png" % int(z))
		var samples: Array[float] = []
		var gpu_samples: Array[float] = []
		var begin := Time.get_ticks_usec()
		for i in 120:
			var before := Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			samples.append(float(Time.get_ticks_usec()-before)/1000.0)
			gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		var average := float(Time.get_ticks_usec()-begin)/120000.0
		samples.sort()
		gpu_samples.sort()
		print("BENCH region=",SnowMountain.region(x, z)," explicit_4k_target=",viewport.size," mean_frame_ms=",average," p95_frame_ms=",samples[114]," gpu_median_ms=",gpu_samples[60]," gpu_p95_ms=",gpu_samples[114]," calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# Look along the north face from the summit with a manual orbit.
	rider.position = top + Vector3(0, 0.7, 0)
	camera.reset()
	camera.look_yaw = PI * 0.5
	camera.lift = 0.65
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/pass3_gorge.png")
	camera.look_yaw = PI
	camera.lift = 0.2
	camera.idle = 0
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/pass3_behind.png")
	for child in game.get_children():
		if child is SnowPauseMenu: child.show_menu()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/pass3_pause.png")
	paused = false
	viewport.queue_free()
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	quit()

