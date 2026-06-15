extends Node

# Headless farm-economy smoke test for the open-grid overhaul: plow an
# arbitrary patch of grass, plant/water/time-travel/harvest, run a sprinkler
# and fertilizer on the open grid, ship a load on the MARKET TRUCK (load →
# send → time-travel the return → coins + research points come back), buy a
# RESEARCH node and see its effect, confirm crops stay gated until researched,
# cover a plowed plot back over (freebies then coins, no plow refund), the
# [E] well refill, and the schema-2 -> schema-3 save migration.
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
		"tiles": {}, "plow_uses": 10, "plows_bought": 0, "cover_freebies": 9,
		"sprinkler_stock": 0,
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
		30:
			_run_plow_modes()
		31:
			_run_cover()
		32:
			_run_automation()
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
	var c := Vector2i(4, 7)
	_check(not farm.tile_map.has("4:7"), "an untouched cell has no tile (plain grass)")
	_check(farm.is_farmable_cell(c), "a mid-pasture cell is plowable")

	# dirt paths stay clear: a path cell is farmland-shaped ground but no plot
	# can be opened on it, and a rejected plow wastes nothing
	var path_cell := Vector2i(6, 5)
	_check(FarmBackground.on_path(farm.cell_center(path_cell)), "the (6,5) cell sits on the dividing path")
	_check(farm.is_farmable_cell(path_cell), "a path cell is still farmland-shaped ground")
	_check(not farm.is_plowable_cell(path_cell), "but a dirt-path cell isn't plowable")
	_check(not farm.plow_cell(path_cell), "plowing a path is rejected")
	_check(not farm.tile_map.has("6:5"), "a rejected path-plow leaves no tile behind")
	_check(farm.plow_uses() == 10, "a rejected path-plow wastes no plow uses")

	_check(farm.buy_seed("russet"), "seed purchase succeeds")
	_check(farm.plow_cell(c), "plowing virgin grass succeeds")
	var tile: FarmTile = farm.tile_map.get("4:7")
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
	_check(SaveDataManager.farm.get("tiles", {}).get("4:7", {}).get("plowed", false), "open-grid tiles persist")

# ── sprinkler + fertilizer on the open grid ──
func _run_sprinkler_fertilizer():
	_check(farm.buy_sprinkler(), "sprinkler purchase succeeds")
	_check(farm.sprinkler_stock() == 1, "sprinkler lands in the pack")
	_check(not farm.place_sprinkler_cell(Vector2i(6, 5)), "a sprinkler can't be dropped on a path")
	_check(farm.sprinkler_stock() == 1, "a rejected path-sprinkler stays in the pack")
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
	_check(SaveDataManager.research_points() == rp_before - 3, "research spends research points")
	_check(not farm.buy_research("tool_radius"), "a node with an unmet prerequisite can't be bought")

	# crop gating
	_check(not _is_plantable("red"), "advanced crops are gated at the start")
	_check(_is_plantable("russet"), "starter crops are always plantable")
	_check(farm.buy_research("crop_red"), "unlocking a crop via research succeeds")
	_check(_is_plantable("red"), "the crop becomes plantable once researched")

	_run_research_map()

# ── node-map backend: full graph, locked/available state, navigation ──
func _run_research_map():
	SaveDataManager.add_research_points(200)  # plenty to shop the tree with

	# the map draws every node; the buyable frontier is a strict subset
	var all = farm.research_all_nodes()
	_check(all.size() == GameData.research_nodes().size(), "research_all_nodes returns every node")
	_check(all.size() > farm.research_menu_nodes().size(), "the frontier is a subset of all nodes")

	# every node carries a valid, unique [gridX, gridY] position
	var seen := {}
	var pos_ok := true
	for node in all:
		var p = node.get("pos", null)
		if not (p is Array) or p.size() != 2:
			pos_ok = false
		else:
			var k = "%d:%d" % [int(p[0]), int(p[1])]
			if seen.has(k):
				pos_ok = false
			seen[k] = true
	_check(pos_ok, "every research node has a unique [gridX, gridY] pos")

	# locked / available classification (logi_cap1 + crop_red are owned by now)
	_check(farm.research_locked(GameData.research_by_id("tool_radius2")), "a node with an unmet prereq is locked")
	_check(not farm.research_locked(GameData.research_by_id("grow_speed1")), "an available root is not locked")
	_check(not farm.research_locked(GameData.research_by_id("logi_cap1")), "an owned node is not locked")

	# directional selection moves to a real neighbour, and stops at the edge
	farm.research_sel_id = "logi_cap1"
	farm.research_select_dir(Vector2.DOWN)
	_check(farm.research_sel_id != "logi_cap1" and farm.research_sel_id != "", "DOWN moves the selection")
	farm.research_sel_id = "logi_speed1"   # top-row node, nothing above it
	farm.research_select_dir(Vector2.UP)
	_check(farm.research_sel_id == "logi_speed1", "selecting past the edge keeps the selection")

	# buying acts on the SELECTED node (the UI path), not a number index
	farm.research_sel_id = "tool_dura1"
	_check(farm.buy_research(farm.research_sel_id), "buying the selected node works")
	_check(farm.has_research("tool_dura1"), "the selected-node buy is applied")

	# new tiers sum through the existing effect plumbing (pure data)
	_check(SaveDataManager.research_bonus("plow_durability") == 5.0, "one durability node sums to +5")
	_check(farm.buy_research("tool_dura2"), "a deeper tier unlocks once its prereq is owned")
	_check(SaveDataManager.research_bonus("plow_durability") == 13.0, "stacked durability nodes sum to +13")
	_check(farm.buy_research("grow_speed1") and farm.buy_research("grow_speed2"),
			"stacked growth-speed tiers buy in order")
	_check(abs(SaveDataManager.grow_time_mult() - 0.7225) < 0.0001, "two grow_mult tiers multiply (0.85 x 0.85)")

	# championship hooks expose their bonus through research_bonus
	_check(farm.buy_research("champ_lucky"), "a championship node buys")
	_check(SaveDataManager.research_bonus("golden_luck") > 0.0, "Lucky Spuds raises golden_luck")
	_check(farm.buy_research("champ_field"), "Field Research buys")
	_check(SaveDataManager.research_bonus("champ_rp_per") > 0.0, "Field Research grants champ_rp_per")

# ── plow modes: research a wider plow, switch sizes, plow a single tile ──
func _run_plow_modes():
	SaveDataManager.farm["wallet"] = 20000
	SaveDataManager.add_research_points(50)
	SaveDataManager.farm["plow_uses"] = 30
	SaveDataManager.farm.erase("plow_mode")
	_check(farm.max_plow_radius() == 0, "no wide plow researched yet")
	_check(farm.buy_research("tool_radius"), "Wide Plow researches once its prereq is owned")
	_check(farm.max_plow_radius() == 1, "Wide Plow lifts the max plow radius to 1 (3x3)")
	_check(farm.plow_radius() == 1, "the active plow defaults to the widest size")
	_check(farm.plow_size_label() == "3×3", "the active size reads 3×3")
	farm.cycle_plow_mode()
	_check(farm.plow_radius() == 0, "[X] cycles down to the single-tile plow")
	# a 1x1 plow stamps exactly one cell, leaving the neighbours untouched
	var c := Vector2i(13, 7)
	_check(farm.plow_cell(c), "single-tile plow succeeds")
	_check(farm.tile_map.has("13:7"), "the targeted cell is plowed")
	_check(not farm.tile_map.has("12:7") and not farm.tile_map.has("14:7"),
			"a 1x1 plow leaves the neighbours untouched")
	farm.cycle_plow_mode()
	_check(farm.plow_radius() == 1, "[X] cycles back up to 3x3")
	# leave the plow on single-tile so the cover test below stamps one cell
	SaveDataManager.farm["plow_mode"] = 0

# ── cover a plot back over: freebies first, then coins, plow never refunded ──
func _run_cover():
	var c := Vector2i(7, 9)
	_check(farm.cover_freebies() == 9, "cover: 9 freebies to start")
	_check(farm.plow_cell(c), "cover: plow a fresh plot to cover")
	var tile: FarmTile = farm.tile_map.get("7:9")
	_check(tile != null and tile.state == FarmTile.TState.PLOWED, "cover: plot starts plowed")
	var uses_before = farm.plow_uses()
	_check(farm.cover_tile(tile), "cover: a freebie cover succeeds")
	_check(farm.cover_freebies() == 8, "cover: a freebie is spent")
	_check(not farm.tile_map.has("7:9"), "cover: covered plot reverts to wild grass")
	_check(farm.plow_uses() == uses_before, "cover: covering doesn't refund the plow")

	# once the freebies are gone, a cover costs coins
	SaveDataManager.farm["cover_freebies"] = 0
	_check(farm.cover_cost() == FarmController.COVER_COST, "cover: costs coins with no freebies")
	farm.plow_cell(c)
	var tile2: FarmTile = farm.tile_map.get("7:9")
	var wallet_before = SaveDataManager.wallet()
	_check(farm.cover_tile(tile2), "cover: a paid cover succeeds")
	_check(SaveDataManager.wallet() == wallet_before - FarmController.COVER_COST, "cover: paid cover spends coins")
	_check(not farm.tile_map.has("7:9"), "cover: paid-covered plot is wild again")

	# broke and out of freebies: covering is refused (land stays plowed)
	SaveDataManager.farm["wallet"] = 0
	farm.plow_cell(c)
	var tile3: FarmTile = farm.tile_map.get("7:9")
	_check(not farm.cover_tile(tile3), "cover: blocked when broke and out of freebies")
	_check(farm.tile_map.has("7:9") and tile3.state == FarmTile.TState.PLOWED, "cover: a refused cover leaves the plot plowed")
	# refill the wallet so later steps (research already ran) aren't starved
	SaveDataManager.farm["wallet"] = 20000

func _is_plantable(id: String) -> bool:
	for p in farm.plantable_potatoes():
		if p["id"] == id:
			return true
	return false

func _tab_has(nodes: Array, id: String) -> bool:
	for n in nodes:
		if str(n.get("id", "")) == id:
			return true
	return false

func _planted_count() -> int:
	var n = 0
	for t in farm.tiles:
		if t.state == FarmTile.TState.PLANTED:
			n += 1
	return n

# ── automation track: tab split, per-tick field automation + purchase orders ──
func _run_automation():
	# the two tabs partition every node; the moved drones live on the automation tab
	var prog = farm.research_nodes_for_tab("progression")
	var auto = farm.research_nodes_for_tab("automation")
	_check(auto.size() >= 8, "the automation tab holds the new track")
	_check(prog.size() + auto.size() == farm.research_all_nodes().size(), "the tabs partition every node")
	_check(_tab_has(auto, "tool_autoharvest") and _tab_has(auto, "tool_autoseed"),
			"auto-harvest/seed were consolidated onto the automation tab")

	SaveDataManager.farm["wallet"] = 20000
	SaveDataManager.farm["plow_uses"] = 50
	SaveDataManager.farm["plow_mode"] = 0   # single-tile plow for predictable setup
	var res: Dictionary = SaveDataManager.farm["research"]

	# auto-water irrigates a dry crop on the tick
	var wt: FarmTile = farm.tile_map.get("15:7")
	if wt == null:
		farm.plow_cell(Vector2i(15, 7)); wt = farm.tile_map.get("15:7")
	farm.buy_seed("russet"); farm.plant_on(wt, "russet")
	_check(not wt.watered, "automation: a fresh crop starts dry")
	res["auto_water"] = true
	farm._auto_farm()
	_check(wt.watered, "automation: Drip Irrigation auto-waters dry crops")

	# auto-fertilize buys a bag (subscription) and works it into the crop
	_check(wt.boost >= 1.0, "automation: crop starts unfertilized")
	SaveDataManager.farm["items"] = {}
	res["auto_fertilize"] = true
	res["auto_buy_fertilizer"] = true
	farm._auto_farm()
	_check(wt.boost < 1.0, "automation: Nutrient Injector auto-fertilizes (auto-bought)")

	# seed standing order: restock helper buys a seed, spends coins
	SaveDataManager.farm["seeds"] = {}
	var coins0 = SaveDataManager.wallet()
	_check(farm._auto_restock_seed("russet"), "automation: the seed standing order buys a seed")
	_check(SaveDataManager.item_count("seeds", "russet") == 1, "automation: the bought seed lands in the pouch")
	_check(SaveDataManager.wallet() < coins0, "automation: the seed purchase order spends coins")

	# auto-seed + purchase order replant an empty-pouch plot
	SaveDataManager.farm["seeds"] = {}
	var sc: FarmTile = farm.tile_map.get("16:7")
	if sc == null:
		farm.plow_cell(Vector2i(16, 7)); sc = farm.tile_map.get("16:7")
	sc.last_potato_id = "russet"
	res["tool_autoseed"] = true   # the node id behind the auto_seed effect
	res["auto_buy_seeds"] = true
	var planted_before = _planted_count()
	var coins1 = SaveDataManager.wallet()
	farm._auto_farm()
	_check(_planted_count() > planted_before, "automation: auto-seed replants via the purchase order")
	_check(SaveDataManager.wallet() < coins1, "automation: replanting auto-buys seeds")

	# auto-dispatch ships the idle truck
	SaveDataManager.add_item("spuds", "russet", 6)
	SaveDataManager.farm["truck"] = {"status": "idle", "cargo": {}, "return_at": 0.0,
			"pending_coins": 0, "pending_rp": 0}
	res["auto_truck"] = true
	farm._auto_farm()
	_check(farm.truck_status() == "away", "automation: Auto-Dispatch loads and ships the truck")

	# the tick speeds up with the auto_speed research, clamped at the floor
	var base_iv = farm.auto_interval()
	res["auto_speed1"] = true
	_check(farm.auto_interval() < base_iv, "automation: auto_speed shortens the tick")
	res["auto_speed2"] = true
	_check(farm.auto_interval() >= 0.25, "automation: the tick is clamped at its floor")

	# batched auto-harvest clears every ready crop in one tick (no one-per-tick)
	SaveDataManager.farm["seeds"] = {}  # stop auto-seed from refilling the plots
	res.erase("tool_autoseed")
	res.erase("auto_buy_seeds")
	for cell in [Vector2i(15, 9), Vector2i(16, 9), Vector2i(17, 9)]:
		farm.plow_cell(cell)
		var t: FarmTile = farm.tile_map.get("%d:%d" % [cell.x, cell.y])
		farm.buy_seed("russet"); farm.plant_on(t, "russet")
		t.planted_at -= 10000.0  # mature it now (FarmTile._process flips READY next frame)
		_check(t.progress() >= 1.0, "automation: crop matured for harvest")
		t.state = FarmTile.TState.READY  # force the state this frame for auto-harvest
	res["tool_autoharvest"] = true   # the node id behind the auto_harvest effect
	farm._auto_farm()
	var any_ready := false
	for cell in [Vector2i(15, 9), Vector2i(16, 9), Vector2i(17, 9)]:
		var t2: FarmTile = farm.tile_map.get("%d:%d" % [cell.x, cell.y])
		if t2 != null and t2.state == FarmTile.TState.READY:
			any_ready = true
	_check(not any_ready, "automation: auto-harvest clears all ready crops in one tick")

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

	# tiles repacked onto the open field's central block, growing crop intact
	var tiles: Dictionary = f.get("tiles", {})
	var grown: Dictionary = tiles.get("5:6", {})
	_check(grown.get("potato_id", "") == "red" and float(grown.get("planted_at", 0)) == 1700000000.0
			and bool(grown.get("watered", false)), "the growing crop migrates intact")
	var bare: Dictionary = tiles.get("6:6", {})
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
