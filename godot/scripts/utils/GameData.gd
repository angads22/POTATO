extends RefCounted
class_name GameData

# Static loader for game-data resources (knives, potatoes).
# Data lives in resources/game_data/*.json so designers can tweak balance
# without touching code. Loaded once and cached.

const KNIVES_PATH = "res://resources/game_data/knives.json"
const POTATOES_PATH = "res://resources/game_data/potatoes.json"

static var _knives: Array = []
static var _potatoes: Array = []

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

# Varieties that can be planted on the farm (anything with a seed price).
static func farmable_potatoes() -> Array:
	return potatoes().filter(func(p): return p.has("seed_cost"))

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
