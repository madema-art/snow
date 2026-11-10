class_name SnowAudio
extends Node3D
## Original seeded synthesis; no downloaded recordings. Pauses with the world.
var rider: SnowRider
var wind: AudioStreamPlayer3D
var snow: AudioStreamPlayer3D
var edge: AudioStreamPlayer3D
var engine: AudioStreamPlayer3D
var voices: Array[AudioStreamPlayer3D] = []
var samples: Dictionary = {}
var voice_index := 0
var rng := RandomNumberGenerator.new()
var wind_filter: AudioEffectLowPassFilter

func _ready() -> void:
	rng.seed = 3129
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -5)
	if AudioServer.get_bus_index("MountainWind") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "MountainWind")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "SFX")
	wind_filter = AudioEffectLowPassFilter.new()
	wind_filter.cutoff_hz = 6000
	var wind_bus := AudioServer.get_bus_index("MountainWind")
	if AudioServer.get_bus_effect_count(wind_bus) == 0:
		AudioServer.add_bus_effect(wind_bus, wind_filter)
	else:
		wind_filter = AudioServer.get_bus_effect(wind_bus, 0)
	wind = player(make_sample("wind", 1.7, true))
	wind.bus = "MountainWind"
	snow = player(make_sample("snow", 1.3, true))
	edge = player(make_sample("edge", 0.9, true))
	engine = player(make_sample("engine", 1.0, true))
	for p in [wind, snow, edge, engine]:
		p.volume_db = -65
		p.play()
	for kind in ["push", "ollie", "air", "land", "crash", "fatal", "charge", "boost", "deplete", "empty"]:
		samples[kind] = make_sample(kind, 0.7 if kind in ["crash", "fatal", "boost"] else 0.38)
	for i in 6:
		voices.append(player(null))
	rider.sound_event.connect(event)

func player(stream: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = 12.0
	p.max_distance = 100
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	add_child(p)
	return p

func make_sample(kind: String, duration: float, loop := false) -> AudioStreamWAV:
	const RATE := 22050
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var q := t / duration
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.07)
		var value := 0.0
		match kind:
			"wind": value = low * 2.0 + noise * 0.05
			"snow": value = noise * 0.35 + low * 0.9
			"edge": value = noise * (0.3 + 0.2 * sin(TAU * 37 * t)) + sin(TAU * 170 * t) * 0.1
			"engine": value = sin(TAU * 66 * t + 2 * sin(TAU * 132 * t)) * 0.35 + low * 1.2
			"land", "crash", "fatal":
				value = (sin(TAU * (65 * t - 24 * t * t)) * 0.75 + low * 1.8 + noise * 0.22) * exp(-q * (6 if kind == "land" else 4))
				if kind != "land":
					value += noise * 0.35 * pow(maxf(0, sin(q * 24)), 8) * (1.0 - q)
			"charge": value = (sin(TAU * 440 * t) + sin(TAU * 660 * t) * 0.5 + sin(TAU * 880 * t) * 0.3) * 0.35 * sin(PI * q) * exp(-q * 2)
			"boost":
				phase += TAU * lerpf(48, 160, q) / RATE
				value = (sin(phase) * 0.65 + low * 2 + noise * 0.12) * sin(PI * pow(q, 0.4))
			"empty": value = (noise * 0.5 + sin(TAU * 58 * t) * 0.5) * pow(maxf(0, sin(TAU * 13 * t)), 3) * (1 - q)
			"deplete": value = (sin(TAU * (260 * t - 220 * t * t)) * 0.4 + noise * 0.2) * (1 - q)
			"ollie", "push": value = (noise * 0.5 + sin(TAU * 110 * t) * 0.25) * exp(-q * 8)
			"air": value = low * 2.0 * sin(PI * q) * (1 - q)
		var envelope := minf(1.0, t / 0.008) * minf(1.0, (duration - t) / 0.015)
		data.encode_s16(i * 2, int(clampf(value * envelope, -0.98, 0.98) * 30000))
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = RATE
	sample.data = data
	if loop:
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin = 0
		sample.loop_end = count
	return sample

func event(kind: String, strength: float) -> void:
	if not samples.has(kind):
		return
	var p := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	p.stream = samples[kind]
	p.volume_db = linear_to_db(clampf(strength, 0.2, 1.0))
	p.pitch_scale = 0.92 if kind == "fatal" else 1.0
	p.play()

func _physics_process(delta: float) -> void:
	global_position = rider.global_position
	var ratio := clampf(rider.speed / 38.0, 0, 1)
	var contact := rider.is_on_floor() and rider.recovery <= 0 and rider.run.state == "running"
	var snow_level := ratio * 0.65 if contact else 0.0
	var edge_level := ratio * absf(rider.steer) * 0.8 if contact else 0.0
	edge_level += Input.get_action_strength("brake") * ratio * 0.35 if contact else 0.0
	var forest := SnowMountain.band(rider.position.z / SnowMountain.DISTANCE_SCALE, 2800, 4700, 250)
	var gust := 0.88 + 0.12 * sin(rider.position.z / 44.0)
	wind_filter.cutoff_hz = lerpf(wind_filter.cutoff_hz, lerpf(6000, 2600, forest), 1.0-exp(-delta*2))
	set_level(wind, (ratio * 0.75 + 0.025) * (1.0 - forest * 0.25) * gust, delta)
	set_level(snow, snow_level, delta)
	set_level(edge, edge_level, delta)
	set_level(engine, 0.8 if rider.boosting else 0.0, delta)
	snow.pitch_scale = 0.75 + ratio * 0.9
	edge.pitch_scale = 0.9 + ratio * 0.5
	engine.pitch_scale = 0.8 + ratio * 0.7

func set_level(p: AudioStreamPlayer3D, level: float, delta: float) -> void:
	p.volume_db = lerpf(p.volume_db, linear_to_db(maxf(0.001, level)), 1.0 - exp(-12 * delta))

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	samples.clear()

