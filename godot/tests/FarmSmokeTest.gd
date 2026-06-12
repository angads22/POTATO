extends Node

# Headless farm-economy smoke test: drives the grid-farming loop — buy a
# seed, plow a tile, plant, water, time-travel to maturity, harvest, sell,
# buy a knife, bank a run payout — then the grid features (plow durability
# and escalating price, section purchase, placeable sprinklers, multi-charge
# fertilizer, drone + seeder), the [E] interaction path at the well, and
# finally the schema-1 -> schema-2 save migration.
# NOTE: writes to the user:// save like a real session would, and never
# triggers a scene change (that would free this test root).
#
#   godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600

var frames := 0
var farm
var fails: Array[String] = []
var expected_wallet := 0

func _ready():
	# deterministic starting economy (rich enough to afford everything)
	SaveDataManager.farm = {
		"schema": 2, "wallet": 20000, "seeds": {}, "spuds": {}, "water": 0,
		"owned_knives": ["butter"], "equipped_knife": "butter",
		"sections_owned": 1, "tiles": {}, "plow_uses": 10, "plows_bought": 0,
		"sprinkler_stock": 0, "tools": [], "items": {}
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
			_run_economy()
		20:
			_run_grid_features()
		30:
			# stand by the well with an empty can for the input probe
			SaveDataManager.farm["water"] = 0
			farm.player.position = FarmBackground.WELL_POS + Vector2(0, 60)
		40:
			_check(farm.prompt.begins_with("[E] Draw water"), "well prompt appears in range")
			_tap(KEY_E)
		50:
			_check(int(SaveDataManager.farm.get("water", 0)) == 4, "[E] at the well refills the can")
			# drop the scene before the migration test so its _process can't
			# write stale tiles over the migrated save
			farm.queue_free()
		56:
			_run_migration()
		60:
			_finish()

func _run_economy():
	expected_wallet = SaveDataManager.wallet()

	# buy a seed
	_check(farm.buy_seed("russet"), "seed purchase succeeds")
	expected_wallet -= 10
	_check(SaveDataManager.wallet() == expected_wallet, "seed purchase charges 10 coins")
	_check(SaveDataManager.item_count("seeds", "russet") == 1, "seed lands in inventory")

	# wild ground refuses the seed until it's plowed
	var tile: FarmTile = farm.tiles[0]
	_check(tile.state == FarmTile.TState.UNPLOWED, "tiles start unplowed")
	_check(not farm.plant_on(tile, "russet"), "planting fails on unplowed ground")
	_check(SaveDataManager.item_count("seeds", "russet") == 1, "failed planting keeps the seed")
	_check(farm.plow_tile(tile), "plowing succeeds")
	_check(tile.state == FarmTile.TState.PLOWED, "tile is plowed")
	_check(farm.plow_uses() == 9, "plowing wears the plow")

	# plant it
	_check(farm.plant_on(tile, "russet"), "planting succeeds on plowed soil")
	_check(tile.state == FarmTile.TState.PLANTED, "tile is planted")
	_check(SaveDataManager.item_count("seeds", "russet") == 0, "planting consumes the seed")

	# water it
	farm.fill_water()
	farm._water_tile(tile)
	_check(tile.watered, "tile is watered")
	_check(int(SaveDataManager.farm.get("water", 0)) == 3, "watering uses a charge")

	# time-travel to maturity and harvest — the soil stays plowed
	tile.planted_at -= 10000.0
	_check(tile.progress() >= 1.0, "crop matures once grow_time passes")
	farm._harvest_tile(tile)
	var n = SaveDataManager.item_count("spuds", "russet")
	_check(n >= 2 and n <= 4, "harvest yields 2-4 potatoes (got %d)" % n)
	_check(tile.state == FarmTile.TState.PLOWED, "harvested soil stays plowed")
	_check(tile.last_potato_id == "russet", "soil remembers its last crop")

	# sell the harvest
	var earned = farm.sell_spuds("russet")
	expected_wallet += n * 6
	_check(earned == n * 6, "spuds sell at 6 coins each")
	_check(SaveDataManager.wallet() == expected_wallet, "sale lands in the wallet")

	# buy + equip a knife, and confirm it multiplies the slicing score
	_check(farm.buy_or_equip_knife("paring"), "knife purchase succeeds")
	expected_wallet -= 150
	_check(SaveDataManager.farm.get("equipped_knife", "") == "paring", "knife auto-equips")
	GameManager.start_game("endless")
	var pts = GameManager.add_score(100, "NORMAL")
	_check(pts == 110, "paring knife multiplies score x1.1 (got %d)" % pts)

	# a finished run banks coins_earned + score/20 into the wallet
	GameManager.current_state.score = 400
	GameManager.current_state.coins_earned = 10
	GameManager.end_game(true)
	expected_wallet += 30
	_check(GameManager.current_state.last_payout == 30, "run payout is coins + score/20")
	_check(SaveDataManager.wallet() == expected_wallet, "payout lands in the wallet")

	# persistence round-trip
	SaveDataManager.save_game()
	SaveDataManager.farm["wallet"] = -123
	SaveDataManager.load_game()
	_check(SaveDataManager.wallet() == expected_wallet, "wallet survives save/load")
	var saved_tiles: Dictionary = SaveDataManager.farm.get("tiles", {})
	_check(saved_tiles.get("0:0:0", {}).get("plowed", false) == true, "tile states persist")

	# a saved tile dict rebuilds a growing crop
	var ghost := FarmTile.new()
	ghost.from_dict({"plowed": true, "potato_id": "russet", "planted_at": 123.0, "watered": true, "last": "russet"})
	_check(ghost.state == FarmTile.TState.PLANTED and ghost.watered, "tile dict round-trips a crop")
	ghost.free()

func _run_grid_features():
	# ── section purchase ──
	var far_tile: FarmTile = farm.tile_map["0:0:2"]
	_check(far_tile.locked, "second section starts locked")
	_check(farm.sections_owned() == 1, "one section owned at the start")
	_check(farm.section_price(1) == 400, "second section costs 400")
	_check(farm.buy_section(), "section purchase succeeds")
	expected_wallet -= 400
	_check(not far_tile.locked, "bought section unlocks its tiles")
	_check(farm.sections_owned() == 2, "sections_owned advances")
	_check(farm.section_price(farm.sections_owned()) == 1000, "next section costs more")

	# ── plow durability and escalating price ──
	SaveDataManager.farm["plow_uses"] = 1
	_check(farm.plow_tile(farm.tile_map["0:0:1"]), "last plow use still works")
	_check(farm.plow_uses() == 0, "plow breaks at zero uses")
	_check(not farm.plow_tile(farm.tile_map["0:0:3"]), "broken plow can't till")
	_check(farm.plow_cost() == 150, "first replacement plow costs 150")
	_check(farm.buy_plow(), "plow purchase succeeds")
	expected_wallet -= 150
	_check(farm.plow_uses() == 10, "new plow arrives with 10 uses")
	_check(not farm.buy_plow(), "can't stack plows while one still works")
	_check(farm.plow_cost() == 250, "plow price escalates per purchase")

	# ── placeable sprinkler waters its neighbours ──
	_check(farm.buy_sprinkler(), "sprinkler purchase succeeds")
	expected_wallet -= 250
	_check(farm.sprinkler_stock() == 1, "sprinkler lands in the pack")
	var spr_tile: FarmTile = farm.tile_map["0:1:1"]
	farm.plow_tile(spr_tile)
	_check(farm.place_sprinkler(spr_tile), "sprinkler placement succeeds")
	_check(spr_tile.has_sprinkler and farm.sprinkler_stock() == 0, "placed sprinkler occupies the tile")
	farm.buy_seed("russet")
	expected_wallet -= 10
	_check(not farm.plant_on(spr_tile, "russet"), "can't plant on the sprinkler tile")
	_check(SaveDataManager.item_count("seeds", "russet") == 1, "blocked planting keeps the seed")
	var crop: FarmTile = farm.tile_map["0:1:0"]
	farm.plow_tile(crop)
	farm.plant_on(crop, "russet")
	_check(not crop.watered, "fresh crop starts dry")
	farm._auto_farm()
	_check(crop.watered, "sprinkler auto-waters the tile beside it")
	_check(farm.pickup_sprinkler(spr_tile), "sprinkler pickup succeeds")
	_check(not spr_tile.has_sprinkler and farm.sprinkler_stock() == 1, "picked-up sprinkler returns to the pack")
	_check(spr_tile.state == FarmTile.TState.PLOWED, "soil under a sprinkler stays plowed")

	# ── multi-charge fertilizer ──
	_check(farm.buy_enhancer("compost"), "fertilizer purchase succeeds")
	expected_wallet -= 90
	_check(SaveDataManager.item_count("items", "compost") == 6, "compost comes with 6 charges")
	_check(farm.apply_enhancer(crop, "compost"), "fertilizer applies to a planted tile")
	_check(crop.boost == 0.7, "compost boosts growth")
	_check(SaveDataManager.item_count("items", "compost") == 5, "applying uses one charge")
	_check(not crop.enhance(0.5, 0), "only one application per crop")

	# ── drone harvests, seeder replants plowed soil ──
	_check(farm.buy_tool("harvest_drone"), "drone purchase succeeds")
	expected_wallet -= 600
	_check(farm.buy_tool("auto_seeder"), "seeder purchase succeeds")
	expected_wallet -= 900
	_check(not farm.buy_tool("harvest_drone"), "tools can't be bought twice")
	crop.planted_at -= 10000.0
	crop.state = FarmTile.TState.READY
	var before = SaveDataManager.item_count("spuds", "russet")
	farm._auto_farm()
	var pulled = SaveDataManager.item_count("spuds", "russet") - before
	_check(pulled >= 2 and pulled <= 4, "drone harvests the ready tile (got %d)" % pulled)
	_check(crop.state == FarmTile.TState.PLOWED, "drone leaves the soil plowed")
	# the seeder replants the first plowed tile that remembers a crop (0:0:0)
	farm.buy_seed("russet")
	expected_wallet -= 10
	farm._auto_farm()
	_check(farm.tiles[0].state == FarmTile.TState.PLANTED and farm.tiles[0].potato_id == "russet",
			"auto-seeder replants the last crop")

	_check(SaveDataManager.wallet() == expected_wallet, "wallet math holds through the grid features")

func _run_migration():
	# a realistic schema-1 save: 12 plots with a crop mid-growth on plot 7,
	# a bare plot that remembers its crop, the old global sprinkler, and a
	# pair of single-use composts
	var old_plots: Array = []
	old_plots.resize(12)
	for i in range(12):
		old_plots[i] = {}
	old_plots[7] = {"potato_id": "red", "planted_at": 1700000000.0, "watered": true,
			"boost": 0.7, "bonus_yield": 0, "last": "red"}
	old_plots[2] = {"last": "yukon_gold"}
	var old = {
		"wallet": 777, "seeds": {"russet": 2}, "spuds": {"russet": 4},
		"plots": old_plots, "water": 2, "owned_knives": ["butter", "paring"],
		"equipped_knife": "paring", "plots_owned": 12,
		"tools": ["sprinkler", "harvest_drone"], "items": {"compost": 2}
	}
	SaveDataManager._save_json(SaveDataManager.FARM_FILE, old)
	SaveDataManager.load_game()

	var f: Dictionary = SaveDataManager.farm
	_check(not f.has("plots") and not f.has("plots_owned"), "migration drops the schema-1 keys")
	_check(SaveDataManager.wallet() == 777, "migration keeps the wallet")
	_check(int(f.get("sections_owned", 0)) == 2, "12 owned plots map to both Field 1 sections")
	_check(int(f.get("sprinkler_stock", 0)) == 2, "old sprinkler network becomes 2 placeable ones")
	_check(not "sprinkler" in f.get("tools", []) and "harvest_drone" in f.get("tools", []),
			"tool list migrates")
	_check(int(f.get("plow_uses", 0)) == 10, "migrated saves get a starting plow")
	_check(SaveDataManager.item_count("items", "compost") == 2, "old enhancers become charges 1:1")
	var tiles: Dictionary = f.get("tiles", {})
	var planted: Dictionary = tiles.get("0:0:0", {})
	_check(planted.get("potato_id", "") == "red" and float(planted.get("planted_at", 0)) == 1700000000.0
			and bool(planted.get("watered", false)), "growing crop migrates intact")
	var bare: Dictionary = tiles.get("0:0:1", {})
	_check(bool(bare.get("plowed", false)) and str(bare.get("last", "")) == "yukon_gold"
			and not bare.has("potato_id"), "bare plots migrate as plowed soil")

func _finish():
	if fails.is_empty():
		print("FARM SMOKE OK — plow, sections, sprinklers, fertilizer and migration all hold")
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
