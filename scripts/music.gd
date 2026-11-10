class_name SnowMusic
extends Node
## Plays the owner's soundtrack from res://assets/music/ on the existing "Music"
## bus: every .ogg / .mp3 / .wav there, in filename order, looping the playlist.
## With no files the node simply stays silent (the game never depends on music).
## Imported resources are preferred; files the editor has not imported yet are
## loaded directly so freshly pulled songs still play. Music keeps playing in the
## pause menu and across restarts; it is never generated or altered by the game.
const EXTENSIONS := ["ogg", "mp3", "wav"]
var music_dir := "res://assets/music/"
var tracks: Array[String] = []
var index := 0
var player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -4.0) # sits under the mountain sound
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.finished.connect(next_track)
	add_child(player)
	scan_and_play()

func scan_and_play() -> void:
	tracks = find_tracks(music_dir)
	index = 0
	if tracks.is_empty():
		player.stop()
		return
	play_current()

static func find_tracks(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file in dir.get_files():
		# Exported builds list "song.ogg.import"/".remap"; map back to the source name.
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in EXTENSIONS and not dir_path.path_join(name) in found:
			found.append(dir_path.path_join(name))
	found.sort()
	return found

static func load_track(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream:
			return stream
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg": return AudioStreamOggVorbis.load_from_file(path)
		"mp3": return AudioStreamMP3.load_from_file(path)
		"wav": return AudioStreamWAV.load_from_file(path)
	return null

func play_current() -> void:
	for attempt in tracks.size():
		var stream := load_track(tracks[index])
		if stream:
			# The playlist loops; each song plays through once even if imported as a loop.
			if stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
			elif "loop" in stream:
				stream.set("loop", false)
			player.stream = stream
			player.play()
			return
		push_warning("SnowMusic: could not load " + tracks[index])
		index = (index + 1) % tracks.size()
	player.stop()

func next_track() -> void:
	if tracks.is_empty():
		return
	index = (index + 1) % tracks.size()
	play_current()

func current_track() -> String:
	return tracks[index] if not tracks.is_empty() and player.playing else ""
