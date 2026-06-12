extends RefCounted
class_name GameData

# Static loader for game-data resources (knives, potatoes).
# Data lives in resources/game_data/*.json so designers can tweak balance
# without touching code. Loaded once and cached.

const KNIVES_PATH = "res://resources/game_data/knives.json"
const POTATOES_PATH = "res://resources/game_data/potatoes.json"
const ITEMS_PATH = "res://resources/game_data/items.json"
const FIELDS_PATH = "res://resources/game_data/fields.json"

static var _knives: Array = []
static var _potatoes: Array = []
static var _tools: Array = []
static var _enhancers: Array = []
static var _fields: Dictionary = {}

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

# Farm tools (permanent, enable auto-farming) and growth enhancers
# (consumables applied to a planted plot)
static func tools() -> Array:
	if _tools.is_empty():
		_tools = _load_array(ITEMS_PATH, "tools")
	return _tools

static func enhancers() -> Array:
	if _enhancers.is_empty():
		_enhancers = _load_array(ITEMS_PATH, "enhancers")
	return _enhancers

static func tool_by_id(id: String) -> Dictionary:
	for tl in tools():
		if tl.get("id", "") == id:
			return tl
	return {}

static func enhancer_by_id(id: String) -> Dictionary:
	for e in enhancers():
		if e.get("id", "") == id:
			return e
	return {}

# Farm field geometry: tile cell size and the fenced fields with their
# purchasable sections (resources/game_data/fields.json)
static func field_cell() -> Vector2:
	var c: Array = _fields_data().get("cell", [140, 110])
	return Vector2(float(c[0]), float(c[1]))

static func fields() -> Array:
	return _fields_data().get("fields", [])

static func _fields_data() -> Dictionary:
	if _fields.is_empty():
		if FileAccess.file_exists(FIELDS_PATH):
			var file = FileAccess.open(FIELDS_PATH, FileAccess.READ)
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_fields = parsed
		else:
			push_warning("GameData: missing data file " + FIELDS_PATH)
	return _fields

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
