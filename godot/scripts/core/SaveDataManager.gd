extends Node

# Persistent data management
# Handles leaderboard, achievements, unlocks, settings

const SAVE_PATH = "user://potato_game/"
const LEADERBOARD_FILE = "leaderboard.json"
const SAVES_FILE = "savegame.json"
const SETTINGS_FILE = "settings.json"

var leaderboard: Array[Dictionary] = []
var achievements: Dictionary = {}
var unlocked_knives: Array[String] = []
var settings: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 1.0,
	"sound_enabled": true,
	"particle_effects": true,
	"screen_shake": true
}

func _ready():
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_PATH):
		DirAccess.make_abs_absolute(SAVE_PATH)
	load_game()

func load_game():
	# Load leaderboard
	var leaderboard_file = SAVE_PATH + LEADERBOARD_FILE
	if ResourceLoader.exists(leaderboard_file):
		var data = load(leaderboard_file)
		if data:
			leaderboard = data.get("scores", [])

	# Load settings
	var settings_file = SAVE_PATH + SETTINGS_FILE
	if ResourceLoader.exists(settings_file):
		var data = load(settings_file)
		if data:
			settings.merge(data, true)

func save_game():
	# Save leaderboard
	var leaderboard_data = {"scores": leaderboard}
	_save_json(LEADERBOARD_FILE, leaderboard_data)

	# Save settings
	_save_json(SETTINGS_FILE, settings)

func add_to_leaderboard(name: String, score: int, mode: String):
	var entry = {
		"name": name,
		"score": score,
		"mode": mode,
		"date": Time.get_ticks_msec(),
		"timestamp": Time.get_datetime_string_from_system()
	}

	leaderboard.append(entry)
	leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
	leaderboard = leaderboard.slice(0, 10)  # Keep top 10

	save_game()

	return leaderboard.find(entry)  # Return rank

func get_leaderboard(mode: String = "", limit: int = 10) -> Array[Dictionary]:
	if mode == "":
		return leaderboard.slice(0, limit)

	var filtered = leaderboard.filter(func(entry): return entry["mode"] == mode)
	return filtered.slice(0, limit)

func unlock_achievement(achievement_id: String) -> bool:
	if achievement_id not in achievements:
		achievements[achievement_id] = {
			"unlocked": true,
			"timestamp": Time.get_ticks_msec()
		}
		save_game()
		return true
	return false

func is_achievement_unlocked(achievement_id: String) -> bool:
	return achievements.has(achievement_id) and achievements[achievement_id]["unlocked"]

func unlock_knife(knife_id: String):
	if knife_id not in unlocked_knives:
		unlocked_knives.append(knife_id)
		save_game()

func is_knife_unlocked(knife_id: String) -> bool:
	return knife_id in unlocked_knives

func update_setting(key: String, value):
	if key in settings:
		settings[key] = value
		save_game()

func _save_json(filename: String, data: Dictionary):
	var file = FileAccess.open(SAVE_PATH + filename, FileAccess.WRITE)
	if file:
		file.store_var(data)
