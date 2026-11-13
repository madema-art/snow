extends SceneTree
## WHOLE-MOUNTAIN PROOF on the 360-degree massif (course massif_v4).
##
## For each compass sector the bot starts on the summit, aims the board with the
## LEFT STICK (the clock must not run), pushes off with A and rides to the bottom
## using ordinary inputs only: steer, brake, tuck (+ ollie/spin/grab/nitro with
## --tricks). It may READ the world to plan (route knowledge: a Dijkstra route
## over a 50 m grid that avoids cliff cells, never climbs, and stays in its
## sector) and to avoid hazards it sees, but it never writes position, velocity,
## heading, nitro or the clock, and never removes hazards.
##   godot --headless --path . --fixed-fps 60 --script res://tests/mountain_test.gd [-- --cautious | --tricks | --camera-only | --sectors N,E,...]
var failures := 0
var game: Node3D
var rider: SnowRider
var run: SnowRun
var camera: SnowCamera
var menu: SnowPauseMenu
var mountain: SnowMountain
var cautious: bool = "--cautious" in OS.get_cmdline_user_args()
var tricks: bool = "--tricks" in OS.get_cmdline_user_args()
const SECTORS := {"N": 0.0, "NE": 45.0, "E": 90.0, "SE": 135.0, "S": 180.0, "SW": 225.0, "W": 270.0, "NW": 315.0}
const GRID := 50.0
const GRID_HALF := 11000.0
var gn := 0
var gh := PackedFloat32Array()
var gcliff := PackedByteArray()
var gforest := PackedFloat32Array()
var gfinish := PackedByteArray()
var route := PackedVector2Array()
var route_index := 0
var stall_frames := 0
var replan_cooldown := 0
var stall_exit := Vector2.ZERO
var trick_phase := ""
var trick_timer := 0
var trick_cooldown := 0
var trick_index := 0
var nitro_earned := 0.0
var boost_frames := 0
var tricks_landed := 0
var obstacles: Array[Vector4] = []
var obstacle_timer := 0

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

## Board heading (radians, +Z = 0) that faces a compass azimuth in degrees (0 = north).
static func heading_for(azimuth_deg: float) -> float:
	var a := deg_to_rad(azimuth_deg)
	return atan2(sin(a), -cos(a))

## Restart, then turn the board on the summit with the left stick only.
func aim(azimuth_deg: float) -> bool:
	clear_inputs()
	menu.restart()
	await step()
	var want := heading_for(azimuth_deg)
	for i in 600:
		var error := wrapf(want - rider.heading, -PI, PI)
		if absf(error) < 0.04:
			break
		# Positive steer turns the board clockwise from above (heading decreases).
		var stick := clampf(-error * 2.0, -1.0, 1.0)
		if absf(stick) < 0.35: stick = 0.35 * signf(stick)
		Input.action_press("steer_right", maxf(stick, 0.0))
		Input.action_press("steer_left", maxf(-stick, 0.0))
		await step()
	clear_inputs()
	for i in 10: await step()
	return absf(wrapf(want - rider.heading, -PI, PI)) < 0.2 and run.elapsed == 0.0 and run.state == "ready"

func push_off() -> void:
	Input.action_press("jump")
	await step()
	await step()
	Input.action_release("jump")

# ------------------------------------------------------------------ route planning
func build_grid() -> void:
	var t0 := Time.get_ticks_msec()
	var top := SnowMountain.spawn_point()
	gn = int(GRID_HALF * 2.0 / GRID) + 1
	gh.resize(gn * gn)
	gcliff.resize(gn * gn)
	gforest.resize(gn * gn)
	gfinish.resize(gn * gn)
	for j in gn:
		for i in gn:
			var x := top.x - GRID_HALF + i * GRID
			var z := top.z - GRID_HALF + j * GRID
			var h := SnowMountain.height_at(x, z)
			var k := j * gn + i
			gh[k] = h
			# A cell is a cliff if any short step around it is steeper than ~45 deg.
			var steep := 0.0
			for d in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20), Vector2(14, 14), Vector2(-14, -14), Vector2(14, -14), Vector2(-14, 14)]:
				steep = maxf(steep, absf(h - SnowMountain.height_at(x + d.x, z + d.y)) / d.length())
			gcliff[k] = 1 if steep > 1.0 else 0
			gforest[k] = SnowMountain.tree_density(x, z)
			gfinish[k] = 1 if SnowMountain.at_bottom(Vector3(x, h, z)) else 0
	print("GRID n=", gn, " ms=", Time.get_ticks_msec() - t0)

func cell_of(p: Vector3) -> Vector2i:
	var top := SnowMountain.spawn_point()
	return Vector2i(clampi(int(round((p.x - top.x + GRID_HALF) / GRID)), 0, gn - 1), clampi(int(round((p.z - top.z + GRID_HALF) / GRID)), 0, gn - 1))

func cell_pos(k: int) -> Vector2:
	var top := SnowMountain.spawn_point()
	return Vector2(top.x - GRID_HALF + (k % gn) * GRID, top.z - GRID_HALF + (k / gn) * GRID)

## Dijkstra from `from` to the nearest valley-floor cell, never climbing and
## never entering a cliff cell, penalised for leaving the sector.
func plan(from: Vector3, azimuth_deg: float) -> PackedVector2Array:
	return plan_with(from, azimuth_deg, false)

func plan_with(from: Vector3, azimuth_deg: float, buffered: bool) -> PackedVector2Array:
	var top := SnowMountain.spawn_point()
	var target := deg_to_rad(azimuth_deg)
	var dist := PackedFloat32Array()
	dist.resize(gn * gn)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(gn * gn)
	prev.fill(-1)
	var heap_k := PackedInt32Array()
	var heap_d := PackedFloat32Array()
	var start_cell := cell_of(from)
	var s := start_cell.y * gn + start_cell.x
	dist[s] = 0.0
	heap_push(heap_k, heap_d, s, 0.0)
	var goal := -1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	while heap_k.size() > 0:
		var k := heap_k[0]
		var d := heap_d[0]
		heap_pop(heap_k, heap_d)
		if d > dist[k]:
			continue
		if gfinish[k] == 1:
			goal = k
			break
		var ci := k % gn
		var cj := k / gn
		for dv in dirs:
			var ni: int = ci + dv.x
			var nj: int = cj + dv.y
			if ni < 0 or nj < 0 or ni >= gn or nj >= gn:
				continue
			var nk := nj * gn + ni
			if gcliff[nk] == 1:
				continue
			# Never squeeze diagonally between two cliff cells.
			if dv.x != 0 and dv.y != 0 and (gcliff[cj * gn + ni] == 1 or gcliff[nj * gn + ci] == 1):
				continue
			var near_cliff := 0.0
			for dv2 in dirs:
				var mi: int = ni + dv2.x
				var mj: int = nj + dv2.y
				if mi >= 0 and mj >= 0 and mi < gn and mj < gn and gcliff[mj * gn + mi] == 1:
					near_cliff = 3.0
					break
			# Keep a cell of clearance from cliff edges where the mountain allows.
			if buffered and near_cliff > 0.0 and k != s:
				continue
			var length := GRID * (1.4142 if dv.x != 0 and dv.y != 0 else 1.0)
			var dh := gh[nk] - gh[k]
			# A board must keep descending: tiny rises only, and near-flat ground
			# (where it would coast to a stop) costs extra.
			if dh > 1.5:
				continue
			var flat_penalty := 2.0 if -dh < length * 0.08 else 0.0
			var p := cell_pos(nk)
			var az := atan2(p.x - top.x, -(p.y - top.z))
			var off := absf(wrapf(az - target, -PI, PI))
			var cost := length * (1.0 + near_cliff + flat_penalty + 1.6 * gforest[nk] + maxf(0.0, off - deg_to_rad(40.0)) * 4.0) + maxf(0.0, dh) * 40.0
			var nd := d + cost
			if nd < dist[nk]:
				dist[nk] = nd
				prev[nk] = k
				heap_push(heap_k, heap_d, nk, nd)
	var reached := 0
	for v in dist:
		if v < INF: reached += 1
	print("PLAN az=", azimuth_deg, " buffered=", buffered, " reached=", reached, " goal=", goal, " cost=", dist[goal] if goal >= 0 else -1.0)
	var path := PackedVector2Array()
	var k := goal
	while k != -1:
		path.append(cell_pos(k))
		k = prev[k]
	path.reverse()
	# Smooth the grid zig-zags into a riding line (Chaikin corner cutting).
	for pass_i in 2:
		if path.size() < 3:
			break
		var smooth := PackedVector2Array([path[0]])
		for i in path.size() - 1:
			smooth.append(path[i].lerp(path[i + 1], 0.25))
			smooth.append(path[i].lerp(path[i + 1], 0.75))
		smooth.append(path[path.size() - 1])
		path = smooth
	# Run a little further onto the floor so the finish is reached riding.
	if path.size() >= 2:
		var last := path[path.size() - 1]
		path.append(last + (last - path[path.size() - 2]).normalized() * 150.0)
	return path

func heap_push(keys: PackedInt32Array, vals: PackedFloat32Array, key: int, val: float) -> void:
	keys.append(key)
	vals.append(val)
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if vals[parent] <= vals[i]:
			break
		var tk := keys[parent]; keys[parent] = keys[i]; keys[i] = tk
		var tv := vals[parent]; vals[parent] = vals[i]; vals[i] = tv
		i = parent

func heap_pop(keys: PackedInt32Array, vals: PackedFloat32Array) -> void:
	var last := keys.size() - 1
	keys[0] = keys[last]
	vals[0] = vals[last]
	keys.resize(last)
	vals.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and vals[l] < vals[m]: m = l
		if r < last and vals[r] < vals[m]: m = r
		if m == i:
			break
		var tk := keys[m]; keys[m] = keys[i]; keys[i] = tk
		var tv := vals[m]; vals[m] = vals[i]; vals[i] = tv
		i = m

# ------------------------------------------------------------------ driving
func drive(azimuth_deg: float) -> void:
	var p2 := Vector2(rider.position.x, rider.position.z)
	# Progress along the route: nearest point ahead of the current index.
	var best := route_index
	var best_d := INF
	for i in range(route_index, mini(route_index + 160, route.size())):
		var d := route[i].distance_to(p2)
		if d < best_d:
			best_d = d
			best = i
	route_index = best
	replan_cooldown -= 1
	if best_d > 160.0 and rider.recovery <= 0.0 and rider.is_on_floor() and replan_cooldown <= 0:
		replan_cooldown = 180
		var fresh := plan(rider.position, azimuth_deg)
		if fresh.size() >= 2:
			route = fresh
		route_index = 0
		print("REPLAN at ", rider.position, " points=", route.size())
	var ahead := clampi(int((30.0 + rider.speed * 1.4) / (GRID * 0.25)) + 1, 2, 16)
	var target: Vector2 = route[mini(route_index + ahead, route.size() - 1)]
	# Upcoming bend: slow down for it like a rider reading the line.
	var bend := 0.0
	if route_index + 16 < route.size():
		var a := (route[route_index + 8] - route[route_index]).normalized()
		var b := (route[mini(route_index + 20, route.size() - 1)] - route[route_index + 8]).normalized()
		bend = acos(clampf(a.dot(b), -1.0, 1.0))
	var target_speed := (27.0 if cautious else 36.0) - bend * (10.0 if cautious else 12.0)
	var trees_here := SnowMountain.tree_density(rider.position.x, rider.position.z)
	if trees_here > 0.25:
		target_speed = minf(target_speed, lerpf(27.0, 19.0, clampf((trees_here - 0.25) / 0.5, 0.0, 1.0)) - (5.0 if cautious else 0.0))
	# Local avoidance of the trees and rocks the bot can see.
	obstacle_timer -= 1
	if obstacle_timer <= 0:
		obstacles = mountain.hazards_near(rider.position, 90.0)
		obstacle_timer = 6
	var to_target := (target - p2)
	var fwd := to_target.normalized() if to_target.length() > 1.0 else Vector2(sin(rider.heading), cos(rider.heading))
	var right := Vector2(-fwd.y, fwd.x)
	var nearest := INF
	var dodge := Vector2.ZERO
	for h in obstacles:
		var rel := Vector2(h.x, h.z) - p2
		var along := rel.dot(fwd)
		if along < -2.0 or along > 30.0 + rider.speed:
			continue
		var lateral := rel.dot(right)
		if absf(lateral) < h.w + 3.0 and along < nearest:
			nearest = along
			var side := -1.0 if lateral > 0.0 else 1.0
			dodge = Vector2(h.x, h.z) + right * side * (h.w + 5.0)
	if nearest < INF:
		target = dodge
		if nearest < 25.0:
			target_speed = minf(target_speed, 20.0)
	if tricks:
		drive_tricks(nearest == INF and bend < 0.25)
	# Stalled (flat bench, against something): point down the fall line and push.
	if rider.speed < 2.0 and rider.recovery <= 0.0 and rider.is_on_floor():
		stall_frames += 1
	elif rider.speed > 6.0 or rider.recovery > 0.0:
		stall_frames = 0
	if stall_frames == 46:
		# Look around for the lowest way out (towards the route where possible),
		# then commit to it until moving again.
		var lowest := INF
		for k in 24:
			var a := TAU * k / 24.0
			for r: float in [30.0, 70.0]:
				var probe: Vector2 = p2 + Vector2(sin(a), cos(a)) * r
				var score: float = SnowMountain.height_at(probe.x, probe.y) - (probe - p2).normalized().dot((target - p2).normalized()) * 4.0
				if score < lowest:
					lowest = score
					stall_exit = p2 + (probe - p2).normalized() * 200.0
	if stall_frames == 360:
		var fresh := plan(rider.position, azimuth_deg)
		if fresh.size() >= 2:
			route = fresh
			route_index = 0
			print("REPLAN (stalled) at ", rider.position)
	if stall_frames > 45 and stall_frames < 360:
		target = stall_exit
	if stall_frames > 45:
		if stall_frames % 20 == 0: Input.action_press("jump")
		elif stall_frames % 20 == 2: Input.action_release("jump")
	if stall_frames > 900:
		stall_frames = 40
	var desired := atan2(target.x - p2.x, target.y - p2.y)
	# Read the ground ahead like a rider would: never ride off a drop. Pick the
	# heading closest to the plan that has no cliff edge in the next 20-90 m.
	var from_top := Vector2(rider.position.x - SnowMountain.summit.x, rider.position.z - SnowMountain.summit.z).length()
	if rider.is_on_floor() and rider.recovery <= 0.0 and rider.speed > 4.0 and from_top > 400.0:
		var safe := desired
		var found := false
		var least := INF
		for offset in [0.0, 0.25, -0.25, 0.5, -0.5, 0.8, -0.8, 1.15, -1.15, 1.5, -1.5, 1.9, -1.9]:
			var drop := cliff_ahead(desired + offset)
			if drop <= 0.0:
				safe = desired + offset
				found = true
				break
			if drop < least:
				least = drop
				safe = desired + offset
		if not found:
			target_speed = minf(target_speed, 8.0)   # no clean way: traverse slowly along the least drop
		elif absf(offset_of(safe, desired)) > 0.7:
			target_speed = minf(target_speed, 18.0)
		desired = safe
	var error := wrapf(desired - rider.heading, -PI, PI)
	# Like a careful human the bot never holds the stick at full lock (over-lean).
	var steer := clampf(-error * 2.8, -0.8, 0.8)
	Input.action_press("steer_right", maxf(steer, 0))
	Input.action_press("steer_left", maxf(-steer, 0))
	var brake := clampf((rider.speed - target_speed) * 0.22 + maxf(0, absf(error) - 0.35) * 0.5, 0, 0.85)
	# Scrub speed into a sharp turn instead of carving it flat out (edge catch).
	if absf(error) > 0.5 and rider.speed > 18.0:
		brake = maxf(brake, 0.3)
	Input.action_press("brake", brake)
	Input.action_press("tuck", 1.0 if rider.speed < target_speed - 0.5 and absf(error) < 0.18 else 0.0)

## The size of the drop (steeper than ~45 degrees, over 6 m) along this heading
## within stopping distance, or 0 if none. The bot may read the terrain it sees.
func cliff_ahead(heading: float) -> float:
	var dir := Vector2(sin(heading), cos(heading))
	var p := Vector2(rider.position.x, rider.position.z)
	var h0 := SnowMountain.height_at(p.x, p.y)
	var reach := clampf(20.0 + rider.speed * 2.0, 30.0, 95.0)
	var n0 := SnowMountain.normal_at(p.x, p.y)
	var along_grade := -Vector2(n0.x, n0.z).dot(dir) / maxf(n0.y, 0.2)   # current slope along this heading
	var d := 8.0
	var prev := h0
	while d <= reach:
		var q := p + dir * d
		var h := SnowMountain.height_at(q.x, q.y)
		# Lips and gully rims: the ground falls away far below the line we ride.
		if rider.speed > 20.0 and (h0 - d * along_grade) - h > 30.0 and h0 - h > 30.0:
			return (h0 - h) * (1.0 + (reach - d) / reach)
		# Only real drops matter (a rider survives small steps and gully walls).
		if prev - h > 8.0 * 1.05 + 1.5 and h0 - h > 18.0:
			return (h0 - h) * (1.0 + (reach - d) / reach)
		prev = h
		d += 8.0
	return 0.0

static func offset_of(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)

## Ollie + spin/grab on open, straight snow; spend nitro on clear terrain.
func drive_tricks(open_ahead: bool) -> void:
	trick_cooldown -= 1
	var open := SnowMountain.forest_amount(rider.position.x, rider.position.z) < 0.15 and SnowMountain.cliff_amount(rider.position.x, rider.position.z) < 0.2
	match trick_phase:
		"":
			Input.action_release("spin_right")
			Input.action_release("grab")
			if open and open_ahead and rider.is_on_floor() and rider.recovery <= 0.0 and rider.speed > 16.0 and trick_cooldown <= 0:
				trick_phase = "preload"
				trick_timer = 14
				Input.action_press("jump")
		"preload":
			trick_timer -= 1
			if trick_timer <= 0:
				Input.action_release("jump")
				trick_phase = "air"
				trick_timer = 0
		"air":
			trick_timer += 1
			var kind := trick_index % 3
			if kind != 1 and rider.spin > -PI * 0.92:
				Input.action_press("spin_right")
			else:
				Input.action_release("spin_right")
			if kind != 0 and trick_timer > 4:
				Input.action_press("grab")
			if rider.is_on_floor() and trick_timer > 6 or rider.recovery > 0.0 or trick_timer > 240:
				Input.action_release("spin_right")
				Input.action_release("grab")
				trick_phase = ""
				trick_index += 1
				trick_cooldown = 150
	var boost := rider.nitro > 0.05 and trick_phase == "" and open_ahead and open and rider.is_on_floor()
	if boost:
		Input.action_press("boost")
		boost_frames += 1
	else:
		Input.action_release("boost")

## One full descent in a sector. Returns a summary dictionary.
func descend(name: String, azimuth_deg: float) -> Dictionary:
	var aimed := await aim(azimuth_deg)
	check(aimed, "%s: the left stick turns the board on the summit to face %s while the clock stays at zero" % [name, name])
	var top := rider.position
	route = plan(rider.position + Vector3(sin(deg_to_rad(azimuth_deg)), 0, -cos(deg_to_rad(azimuth_deg))) * 220.0, azimuth_deg)
	route.insert(0, Vector2(top.x, top.z))
	route_index = 0
	if route.size() < 3:
		check(false, "%s: a route to the valley exists" % name)
		return {}
	await push_off()
	var crashes := 0
	var distance := 0.0
	var max_speed := 0.0
	var previous := rider.position
	var was_recovering := false
	var moving_at := -1.0
	var camera_aligned := 0
	var camera_samples := 0
	for i in 36000:
		drive(azimuth_deg)
		await step()
		distance += previous.distance_to(rider.position)
		previous = rider.position
		max_speed = maxf(max_speed, rider.speed)
		if moving_at < 0.0 and rider.speed > 8.0:
			moving_at = run.elapsed
		if rider.recovery > 0.0 and not was_recovering:
			crashes += 1
		was_recovering = rider.recovery > 0.0
		# The chase camera follows the actual direction of travel, whatever it is.
		if i % 120 == 60 and rider.speed > 12.0 and rider.recovery <= 0.0 and rider.is_on_floor():
			camera_samples += 1
			var view := -camera.global_basis.z
			var travel := Vector3(rider.velocity.x, 0, rider.velocity.z).normalized()
			if Vector2(view.x, view.z).normalized().dot(Vector2(travel.x, travel.z)) > 0.8:
				camera_aligned += 1
		if i % 3600 == 0:
			print("  %s t=%.0f p=%s speed=%.1f h=%.0f recovery=%.1f l0=%d" % [name, run.elapsed, rider.position, rider.speed, rider.position.y, rider.recovery, mountain.l0.size()])
		if run.state != "running":
			break
	clear_inputs()
	var face: String = run.record_faces[run.last_rank] if run.last_rank >= 0 and run.last_rank < run.record_faces.size() else ""
	var result := {"state": run.state, "time": run.elapsed, "distance": distance, "max_speed": max_speed, "crashes": crashes, "face": face, "end": rider.position, "drop": top.y - rider.position.y, "moving_at": moving_at, "camera": [camera_aligned, camera_samples]}
	print("SECTOR %s RESULT state=%s time=%.1f distance=%.0f max_speed=%.1f crashes=%d drop=%.0f face=%s end=%s camera=%d/%d" % [name, run.state, run.elapsed, distance, max_speed, crashes, top.y - rider.position.y, face, rider.position, camera_aligned, camera_samples])
	check(moving_at >= 0.0 and moving_at < 12.0, "%s: gravity takes the board away from the summit (8 m/s after %.1f s)" % [name, moving_at])
	check(run.state == "finished", "%s: ordinary inputs reach the bottom of the mountain" % name)
	var sector_index := int(round(azimuth_deg / 45.0)) % 8
	var face_index := SnowMountain.FACES.find(face)
	check(face_index >= 0 and absi(wrapi(face_index - sector_index, -4, 4)) <= 1, "%s: the run finished on its own side of the mountain (%s valley)" % [name, face])
	check(camera_samples == 0 or camera_aligned >= camera_samples * 0.75, "%s: the chase camera follows the direction of travel (%d/%d)" % [name, camera_aligned, camera_samples])
	return result

func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	rider = game.get_node("Rider")
	camera = game.get_node("ChaseCamera")
	mountain = game.get_node("Mountain")
	for child in game.get_children():
		if child is SnowRun: run = child
		if child is SnowPauseMenu: menu = child
		if child is SnowControls:
			child.bindings = SnowControls.DEFAULTS.duplicate(true)
			child.apply_bindings()
	run.records_path = "user://test_massif_records.json"
	run.settings_path = "user://test_massif_settings.json"
	run.records.clear()
	run.record_faces.clear()
	rider.sound_event.connect(func(kind: String, _strength: float):
		if kind == "charge":
			nitro_earned += rider.last_reward
			tricks_landed += 1
		if kind in ["crash", "fatal"]: print("FALL ", kind, " reason=", rider.last_crash_reason, " p=", rider.position, " t=", run.elapsed))
	# --- camera at the summit -------------------------------------------------
	var old_heading := rider.heading
	var old_velocity := rider.velocity
	for i in 180: camera.orbit_input(1.0 / 60, Vector2(1, 0), false)
	check(absf(camera.orbit) > TAU, "camera continuous full 360 orbit at the summit")
	camera.orbit_input(1.0 / 60, Vector2(1, 0), true)
	check(not camera.recentering, "active manual camera input wins over recenter")
	for i in 90: camera.orbit_input(1.0 / 60, Vector2(0, 1), false)
	check(is_equal_approx(camera.lift, SnowCamera.PITCH_MAX), "camera substantial upper pitch range")
	for i in 90: camera.orbit_input(1.0 / 60, Vector2(0, -1), false)
	check(is_equal_approx(camera.lift, SnowCamera.PITCH_MIN), "camera lower pitch range")
	check(rider.heading == old_heading and rider.velocity == old_velocity, "the camera never turns the board or moves the rider")
	camera.orbit_input(1.0 / 60, Vector2.ZERO, true)
	for i in 120: camera.orbit_input(1.0 / 60, Vector2.ZERO, false)
	var obstruction := StaticBody3D.new()
	obstruction.collision_layer = 2
	camera.reset()
	for i in 3: await step()
	var behind := -rider.forward() * 5.0
	obstruction.position = rider.position + Vector3(0, 2, 0) + behind
	var camera_block := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 1)
	camera_block.shape = box
	obstruction.add_child(camera_block)
	obstruction.look_at_from_position(obstruction.position, rider.position + Vector3(0, 2, 0))
	game.add_child(obstruction)
	camera.reset()
	for i in 3: await step()
	check((camera.global_position - rider.position).dot(-rider.forward()) < 4.5, "camera sphere retracts before an actual obstruction")
	obstruction.queue_free()
	await step()
	if "--camera-only" in OS.get_cmdline_user_args():
		finish()
		return
	build_grid()
	if "--map" in OS.get_cmdline_user_args():
		write_map()
		finish()
		return
	# --- straight lines: point the board and let go ---------------------------
	var straight_clean := 0
	for name in ([] if "--no-straight" in OS.get_cmdline_user_args() else ["N", "E", "S", "W"]):
		await aim(SECTORS[name])
		await push_off()
		var falls := 0
		var was := false
		for i in 12000:
			await step()
			if rider.recovery > 0.0 and not was: falls += 1
			was = rider.recovery > 0.0
			if run.state != "running": break
		print("STRAIGHT %s state=%s time=%.1f falls=%d p=%s" % [name, run.state, run.elapsed, falls, rider.position])
		if run.state == "finished" and falls == 0:
			straight_clean += 1
	check(straight_clean == 0, "riding straight with no input never makes a clean descent: the mountain's hazards meet it")
	# --- every sector ----------------------------------------------------------
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sectors="):
			only = arg.trim_prefix("--sectors=").split(",")
	var times: Array = []
	for name in SECTORS:
		if not only.is_empty() and not name in only:
			continue
		var result := await descend(name, SECTORS[name])
		if result.get("state", "") == "finished":
			times.append(result["time"])
			check(result["drop"] > SnowMountain.FINISH_DROP and result["distance"] > 5000.0, "%s: a real descent (%.0f m down, %.0f m travelled)" % [name, result["drop"], result["distance"]])
	if not times.is_empty():
		times.sort()
		var median: float = times[times.size() / 2]
		print("DESCENT TIMES ", times, " median=", median)
		if cautious:
			check(median >= 280.0 and median <= 560.0, "cautious riding takes longer (median %.0f s)" % median)
		else:
			check(median >= 220.0 and median <= 420.0, "a skilled descent takes about five minutes (median %.0f s)" % median)
	if tricks:
		print("TRICK RESULT rewarded_landings=", tricks_landed, " nitro_earned=", nitro_earned, " boost_seconds=", boost_frames / 60.0)
		check(tricks_landed >= 4 and nitro_earned > 0.3 and boost_frames > 60, "tricks earn nitro that is then spent on real boosts")
	check(run.records.size() >= 1 and run.records.size() <= 10, "finished descents from any side enter one top ten")
	finish()

## Debug picture: shaded height, cliff cells (red), valley floors (blue),
## forest (green) and each sector's planned route (yellow) -> work/route_map.png.
func write_map() -> void:
	var img := Image.create(gn, gn, false, Image.FORMAT_RGB8)
	var top := SnowMountain.spawn_point()
	for j in gn:
		for i in gn:
			var k := j * gn + i
			var shade := clampf((gh[k] - 200.0) / 3600.0, 0.0, 1.0) * 0.6 + 0.3
			if i > 0 and j > 0:
				shade += clampf((gh[k] - gh[k - 1] + gh[k] - gh[k - gn]) * 0.004, -0.25, 0.25)
			var col := Color(shade, shade, shade)
			if gforest[k] > 0.3: col = col.lerp(Color(0.1, 0.45, 0.15), 0.5)
			if gfinish[k] == 1: col = col.lerp(Color(0.2, 0.3, 0.9), 0.6)
			if gcliff[k] == 1: col = col.lerp(Color(0.85, 0.1, 0.1), 0.7)
			img.set_pixel(i, j, col)
	for name in SECTORS:
		var az: float = SECTORS[name]
		var path := plan(top + Vector3(sin(deg_to_rad(az)), 0, -cos(deg_to_rad(az))) * 220.0, az)
		for p in path:
			var c := cell_of(Vector3(p.x, 0, p.y))
			img.set_pixel(c.x, c.y, Color(1, 0.9, 0.1))
		print("MAP ", name, " points=", path.size())
	DirAccess.make_dir_recursive_absolute("res://work")
	img.save_png("res://work/route_map.png")

func finish() -> void:
	clear_inputs()
	paused = false
	game.queue_free()
	await process_frame
	OS.delay_msec(100)
	for path in ["user://test_massif_records.json", "user://test_massif_settings.json"]:
		DirAccess.remove_absolute(path)
	print("MASSIF TESTS failures=", failures)
	quit(0 if failures == 0 else 1)
