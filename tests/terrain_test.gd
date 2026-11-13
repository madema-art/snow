extends SceneTree
## Terrain and streaming fixtures on the 360-degree mountain (LOCAL fixtures,
## explicitly NOT the whole-run navigation proof, which is mountain_test.gd).
##   godot --headless --path . --fixed-fps 60 --script res://tests/terrain_test.gd
var failures := 0
func _initialize() -> void: go.call_deferred()
func check(value: bool, message: String) -> void:
	print("PASS: " if value else "FAIL: ", message)
	if not value: failures += 1

func go() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var rider: SnowRider = game.get_node("Rider")
	var mountain: SnowMountain = game.get_node("Mountain")
	for child in game.get_children():
		if child is SnowControls:
			child.bindings = SnowControls.DEFAULTS.duplicate(true)
			child.apply_bindings()
	var run := rider.run
	run.records_path = "user://test_terrain_unused.json"
	run.settings_path = "user://test_terrain_settings.json"
	for i in 2: await physics_frame
	var top := SnowMountain.spawn_point()

	# 1. Render triangles == collision triangles: a ray onto the streamed L0 mesh
	# lands within centimetres of the analytic surface at grid vertices.
	var worst := 0.0
	var space := rider.get_world_3d().direct_space_state
	for k in 40:
		var x := snappedf(top.x + randf_range(-500.0, 500.0), SnowMountain.STEP) + fposmod(-SnowMountain.extent, SnowMountain.STEP)
		var z := snappedf(top.z + randf_range(-500.0, 500.0), SnowMountain.STEP) + fposmod(-SnowMountain.extent, SnowMountain.STEP)
		var h := SnowMountain.height_at(x, z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, h + 30, z), Vector3(x, h - 30, z), 1))
		if not hit.is_empty():
			worst = maxf(worst, absf(hit["position"].y - h))
	check(worst < 0.05, "collision mesh vertices sit on the analytic terrain (worst %.3f m)" % worst)

	# 2. Tile seams: a 40 m/s run straight across an L0 tile boundary keeps its
	# momentum (no seam losses, no fall-through).
	var seam_found := Vector3.INF
	for d in range(300, 4000, 20):
		var q := top + Vector3(0, 0, 1) * d
		var n := SnowMountain.normal_at(q.x, q.z)
		var gz := fposmod(q.z + SnowMountain.extent, SnowMountain.TILE)
		if gz > SnowMountain.TILE - 70.0 and n.y > 0.93 and n.y < 0.98 and SnowMountain.forest_amount(q.x, q.z) < 0.05 and SnowMountain.cliff_amount(q.x, q.z) < 0.05:
			seam_found = q
			break
	if seam_found != Vector3.INF:
		run.restart()
		run.push_off()
		mountain.prepare(seam_found)
		rider.position = Vector3(seam_found.x, rider.ground_y(seam_found.x, seam_found.z) + 0.75, seam_found.z)
		rider.heading = 0.0
		rider.velocity = Vector3(0, -4, 40)               # FIXTURE: fast, straight across the seam
		var start_tile := SnowMountain.tile_of(rider.position)
		var speeds: Array[float] = []
		var crossed := -1
		for i in 120:
			await physics_frame
			speeds.append(rider.speed)
			if crossed < 0 and SnowMountain.tile_of(rider.position) != start_tile:
				crossed = i
		# Compare the speed change across the seam with the change just before it
		# (drag and gravity act the same; a seam would add a sudden loss).
		var across := speeds[mini(crossed + 3, 119)] - speeds[maxi(crossed - 3, 0)] if crossed >= 3 else -99.0
		var before := speeds[maxi(crossed - 3, 0)] - speeds[maxi(crossed - 9, 0)] if crossed >= 9 else 0.0
		check(crossed >= 0 and rider.recovery == 0.0 and across > before - 1.0 and rider.position.y > SnowMountain.height_at(rider.position.x, rider.position.z) - 1.0, "crossing a tile seam at 40 m/s keeps momentum (%.2f m/s across the seam vs %.2f just before)" % [across, before])
	else:
		check(false, "found an open slope across a tile seam for the fixture")

	# 3. Streaming follows the rider in any direction: collision appears ahead
	# before the rider gets there, whichever way it travels.
	var ok := true
	for az in [0.0, 90.0, 180.0, 270.0, 45.0]:
		var a := deg_to_rad(az)
		var p := top + Vector3(sin(a), 0, -cos(a)) * 3000.0
		mountain.prepare(p)
		var centre := SnowMountain.tile_of(p)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if not mountain.l0.has(centre + Vector2i(dx, dz)):
					ok = false
	check(ok, "the 3x3 collision tiles stream around the rider in every direction")
	check(mountain.l0.size() <= 30, "streaming keeps memory bounded (%d collision tiles loaded)" % mountain.l0.size())
	# Riding a long way: streaming keeps up without synchronous builds or long frames.
	run.restart()
	var syncs: int = mountain.stream_stats["sync_builds"]
	mountain.stream_stats["max_frame_ms"] = 0.0
	run.push_off()
	var far_start := top + Vector3(0, 0, 1) * 1200.0
	mountain.prepare(far_start)
	rider.position = Vector3(far_start.x, rider.ground_y(far_start.x, far_start.z) + 0.75, far_start.z)
	rider.heading = 0.0
	var crossed_tiles := {}
	for i in 1500:
		rider.velocity = Vector3(0, minf(rider.velocity.y, 0.0), 42.0)   # FIXTURE: hold 42 m/s due south
		rider.recovery = 0.0
		await physics_frame
		await process_frame
		crossed_tiles[SnowMountain.tile_of(rider.position)] = true
	print("STREAM ride tiles=", crossed_tiles.size(), " stats=", mountain.stream_stats)
	check(crossed_tiles.size() >= 3 and mountain.stream_stats["sync_builds"] == syncs, "at 42 m/s the streamer stays ahead of the rider (%d tiles, no emergency builds)" % crossed_tiles.size())
	print("STREAM stats=", mountain.stream_stats)

	# 4. Natural kickers: open slopes carry wind-drift rollers, so a fast rider
	# going straight leaves the snow somewhere on the south snowfields.
	run.restart()
	run.push_off()
	var airtime := 0.0
	for dist in [1500.0, 2200.0, 2900.0, 3600.0]:
		run.restart()
		run.push_off()
		var start: Vector3 = top + Vector3(0, 0, 1) * dist
		mountain.prepare(start)
		rider.position = Vector3(start.x, rider.ground_y(start.x, start.z) + 0.75, start.z)
		var fall := SnowRider.fall_dir(rider.position)
		rider.heading = atan2(fall.x, fall.z)
		rider.velocity = fall * 30.0                      # FIXTURE: carrying speed down the fall line
		var travelled := 0.0
		var last := rider.position
		for i in 600:
			await physics_frame
			travelled += last.distance_to(rider.position)
			last = rider.position
			if rider.air_time > airtime:
				airtime = rider.air_time
			if rider.recovery > 0.0 or run.state != "running":
				break
		print("ROLLERS from %.0f m: travelled %.0f m, best air %.2f s, end=%s reason=%s" % [dist, travelled, airtime, run.state, rider.last_crash_reason])
	check(airtime > 0.25, "rollers on the open south face launch a fast rider (%.2f s of air)" % airtime)

	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	for path in ["user://test_terrain_unused.json", "user://test_terrain_settings.json"]:
		DirAccess.remove_absolute(path)
	print("TERRAIN TESTS failures=", failures)
	quit(0 if failures == 0 else 1)
