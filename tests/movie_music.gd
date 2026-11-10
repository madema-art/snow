extends SceneTree
## Movie Maker check of the soundtrack through the real mixer (audio-focused):
## 0-4 s summit with the opener, 4-7 s paused (silence), 7-10 s resumed, then a
## forced crossfade to the next song.
##   xvfb-run godot --path . --resolution 320x180 --fixed-fps 60 --write-movie work/movie/music.avi --script res://tests/movie_music.gd
var game: Node3D
func _initialize() -> void: go.call_deferred()
func wait(seconds: float) -> void:
	for i in int(seconds * 60):
		await process_frame
func go() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var music: SnowMusic = game.get_node("Music")
	var menu: SnowPauseMenu
	for c in game.get_children():
		if c is SnowPauseMenu: menu = c
	print("MUSIC opener=", music.current_title())
	await wait(4.0)
	menu.show_menu()
	print("MUSIC paused at ", music.players[music.active].get_playback_position())
	await wait(3.0)
	menu.hide_menu()
	print("MUSIC resumed at ", music.players[music.active].get_playback_position())
	await wait(3.0)
	music.advance()
	print("MUSIC crossfade to ", music.current_title())
	await wait(4.0)
	print("MUSIC DONE")
	quit()
