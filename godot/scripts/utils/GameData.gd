extends RefCounted
class_name GameData

# Static loader for game-data resources (knives, potatoes, achievements).
# Data lives in resources/game_data/*.json so designers can tweak balance
# without touching code. Loaded once and cached. The farm's balance lives in
# farm.json and is read by scripts/farm/FarmEconomy.gd, not here.
#
# resources/game_data/legacy/ holds the FROZEN v4.0.0 (farm schema 3) tables:
# the research tree, the plow/sprinkler/fertilizer items and the old per-crop
# seed/sell/yield values. Only the save migration reads them (FarmMigration via
# SaveDataManager), so later balance edits can never change how an old save
# lands. Never edit those files.

const KNIVES_PATH = "res://resources/game_data/knives.json"
const POTATOES_PATH = "res://resources/game_data/potatoes.json"
const ACHIEVEMENTS_PATH = "res://resources/game_data/achievements.json"
const LEGACY_RESEARCH_PATH = "res://resources/game_data/legacy/research_v3.json"
const LEGACY_ITEMS_PATH = "res://resources/game_data/legacy/items_v3.json"
const LEGACY_CROPS_PATH = "res://resources/game_data/legacy/crops_v3.json"

static var _knives: Array = []
static var _potatoes: Array = []
static var _achievements: Array = []
static var _legacy_research: Array = []
static var _legacy_items: Dictionary = {}
static var _legacy_crops: Array = []

static func knives() -> Array:
	if _knives.is_empty():
		_knives = _load_array(KNIVES_PATH, "knives")
	return _knives

static func potatoes() -> Array:
	if _potatoes.is_empty():
		_potatoes = _load_array(POTATOES_PATH, "potatoes")
	return _potatoes

static func knife_by_id(id: String) -> Dictionary:
	for k in knives():
		if k.get("id", "") == id:
			return k
	return {}

static func potato_by_id(id: String) -> Dictionary:
	for p in potatoes():
		if p.get("id", "") == id:
			return p
	return {}

# Returns the regular (non-rare, non-rotten) potatoes for normal spawning.
static func standard_potatoes() -> Array:
	return potatoes().filter(func(p): return not p.get("rotten", false) and not p.get("rare", false))

# Achievement catalogue (resources/game_data/achievements.json): {id, name,
# desc}. Awarded at runtime via SaveDataManager.unlock_achievement(id).
static func achievements() -> Array:
	if _achievements.is_empty():
		_achievements = _load_array(ACHIEVEMENTS_PATH, "achievements")
	return _achievements

static func achievement_by_id(id: String) -> Dictionary:
	for a in achievements():
		if a.get("id", "") == id:
			return a
	return {}

# ── frozen schema-3 tables (save migration only) ──

# The v3 research tree: [{id, name, branch, cost_coins, cost_rp, requires,
# effect, ...}] (87 nodes).
static func legacy_research_nodes() -> Array:
	if _legacy_research.is_empty():
		_legacy_research = _load_array(LEGACY_RESEARCH_PATH, "nodes")
	return _legacy_research

# The v3 shop items: {"tools": [plow, sprinkler], "enhancers": [compost,
# super_grow, miracle_mulch]}.
static func legacy_items() -> Dictionary:
	if _legacy_items.is_empty():
		_legacy_items = {"tools": _load_array(LEGACY_ITEMS_PATH, "tools"),
				"enhancers": _load_array(LEGACY_ITEMS_PATH, "enhancers")}
	return _legacy_items

# The v3 per-crop farm values: [{id, seed_cost, grow_time, sell_value, yield}].
static func legacy_crops() -> Array:
	if _legacy_crops.is_empty():
		_legacy_crops = _load_array(LEGACY_CROPS_PATH, "crops")
	return _legacy_crops

# Everything FarmMigration.migrate_v3() needs, in the shape it takes.
static func legacy_tables() -> Dictionary:
	return {"research": legacy_research_nodes(), "items": legacy_items(), "crops": legacy_crops()}

static func _load_array(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("GameData: missing data file " + path)
		return []
	var file = FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.has(key):
		return parsed[key]
	return []
