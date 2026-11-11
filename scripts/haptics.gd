class_name SnowHaptics
extends Node
## Controller vibration that supports (never replaces) the sound: a continuous
## snow texture that sharpens on ice and skids, landing and crash impacts scaled
## by severity, a nitro ignition kick with sustained rumble, and the distinctive
## stuttering pulses of an empty-nitro sputter. Uses the first connected pad.
## Stops whenever the game pauses (this node only runs while unpaused).
var rider: SnowRider
var pulses: Array = []      # [time, weak, strong, duration]
var clock := 0.0
var refresh := 0.0
var device := -1

func _ready() -> void:
	rider.sound_event.connect(_on_event)
	rider.reset_performed.connect(stop)
	Input.joy_connection_changed.connect(func(_id, _connected): pick_device())
	pick_device()

func pick_device() -> void:
	var pads := Input.get_connected_joypads()
	device = pads[0] if not pads.is_empty() else -1

func stop() -> void:
	pulses.clear()
	if device >= 0:
		Input.stop_joy_vibration(device)

func queue(delay: float, weak: float, strong: float, duration: float) -> void:
	pulses.append([clock + delay, weak, strong, duration])

func _on_event(kind: String, strength: float) -> void:
	match kind:
		"land", "land_sketchy":
			queue(0.0, 0.25 + strength * 0.3, 0.15 + strength * 0.65, 0.09 + strength * 0.12)
		"ollie":
			queue(0.0, 0.25, 0.05, 0.05)
		"crash":
			var tier := rider.crash_tier()
			queue(0.0, 0.5, 0.55 + tier * 0.2, 0.22 + tier * 0.12)
			queue(0.3, 0.3, 0.3 + tier * 0.1, 0.12)
		"fatal":
			queue(0.0, 0.8, 1.0, 0.6)
			queue(0.65, 0.4, 0.6, 0.4)
		"tumble":
			queue(0.0, 0.3 + strength * 0.3, 0.25 + strength * 0.7, 0.09 + strength * 0.1)
		"boost":
			queue(0.0, 0.4, 0.9, 0.18)
		"empty":
			for p in [[0.0, 0.8], [0.2, 0.65], [0.37, 0.5], [0.6, 0.3]]:
				queue(p[0], 0.15, p[1], 0.07)
		"charge":
			queue(0.0, 0.35 * strength, 0.0, 0.08)

func _physics_process(delta: float) -> void:
	clock += delta
	if device < 0:
		pulses.clear()
		return
	for i in range(pulses.size() - 1, -1, -1):
		var p: Array = pulses[i]
		if clock >= p[0]:
			Input.start_joy_vibration(device, p[1], p[2], p[3])
			pulses.remove_at(i)
			refresh = p[3]
	refresh -= delta
	if refresh > 0.0:
		return
	refresh = 0.1
	var grounded := rider.ground_contact and rider.recovery <= 0.0 and rider.run.state == "running"
	var r := clampf(rider.speed / 40.0, 0.0, 1.3)
	var weak := 0.0
	var strong := 0.0
	if grounded:
		weak = r * 0.12 + rider.surface.y * r * 0.25 + rider.brake_input * r * 0.25 + absf(rider.steer) * r * 0.08
		strong = rider.surface.y * r * 0.08 + rider.brake_input * r * 0.12
		# Deep lean: the plume buzzes lightly; an edge about to wash out shudders hard.
		weak += rider.plume * 0.18
		strong += rider.over_lean * rider.over_lean * 0.6
	if rider.boosting:
		strong += 0.3
		weak += 0.1
	if weak > 0.01 or strong > 0.01:
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), 0.14)
