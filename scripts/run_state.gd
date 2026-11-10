class_name SnowRun
extends Node
## Only push_off() starts the clock; recovering still counts as running.
signal ended
var elapsed := 0.0
var state := "ready"
var records: Array = []
var records_path := "user://snow_records_massif_v2.json"
var last_rank := -1 # Index in the top ten of the latest finish, or -1.

func _ready() -> void:
	load_records()

func push_off() -> void:
	if state == "ready":
		state = "running"

func tick(delta: float) -> void:
	if state == "running" and not get_tree().paused:
		elapsed += delta

func restart() -> void:
	elapsed = 0.0
	last_rank = -1
	state = "ready"

func finish() -> void:
	if state != "running":
		return
	state = "finished"
	var time := snappedf(elapsed, 0.001)
	records.append(time)
	records.sort()
	records = records.slice(0, 10)
	last_rank = records.find(time)
	save_records()
	ended.emit()

func fatal() -> void:
	if state == "running":
		state = "ended"
		ended.emit()

func save_records() -> void:
	var file := FileAccess.open(records_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records))

func load_records() -> void:
	records.clear()
	if not FileAccess.file_exists(records_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(records_path))
	if parsed is Array:
		for value in parsed:
			if (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0:
				records.append(float(value))
		records.sort()
		records = records.slice(0, 10)

static func clock_text(seconds: float) -> String:
	var centis := int(round(seconds * 100.0))
	return "%02d:%02d.%02d" % [centis / 6000, (centis / 100) % 60, centis % 100]
