class_name SnowRider
extends CharacterBody3D
signal sound_event(kind: String, strength: float)
signal reset_performed
@export var gravity := 20.0
@export var ollie_speed := 8.8
@export var edge_grip := 5.2
@export var turn_rate := 1.28
@export var boost_acceleration := 24.0
@export var nitro_burn := 0.25 # Full charge lasts four seconds; releases preserve remainder.
@export var drag := 0.0075 # Quadratic drag gives ~26 m/s on the main grade.
var run: SnowRun
var visual: SnowRiderVisual
var heading := 0.0
var nitro := 0.0
var recovery := 0.0
var recovery_length := 0.0
var steer := 0.0
var speed := 0.0
var boosting := false
var air_time := 0.0
var spin := 0.0
var spin_distance := 0.0
var flip := 0.0
var flip_distance := 0.0
var grabbed := 0.0
var previous_ground := false
var launch_height := 0.0
var safe_position := Vector3.ZERO
var grounded_normal := Vector3.UP
var last_crash_reason := ""

func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	floor_max_angle = deg_to_rad(57.0)
	floor_snap_length = 0.85
	floor_stop_on_slope = false
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.3
	collision.shape = capsule
	add_child(collision)
	visual = SnowRiderVisual.new()
	add_child(visual)
	reset()

func reset() -> void:
	position = Vector3(0, SnowMountain.height_at(0, 8) + 0.7, 8)
	velocity = Vector3.ZERO
	heading = 0.0
	nitro = 0.0
	recovery = 0.0
	recovery_length = 0.0
	speed = 0.0
	boosting = false
	air_time = 0.0
	steer = 0.0
	spin = 0.0
	flip = 0.0
	spin_distance = 0.0
	flip_distance = 0.0
	grabbed = 0.0
	launch_height = position.y
	previous_ground = false
	last_crash_reason = ""
	safe_position = position
	grounded_normal = SnowMountain.normal_at(0, 8)
	if is_instance_valid(visual):
		visual.basis = basis_for(grounded_normal, 0.0)
		visual.body.rotation = Vector3.ZERO
		visual.body.position = Vector3.ZERO
		visual.animate(0, 0, 0, 0, false, 0)
	reset_performed.emit()

func forward() -> Vector3:
	return Vector3(sin(heading), 0, cos(heading))

func basis_for(up: Vector3, yaw: float) -> Basis:
	var z := Vector3(sin(yaw), 0, cos(yaw)).slide(up).normalized()
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x).normalized(), z)

func crash(severity: float, fatal := false) -> void:
	# This invariant applies to every fall, including fatal and landing failures.
	nitro = 0.0
	velocity = Vector3.ZERO
	speed = 0.0
	boosting = false
	visual.animate(0, 0, 0, 0, false, 1)
	launch_height = position.y
	air_time = 0
	spin = 0
	flip = 0
	spin_distance = 0
	flip_distance = 0
	grabbed = 0
	recovery_length = clampf(1.2 + severity * 0.12, 1.2, 7.0)
	recovery = recovery_length
	sound_event.emit("fatal" if fatal else "crash", clampf(severity / 30.0, 0.25, 1.0))
	Input.start_joy_vibration(0, 0.65, 0.9, 0.25)
	if fatal:
		run.fatal()

func landed(impact: float) -> void:
	var yaw_error := absf(wrapf(spin, -PI, PI))
	# A 180 can ride away switch. Incomplete quarter turns catch an edge.
	yaw_error = minf(yaw_error, absf(PI - yaw_error))
	var pitch_error := absf(wrapf(flip, -PI, PI))
	if impact > 24.0 or yaw_error > 0.85 or pitch_error > 0.7:
		last_crash_reason = "landing"
		crash(impact + yaw_error * 8.0)
	else:
		if air_time > 0.25:
			var reward := clampf(0.035 + air_time * 0.025 + floorf(absf(spin) / PI) * 0.13 + floorf(absf(flip) / TAU) * 0.28 + minf(grabbed, 1.5) * 0.1, 0.0, 0.85)
			nitro = minf(1.0, nitro + reward)
			sound_event.emit("charge", reward)
		sound_event.emit("land", clampf(impact / 17.0, 0.15, 1.0))
		Input.start_joy_vibration(0, 0.2, clampf(impact / 24.0, 0, 0.7), 0.12)
	spin = 0.0
	flip = 0.0
	air_time = 0.0
	spin_distance = 0.0
	flip_distance = 0.0
	grabbed = 0.0

func recovery_point(at: Vector3, normal: Vector3) -> Vector3:
	# A clear lateral offset avoids repeatedly getting up directly in front of a tree.
	var side := normal.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = (get_child(0) as CollisionShape3D).shape
	probe.collision_mask = 2
	var base := at + normal * 3.0 - Vector3(0, 0, 3)
	for offset in [3.0, -3.0, 6.0, -6.0, 9.0, -9.0]:
		var candidate: Vector3 = base + side * offset
		candidate.y = SnowMountain.height_at(candidate.x, candidate.z) + 0.72
		if absf(candidate.y - at.y) > 5 or SnowMountain.normal_at(candidate.x, candidate.z).y < 0.75:
			continue
		probe.transform = Transform3D(Basis(), candidate)
		if get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
			return candidate
	return safe_position

func _physics_process(delta: float) -> void:
	var just_pushed_off := false
	if Input.is_action_just_pressed("restart"):
		run.restart()
		reset()
		return
	if run.state == "finished" or run.state == "ended":
		return
	if run.state == "ready":
		if Input.is_action_just_pressed("jump"):
			just_pushed_off = true
			run.push_off()
			velocity = Vector3(0, -1, 3.0)
			sound_event.emit("push", 0.5)
		else:
			update_visual(delta)
			return
	run.tick(delta)
	if recovery > 0.0:
		recovery = maxf(0.0, recovery - delta)
		velocity = Vector3.ZERO
		if recovery == 0.0:
			position = safe_position
			launch_height = position.y
			heading = 0.0
			velocity = Vector3(0, -1, 1.0)
			previous_ground = false
		update_visual(delta)
		return
	steer = lerpf(steer, Input.get_axis("steer_left", "steer_right"), 1.0 - exp(-9.0 * delta))
	speed = Vector2(velocity.x, velocity.z).length()
	# Ignore cached CharacterBody contact from the previous run on the push-off tick.
	var ground := is_on_floor() and not just_pushed_off
	var brake := Input.get_action_strength("brake")
	var tuck := Input.get_action_strength("tuck")
	if ground:
		grounded_normal = get_floor_normal()
		# Looking downhill along +Z, screen-right is world -X.
		heading -= steer * turn_rate * (1.0 / (1.0 + speed / 42.0)) * delta
		var fwd := forward().slide(grounded_normal).normalized()
		var side := grounded_normal.cross(fwd).normalized()
		# Project gravity onto the snow. Lateral edge damping preserves forward inertia.
		# CharacterBody clears vertical velocity on floor contact. Reconstruct the tangent
		# without projecting (and shrinking) the horizontal momentum every physics tick.
		velocity.y = -(velocity.x * grounded_normal.x + velocity.z * grounded_normal.z) / maxf(0.1, grounded_normal.y)
		velocity += Vector3.DOWN.slide(grounded_normal) * gravity * delta
		var lateral := velocity.dot(side)
		velocity -= side * lateral * (1.0 - exp(-edge_grip * (1.0 - brake * 0.65) * delta))
		var resistance := 0.4 + drag * (1.0 - tuck * 0.58) * speed * speed + brake * (9.0 + speed * 0.2) + absf(steer) * speed * 0.018
		velocity = velocity.move_toward(Vector3.ZERO, resistance * delta)
		# Extreme cross-edge sliding at speed can catch the downhill edge.
		if absf(lateral) > 17.0 and speed > 21.0 and brake < 0.2:
			last_crash_reason = "edge catch"
			crash(speed * 0.6)
			update_visual(delta)
			return
		if Input.is_action_just_pressed("jump"):
			velocity += grounded_normal * ollie_speed
			ground = false
			sound_event.emit("ollie", 0.7)
		if ground:
			velocity.y -= 0.35 # Downward contact pressure, without artificial uphill thrust.
	else:
		velocity.y -= gravity * delta
		var spin_input := Input.get_action_strength("spin_right") - Input.get_action_strength("spin_left")
		var amount := -spin_input * 3.7 * delta
		spin += amount
		spin_distance += absf(amount)
		var pitch_amount := Input.get_axis("flip_forward", "flip_back") * 3.1 * delta
		flip += pitch_amount
		flip_distance += absf(pitch_amount)
		if Input.is_action_pressed("grab"):
			grabbed += delta
		air_time += delta
		launch_height = maxf(launch_height, position.y)
	var was_boosting := boosting
	boosting = Input.is_action_pressed("boost") and nitro > 0.0
	if Input.is_action_just_pressed("boost") and nitro <= 0.0:
		sound_event.emit("empty", 1.0)
		Input.start_joy_vibration(0, 0.2, 0.4, 0.18)
	if boosting:
		var spent := minf(nitro, nitro_burn * delta)
		velocity += forward() * boost_acceleration * (spent / nitro_burn)
		nitro -= spent
		if not was_boosting:
			sound_event.emit("boost", 1.0)
		if nitro <= 0.0:
			sound_event.emit("deplete", 0.8)
	var before := velocity
	move_and_slide()
	var snow_contacts_only := true
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var object := hit.get_collider()
		if object is Node and object.has_meta("hazard"):
			snow_contacts_only = false
			var impact := maxf(0.0, -before.dot(hit.get_normal()))
			if impact < 5.0:
				continue
			last_crash_reason = str(object.get_meta("hazard"))
			crash(maxf(4, impact), impact > (30.0 if object.get_meta("hazard") == "tree" else 34.0))
			# Restore to a clear place behind the impact, not inside its collider.
			safe_position = recovery_point(position, hit.get_normal())
			update_visual(delta)
			return
		elif hit.get_normal().y < 0.45 and -before.dot(hit.get_normal()) > 16 and SnowMountain.normal_at(hit.get_position().x, hit.get_position().z).y < 0.65:
			var wall_impact := -before.dot(hit.get_normal())
			last_crash_reason = "rock face"
			crash(wall_impact, wall_impact > 34)
			safe_position = recovery_point(position, hit.get_normal())
			update_visual(delta)
			return
		elif hit.get_normal().y < 0.55 and SnowMountain.normal_at(hit.get_position().x, hit.get_position().z).y < 0.65:
			snow_contacts_only = false
	# Preserve tangent momentum across internal snow triangle seams. CharacterBody's
	# repeated contact resolution can otherwise discard almost all horizontal speed
	# on an innocuous 8 m mesh edge. Never restore through a solid hazard or wall.
	if is_on_floor() and snow_contacts_only:
		var candidate := before + (Vector3.UP * 0.35 if ground else Vector3.ZERO)
		velocity = candidate.slide(get_floor_normal())
	if is_on_floor() and not previous_ground:
		var impact := maxf(0, -before.dot(get_floor_normal()))
		if air_time > 0.3 and launch_height - position.y > 35.0:
			last_crash_reason = "cliff landing"
			crash(50.0, true)
		else:
			landed(impact)
	if not is_on_floor() and previous_ground:
		launch_height = position.y
		sound_event.emit("air", 0.4)
	if is_on_floor() and recovery <= 0:
		safe_position = position
	previous_ground = is_on_floor()
	# Sustained physical fall distance, never an arbitrary coordinate death boundary.
	if not is_on_floor() and air_time > 1 and launch_height - position.y > 55 and velocity.y < -20:
		last_crash_reason = "cliff fall"
		crash(50.0, true)
	if position.z >= SnowMountain.FINISH and absf(position.x) < 50.0 and is_on_floor() and recovery <= 0:
		velocity = Vector3.ZERO
		run.finish()
	update_visual(delta)

func update_visual(delta: float) -> void:
	var up := grounded_normal if is_on_floor() or run.state == "ready" else Vector3.UP
	var target := basis_for(up, heading + spin)
	target = target * Basis(Vector3.RIGHT, flip) * Basis(Vector3.FORWARD, -steer * 0.2 if is_on_floor() else 0.0)
	visual.basis = visual.basis.slerp(target, 1.0 - exp(-14 * delta)).orthonormalized()
	visual.animate(delta, nitro, steer, Input.get_action_strength("tuck"), not is_on_floor() and Input.is_action_pressed("grab"), clampf(recovery, 0, 1))
