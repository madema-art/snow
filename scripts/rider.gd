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
var mountain: SnowMountain       # streams collision around the rider (may be null in tools)
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
var tumble_basis := Basis()
var tumble_origin := Vector3.ZERO
var tumble_hit_cooldown := 0.0
var getup_started := false
var wedged := 0
var restart_hold := 0.0
var restart_done := false
# Deep carving: plume (0..1 rooster tail strength), its side (+1 thrown to the
# rider's left/-1 right, i.e. opposite the lean) and over_lean (0..1 toward tipping).
var plume := 0.0
var plume_side := 0.0
var over_lean := 0.0
var lean_side := 0.0
var tumble_omega := Vector3.ZERO
var tumble_time := 0.0
var tumble_apex := 0.0
var tumble_resting := false
var tumble_airborne := true
var tumble_hop := 0.0
var leaning_normal := Vector3.ZERO
var summit_turn := 0.0            # smoothed LS aim while choosing a direction at the summit
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
	# Every run starts stationary on the summit, the highest point of the world,
	# with the board facing south; the left stick aims it anywhere before push-off.
	var top := SnowMountain.spawn_point()
	position = top + Vector3(0, 0.7, 0)
	if mountain != null and mountain.is_inside_tree():
		mountain.ensure_ready(position, 1)
		position.y = ground_y(top.x, top.z) + 0.7
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
	tumble_resting = false
	getup_started = false
	plume = 0.0
	plume_side = 0.0
	over_lean = 0.0
	lean_side = 0.0
	_rng.seed = 5521
	safe_position = position
	grounded_normal = SnowMountain.normal_at(top.x, top.z)
	surface = SnowMountain.surface_at(top.x, top.z)
	if is_instance_valid(visual):
		visual.reset_pose(basis_for(grounded_normal, 0.0))
	reset_performed.emit()

func forward() -> Vector3:
	return Vector3(sin(heading), 0, cos(heading))

## Heading that points straight down the local fall line (any compass direction).
static func fall_heading(p: Vector3, fallback: float) -> float:
	var n := SnowMountain.normal_at(p.x, p.z)
	var flat := Vector2(n.x, n.z)
	return atan2(flat.x, flat.y) if flat.length() > 0.03 else fallback

## Downhill direction on the ground at `p` (unit, horizontal).
static func fall_dir(p: Vector3) -> Vector3:
	var n := SnowMountain.normal_at(p.x, p.z)
	var flat := Vector3(n.x, 0, n.z)
	return flat.normalized() if flat.length() > 0.03 else Vector3(0, 0, 1)

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
	plume = 0.0
	over_lean = 0.0
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
	tumble_resting = false
	tumble_airborne = true
	tumble_time = 0.0
	tumble_hop = 0.2
	tumble_pos = global_position
	tumble_origin = global_position
	tumble_apex = tumble_pos.y
	tumble_basis = visual.global_basis.orthonormalized() if is_instance_valid(visual) and visual.is_inside_tree() else global_basis
	if fatal and motion.y < -8.0:
		tumble_vel = motion # A real fall keeps falling.
	elif hit_normal != Vector3.ZERO:
		# Thrown back off the trunk or boulder, keeping the glancing part of the speed.
		var n := hit_normal.normalized()
		tumble_vel = motion.bounce(n) * T.TUMBLE_REBOUND + motion.slide(n) * 0.3 + n * 2.0
	else:
		tumble_vel = motion * T.TUMBLE_MOMENTUM
	if is_on_floor() and not (fatal and motion.y < -8.0):
		# Pitched off the snow: keep the along-slope momentum, add a pop off the surface.
		tumble_vel = tumble_vel.slide(grounded_normal) + grounded_normal * (2.2 + minf(severity, 40.0) * 0.07)
	spin_up(1.0)
	tumble_hit_cooldown = 0.0

## Angular velocity of a body cartwheeling in its direction of travel, with a
## random wobble so no two falls look alike.
func spin_up(blend: float) -> void:
	var flat := Vector3(tumble_vel.x, 0, tumble_vel.z)
	var rolling := Vector3.ZERO
	if flat.length() > 0.3:
		rolling = Vector3.UP.cross(flat.normalized()) * clampf(flat.length() / 0.55, 2.5, 15.0)
	rolling += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * clampf(flat.length() * 0.18, 0.5, 3.5)
	tumble_omega = tumble_omega.lerp(rolling, blend)

## Momentum physics for the fallen rider: ballistic flight, bounces off snow,
## trunks and boulders, then a rolling, ploughing slide that follows the slope
## until friction wins. The riding body itself stays frozen with zero speed.
func update_tumble(delta: float) -> void:
	if not tumble_active or tumble_resting:
		return
	var space := get_world_3d().direct_space_state
	tumble_time += delta
	tumble_hit_cooldown = maxf(0.0, tumble_hit_cooldown - delta)
	tumble_vel.y -= gravity * delta
	var next := tumble_pos + tumble_vel * delta
	_ray.from = tumble_pos
	_ray.to = next + tumble_vel.normalized() * 0.3
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		var hit_speed := maxf(0.0, -tumble_vel.dot(hit.normal))
		tumble_vel = tumble_vel.bounce(hit.normal) * 0.4
		next = hit.position + hit.normal * 0.4
		spin_up(0.8)
		if tumble_hit_cooldown == 0.0:
			sound_event.emit("tumble", clampf(hit_speed / 9.0 + 0.3, 0.3, 1.0))
			tumble_hit_cooldown = 0.16
	var ground := SnowMountain.height_at(next.x, next.z) + 0.32
	# In contact when it reaches the snow, and it stays in contact (hugging rolls
	# and convex ground) until a hop or a real drop throws it clear again.
	if next.y <= ground or (not tumble_airborne and next.y - ground < 0.6):
		next.y = ground
		var n := SnowMountain.normal_at(next.x, next.z)
		var into := tumble_vel.dot(n)
		if into < 0.0:
			var impact := -into
			var tangent := tumble_vel - n * into
			if tumble_airborne and impact > 2.2:
				# A real impact: lose sliding speed, bounce, re-spin, throw snow, hurt.
				var drop := tumble_apex - next.y
				if not fatal_crash and drop >= T.TUMBLE_FATAL_DROP:
					fatal_crash = true
					last_crash_reason = "tumbled off a drop"
					sound_event.emit("fatal", 1.0)
					run.fatal()
				tangent *= 1.0 - T.TUMBLE_IMPACT_LOSS
				tumble_vel = tangent + n * impact * T.TUMBLE_RESTITUTION
				spin_up(0.7)
				if tumble_hit_cooldown == 0.0:
					sound_event.emit("tumble", clampf(impact / 11.0, 0.2, 1.0))
					tumble_hit_cooldown = 0.14
			else:
				tumble_vel = tangent
		tumble_airborne = false
		# Sliding down a rock face counts like falling: the height lost since the
		# body last touched gentle ground decides whether the fall is fatal.
		if n.y > 0.6:
			if not fatal_crash and tumble_apex - next.y >= T.TUMBLE_FATAL_DROP:
				fatal_crash = true
				last_crash_reason = "tumbled off a drop"
				sound_event.emit("fatal", 1.0)
				run.fatal()
			tumble_apex = next.y
		# Rolling, ploughing slide: gravity along the slope is already in tumble_vel.
		var slide_speed := tumble_vel.length()
		var friction := T.TUMBLE_FRICTION + T.TUMBLE_PLOW * slide_speed
		var travelled := Vector2(next.x - tumble_origin.x, next.z - tumble_origin.z).length()
		if tumble_time > T.TUMBLE_MAX_TIME or travelled > T.TUMBLE_MAX_TRAVEL:
			friction *= 4.0
		tumble_vel = tumble_vel.move_toward(Vector3.ZERO, friction * delta)
		spin_up(clampf(6.0 * delta, 0.0, 1.0))
		# Cartwheeling: while it still has real speed the body keeps catching the snow
		# and being pitched back into the air, each landing another impact.
		tumble_hop -= delta
		if tumble_hop <= 0.0 and slide_speed > T.TUMBLE_HOP_MIN_SPEED and not tumble_resting:
			tumble_vel += n * clampf(slide_speed * T.TUMBLE_HOP, 2.0, 7.0)
			tumble_hop = _rng.randf_range(0.28, 0.5)
			tumble_airborne = true
		# As the tumble dies, the body settles onto its back with the board downslope.
		var settle := clampf(1.0 - tumble_vel.length() / 4.0, 0.0, 1.0)
		if settle > 0.0:
			tumble_omega *= 1.0 - settle
			tumble_basis = tumble_basis.slerp(lying_basis(n), clampf(settle * 5.0 * delta, 0.0, 1.0)).orthonormalized()
			next.y = lerpf(next.y, ground - 0.08, settle * 0.5)
		if tumble_vel.length() < 0.5 and n.y > 0.6:
			tumble_vel = Vector3.ZERO
			tumble_resting = true
			if not fatal_crash and last_crash_severity >= 12.0:
				sound_event.emit("groan", clampf(last_crash_severity / 35.0, 0.3, 1.0))
	else:
		if not tumble_airborne and next.y - ground > 0.6:
			tumble_airborne = true
			tumble_apex = next.y
		tumble_apex = maxf(tumble_apex, next.y)
	tumble_pos = next
	if tumble_omega.length() > 0.01:
		tumble_basis = (Basis(tumble_omega.normalized(), tumble_omega.length() * delta) * tumble_basis).orthonormalized()

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
	# A little uphill of the impact (whatever way the slope falls) and off to the side.
	var uphill := -fall_dir(at)
	var base := at + normal * 3.0 + uphill * 3.0
	for back in [0.0, 5.0]:
		for offset in [3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 13.0, -13.0]:
			var candidate: Vector3 = base + side * offset + uphill * back
			candidate.y = ground_y(candidate.x, candidate.z) + 0.72
			if absf(candidate.y - at.y) > 6:
				continue
			if standable(candidate):
				return candidate
	return safe_position

## Height of the actual collision surface (the 8 m mesh the board rides on),
## falling back to the analytic terrain where no collision is loaded. Standing
## the rider up by this, never by the analytic value, keeps it above the mesh.
func ground_y(x: float, z: float) -> float:
	var analytic := SnowMountain.height_at(x, z)
	if not is_inside_tree():
		return analytic
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, analytic + 40.0, z), Vector3(x, analytic - 40.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit["position"].y if not hit.is_empty() else analytic

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
	to.y = ground_y(to.x, to.z) + 0.72
	probe.motion = to - candidate
	if space.cast_motion(probe)[0] < 0.99:
		return false
	# ...and no cliff edge just below: nobody stands up facing a drop.
	var here := SnowMountain.height_at(candidate.x, candidate.z)
	for d: float in [10.0, 20.0, 30.0]:
		var q := candidate + fall * d
		if here - SnowMountain.height_at(q.x, q.z) > d * 1.0 + 6.0:
			return false
	return true

## Where the rider stands up: where the tumble actually came to rest. If that
## exact spot is not safe to stand on (steep, boxed in, inside scenery) the nearest
## clear spot around it; only as a last resort the place the fall began.
func getup_point() -> Vector3:
	var candidate := Vector3(tumble_pos.x, ground_y(tumble_pos.x, tumble_pos.z) + 0.72, tumble_pos.z)
	if standable(candidate):
		return candidate
	var around := recovery_point(candidate, SnowMountain.normal_at(candidate.x, candidate.z))
	return around

func _physics_process(delta: float) -> void:
	var just_pushed_off := false
	# Restart is held briefly so a stray tap can never throw a run away.
	if Input.is_action_pressed("restart"):
		restart_hold += delta
		if restart_hold >= T.RESTART_HOLD and not restart_done:
			restart_done = true # one restart per hold
			run.restart()
			reset()
			return
	else:
		restart_hold = 0.0
		restart_done = false
	update_tumble(delta)
	if run.state == "finished":
		coast(delta)
		return
	if run.state == "ended":
		update_visual(delta)
		return
	if run.state == "ready":
		# On the summit the left stick turns the board on the spot: choose any face
		# of the mountain. The clock does not run until the push-off.
		var aim := Input.get_axis("steer_left", "steer_right")
		aim = signf(aim) * smoothstep(0.15, 1.0, absf(aim))
		summit_turn = lerpf(summit_turn, aim, 1.0 - exp(-10.0 * delta))
		heading = wrapf(heading - summit_turn * T.SUMMIT_TURN_RATE * delta, -PI, PI)
		if Input.is_action_just_pressed("jump"):
			just_pushed_off = true
			run.push_off()
			velocity = forward().slide(grounded_normal).normalized() * T.PUSH_SPEED + Vector3.DOWN
			summit_turn = 0.0
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
		# Nobody stands up while still tumbling: the get-up waits for the body to rest.
		if tumble_active and not tumble_resting and not getup_started:
			recovery = maxf(recovery, T.GETUP_TIME + 0.45)
		velocity = Vector3.ZERO
		if recovery <= T.GETUP_TIME and not getup_started:
			getup_started = true
			tumble_active = false
			safe_position = getup_point()
			position = safe_position
			tumble_pos = safe_position
			heading = fall_heading(safe_position, heading)
			switch_stance = false
			grounded_normal = SnowMountain.normal_at(position.x, position.z)
			sound_event.emit("getup", 0.5)
		if recovery == 0.0:
			position = safe_position
			launch_height = position.y
			heading = fall_heading(safe_position, heading)
			switch_stance = false
			velocity = forward() * 1.0 + Vector3.DOWN
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
	# Left stick forward crouches into a tuck, back brakes (triggers do the same).
	brake_input = maxf(Input.get_action_strength("brake"), Input.get_action_strength("lean_back"))
	tuck_input = maxf(Input.get_action_strength("tuck"), Input.get_action_strength("lean_forward"))
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
		# Deep lean: past DEEP_LEAN_START the board turns tighter and throws a plume
		# of snow out the far side -- but held too long the edge washes out.
		var deep := smoothstep(T.DEEP_LEAN_START, 1.0, absf(raw))
		max_yaw *= 1.0 + T.DEEP_LEAN_TURN_BONUS * deep * (1.0 - brake)
		yaw_rate = -steer * max_yaw
		var plume_target := smoothstep(T.PLUME_START, T.PLUME_FULL, absf(steer)) * smoothstep(T.PLUME_MIN_SPEED, T.PLUME_FULL_SPEED, speed)
		plume = lerpf(plume, plume_target, 1.0 - exp(-10.0 * delta))
		if absf(steer) > 0.05:
			plume_side = signf(steer)
		if signf(raw) != lean_side:
			lean_side = signf(raw)
			over_lean *= 0.3 # switching edges brings the rider back through upright
		var tipping := deep * smoothstep(T.OVERLEAN_MIN_SPEED, T.OVERLEAN_FULL_SPEED, speed) * (1.0 - smoothstep(0.2, 0.5, brake))
		if tipping > 0.0:
			over_lean += tipping * delta / T.OVERLEAN_TIME
		else:
			over_lean = maxf(0.0, over_lean - delta / T.OVERLEAN_RECOVER)
		if over_lean >= 1.0:
			last_crash_reason = "over-lean"
			# The edge lets go: the rider is flung low-side along the direction of travel.
			crash(maxf(6.0, speed * 0.45), false, Vector3.ZERO, velocity + grounded_normal.cross(forward()) * signf(steer) * 3.0)
			update_visual(delta)
			return
		# Screen-right (positive steer) turns the board clockwise seen from above,
		# in every direction of travel.
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
		plume = lerpf(plume, 0.0, 1.0 - exp(-14.0 * delta))
		over_lean = maxf(0.0, over_lean - delta / T.OVERLEAN_RECOVER)
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
	# The finish is the bottom of the mountain, on any side: riding (grounded, not
	# recovering, not in the air) on a real valley floor far below the summit.
	if run.state == "running" and is_on_floor() and recovery <= 0 and not airborne and SnowMountain.at_bottom(position):
		run.finish(SnowMountain.face_name(position.x, position.z))
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
