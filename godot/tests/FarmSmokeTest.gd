extends Node

# Headless farm-economy smoke test for the open-grid overhaul: plow an
# arbitrary patch of grass, plant/water/time-travel/harvest, run a sprinkler
# and fertilizer on the open grid, ship a load on the MARKET TRUCK (load →
# send → time-travel the return → coins + research points come back), buy a
# RESEARCH node and see its effect, confirm crops stay gated until researched,
# the [E] well refill, and the schema-2 -> schema-3 save migration.
# NOTE: writes to the user:// save like a real session would, and never
# triggers a scene change (that would free this test root).
#
#   godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600

var frames := 0
var farm
var fails: Array[String] = []

func _ready():
	# deterministic starting economy (rich enough to afford everything)
	SaveDataManager.farm = {
		"schema": 3, "wallet": 20000, "seeds": {}, "spuds": {}, "water": 0,
		"owned_knives": ["butter"], "equipped_knife": "butter",
		"tiles": {}, "plow_uses": 10, "plows_bought": 0, "sprinkler_stock": 0,
		"items": {}, "research_points": 0, "research": {},
		"truck": {"status": "idle", "cargo": {}, "return_at": 0.0,
				"pending_coins": 0, "pending_rp": 0}
	}
	farm = load("res://scenes/Farm/FarmScene.tscn").instantiate()
	add_child(farm)

func _check(cond: bool, what: String):
	if not cond:
		fails.append(what)

func _process(_delta):
	frames += 1
	match frames:
		10:
			_run_grid()
		16:
			_run_sprinkler_fertilizer()
		22:
			_run_truck()
		28:
			_run_research()
		34:
			# stand by the well with an empty can for the input probe
			SaveDataManager.farm["water"] = 0
			farm.player.position = FarmBackground.WELL_POS + Vector2(0, 60)
		38:
			_check(farm.prompt.begins_with("[E] Draw water"), "well prompt appears in range")
			_tap(KEY_E)
		42:
			_check(int(SaveDataManager.farm.get("water", 0)) == 4, "[E] at the well refills the can")
			# drop the scene before the migration test so its _process can't
			# write stale tiles over the migrated save
			farm.queue_free()
		48:
			_run_migration()
		54:
			_finish()

# ── the open grid: plow anywhere, grow, harvest ──
func _run_grid():
	var c := Vector2i(8, 6)
	_check(not farm.tile_map.has("8:6"), "an untouched cell has no tile (plain grass)")
	_check(farm.is_farmable_cell(c), "a mid-pasture cell is plowable")

	_check(farm.buy_seed("russet"), "seed purchase succeeds")
	_check(farm.plow_cell(c), "plowing virgin grass succeeds")
	var tile: FarmTile = farm.tile_map.get("8:6")
	_check(tile != null and tile.state == FarmTile.TState.PLOWED, "plowing creates a plowed tile")
	_check(farm.plow_uses() == 9, "plowing wears the plow")

	_check(farm.plant_on(tile, "russet"), "planting succeeds on plowed soil")
	_check(SaveDataManager.item_count("seeds", "russet") == 0, "planting consumes the seed")
	farm.fill_water()
	farm._water_tile(tile)
	_check(tile.watered, "tile is watered")

	var rp_before = SaveDataManager.research_points()
	tile.planted_at -= 10000.0
	_check(tile.progress() >= 1.0, "crop matures once grow_time passes")
	farm._harvest_tile(tile)
	var n = SaveDataManager.item_count("spuds", "russet")
	_check(n >= 2 and n <= 4, "harvest yields 2-4 potatoes (got %d)" % n)
	_check(tile.state == FarmTile.TState.PLOWED, "harvested soil stays plowed")
	_check(SaveDataManager.research_points() > rp_before, "harvesting grants research points")

	# persistence round-trip on the new col:row keys
	SaveDataManager.save_game()
	SaveDataManager.farm["wallet"] = -1
	SaveDataManager.load_game()
	_check(SaveDataManager.wallet() != -1, "wallet survives save/load")
	_check(SaveDataManager.farm.get("tiles", {}).get("8:6", {}).get("plowed", false), "open-grid tiles persist")

# ── sprinkler + fertilizer on the open grid ──
func _run_sprinkler_fertilizer():
	_check(farm.buy_sprinkler(), "sprinkler purchase succeeds")
	_check(farm.sprinkler_stock() == 1, "sprinkler lands in the pack")
	var sc := Vector2i(10, 8)
	_check(farm.place_sprinkler_cell(sc), "sprinkler drops onto open grass")
	var spr: FarmTile = farm.tile_map.get("10:8")
	_check(spr != null and spr.has_sprinkler and farm.sprinkler_stock() == 0, "placed sprinkler occupies the cell")

	farm.buy_seed("russet")
	var nc := Vector2i(9, 8)
	_check(farm.plow_cell(nc), "plow a neighbour of the sprinkler")
	var crop: FarmTile = farm.tile_map.get("9:8")
	farm.plant_on(crop, "russet")
	_check(not crop.watered, "fresh crop starts dry")
	farm._auto_farm()
	_check(crop.watered, "sprinkler auto-waters the neighbouring crop")

	_check(farm.pickup_sprinkler(spr), "sprinkler pickup succeeds")
	_check(farm.sprinkler_stock() == 1, "picked-up sprinkler returns to the pack")
	_check(not farm.tile_map.has("10:8"), "an emptied grass cell drops its tile node")

	_check(farm.buy_enhancer("compost"), "fertilizer purchase succeeds")
	_check(SaveDataManager.item_count("items", "compost") == 6, "compost comes with 6 charges")
	_check(farm.apply_enhancer(crop, "compost"), "fertilizer applies to a planted tile")
	_check(crop.boost == 0.7, "compost boosts growth")
	_check(not crop.enhance(0.5, 0), "only one application per crop")

# ── the market truck: load, ship, return with coins + research ──
func _run_truck():
	var spuds = SaveDataManager.item_count("spuds", "russet")
	_check(spuds > 0, "there are spuds to ship")
	_check(farm.truck_load("russet"), "load one spud onto the truck")
	_check(farm.truck_cargo_count() == 1, "cargo increments")
	_check(SaveDataManager.item_count("spuds", "russet") == spuds - 1, "loaded spud leaves the pantry")
	farm.truck_load_all()
	_check(farm.truck_cargo_count() == spuds, "load-all fills the truck from the pantry")

	var wallet_before = SaveDataManager.wallet()
	var rp_before = SaveDataManager.research_points()
	_check(farm.truck_send(), "sending the truck succeeds")
	_check(farm.truck_status() == "away", "the truck is away")
	var pending = int(farm._truck().get("pending_coins", 0))
	_check(pending > 0, "a payout is computed for the trip")
	_check(not farm.truck_send(), "can't send the truck while it's away")

	# time-travel the return so the test doesn't wait two minutes
	SaveDataManager.farm["truck"]["return_at"] = Time.get_unix_time_from_system() - 1.0
	farm.truck_tick()
	_check(farm.truck_status() == "idle", "the truck comes back idle")
	_check(SaveDataManager.wallet() == wallet_before + pending, "the payout lands in the wallet")
	_check(SaveDataManager.research_points() > rp_before, "the shipment grants research points")
	_check(farm.truck_cargo_count() == 0, "the cargo is cleared on return")

# ── research tree: spend coins + RP, gate crops ──
func _run_research():
	SaveDataManager.add_research_points(40)  # plenty to shop with
	var cap_before = farm.truck_capacity()
	var coins_before = SaveDataManager.wallet()
	var rp_before = SaveDataManager.research_points()
	_check(farm.buy_research("logi_cap1"), "buying a research node succeeds")
	_check(farm.has_research("logi_cap1"), "the node is marked researched")
	_check(farm.truck_capacity() == cap_before + 15, "research lifts the truck capacity")
	_check(SaveDataManager.wallet() == coins_before - 300, "research spends coins")
	_check(SaveDataManager.research_points() == rp_before - 4, "research spends research points")
	_check(not farm.buy_research("tool_radius"), "a node with an unmet prerequisite can't be bought")

	# crop gating
	_check(not _is_plantable("red"), "advanced crops are gated at the start")
	_check(_is_plantable("russet"), "starter crops are always plantable")
	_check(farm.buy_research("crop_red"), "unlocking a crop via research succeeds")
	_check(_is_plantable("red"), "the crop becomes plantable once researched")

func _is_plantable(id: String) -> bool:
	for p in farm.plantable_potatoes():
		if p["id"] == id:
			return true
	return false

# ── schema-2 -> schema-3 migration ──
func _run_migration():
	# a realistic schema-2 save: a fenced-field grid with a crop mid-growth, a
	# bare plot that remembers its crop, the old drone tool, and some spuds of
	# an "advanced" variety the player should keep access to.
	var old = {
		"schema": 2, "wallet": 777, "seeds": {"russet": 2}, "spuds": {"purple": 4},
		"water": 2, "owned_knives": ["butter", "paring"], "equipped_knife": "paring",
		"sections_owned": 2,
		"tiles": {
			"0:0:0": {"plowed": true, "potato_id": "red", "planted_at": 1700000000.0,
					"watered": true, "boost": 0.7, "bonus_yield": 0, "last": "red"},
			"0:0:1": {"plowed": true, "last": "yukon_gold"}
		},
		"plow_uses": 5, "plows_bought": 1, "sprinkler_stock": 1,
		"tools": ["harvest_drone"], "items": {"compost": 2}
	}
	SaveDataManager._save_json(SaveDataManager.FARM_FILE, old)
	SaveDataManager.load_game()

	var f: Dictionary = SaveDataManager.farm
	_check(int(f.get("schema", 0)) == 3, "save upgrades to schema 3")
	_check(not f.has("sections_owned"), "migration drops sections_owned")
	_check(not f.has("tools"), "migration drops the tools list")
	_check(SaveDataManager.wallet() == 777, "migration keeps the wallet")
	_check(SaveDataManager.item_count("items", "compost") == 2, "fertilizer charges survive")
	_check(SaveDataManager.has_research("tool_autoharvest"), "the old drone becomes a research node")

	# tiles repacked onto the open grid's central block, growing crop intact
	var tiles: Dictionary = f.get("tiles", {})
	var grown: Dictionary = tiles.get("5:5", {})
	_check(grown.get("potato_id", "") == "red" and float(grown.get("planted_at", 0)) == 1700000000.0
			and bool(grown.get("watered", false)), "the growing crop migrates intact")
	var bare: Dictionary = tiles.get("6:5", {})
	_check(bool(bare.get("plowed", false)) and str(bare.get("last", "")) == "yukon_gold"
			and not bare.has("potato_id"), "bare plowed soil migrates with its memory")

	# crops the player already owned are unlocked so gating can't hide them
	_check(SaveDataManager.has_research("crop_red"), "a growing crop's variety is unlocked")
	_check(SaveDataManager.has_research("crop_purple"), "an owned-spud variety is unlocked")

func _finish():
	if fails.is_empty():
		print("FARM SMOKE OK — open grid, sprinklers, truck, research and migration all hold")
		get_tree().quit(0)
	else:
		print("FARM SMOKE FAIL:")
		for f in fails:
			print("  - " + f)
		get_tree().quit(1)

func _tap(key: Key):
	var down = InputEventKey.new()
	down.keycode = key
	down.pressed = true
	get_tree().root.push_input(down)
	var up = InputEventKey.new()
	up.keycode = key
	up.pressed = false
	get_tree().root.push_input(up)
