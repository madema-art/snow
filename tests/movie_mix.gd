extends SceneTree
## Mix balance probe for Movie Maker (audio only; the mountain is hidden so software
## GL renders fast). A real push-off and 40 s tucked descent with carves on the
## real course. Record twice to compare the two halves of the mix in isolation:
##   ... --write-movie work/movie/mix_sfx.avi   --script res://tests/movie_mix.gd -- --mute-music
##   ... --write-movie work/movie/mix_music.avi --script res://tests/movie_mix.gd -- --mute-sfx
## then: ffmpeg -i X.avi -af ebur128 -f null -   (integrated LUFS of each half)
func _initialize() -> void: go.call_deferred()
func go() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var rider: SnowRider = game.get_node("Rider")
	game.get_node("Mountain").visible = false
	var args := OS.get_cmdline_user_args()
	if "--mute-music" in args: AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	if "--mute-sfx" in args: AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
	for i in 120: await physics_frame
	Input.action_press("jump")
	for i in 2: await physics_frame
	Input.action_release("jump")
	for i in 60 * 40:
		var target_x := -150.0 + 120.0 * sin(i / 150.0)
		var desired := atan2(target_x - rider.position.x, 60.0)
		var s := clampf(-(desired - rider.heading) * 2.5, -1, 1)
		Input.action_press("steer_right", maxf(s, 0))
		Input.action_press("steer_left", maxf(-s, 0))
		Input.action_press("tuck", 1.0)
		if i % 300 == 0: print("MIX t=", i / 60.0, " speed=", rider.speed, " rec=", rider.recovery)
		await physics_frame
	print("MIX DONE")
	quit()
