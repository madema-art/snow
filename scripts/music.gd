class_name SnowMusic
extends Node
## Soundtrack manager: the owner's songs from res://assets/music/ on the "Music" bus.
##
## Playback rules
## - Every launch opens with OPENING_TRACK (exact filename). If it is missing, a
##   random available track opens instead. No music installed -> silent, no errors.
## - Then a shuffle bag of every OTHER song, each once. Every later cycle reshuffles
##   ALL songs (opener included). The same song never plays twice in a row, also
##   across cycle boundaries (unless only one song exists).
## - Equal-power crossfades of CROSSFADE seconds between songs.
## - Continues through crashes, recoveries, finishes and restarts (restart never
##   touches the soundtrack). Explicit pauses (Menu, disconnect, focus loss) pause it
##   at the exact position; resuming continues from there.
## - New .mp3/.ogg files dropped into the folder are discovered automatically, in
##   the editor (source files, imported or not yet imported) and in exported builds
##   (ResourceLoader.list_directory / ".import" entries).
## - Gentle ducking under crashes and nitro ignition keeps key gameplay sounds clear.
## Nothing is ever displayed: no titles, no controls, no HUD.
const OPENING_TRACK := "Alpine Shift (Take 2) (Remix).mp3"
const EXTENSIONS := ["mp3", "ogg"]
const CROSSFADE := 2.5
const MUSIC_BUS_DB := -8.0   # Tracks measure -14..-20 LUFS; SFX bed ~-18 LUFS.
const DUCK_DB := -5.0
var music_dir := "res://assets/music/"
var rider: SnowRider
var tracks: Array[String] = []
var bag: Array[String] = []
var history: Array[String] = []
var current := ""
var players: Array[AudioStreamPlayer] = []
var active := 0
var fading := false
var fade := 1.0
var paused := false
var duck := 0.0               # 0..1 current ducking amount
var duck_hold := 0.0
var cycle := 0                # 0 = opener + "every other song" cycle
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Always process so results/finish screens keep the music going; explicit
	# pauses call set_paused() instead of relying on the tree pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	var bus := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_volume_db(bus, MUSIC_BUS_DB)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		players.append(p)
	if rider:
		rider.sound_event.connect(_on_rider_event)
	start()

# ------------------------------------------------------------------ discovery
static func discover(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var add := func(file: String):
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in EXTENSIONS and not name in names:
			names.append(name)
	if ClassDB.class_has_method("ResourceLoader", "list_directory"):
		for file in ResourceLoader.list_directory(dir_path):
			add.call(file)
	var dir := DirAccess.open(dir_path)
	if dir:
		for file in dir.get_files():
			add.call(file)
	names.sort()
	var found: Array[String] = []
	for name in names:
		found.append(dir_path.path_join(name))
	return found

static func load_track(path: String) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and FileAccess.file_exists(path):
		# Freshly pulled, not yet imported by the editor: decode the source directly.
		match path.get_extension().to_lower():
			"mp3": stream = AudioStreamMP3.load_from_file(path)
			"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
	if stream and "loop" in stream:
		stream.set("loop", false) # each song plays once; the playlist decides what follows
	return stream

# ------------------------------------------------------------------ playlist
func start() -> void:
	for p in players:
		p.stop()
	tracks = discover(music_dir)
	bag.clear()
	history.clear()
	cycle = 0
	current = ""
	fading = false
	if tracks.is_empty():
		return
	var opener := music_dir.path_join(OPENING_TRACK)
	var first := opener if opener in tracks else tracks[rng.randi_range(0, tracks.size() - 1)]
	play_now(first)

func shuffled(items: Array[String]) -> Array[String]:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: String = out[i]
		out[i] = out[j]
		out[j] = t
	return out

## Next song from the shuffle bag (refilling it per the cycle rules).
func next_track_name() -> String:
	if tracks.is_empty():
		return ""
	# Songs added or removed while playing are picked up at the next refill.
	if bag.is_empty():
		var fresh := discover(music_dir)
		if not fresh.is_empty():
			tracks = fresh
		if cycle == 0:
			var others: Array[String] = []
			for t in tracks:
				if t != current:
					others.append(t)
			bag = shuffled(others if not others.is_empty() else tracks)
		else:
			bag = shuffled(tracks)
			if bag.size() > 1 and bag[0] == current:
				var swap := rng.randi_range(1, bag.size() - 1)
				bag[0] = bag[swap]
				bag[swap] = current
		cycle += 1
	return bag.pop_front()

func play_now(path: String) -> void:
	var stream := load_track(path)
	if stream == null:
		push_warning("SnowMusic: could not load " + path)
		tracks.erase(path)
		if not tracks.is_empty():
			play_now(next_track_name())
		return
	var p := players[active]
	p.stream = stream
	p.volume_db = 0.0
	p.play()
	p.stream_paused = paused
	current = path
	history.append(path)

func crossfade_to(path: String) -> void:
	var stream := load_track(path)
	if stream == null:
		tracks.erase(path)
		bag.erase(path)
		return
	active = 1 - active
	var p := players[active]
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	p.stream_paused = paused
	current = path
	history.append(path)
	fading = true
	fade = 0.0

## Skip to the next song now (crossfaded). Also used by tests.
func advance() -> void:
	if tracks.is_empty():
		return
	if fading:
		finish_fade()
	crossfade_to(next_track_name())

func finish_fade() -> void:
	fading = false
	fade = 1.0
	players[1 - active].stop()
	players[active].volume_db = 0.0

func set_paused(value: bool) -> void:
	paused = value
	for p in players:
		if p.playing or p.stream_paused:
			p.stream_paused = value

func current_title() -> String:
	return current.get_file()

# ------------------------------------------------------------------ runtime
func _on_rider_event(kind: String, strength: float) -> void:
	if kind in ["crash", "fatal", "boost"]:
		duck_hold = 1.2 if kind == "boost" else 1.0 + strength

func _process(delta: float) -> void:
	if paused or tracks.is_empty():
		return
	duck_hold = maxf(0.0, duck_hold - delta)
	duck = lerpf(duck, 1.0 if duck_hold > 0.0 else 0.0, 1.0 - exp(-(10.0 if duck_hold > 0.0 else 1.2) * delta))
	var p := players[active]
	if fading:
		fade = minf(1.0, fade + delta / CROSSFADE)
		players[1 - active].volume_db = linear_to_db(maxf(cos(fade * PI * 0.5), 0.0001))
		p.volume_db = linear_to_db(maxf(sin(fade * PI * 0.5), 0.0001))
		if fade >= 1.0:
			finish_fade()
	elif p.stream:
		var remaining := p.stream.get_length() - p.get_playback_position()
		if not p.playing or (p.stream.get_length() > CROSSFADE * 3.0 and remaining <= CROSSFADE):
			crossfade_to(next_track_name())
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), MUSIC_BUS_DB + DUCK_DB * duck)
