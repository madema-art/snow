class_name SnowRider
extends CharacterBody3D
## The one rider. Physics: swept CharacterBody on identical render/collision terrain.
## Gravity, edge carving, inertia, brake skid, tuck, preloaded ollie, aerial tricks,
## landing evaluation, nitro and crash rules. All feel constants live in SnowTuning.
## Presentation (rig pose, FX, audio, haptics, camera) only READS this state.
signal sound_event(kind: String, strength: float)
signal reset_performed
const T = preload("res://scripts/snow_tuning.gd")
@export var gravity := T.GRAVITY
@export var ollie_speed := T.OLLIE_SPEED
@export var edge_grip := T.EDGE_GRIP
@export var boost_acceleration := T.BOOST_ACCEL
@export var nitro_burn := T.NITRO_BURN
@export var drag := T.DRAG
var run: SnowRun
var visual: SnowRiderVisual
var heading := 0.0
var nitro := 0.0
var recovery := 0.0
var recovery_length := 0.0
var steer := 0.0          # Smoothed, shaped edge engagement -1..1 (positive = screen right).
var speed := 0.0
var boosting := false
var boost_time := 0.0
var air_time := 0.0
var spin := 0.0
var spin_rate := 0.0
var flip := 0.0
var flip_rate := 0.0
var grabbed := 0.0
var switch_stance := false
var previous_ground := false
var launch_height := 0.0
var safe_position := Vector3.ZERO
var grounded_normal := Vector3.UP
var last_crash_reason := ""
var last_crash_severity := 0.0
var fatal_crash := false
# Feel / presentation state (read-only for other systems).
var brake_input := 0.0
var tuck_input := 0.0
var surface := Vector2.ZERO        # x powder, y ice under the board
var yaw_rate := 0.0                # actual carve yaw rate (rad/s)
var lateral_slip := 0.0            # sideways skid speed (m/s)
var ollie_preload := 0.0                 # ollie crouch 0..1
var jump_armed := false
var since_ground := 0.0
var pop_time := 0.0                # seconds since the last ollie pop
var land_impact := 0.0             # last landing compression strength 0..1
var land_time := 10.0
var last_reward := 0.0
var last_landing_quality := 1.0
var last_trick := ""
var fatigue: Dictionary = {}
var airborne := false              # confirmed air (filters tiny terrain hops)
var ground_contact := false
# Visual-only tumble. It NEVER feeds back into velocity, speed or nitro.
var tumble_active := false
var tumble_pos := Vector3.ZERO
var tumble_vel := Vector3.ZERO
var tumble_axis := Vector3.RIGHT
var tumble_spin := 0.0
var tumble_basis := Basis()
var tumble_origin := Vector3.ZERO
var tumble_hit_cooldown := 0.0
var getup_started := false
var wedged := 0
var leaning_normal := Vector3.ZERO
var leaning_time := 10.0
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()

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
	visual.rider = self
	add_child(visual)
	_ray.collision_mask = 2
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
	boost_time = 0.0
	air_time = 0.0
	steer = 0.0
	spin = 0.0
	spin_rate = 0.0
	flip = 0.0
	flip_rate = 0.0
	grabbed = 0.0
	switch_stance = false
	launch_height = position.y
	previous_ground = false
	last_crash_reason = ""
	last_crash_severity = 0.0
	fatal_crash = false
	brake_input = 0.0
	tuck_input = 0.0
	yaw_rate = 0.0
	lateral_slip = 0.0
	ollie_preload = 0.0
	jump_armed = false
	since_ground = 0.0
	pop_time = 10.0
	land_impact = 0.0
	land_time = 10.0
	last_reward = 0.0
	last_landing_quality = 1.0
	last_trick = ""
	fatigue.clear()
	airborne = false
	ground_contact = false
	tumble_active = false
	getup_started = false
	_rng.seed = 5521
	safe_position = position
	grounded_normal = SnowMountain.normal_at(0, 8)
	surface = SnowMountain.surface_at(0, 8)
	if is_instance_valid(visual):
		visual.reset_pose(basis_for(grounded_normal, 0.0))
	reset_performed.emit()

func forward() -> Vector3:
	return Vector3(sin(heading), 0, cos(heading))

func basis_for(up: Vector3, yaw: float) -> Basis:
	var z := Vector3(sin(yaw), 0, cos(yaw)).slide(up).normalized()
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x).normalized(), z)

## Severity tier used by presentation: 0 minor, 1 moderate, 2 severe, 3 fatal.
func crash_tier() -> int:
	if fatal_crash: return 3
	if last_crash_severity < 12.0: return 0
	if last_crash_severity < 26.0: return 1
	return 2

func crash(severity: float, fatal := false, hit_normal := Vector3.ZERO, motion = null) -> void:
	var impact_motion: Vector3 = velocity if motion == null else motion
	# ABSOLUTE RULE: every fall, however minor, immediately wipes ALL speed and nitro.
	nitro = 0.0
	velocity = Vector3.ZERO
	speed = 0.0
	boosting = false
	boost_time = 0.0
	launch_height = position.y
	air_time = 0
	spin = 0
	spin_rate = 0
	flip = 0
	flip_rate = 0
	grabbed = 0
	ollie_preload = 0
	jump_armed = false
	airborne = false
	last_crash_severity = severity
	fatal_crash = fatal
	recovery_length = clampf(T.RECOVERY_MIN + severity * T.RECOVERY_PER_SEVERITY, T.RECOVERY_MIN, T.RECOVERY_MAX)
	recovery = recovery_length
	getup_started = false
	start_tumble(impact_motion, severity, hit_normal, fatal)
	visual.refresh_charge(0.0)
	sound_event.emit("fatal" if fatal else "crash", clampf(severity / 30.0, 0.25, 1.0))
	if fatal:
		run.fatal()

func start_tumble(motion: Vector3, severity: float, hit_normal: Vector3, fatal: bool) -> void:
	tumble_active = true
	tumble_pos = global_position
	tumble_origin = global_position
	tumble_basis = visual.global_basis.orthonormalized() if is_instance_valid(visual) and visual.is_inside_tree() else global_basis
	if fatal and motion.y < -8.0:
		tumble_vel = motion # A real fall keeps falling (presentation only; the run is over).
	elif hit_normal != Vector3.ZERO:
		tumble_vel = motion.bounce(hit_normal.normalized()) * 0.22
	else:
		tumble_vel = motion * T.TUMBLE_SPEED_SHARE
	tumble_vel.y = maxf(tumble_vel.y, 1.5 + minf(severity, 40.0) * 0.07)
	var flat := Vector3(motion.x, 0, motion.z)
	var axis := flat.cross(Vector3.UP).normalized() if flat.length() > 0.5 else Vector3.RIGHT
	tumble_axis = (axis + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.4, 0.4))).normalized()
	tumble_spin = -(3.0 + minf(severity, 45.0) * 0.22)
	tumble_hit_cooldown = 0.0

func update_tumble(delta: float) -> void:
	if not tumble_active:
		return
	var space := get_world_3d().direct_space_state
	tumble_hit_cooldown = maxf(0.0, tumble_hit_cooldown - delta)
	tumble_vel.y -= gravity * delta
	var next := tumble_pos + tumble_vel * delta
	_ray.from = tumble_pos
	_ray.to = next
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		tumble_vel = tumble_vel.bounce(hit.normal) * 0.3
		next = hit.position + hit.normal * 0.35
		tumble_spin *= -0.6
		if tumble_hit_cooldown == 0.0:
			sound_event.emit("tumble", clampf(tumble_vel.length() / 8.0 + 0.3, 0.2, 1.0))
			tumble_hit_cooldown = 0.18
	var ground := SnowMountain.height_at(next.x, next.z) + 0.32
	var current_ground := SnowMountain.height_at(tumble_pos.x, tumble_pos.z)
	if not fatal_crash:
		# A recoverable tumble may never carry the rider off a lip or far downhill.
		var flat := Vector2(next.x - tumble_origin.x, next.z - tumble_origin.z)
		if flat.length() > T.TUMBLE_MAX_TRAVEL or ground - 0.32 < current_ground - 2.5:
			next.x = tumble_pos.x
			next.z = tumble_pos.z
			tumble_vel.x *= -0.1
			tumble_vel.z *= -0.1
			ground = current_ground + 0.32
	if next.y <= ground:
		next.y = ground
		var n := SnowMountain.normal_at(next.x, next.z)
		var into := tumble_vel.dot(n)
		if into < 0.0:
			if into < -2.5 and tumble_hit_cooldown == 0.0:
				sound_event.emit("tumble", clampf(-into / 10.0, 0.15, 1.0))
				tumble_hit_cooldown = 0.16
			tumble_vel -= n * into * 1.3
		tumble_vel = tumble_vel.move_toward(Vector3.ZERO, 7.5 * delta)
		tumble_spin = move_toward(tumble_spin, 0.0, 7.0 * delta)
		# As the tumble dies, the body settles onto its back with the board downslope.
		var settle := clampf(1.0 - tumble_vel.length() / 5.0, 0.0, 1.0)
		if settle > 0.0:
			tumble_basis = tumble_basis.slerp(lying_basis(n), clampf(settle * 4.0 * delta, 0.0, 1.0)).orthonormalized()
			next.y = lerpf(next.y, ground - 0.08, settle * 0.5)
	tumble_pos = next
	tumble_basis = (Basis(tumble_axis, tumble_spin * delta) * tumble_basis).orthonormalized()

func lying_basis(n: Vector3) -> Basis:
	var x := -n
	var y := (tumble_basis.y - n * tumble_basis.y.dot(n))
	if y.length() < 0.1:
		y = Vector3.FORWARD.slide(n)
	y = y.normalized()
	return Basis(x, y, x.cross(y).normalized()).orthonormalized()

func landed(impact: float) -> void:
	var yaw_error := absf(wrapf(spin, -PI, PI))
	# A 180 rides away switch. Incomplete quarter turns catch an edge.
	yaw_error = minf(yaw_error, absf(PI - yaw_error))
	var pitch_error := absf(wrapf(flip, -PI, PI))
	var flat := Vector2(velocity.x, velocity.z)
	var align_error := 0.0
	if flat.length() > 12.0:
		align_error = absf(wrapf(atan2(flat.x, flat.y) - heading, -PI * 0.5, PI * 0.5))
	var quality := clampf(1.0 - yaw_error / T.LAND_YAW_TOLERANCE * 0.45 - pitch_error / T.LAND_PITCH_TOLERANCE * 0.45 - maxf(0.0, impact - 10.0) / 14.0 * 0.3 - align_error / T.LAND_ALIGN_LIMIT * 0.3, 0.0, 1.0)
	last_landing_quality = quality
	if impact > T.LAND_IMPACT_LIMIT or yaw_error > T.LAND_YAW_TOLERANCE or pitch_error > T.LAND_PITCH_TOLERANCE or align_error > T.LAND_ALIGN_LIMIT:
		last_crash_reason = "landing"
		crash(impact + yaw_error * 8.0 + pitch_error * 10.0)
	else:
		var half_spins := int(round(absf(spin) / PI))
		if half_spins % 2 == 1:
			switch_stance = not switch_stance
		var reward := trick_reward(air_time, launch_height - position.y, half_spins, int(round(absf(flip) / TAU)), grabbed, quality)
		if reward > 0.0:
			var before := nitro
			nitro = minf(1.0, nitro + reward)
			sound_event.emit("charge", clampf(reward / 0.45, 0.15, 1.0))
			if before < 0.999 and nitro >= 0.999:
				sound_event.emit("full", 1.0)
		land_impact = clampf(impact / 18.0 + air_time * 0.12, 0.1, 1.0)
		land_time = 0.0
		if air_time > T.AIR_CONFIRM or impact > 4.0:
			sound_event.emit("land" if quality > 0.55 else "land_sketchy", clampf(impact / 17.0 + air_time * 0.08, 0.12, 1.0))
		visual.refresh_charge(nitro)
	spin = 0.0
	spin_rate = 0.0
	flip = 0.0
	flip_rate = 0.0
	air_time = 0.0
	grabbed = 0.0

## Stored-nitro value of a landed jump. Pure function of what the rider did plus
## per-trick fatigue, so it can be unit tested and tuned in SnowTuning.
func trick_reward(time_in_air: float, drop: float, half_spins: int, flips: int, grab_time: float, quality: float) -> float:
	last_reward = 0.0
	last_trick = ""
	if time_in_air < T.REWARD_MIN_AIR:
		return 0.0
	var reward := T.REWARD_AIR_BASE + (time_in_air - T.REWARD_MIN_AIR) * T.REWARD_AIR_PER_SECOND
	reward += clampf((drop - 4.0) * T.REWARD_DROP_PER_METRE, 0.0, T.REWARD_DROP_MAX)
	var elements := 0
	if half_spins > 0:
		reward += T.REWARD_SPIN[mini(half_spins, T.REWARD_SPIN.size() - 1)]
		elements += 1
	if flips > 0:
		reward += T.REWARD_FLIP[mini(flips, T.REWARD_FLIP.size() - 1)]
		elements += 1
	if grab_time > 0.2:
		reward += T.REWARD_GRAB_BASE + minf(grab_time, 1.5) * T.REWARD_GRAB_PER_SECOND
		elements += 1
	if elements > 1:
		reward *= 1.0 + T.REWARD_COMBO * (elements - 1)
	reward *= 0.5 + 0.5 * quality
	last_trick = "s%d f%d g%d" % [half_spins, flips, 1 if grab_time > 0.2 else 0]
	var tired: float = fatigue.get(last_trick, 0.0)
	var recent: float = fatigue.get("_all", 0.0)
	reward /= 1.0 + tired + recent * T.GLOBAL_FATIGUE
	fatigue[last_trick] = tired + 1.0
	fatigue["_all"] = recent + 1.0
	last_reward = minf(reward, T.REWARD_CAP)
	return last_reward

func recovery_point(at: Vector3, normal: Vector3) -> Vector3:
	# A clear lateral offset avoids repeatedly getting up directly in front of a tree.
	var side := normal.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var base := at + normal * 3.0 - Vector3(0, 0, 3)
	for back in [0.0, 5.0]:
		for offset in [3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 13.0, -13.0]:
			var candidate: Vector3 = base + side * offset - Vector3(0, 0, back)
			candidate.y = SnowMountain.height_at(candidate.x, candidate.z) + 0.72
			if absf(candidate.y - at.y) > 6:
				continue
			if standable(candidate):
				return candidate
	return safe_position

func standable(candidate: Vector3) -> bool:
	if SnowMountain.normal_at(candidate.x, candidate.z).y < 0.75:
		return false
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = (get_child(0) as CollisionShape3D).shape
	probe.collision_mask = 2
	probe.transform = Transform3D(Basis(), candidate)
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(probe, 1).is_empty():
		return false
	# Room to ride away: an unobstructed 7 m slide down the fall line, so nobody
	# stands up boxed into a notch between boulders or nose-first against a trunk.
	var n := SnowMountain.normal_at(candidate.x, candidate.z)
	var fall := Vector3(n.x, 0, n.z)
	fall = fall.normalized() if fall.length() > 0.05 else Vector3(0, 0, 1)
	var to := candidate + fall * 7.0
	to.y = SnowMountain.height_at(to.x, to.z) + 0.72
	probe.motion = to - candidate
	return space.cast_motion(probe)[0] >= 0.99

## Where the rider stands up: where the tumble actually came to rest when that
## spot is safe and close; otherwise the conservative safe/recovery point.
func getup_point() -> Vector3:
	var candidate := Vector3(tumble_pos.x, SnowMountain.height_at(tumble_pos.x, tumble_pos.z) + 0.72, tumble_pos.z)
	var travel := Vector2(candidate.x - tumble_origin.x, candidate.z - tumble_origin.z).length()
	if travel <= T.TUMBLE_MAX_TRAVEL + 0.5 and absf(candidate.y - safe_position.y) < 5.0 and standable(candidate):
		_ray.from = tumble_origin + Vector3.UP * 0.4
		_ray.to = candidate + Vector3.UP * 0.4
		if get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
			return candidate
	return safe_position

func _physics_process(delta: float) -> void:
	var just_pushed_off := false
	if Input.is_action_just_pressed("restart"):
		run.restart()
		reset()
		return
	update_tumble(delta)
	if run.state == "finished":
		coast(delta)
		return
	if run.state == "ended":
		update_visual(delta)
		return
	if run.state == "ready":
		if Input.is_action_just_pressed("jump"):
			just_pushed_off = true
			run.push_off()
			velocity = Vector3(0, -1, 3.0)
			pop_time = 0.0
			sound_event.emit("push", 0.6)
		else:
			update_visual(delta)
			return
	run.tick(delta)
	for trick in fatigue.keys():
		fatigue[trick] = maxf(0.0, fatigue[trick] - (T.GLOBAL_FATIGUE_DECAY if trick == "_all" else T.FATIGUE_DECAY) * delta)
	land_time += delta
	pop_time += delta
	leaning_time += delta
	if recovery > 0.0:
		recovery = maxf(0.0, recovery - delta)
		velocity = Vector3.ZERO
		if recovery <= T.GETUP_TIME and not getup_started:
			getup_started = true
			tumble_active = false
			safe_position = getup_point()
			position = safe_position
			tumble_pos = safe_position
			heading = 0.0
			switch_stance = false
			grounded_normal = SnowMountain.normal_at(position.x, position.z)
			sound_event.emit("getup", 0.5)
		if recovery == 0.0:
			position = safe_position
			launch_height = position.y
			heading = 0.0
			switch_stance = false
			velocity = Vector3(0, -1, 1.0)
			previous_ground = false
			tumble_active = false
		update_visual(delta)
		return
	var raw := Input.get_axis("steer_left", "steer_right")
	var shaped := signf(raw) * pow(absf(raw), T.STEER_CURVE)
	var edge_rate := T.EDGE_ENGAGE_RATE if absf(shaped) > absf(steer) else T.EDGE_RELEASE_RATE
	steer = lerpf(steer, shaped, 1.0 - exp(-edge_rate * delta))
	speed = Vector2(velocity.x, velocity.z).length()
	# Ignore cached CharacterBody contact from the previous run on the push-off tick.
	var ground := is_on_floor() and not just_pushed_off
	brake_input = Input.get_action_strength("brake")
	tuck_input = Input.get_action_strength("tuck")
	var brake := brake_input
	var tuck := tuck_input
	if Input.is_action_just_pressed("jump") and not just_pushed_off:
		if ground and speed < T.PUSH_MAX_SPEED:
			# Nearly stopped (flat bench, wedged against a rock, facing uphill): A is a
			# push-off again, a small hop in the direction the board points.
			var push_dir := forward()
			if leaning_time < 0.5:
				# Leaning on a trunk or boulder: kick away from it and along it.
				push_dir = (leaning_normal * 0.9 + push_dir.slide(leaning_normal)).normalized()
			velocity += push_dir.slide(get_floor_normal()).normalized() * T.PUSH_SPEED + get_floor_normal() * 1.6
			pop_time = 0.0
			sound_event.emit("push", 0.5)
		else:
			jump_armed = true
	if ground:
		since_ground = 0.0
		grounded_normal = get_floor_normal()
		surface = SnowMountain.surface_at(position.x, position.z)
		var powder := surface.x
		var ice := surface.y
		# Carve: yaw rate is limited by the lateral acceleration an edge can hold, so
		# low speed pivots easily and high speed demands committed, earlier turns.
		var max_yaw := minf(T.PIVOT_RATE, T.CARVE_ACCEL / maxf(speed, 1.0)) * (1.0 + brake * T.SKID_TURN_BONUS)
		yaw_rate = -steer * max_yaw
		# Looking downhill along +Z, screen-right is world -X.
		heading += yaw_rate * delta
		var fwd := forward().slide(grounded_normal).normalized()
		var side := grounded_normal.cross(fwd).normalized()
		# CharacterBody clears vertical velocity on floor contact. Reconstruct the tangent
		# without projecting (and shrinking) the horizontal momentum every physics tick.
		velocity.y = -(velocity.x * grounded_normal.x + velocity.z * grounded_normal.z) / maxf(0.1, grounded_normal.y)
		velocity += Vector3.DOWN.slide(grounded_normal) * gravity * delta
		var lateral := velocity.dot(side)
		lateral_slip = lateral
		var grip := edge_grip * lerpf(T.FLAT_BASE_GRIP, 1.0, absf(steer)) * (1.0 - T.ICE_GRIP_LOSS * ice) * (1.0 - brake * T.BRAKE_GRIP_LOSS)
		velocity -= side * lateral * (1.0 - exp(-grip * delta))
		var resistance := T.ROLLING_RESISTANCE + powder * T.POWDER_RESISTANCE + ice * T.ICE_RESISTANCE
		resistance += drag * (1.0 - tuck * T.TUCK_DRAG_REDUCTION) * (1.0 + powder * T.POWDER_DRAG) * speed * speed
		resistance += brake * (T.BRAKE_BASE + speed * T.BRAKE_SPEED) + absf(steer) * speed * T.CARVE_SCRUB
		velocity = velocity.move_toward(Vector3.ZERO, maxf(0.0, resistance) * delta)
		# Extreme cross-edge sliding at speed can catch the downhill edge.
		if absf(lateral) > T.EDGE_CATCH_LATERAL and speed > T.EDGE_CATCH_SPEED and brake < 0.2:
			last_crash_reason = "edge catch"
			crash(speed * 0.6)
			update_visual(delta)
			return
		if jump_armed and Input.is_action_pressed("jump"):
			ollie_preload = minf(1.0, ollie_preload + delta / T.OLLIE_PRELOAD_TIME)
		if jump_armed and not Input.is_action_pressed("jump"):
			pop(grounded_normal)
			ground = false
		if ground:
			velocity.y -= 0.35 # Downward contact pressure, without artificial uphill thrust.
	else:
		since_ground += delta
		yaw_rate = 0.0
		if jump_armed and not Input.is_action_pressed("jump"):
			if since_ground <= T.COYOTE_TIME and previous_ground_recent():
				pop(grounded_normal)
			else:
				jump_armed = false
				ollie_preload = 0.0
		velocity.y -= gravity * delta
		var flat := Vector3(velocity.x, 0, velocity.z)
		var air_drag := drag * T.AIR_DRAG_SCALE * (1.0 - tuck * T.TUCK_DRAG_REDUCTION) * flat.length_squared()
		velocity -= flat.normalized() * minf(flat.length(), air_drag * delta) if flat.length() > 0.01 else Vector3.ZERO
		# LS only pre-aims the board for landing; it never pushes the rider sideways.
		heading -= shaped * T.AIR_STEER_RATE * delta
		var spin_input := Input.get_action_strength("spin_right") - Input.get_action_strength("spin_left")
		spin_rate = move_toward(spin_rate, spin_input * T.SPIN_RATE, T.SPIN_ACCEL * delta)
		spin -= spin_rate * delta
		var flip_input := Input.get_axis("flip_forward", "flip_back")
		flip_rate = move_toward(flip_rate, flip_input * T.FLIP_RATE, T.FLIP_ACCEL * delta)
		flip += flip_rate * delta
		if Input.is_action_pressed("grab"):
			grabbed += delta
		air_time += delta
		launch_height = maxf(launch_height, position.y)
		if not airborne and air_time > T.AIR_CONFIRM:
			airborne = true
			sound_event.emit("air", clampf(speed / 30.0, 0.2, 1.0))
	var was_boosting := boosting
	boosting = Input.is_action_pressed("boost") and nitro > 0.0
	if Input.is_action_just_pressed("boost") and nitro <= 0.0:
		sound_event.emit("empty", 1.0)
	if boosting:
		var spent := minf(nitro, nitro_burn * delta)
		# Nitro is pure forward thrust: it never adds edge grip or steering traction.
		velocity += forward() * boost_acceleration * (spent / nitro_burn)
		nitro -= spent
		boost_time += delta
		if not was_boosting:
			sound_event.emit("boost", 1.0)
		if nitro <= 0.0:
			sound_event.emit("deplete", 0.8)
	else:
		if was_boosting and nitro > 0.0:
			sound_event.emit("boost_release", nitro)
		boost_time = 0.0
	visual.refresh_charge(nitro)
	# After a pop the board leaves the slope plane even when (on steep, fast snow)
	# its world velocity still points downward; floor snap must not glue it back.
	floor_snap_length = 0.0 if pop_time < 0.2 else 0.85
	var before := velocity
	var from := position
	move_and_slide()
	# Trimesh creases can very rarely pin the capsule in place while it still has
	# full velocity (the solver reports the same snow contact every slide). Lift the
	# board a few centimetres, a little more each stuck tick, until it rides free.
	if before.length() > 3.0 and position.distance_to(from) < before.length() * delta * 0.15 and is_on_floor():
		wedged += 1
		position += get_floor_normal() * minf(0.03 * wedged, 0.25)
	else:
		wedged = 0
	var snow_contacts_only := true
	var brush_normal := Vector3.ZERO
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var object := hit.get_collider()
		if object is Node and object.has_meta("hazard"):
			snow_contacts_only = false
			var impact := maxf(0.0, -before.dot(hit.get_normal()))
			if impact < T.BRUSH_IMPACT:
				brush_normal = hit.get_normal()
				leaning_normal = Vector3(brush_normal.x, 0, brush_normal.z).normalized()
				leaning_time = 0.0
				continue
			var kind := str(object.get_meta("hazard"))
			last_crash_reason = kind
			crash(maxf(4, impact), impact > (T.FATAL_TREE_IMPACT if kind == "tree" else T.FATAL_ROCK_IMPACT), hit.get_normal(), before)
			# Restore to a clear place behind the impact, not inside its collider.
			safe_position = recovery_point(position, hit.get_normal())
			update_visual(delta)
			return
		elif hit.get_normal().y < 0.45 and -before.dot(hit.get_normal()) > T.WALL_CRASH_IMPACT and SnowMountain.normal_at(hit.get_position().x, hit.get_position().z).y < 0.65:
			var wall_impact := -before.dot(hit.get_normal())
			last_crash_reason = "rock face"
			crash(wall_impact, wall_impact > T.FATAL_ROCK_IMPACT, hit.get_normal(), before)
			safe_position = recovery_point(position, hit.get_normal())
			update_visual(delta)
			return
		elif hit.get_normal().y < 0.55 and SnowMountain.normal_at(hit.get_position().x, hit.get_position().z).y < 0.65:
			snow_contacts_only = false
	# Leaning on a trunk or boulder at walking pace: the rider shuffles around it in
	# the direction the board points instead of staying pinned by gravity.
	if brush_normal != Vector3.ZERO and is_on_floor() and Vector2(velocity.x, velocity.z).length() < 3.0:
		var flat_normal := Vector3(brush_normal.x, 0, brush_normal.z).normalized()
		var around := forward().slide(flat_normal)
		if around.length() < 0.2:
			around = flat_normal.cross(Vector3.UP) * (1.0 if steer >= 0.0 else -1.0)
		velocity += (around.normalized() * 3.5 + flat_normal * 1.0) * delta
	# Preserve tangent momentum across internal snow triangle seams. CharacterBody's
	# repeated contact resolution can otherwise discard almost all horizontal speed
	# on an innocuous 8 m mesh edge. Never restore through a solid hazard or wall.
	if is_on_floor() and snow_contacts_only:
		var candidate := before + (Vector3.UP * 0.35 if ground else Vector3.ZERO)
		velocity = candidate.slide(get_floor_normal())
	if is_on_floor() and not previous_ground:
		var impact := maxf(0, -before.dot(get_floor_normal()))
		airborne = false
		if air_time > 0.3 and launch_height - position.y > T.FATAL_LANDING_DROP:
			last_crash_reason = "cliff landing"
			crash(50.0, true, Vector3.ZERO, before)
		else:
			landed(impact)
	if not is_on_floor() and previous_ground:
		launch_height = position.y
	if is_on_floor() and recovery <= 0:
		safe_position = position
	previous_ground = is_on_floor()
	ground_contact = previous_ground
	# Sustained physical fall distance, never an arbitrary coordinate death boundary.
	if not is_on_floor() and air_time > 1 and launch_height - position.y > T.FATAL_FALL_DROP and velocity.y < -20 and recovery <= 0.0:
		last_crash_reason = "cliff fall"
		crash(50.0, true, Vector3.ZERO, velocity)
	if position.z >= SnowMountain.FINISH and absf(position.x) < 50.0 and is_on_floor() and recovery <= 0 and run.state == "running":
		run.finish()
		sound_event.emit("finish", 1.0)
	update_visual(delta)

func previous_ground_recent() -> bool:
	return pop_time > 0.3

func pop(normal: Vector3) -> void:
	var strength := 1.0 + T.OLLIE_PRELOAD_BONUS * ollie_preload
	velocity += normal.lerp(Vector3.UP, 0.25).normalized() * ollie_speed * strength
	sound_event.emit("ollie", 0.55 + 0.45 * ollie_preload)
	jump_armed = false
	ollie_preload = 0.0
	pop_time = 0.0
	since_ground = 1.0

## After the finish line the clock is frozen; the rider simply skids to a stop.
func coast(delta: float) -> void:
	brake_input = 1.0
	tuck_input = 0.0
	steer = lerpf(steer, 0.0, 1.0 - exp(-4.0 * delta))
	if is_on_floor():
		grounded_normal = get_floor_normal()
		velocity.y = -(velocity.x * grounded_normal.x + velocity.z * grounded_normal.z) / maxf(0.1, grounded_normal.y)
		velocity = velocity.move_toward(Vector3.ZERO, (14.0 + speed * 0.25) * delta)
		velocity.y -= 0.35
	else:
		velocity.y -= gravity * delta
	speed = Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	update_visual(delta)

func update_visual(delta: float) -> void:
	var on_ground := is_on_floor() or run.state == "ready"
	var up := grounded_normal if on_ground else Vector3.UP
	var yaw := heading + spin + (PI if switch_stance else 0.0)
	var target := basis_for(up, yaw) * Basis(Vector3.RIGHT, flip)
	visual.update_pose(delta, target, on_ground)
