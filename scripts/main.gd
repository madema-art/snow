extends Node3D

func _ready() -> void:
	var controls := SnowControls.new()
	add_child(controls)
	var run := SnowRun.new()
	add_child(run)
	var mountain := SnowMountain.new()
	mountain.name = "Mountain"
	add_child(mountain)
	# Time of day: the remembered choice applies at once on launch, later changes
	# (only possible outside a timed run) cross-fade.
	mountain.atmosphere.set_mode(run.mode, true)
	run.mode_changed.connect(func(mode: String): mountain.atmosphere.set_mode(mode))
	var rider := SnowRider.new()
	rider.name = "Rider"
	rider.run = run
	add_child(rider)
	var camera := SnowCamera.new()
	camera.name = "ChaseCamera"
	camera.rider = rider
	add_child(camera)
	rider.reset_performed.connect(camera.reset)
	var fx := SnowFX.new()
	fx.name = "SnowFX"
	fx.rider = rider
	fx.mountain = mountain
	add_child(fx)
	var audio := SnowAudio.new()
	audio.rider = rider
	audio.mountain = mountain
	add_child(audio)
	var haptics := SnowHaptics.new()
	haptics.name = "Haptics"
	haptics.rider = rider
	add_child(haptics)
	var music := SnowMusic.new()
	music.name = "Music"
	music.rider = rider
	add_child(music)
	var menu := SnowPauseMenu.new()
	menu.run = run
	menu.controls = controls
	menu.rider = rider
	menu.camera = camera
	menu.music = music
	add_child(menu)
	var title := SnowTitle.new()
	title.name = "Title"
	title.run = run
	add_child(title)
