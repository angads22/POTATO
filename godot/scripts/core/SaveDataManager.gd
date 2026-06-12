extends Node

# Persistent data management
# Handles leaderboard, achievements, unlocks, settings

const SAVE_PATH = "user://potato_game/"
const LEADERBOARD_FILE = "leaderboard.json"
const ACHIEVEMENTS_FILE = "achievements.json"
const SETTINGS_FILE = "settings.json"
const UNLOCKS_FILE = "unlocks.json"
const FARM_FILE = "farm.json"

var leaderboard: Array[Dictionary] = []
var achievements: Dictionary = {}
var unlocked_knives: Array[String] = []
var settings: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 1.0,
	"sound_enabled": true,
	"particle_effects": true,
	"screen_shake": true,
	"graphics_style": "classic"  # classic | pixel | hyperreal (see StyleManager)
}

# Farm + economy state (schema 2, grid-based fields). New games start with a
# few russet seeds, pocket change and a fresh plow so the farming loop can
# begin immediately. Tiles are keyed "field:row:col" and hold
# {plowed, potato_id, planted_at (unix), watered, ...} — growth survives
# quitting because it's measured against the wall clock.
var farm: Dictionary = {
	"schema": 2,
	"wallet": 50,
	"seeds": {"russet": 3},
	"spuds": {},
	"water": 0,
	"owned_knives": ["butter"],
	"equipped_knife": "butter",
	"sections_owned": 1,    # field sections unlock in order; 1 = Field 1's first
	"tiles": {},            # sparse "field:row:col" -> tile dict
	"plow_uses": 10,        # durability left on the current plow; 0 = broken
	"plows_bought": 0,      # replacement purchases — each one costs more
	"sprinkler_stock": 0,   # sprinklers bought but not yet placed on a tile
	"tools": [],            # global auto-farming gear (harvest_drone, auto_seeder)
	"items": {}             # fertilizer charges remaining, per enhancer id
}

func _ready():
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_PATH):
		DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	load_game()

func load_game():
	# Load leaderboard
	var leaderboard_data = _load_json(LEADERBOARD_FILE)
	if leaderboard_data.has("scores"):
		leaderboard.assign(leaderboard_data["scores"])

	# Load achievements
	var achievements_data = _load_json(ACHIEVEMENTS_FILE)
	if not achievements_data.is_empty():
		achievements = achievements_data

	# Load settings
	var settings_data = _load_json(SETTINGS_FILE)
	if not settings_data.is_empty():
		settings.merge(settings_data, true)

	# Load unlocked knives
	var unlocks_data = _load_json(UNLOCKS_FILE)
	if unlocks_data.has("knives"):
		unlocked_knives.assign(unlocks_data["knives"])

	# Load farm — saved keys override the new-game defaults. Migration must
	# happen on the raw dict: after the merge the defaults' "schema" key
	# would mask an old save.
	var farm_data = _load_json(FARM_FILE)
	if not farm_data.is_empty():
		farm_data = _migrate_farm(farm_data)
		farm.merge(farm_data, true)

func save_game():
	_save_json(LEADERBOARD_FILE, {"scores": leaderboard})
	_save_json(ACHIEVEMENTS_FILE, achievements)
	_save_json(SETTINGS_FILE, settings)
	_save_json(UNLOCKS_FILE, {"knives": unlocked_knives})
	_save_json(FARM_FILE, farm)

# Upgrade a schema-1 farm save (fixed "plots" array, "plots_owned" counter,
# global "sprinkler" tool) to the schema-2 grid. Crops are re-homed onto
# Field 1's tiles, the old sprinkler becomes two placeable ones, and the
# player is handed a fresh plow.
func _migrate_farm(raw: Dictionary) -> Dictionary:
	if int(raw.get("schema", 1)) >= 2 and not raw.has("plots") and not raw.has("plots_owned"):
		return raw
	var out := raw.duplicate(true)
	out.erase("plots")
	out.erase("plots_owned")
	out["schema"] = 2

	# old 12-plot field maps onto Field 1's 12 tiles: anything past the
	# 6-plot default footprint means the second section was (part-)bought
	var plots: Array = raw.get("plots", [])
	var owned_plots := int(raw.get("plots_owned", 6))
	for i in range(plots.size()):
		if plots[i] is Dictionary and plots[i].has("potato_id"):
			owned_plots = maxi(owned_plots, i + 1)
	out["sections_owned"] = 2 if owned_plots > 6 else 1

	# the old global Sprinkler Network becomes two placeable sprinklers
	var tools: Array = raw.get("tools", []).duplicate()
	if "sprinkler" in tools:
		tools.erase("sprinkler")
		out["sprinkler_stock"] = 2
	out["tools"] = tools

	# everyone starts the grid era with a working plow
	out["plow_uses"] = 10
	out["plows_bought"] = 0

	# re-home old plots sequentially: planted crops first, then bare plots
	# that only remember their last crop. Slot order is frozen here (Field 1,
	# section by section, row-major) so old saves land the same way even if
	# fields.json changes later.
	var entries: Array = []
	for p in plots:
		if p is Dictionary and p.has("potato_id"):
			entries.append(p)
	for p in plots:
		if p is Dictionary and not p.has("potato_id") and str(p.get("last", "")) != "":
			entries.append(p)
	var planted := 0
	for p in entries:
		if p.has("potato_id"):
			planted += 1
	if planted > int(out["sections_owned"]) * 6:
		out["sections_owned"] = 2  # never strand a growing crop on locked land
	var slots: Array = []
	for cols in [[0, 1], [2, 3]]:
		for row in range(3):
			for col in cols:
				slots.append("0:%d:%d" % [row, col])
	var tiles := {}
	var limit = mini(entries.size(), int(out["sections_owned"]) * 6)
	for i in range(limit):
		var src: Dictionary = entries[i]
		var td := {"plowed": true, "last": str(src.get("last", src.get("potato_id", "")))}
		if src.has("potato_id"):
			td["potato_id"] = src["potato_id"]
			td["planted_at"] = float(src.get("planted_at", 0.0))
			td["watered"] = bool(src.get("watered", false))
			td["boost"] = float(src.get("boost", 1.0))
			td["bonus_yield"] = int(src.get("bonus_yield", 0))
		tiles[slots[i]] = td
	out["tiles"] = tiles
	return out

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

# ── farm economy helpers ──

func wallet() -> int:
	return int(farm.get("wallet", 0))

func add_coins(amount: int):
	farm["wallet"] = wallet() + amount
	save_game()

func spend_coins(amount: int) -> bool:
	if wallet() < amount:
		return false
	farm["wallet"] = wallet() - amount
	save_game()
	return true

# Generic counter bump for the "seeds"/"spuds" inventories
func add_item(inventory: String, id: String, count: int = 1):
	var inv: Dictionary = farm.get(inventory, {})
	inv[id] = int(inv.get(id, 0)) + count
	if inv[id] <= 0:
		inv.erase(id)
	farm[inventory] = inv
	save_game()

func item_count(inventory: String, id: String) -> int:
	return int(farm.get(inventory, {}).get(id, 0))

func equipped_knife() -> Dictionary:
	# preload by path: autoloads compile before the global class_name cache
	# exists on a clean import, so "GameData" isn't resolvable here by name
	return preload("res://scripts/utils/GameData.gd").knife_by_id(farm.get("equipped_knife", "butter"))

func _save_json(filename: String, data) -> void:
	var file = FileAccess.open(SAVE_PATH + filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func _load_json(filename: String) -> Dictionary:
	var path = SAVE_PATH + filename
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
