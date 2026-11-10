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
	for logical_z in [8.0, 1400.0, 3500.0, 5350.0, 7450.0]:
		var z: float = logical_z * SnowMountain.DISTANCE_SCALE
		var x := -310.0 if logical_z == 1400 else 0.0
		rider.position = Vector3(x, SnowMountain.height_at(x,z)+0.7,z)
		rider.grounded_normal = SnowMountain.normal_at(x,z)
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
		print("BENCH region=",SnowMountain.region(z)," explicit_4k_target=",viewport.size," mean_frame_ms=",average," p95_frame_ms=",samples[114]," gpu_median_ms=",gpu_samples[60]," gpu_p95_ms=",gpu_samples[114]," calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# Look back and down into the real gorge using manual orbit positions.
	rider.position = Vector3(-310, SnowMountain.height_at(-310,1480*SnowMountain.DISTANCE_SCALE)+0.7,1480*SnowMountain.DISTANCE_SCALE)
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

