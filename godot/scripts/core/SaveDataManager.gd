extends Node

# Persistent data management
# Handles leaderboard, achievements, unlocks, settings

const SAVE_PATH = "user://potato_game/"
const LEADERBOARD_FILE = "leaderboard.json"
const ACHIEVEMENTS_FILE = "achievements.json"
const SETTINGS_FILE = "settings.json"
const UNLOCKS_FILE = "unlocks.json"
const FARM_FILE = "farm.json"

# ── save slots ──
# The player keeps up to MAX_SLOTS fully independent save files. Each slot's
# data lives in its own subfolder (user://potato_game/slotN/), so a slot is the
# whole game state — leaderboard, achievements, unlocks, settings and farm. The
# active slot is recorded in a base-folder meta file (PROFILE_FILE) that is NOT
# per-slot, so the right slot loads on launch. A pre-slots save (files sitting
# directly in SAVE_PATH) is migrated into slot 1 on first run so nobody loses
# progress. Switch with switch_slot(); the menu's Settings screen drives it.
const MAX_SLOTS := 3
const PROFILE_FILE = "profile.json"
const DATA_FILES := [LEADERBOARD_FILE, ACHIEVEMENTS_FILE, SETTINGS_FILE, UNLOCKS_FILE, FARM_FILE]

var current_slot: int = 1
var _default_settings: Dictionary = {}   # captured at _ready, used to reset a slot
var _default_farm: Dictionary = {}

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
	"graphics_style": "classic",  # classic | pixel | hyperreal (see StyleManager)
	# SPUD BLASTER economy: "starch" is the premium currency, earned only by
	# winning a match and spent at the lobby Starch Exchange. "lifetime_starch"
	# is the all-time total that ranks the global leaderboard. fps_unlocks holds
	# bought skin ids and the exclusive "plasma_fryer"; fps_skin is the equipped
	# cosmetic tint.
	"starch": 0,
	"lifetime_starch": 0,
	"fps_unlocks": [],
	"fps_skin": "classic",
	# Chef career: XP earned from championship/endless runs (score / 100 each
	# run). Drives the rank ladder (RANKS) shown on the menu and gates the
	# top-tier knives (knives.json "unlock_xp"). Persisted here, not in `farm`.
	"career_xp": 0
}

# Career rank ladder: {xp floor, title}. career_rank() finds the highest floor
# the player has cleared. Mirrors the console edition's chef-rank flavour.
const RANKS := [
	{"floor": 0,     "name": "Dishwasher"},
	{"floor": 100,   "name": "Prep Cook"},
	{"floor": 300,   "name": "Line Cook"},
	{"floor": 700,   "name": "Sous Chef"},
	{"floor": 1500,  "name": "Chef de Partie"},
	{"floor": 3000,  "name": "Head Chef"},
	{"floor": 6000,  "name": "Executive Chef"},
	{"floor": 10000, "name": "Master Chef"},
	{"floor": 20000, "name": "Legendary Potato Master"},
]

# Farm + economy state (schema 3, free-form open grid). New games start with a
# few russet seeds, pocket change and a fresh plow so the farming loop can
# begin immediately. The whole pasture is one plowable grid: tiles are sparse
# (only plowed / planted / sprinkler cells exist), keyed "col:row" and holding
# {plowed, potato_id, planted_at (unix), watered, ...} — growth survives
# quitting because it's measured against the wall clock. Progression runs on
# the Research Shed (research points + coins) and crops haul to market on the
# truck. Schema-1 ("plots" array) and schema-2 ("field:row:col" + sections)
# saves migrate automatically (see _migrate_farm).
var farm: Dictionary = {
	"schema": 3,
	"wallet": 50,
	"seeds": {"russet": 3},
	"spuds": {},
	"water": 0,
	"owned_knives": ["butter"],
	"equipped_knife": "butter",
	"tiles": {},            # sparse "col:row" -> tile dict
	"plow_uses": 10,        # durability left on the current plow; 0 = broken
	"plows_bought": 0,      # replacement purchases — each one costs more
	"cover_freebies": 9,    # free "cover plot" uses; once spent, covering costs coins
	"sprinkler_stock": 0,   # sprinklers bought but not yet placed on a tile
	"items": {},            # fertilizer charges remaining, per enhancer id
	"research_points": 0,   # spent with coins on the research tree
	"research": {},         # unlocked research node ids -> true
	# market truck: load spuds, send it off, coins + RP arrive after a trip
	"truck": {"status": "idle", "cargo": {}, "return_at": 0.0,
			"pending_coins": 0, "pending_rp": 0},
	# Standing orders, configured at the farm's two order depots (each gated
	# behind its automation research). "crops"/"grade" name what's restocked,
	# "stock_target" how many to keep on hand. The Seed Co-op + Supply Depot
	# unlock once auto_buy_seeds / auto_buy_fertilizer are researched. Orders
	# pay a delivery premium over the shop price (see FarmController), so the
	# automated farm runs at a thinner margin than hands-on buying.
	"seed_order": {"enabled": true, "crops": ["russet", "yukon_gold"], "stock_target": 5},
	"fertilizer_order": {"enabled": true, "grade": "compost", "stock_target": 3}
}

func _ready():
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_PATH):
		DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	# Pristine copies of the new-game defaults, so switching to an empty slot
	# starts a clean game instead of inheriting the previous slot's state.
	_default_settings = settings.duplicate(true)
	_default_farm = farm.duplicate(true)
	# Pick the active slot (migrating a pre-slots save into slot 1 the first time).
	if FileAccess.file_exists(SAVE_PATH + PROFILE_FILE):
		var meta = _load_json_at(SAVE_PATH + PROFILE_FILE)
		current_slot = clampi(int(meta.get("slot", 1)), 1, MAX_SLOTS)
	else:
		_migrate_legacy_to_slot1()
		current_slot = 1
		_save_meta()
	DirAccess.make_dir_recursive_absolute(_slot_dir())
	load_game()

# ── save-slot plumbing ──

func _slot_dir() -> String:
	return SAVE_PATH + "slot%d/" % current_slot

func _save_meta():
	var file = FileAccess.open(SAVE_PATH + PROFILE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"slot": current_slot}, "\t"))
		file.close()

# One-time move of a pre-slots save (files sitting in SAVE_PATH) into slot 1.
func _migrate_legacy_to_slot1():
	var dst_dir := SAVE_PATH + "slot1/"
	DirAccess.make_dir_recursive_absolute(dst_dir)
	for fn in DATA_FILES:
		var src: String = SAVE_PATH + fn
		var dst: String = dst_dir + fn
		if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
			DirAccess.copy_absolute(src, dst)
			DirAccess.remove_absolute(src)

# Wipe the in-memory state back to new-game defaults, used before loading a slot
# so an empty slot doesn't keep the previous slot's progress.
func _reset_state_to_defaults():
	leaderboard.clear()
	achievements.clear()
	unlocked_knives.clear()
	settings = _default_settings.duplicate(true)
	farm = _default_farm.duplicate(true)

# Persist the current slot, switch to slot n (1..MAX_SLOTS), and load it — an
# empty slot loads the defaults, i.e. a fresh game. Returns true if the slot
# actually changed.
func switch_slot(n: int) -> bool:
	n = clampi(n, 1, MAX_SLOTS)
	if n == current_slot:
		return false
	save_game()
	current_slot = n
	_save_meta()
	DirAccess.make_dir_recursive_absolute(_slot_dir())
	_reset_state_to_defaults()
	load_game()
	return true

# True once a slot holds a started game (its farm save exists).
func slot_has_data(n: int) -> bool:
	return FileAccess.file_exists(SAVE_PATH + "slot%d/" % clampi(n, 1, MAX_SLOTS) + FARM_FILE)

# A short one-line summary of a slot for the menu (without switching to it).
func slot_summary(n: int) -> String:
	n = clampi(n, 1, MAX_SLOTS)
	if not slot_has_data(n):
		return "Empty — new game"
	var dir := SAVE_PATH + "slot%d/" % n
	var farm_d = _load_json_at(dir + FARM_FILE)
	var set_d = _load_json_at(dir + SETTINGS_FILE)
	return "%d coins · %d Chef XP" % [int(farm_d.get("wallet", 0)), int(set_d.get("career_xp", 0))]

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

# Bring any older farm save up to the current schema. Runs as a chain on the
# raw dict (before the defaults merge, so an old "schema" key can't mask it):
# schema-1 ("plots" array) -> schema-2 ("field:row:col" grid + sections) ->
# schema-3 (free-form "col:row" grid + research + truck).
func _migrate_farm(raw: Dictionary) -> Dictionary:
	if int(raw.get("schema", 1)) >= 3 and not raw.has("plots") \
			and not raw.has("plots_owned") and not raw.has("sections_owned"):
		return raw
	var out := raw
	if int(out.get("schema", 1)) < 2 or out.has("plots") or out.has("plots_owned"):
		out = _migrate_1_to_2(out)
	if int(out.get("schema", 2)) < 3:
		out = _migrate_2_to_3(out)
	return out

# schema-1 (fixed "plots" array, "plots_owned" counter, global "sprinkler"
# tool) -> schema-2 grid. Crops are re-homed onto Field 1's tiles, the old
# sprinkler becomes two placeable ones, and the player is handed a fresh plow.
func _migrate_1_to_2(raw: Dictionary) -> Dictionary:
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

# schema-2 ("field:row:col" grid, "sections_owned", drone/seeder in "tools")
# -> schema-3 (free-form "col:row" grid, research tree, market truck). Saved
# tiles are repacked into a clear central block of the open grid (no old field
# geometry needed), the old automation tools become research nodes, and every
# crop the player already owns is unlocked so crop-gating can't strand a save.
func _migrate_2_to_3(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	out["schema"] = 3
	out.erase("sections_owned")

	# old global automation tools become research nodes
	var research: Dictionary = out.get("research", {})
	var tools: Array = out.get("tools", [])
	if "harvest_drone" in tools:
		research["tool_autoharvest"] = true
	if "auto_seeder" in tools:
		research["tool_autoseed"] = true
	out.erase("tools")

	out["research_points"] = int(out.get("research_points", 0))
	if not out.has("truck"):
		out["truck"] = {"status": "idle", "cargo": {}, "return_at": 0.0,
				"pending_coins": 0, "pending_rp": 0}

	# Repack the old field tiles into a frozen block of open-grid cells. Order
	# is fixed (growing crops first, then plowed-with-memory, then bare plowed,
	# then sprinklers) so nothing important is dropped if the block is small.
	# The block sits in the open mid-pasture, clear of the house/well/pond/
	# truck/shed, so every destination cell is plowable. Constants are frozen
	# here so future map edits don't shuffle migrated saves.
	var old_tiles: Dictionary = out.get("tiles", {})
	var growing: Array = []
	var plowed_mem: Array = []
	var bare: Array = []
	var sprinklers: Array = []
	for k in old_tiles:
		var td = old_tiles[k]
		if not (td is Dictionary) or td.is_empty():
			continue
		if td.get("sprinkler", false):
			sprinklers.append(td)
		elif td.has("potato_id"):
			growing.append(td)
		elif str(td.get("last", "")) != "":
			plowed_mem.append(td)
		else:
			bare.append(td)
	var ordered: Array = growing + plowed_mem + bare + sprinklers

	const PACK_START := Vector2i(5, 6)
	const PACK_WIDTH := 12
	var tiles := {}
	for i in range(ordered.size()):
		var col = PACK_START.x + i % PACK_WIDTH
		var row = PACK_START.y + i / PACK_WIDTH
		tiles["%d:%d" % [col, row]] = ordered[i]
	out["tiles"] = tiles

	# Unlock every crop the player already holds (seeds, harvested spuds, or
	# growing in a tile) so the new crop-gating never hides their own potatoes.
	var owned_ids := {}
	for id in out.get("seeds", {}).keys():
		owned_ids[id] = true
	for id in out.get("spuds", {}).keys():
		owned_ids[id] = true
	for td in ordered:
		if td.has("potato_id"):
			owned_ids[str(td["potato_id"])] = true
		if str(td.get("last", "")) != "":
			owned_ids[str(td["last"])] = true
	var gd = preload("res://scripts/utils/GameData.gd")
	for node in gd.research_nodes():
		var eff: Dictionary = node.get("effect", {})
		if eff.has("unlock_crop") and owned_ids.has(eff["unlock_crop"]):
			research[node["id"]] = true
	out["research"] = research
	return out

func add_to_leaderboard(name: String, score: int, mode: String):
	# Sanitise/clamp before persisting so a crafted name or score can't corrupt
	# the local save or, later, the online submission (defence in depth).
	var entry = {
		"name": Security.sanitize_name(name, "CHEF"),
		"score": Security.clamp_int(score, 0, Security.MAX_SCORE),
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

# ── chef career XP + ranks ──

func career_xp() -> int:
	return int(settings.get("career_xp", 0))

# Adds XP and saves. Returns true when this push crossed into a new rank, so
# the results screen can celebrate a promotion.
func add_career_xp(amount: int) -> bool:
	if amount <= 0:
		return false
	var before: int = career_rank()["index"]
	settings["career_xp"] = career_xp() + amount
	save_game()
	return career_rank()["index"] > before

# Highest rank whose floor the player has cleared, with the next floor for the
# progress bar. {name, index, floor, next_floor}.
func career_rank() -> Dictionary:
	var xp := career_xp()
	var idx := 0
	for i in range(RANKS.size()):
		if xp >= int(RANKS[i]["floor"]):
			idx = i
	var next_floor := int(RANKS[idx]["floor"])
	if idx + 1 < RANKS.size():
		next_floor = int(RANKS[idx + 1]["floor"])
	return {
		"name": RANKS[idx]["name"],
		"index": idx,
		"floor": int(RANKS[idx]["floor"]),
		"next_floor": next_floor,
	}

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

# ── SPUD BLASTER premium economy (starch) ──

func starch() -> int:
	return int(settings.get("starch", 0))

func lifetime_starch() -> int:
	return int(settings.get("lifetime_starch", 0))

# Earned only by winning a match; bumps both the spendable balance and the
# all-time total that ranks the global leaderboard.
func add_starch(amount: int):
	settings["starch"] = starch() + amount
	settings["lifetime_starch"] = lifetime_starch() + maxi(0, amount)
	save_game()

func spend_starch(amount: int) -> bool:
	if starch() < amount:
		return false
	settings["starch"] = starch() - amount
	save_game()
	return true

# Starch Exchange unlocks (skin ids + the exclusive "plasma_fryer")
func fps_owns(id: String) -> bool:
	return id in settings.get("fps_unlocks", [])

func fps_unlock(id: String):
	var owned: Array = settings.get("fps_unlocks", [])
	if id not in owned:
		owned.append(id)
		settings["fps_unlocks"] = owned
		save_game()

func fps_skin() -> String:
	return str(settings.get("fps_skin", "classic"))

func set_fps_skin(id: String):
	settings["fps_skin"] = id
	save_game()

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

# ── research progression ──

func research_points() -> int:
	return int(farm.get("research_points", 0))

func add_research_points(n: int):
	farm["research_points"] = research_points() + n
	save_game()

func has_research(id: String) -> bool:
	return bool(farm.get("research", {}).get(id, false))

func unlock_research(id: String):
	var r: Dictionary = farm.get("research", {})
	r[id] = true
	farm["research"] = r
	save_game()

# Crop ids the player may currently plant: starter crops plus everything an
# unlocked research node grants via its "unlock_crop" effect.
func unlocked_crops() -> Array:
	var out: Array = []
	var gd = preload("res://scripts/utils/GameData.gd")
	for node in gd.research_nodes():
		if has_research(node.get("id", "")):
			var eff: Dictionary = node.get("effect", {})
			if eff.has("unlock_crop"):
				out.append(eff["unlock_crop"])
	return out

# Sum a numeric research effect (e.g. "plow_durability") across unlocked nodes.
func research_bonus(effect_key: String) -> float:
	var total := 0.0
	var gd = preload("res://scripts/utils/GameData.gd")
	for node in gd.research_nodes():
		if has_research(node.get("id", "")):
			var eff: Dictionary = node.get("effect", {})
			if eff.has(effect_key):
				total += float(eff[effect_key])
	return total

# Product of every unlocked "grow_mult" effect (1.0 = none), applied to crop
# grow times so research-sped crops keep growing correctly across reloads.
func grow_time_mult() -> float:
	var m := 1.0
	var gd = preload("res://scripts/utils/GameData.gd")
	for node in gd.research_nodes():
		if has_research(node.get("id", "")):
			var eff: Dictionary = node.get("effect", {})
			if eff.has("grow_mult"):
				m *= float(eff["grow_mult"])
	return m

# True when any unlocked node carries the given boolean effect (e.g. "auto_harvest").
func research_flag(effect_key: String) -> bool:
	var gd = preload("res://scripts/utils/GameData.gd")
	for node in gd.research_nodes():
		if has_research(node.get("id", "")):
			if bool(node.get("effect", {}).get(effect_key, false)):
				return true
	return false

func equipped_knife() -> Dictionary:
	# preload by path: autoloads compile before the global class_name cache
	# exists on a clean import, so "GameData" isn't resolvable here by name
	return preload("res://scripts/utils/GameData.gd").knife_by_id(farm.get("equipped_knife", "butter"))

func _save_json(filename: String, data) -> void:
	var file = FileAccess.open(_slot_dir() + filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func _load_json(filename: String) -> Dictionary:
	return _load_json_at(_slot_dir() + filename)

# Parse a JSON dict at an absolute user:// path (empty dict if missing/invalid).
# Used for the active slot, the meta file and peeking at other slots' summaries.
func _load_json_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
