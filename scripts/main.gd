extends Node3D

func _ready() -> void:
	var controls := SnowControls.new()
	add_child(controls)
	var run := SnowRun.new()
	add_child(run)
	add_child(SnowMountain.new())
	var rider := SnowRider.new()
	rider.name = "Rider"
	rider.run = run
	add_child(rider)
	var camera := SnowCamera.new()
	camera.name = "ChaseCamera"
	camera.rider = rider
	add_child(camera)
	rider.reset_performed.connect(camera.reset)
	var audio := SnowAudio.new()
	audio.rider = rider
	add_child(audio)
	var menu := SnowPauseMenu.new()
	menu.run = run
	menu.controls = controls
	menu.rider = rider
	menu.camera = camera
	add_child(menu)
