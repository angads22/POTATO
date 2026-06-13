extends RefCounted
class_name GameData

# Static loader for game-data resources (knives, potatoes).
# Data lives in resources/game_data/*.json so designers can tweak balance
# without touching code. Loaded once and cached.

const KNIVES_PATH = "res://resources/game_data/knives.json"
const POTATOES_PATH = "res://resources/game_data/potatoes.json"
const ITEMS_PATH = "res://resources/game_data/items.json"
const RESEARCH_PATH = "res://resources/game_data/research.json"

# Crops a brand-new farm can plant before any research; the rest unlock via
# the Research Shed (see research.json "unlock_crop" effects).
const STARTER_CROPS = ["russet", "yukon_gold"]

static var _knives: Array = []
static var _potatoes: Array = []
static var _tools: Array = []
static var _enhancers: Array = []
static var _research: Array = []

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

# Farmable varieties the player may currently plant/buy: the starter crops
# plus any unlocked through research. Pass the unlocked-crop id list so this
# stays stateless (SaveDataManager.unlocked_crops()).
static func unlocked_potatoes(unlocked_ids: Array) -> Array:
	return farmable_potatoes().filter(
		func(p): return p["id"] in STARTER_CROPS or p["id"] in unlocked_ids)

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

# Research tree nodes (resources/game_data/research.json): permanent farm
# upgrades bought with coins + research points (logistics, tools, crops, growth).
static func research_nodes() -> Array:
	if _research.is_empty():
		_research = _load_array(RESEARCH_PATH, "nodes")
	return _research

static func research_by_id(id: String) -> Dictionary:
	for n in research_nodes():
		if n.get("id", "") == id:
			return n
	return {}

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
