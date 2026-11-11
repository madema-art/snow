class_name SnowRun
extends Node
## Run state, the clock, the time of day and the records.
## Only push_off() starts the clock; recovering still counts as running.
##
## Time of day ("day" / "night") can be changed whenever no timed descent is in
## progress and is locked from push-off until the run ends or is restarted. The
## choice is remembered in `settings_path`. Because night changes visibility,
## each mode keeps its own top ten: Day in `records_path` (the file every earlier
## massif_v3 record already lives in, so nothing is lost or moved) and Night in
## the same name with `_night` appended.
signal ended
signal mode_changed(mode: String)
const MODES := ["day", "night"]
var elapsed := 0.0
var state := "ready"
var mode := "day"
var records: Array = []                 # top ten of the CURRENT mode
var by_mode: Dictionary = {"day": [], "night": []}
var records_path := "user://snow_records_massif_v3.json"
var settings_path := "user://snow_settings.json"
var last_rank := -1 # Index in the top ten of the latest finish, or -1.

func _ready() -> void:
	load_settings()
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
	by_mode[mode] = records
	last_rank = records.find(time)
	save_records()
	ended.emit()

func fatal() -> void:
	if state == "running":
		state = "ended"
		ended.emit()

# ------------------------------------------------------------------ time of day
func can_change_mode() -> bool:
	return state != "running"

## Returns false (and changes nothing) during a timed descent.
func set_mode(new_mode: String) -> bool:
	if not new_mode in MODES or not can_change_mode():
		return false
	if new_mode == mode:
		return true
	by_mode[mode] = records
	mode = new_mode
	records = by_mode[mode]
	last_rank = -1
	save_settings()
	mode_changed.emit(mode)
	return true

func toggle_mode() -> bool:
	return set_mode("night" if mode == "day" else "day")

func save_settings() -> void:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"mode": mode}))

func load_settings() -> void:
	mode = "day" # a fresh install starts in daylight
	if not FileAccess.file_exists(settings_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if parsed is Dictionary and parsed.get("mode") in MODES:
		mode = parsed["mode"]

# ------------------------------------------------------------------ records
func records_file(for_mode: String) -> String:
	return records_path if for_mode == "day" else records_path.trim_suffix(".json") + "_night.json"

func save_records() -> void:
	var file := FileAccess.open(records_file(mode), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records))

func load_records() -> void:
	for m in MODES:
		by_mode[m] = read_records(records_file(m))
	records = by_mode[mode]

func read_records(path: String) -> Array:
	var list: Array = []
	if not FileAccess.file_exists(path):
		return list
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		for value in parsed:
			if (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0:
				list.append(float(value))
		list.sort()
		list = list.slice(0, 10)
	return list

static func clock_text(seconds: float) -> String:
	var centis := int(round(seconds * 100.0))
	return "%02d:%02d.%02d" % [centis / 6000, (centis / 100) % 60, centis % 100]
