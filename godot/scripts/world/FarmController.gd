extends WorldController
class_name FarmController

# The farm: walk the chef potato around the homestead and work the land. The
# whole pasture is one free-form grid — plow any patch of grass (the plow wears
# out), plant and water crops, and haul the harvest to the market TRUCK by the
# top hedge to ship it for coins. Tiles are sparse: a FarmTile exists only once
# a cell is plowed or holds a sprinkler. Progression runs on the RESEARCH SHED
# (research points + coins buy permanent upgrades and unlock new crops). Coins
# persist in SaveDataManager.farm and flow both ways — slicing runs bank coins,
# the farm grows potatoes, and better knives multiply slicing scores.

# Open-grid geometry: cell size matches the FarmTile art (130x90 on a 140x110
# cell); the grid is conceptual, no node exists for plain grass.
const CELL := Vector2(140, 110)
const GRID_ORIGIN := Vector2(70, 70)   # world position of cell (0,0)'s centre
# interior bounds a cell centre must sit inside to be plowable (off the hedge)
const FARM_MARGIN := Vector2(110, 120)

var bg: FarmBackground
var fireflies: CPUParticles2D
var tiles: Array[FarmTile] = []
var tile_map: Dictionary = {}      # "col:row" -> FarmTile
var plant_target: FarmTile = null
var enhance_target: FarmTile = null
var prompt_tile: FarmTile = null   # tile the current prompt refers to (or null)
var prompt_cell := Vector2i.ZERO   # grid cell the prompt refers to
var prompt_cell_valid := false     # true when prompt_cell is virgin grass
var auto_t := 0.0                  # auto-farming tick accumulator

func _ready():
	super._ready()
	_show_banner("POTATO FARM")

func _world_size() -> Vector2:
	return FarmBackground.WORLD

func _spawn_point() -> Vector2:
	if WorldController.travel_spawn == "from_town":
		WorldController.travel_spawn = ""
		return Vector2(2410, 870)
	return Vector2(1450, 620)

func _build_world():
	bg = FarmBackground.new()
	add_child(bg)
	world_bg = bg

	blockers = [
		FarmBackground.HOUSE_WALL.grow(6),
		Rect2(FarmBackground.WELL_POS - Vector2(55, 45), Vector2(110, 90)),
		FarmBackground.TRUCK_RECT.grow(6),
		FarmBackground.RESEARCH_WALL.grow(6),
	]

	_restore_tiles()

	# fireflies wake up at night around the pond
	fireflies = CPUParticles2D.new()
	fireflies.position = FarmBackground.POND_C + Vector2(0, -60)
	fireflies.amount = 26
	fireflies.lifetime = 4.0
	fireflies.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	fireflies.emission_sphere_radius = 320.0
	fireflies.gravity = Vector2.ZERO
	fireflies.initial_velocity_min = 6.0
	fireflies.initial_velocity_max = 22.0
	fireflies.scale_amount_min = 1.5
	fireflies.scale_amount_max = 3.0
	fireflies.color = Color(0.85, 1.0, 0.5, 0.85)
	fireflies.emitting = false
	fireflies.z_index = 3
	add_child(fireflies)

# Rebuild the sparse tile nodes from the save (only plowed/planted/sprinkler
# cells were ever stored), so crops kept growing while away.
func _restore_tiles():
	var saved: Dictionary = SaveDataManager.farm.get("tiles", {})
	for k in saved:
		if not (saved[k] is Dictionary) or saved[k].is_empty():
			continue
		var c = key_to_cell(k)
		var tile := FarmTile.new()
		tile.col = c.x
		tile.row = c.y
		tile.position = cell_center(c)
		tile.from_dict(saved[k])
		add_child(tile)
		tiles.append(tile)
		tile_map[tile.key()] = tile

# ── grid helpers ──

func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(int(round((world.x - GRID_ORIGIN.x) / CELL.x)),
			int(round((world.y - GRID_ORIGIN.y) / CELL.y)))

func cell_center(c: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(c.x * CELL.x, c.y * CELL.y)

func cell_key(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]

func key_to_cell(k: String) -> Vector2i:
	var parts = k.split(":")
	return Vector2i(int(parts[0]), int(parts[1]))

# The one place that decides "can I plow here": inside the interior bounds and
# walkable (so not under the house, well, truck, shed or pond).
func is_farmable_cell(c: Vector2i) -> bool:
	var p = cell_center(c)
	if p.x < FARM_MARGIN.x or p.x > world_size.x - FARM_MARGIN.x:
		return false
	if p.y < FARM_MARGIN.y or p.y > world_size.y - FARM_MARGIN.y:
		return false
	return _walkable(p)

func _ensure_tile(c: Vector2i) -> FarmTile:
	var k = cell_key(c)
	if tile_map.has(k):
		return tile_map[k]
	var tile := FarmTile.new()
	tile.col = c.x
	tile.row = c.y
	tile.position = cell_center(c)
	add_child(tile)
	tiles.append(tile)
	tile_map[k] = tile
	return tile

# Drop a tile that has reverted to plain grass (unplowed, no sprinkler, no crop)
# so the sparse map and the save don't accumulate empty cells.
func _drop_tile(tile: FarmTile):
	if not tile.to_dict().is_empty():
		return
	tiles.erase(tile)
	tile_map.erase(tile.key())
	tile.queue_free()

func _tick(delta):
	fireflies.emitting = night01 > 0.5
	truck_tick()
	# auto-farming gear works the land every couple of seconds
	auto_t += delta
	if auto_t >= 2.0:
		auto_t = 0.0
		_auto_farm()

func _walkable(p: Vector2) -> bool:
	if not super._walkable(p):
		return false
	var d = (p - FarmBackground.POND_C) / (FarmBackground.POND_R + Vector2(28, 30))
	return d.length() > 1.0

# ────────────────────────────────────────────────────────
#  Interactions
# ────────────────────────────────────────────────────────

func _scan_interactions():
	prompt = ""
	prompt_action = Callable()
	prompt_tile = null
	prompt_cell_valid = false
	if open_shop != "":
		return

	# Stations first — the player is always standing over some grid cell now,
	# so a cell prompt would otherwise mask the well/truck/shed/gate prompts.
	var stations = [
		{"pos": FarmBackground.WELL_POS + Vector2(0, 50), "r": 110.0,
			"text": "[E] Draw water — refill the can", "act": fill_water},
		{"pos": FarmBackground.TRUCK_POS, "r": 130.0, "act": _truck_station},
		{"pos": FarmBackground.RESEARCH_POS, "r": 120.0,
			"text": "[E] Open the Research Shed", "act": _open_research},
		{"pos": Vector2(FarmBackground.HOUSE_WALL.get_center().x, FarmBackground.HOUSE_WALL.end.y + 25), "r": 100.0,
			"text": "[E] Nap until morning", "act": _nap},
		{"pos": FarmBackground.TOWN_GATE_POS, "r": 120.0,
			"text": "[E] Take the road into town", "act": _goto_town},
	]
	for s in stations:
		if player.position.distance_to(s.pos) < s.r:
			if s.has("act") and (s["act"] as Callable).is_valid() and not s.has("text"):
				s["act"].call()  # station builds its own prompt (the truck)
			else:
				prompt = s.text
				prompt_action = s.act
			return

	# Otherwise act on the cell under the player's feet
	var c = cell_of(player.position)
	if not is_farmable_cell(c):
		return
	var existing = tile_map.get(cell_key(c))
	if existing != null:
		_set_tile_prompt(existing)
	else:
		_set_grass_prompt(c)

# Virgin grass: offer to plow it (and to drop a sprinkler on it)
func _set_grass_prompt(c: Vector2i):
	prompt_cell = c
	prompt_cell_valid = true
	if plow_uses() > 0:
		prompt = "[E] Plow the soil — plow has %d uses left" % plow_uses()
		prompt_action = func(): plow_cell(c)
	else:
		prompt = "Wild soil — your plow is broken; buy a new one in town"
	if sprinkler_stock() > 0:
		prompt += "  ·  [F] Place sprinkler"

func _set_tile_prompt(tile: FarmTile):
	prompt_tile = tile
	prompt_cell = Vector2i(tile.col, tile.row)
	if tile.has_sprinkler:
		prompt = "Sprinkler — waters the tiles around it  ·  [F] Pick up"
		return
	match tile.state:
		FarmTile.TState.UNPLOWED:
			if plow_uses() > 0:
				prompt = "[E] Plow the soil — plow has %d uses left" % plow_uses()
				prompt_action = func(): plow_tile(tile)
			else:
				prompt = "Wild soil — your plow is broken; buy a new one in town"
			if sprinkler_stock() > 0:
				prompt += "  ·  [F] Place sprinkler"
		FarmTile.TState.PLOWED:
			if _total_seeds() > 0:
				prompt = "[E] Plant a seed"
				prompt_action = func(): _open_plant_menu(tile)
			else:
				prompt = "Plowed soil — buy seeds at the town seed shop"
			if sprinkler_stock() > 0:
				prompt += "  ·  [F] Place sprinkler"
		FarmTile.TState.PLANTED:
			var pct = int(tile.progress() * 100.0)
			var nm = GameData.potato_by_id(tile.potato_id).get("name", "?")
			if not tile.watered and int(SaveDataManager.farm.get("water", 0)) > 0:
				prompt = "[E] Water the %s — %d%% grown" % [nm, pct]
				prompt_action = func(): _water_tile(tile)
			elif tile.watered:
				prompt = "%s growing fast — %d%%" % [nm, pct]
			else:
				prompt = "%s growing — %d%% (fetch water to speed up)" % [nm, pct]
			if tile.boost >= 1.0 and _total_enhancers() > 0:
				prompt += "  ·  [F] Fertilize"
		FarmTile.TState.READY:
			var nm2 = GameData.potato_by_id(tile.potato_id).get("name", "?")
			prompt = "[E] Harvest the %s!" % nm2
			prompt_action = func(): _harvest_tile(tile)

# [F]: pick up / place sprinklers, or open the fertilizer menu on a crop
func _on_alt_interact():
	if prompt_tile != null:
		var tile = prompt_tile
		if tile.has_sprinkler:
			pickup_sprinkler(tile)
			return
		match tile.state:
			FarmTile.TState.UNPLOWED, FarmTile.TState.PLOWED:
				if sprinkler_stock() > 0:
					place_sprinkler(tile)
			FarmTile.TState.PLANTED:
				if tile.boost >= 1.0 and _total_enhancers() > 0:
					enhance_target = tile
					open_shop = "enhance"
	elif prompt_cell_valid and sprinkler_stock() > 0:
		place_sprinkler_cell(prompt_cell)

func _shop_input(key: Key):
	var idx = key - KEY_1  # 0-based row number
	match open_shop:
		"plant":
			var farmables = plantable_potatoes()
			if idx >= 0 and idx < farmables.size() and plant_target:
				if plant_on(plant_target, farmables[idx]["id"]):
					open_shop = ""
					plant_target = null
		"enhance":
			var owned_enh = owned_enhancers()
			if idx >= 0 and idx < owned_enh.size() and enhance_target:
				if apply_enhancer(enhance_target, owned_enh[idx]["id"]):
					open_shop = ""
					enhance_target = null
		"truck":
			if key == KEY_A:
				truck_load_all()
			elif key == KEY_S:
				truck_send()
			else:
				var sellable = GameData.farmable_potatoes()
				if idx >= 0 and idx < sellable.size():
					truck_load(sellable[idx]["id"])
		"research":
			var nodes = research_menu_nodes()
			if idx >= 0 and idx < nodes.size():
				buy_research(nodes[idx]["id"])
		_:
			super._shop_input(key)

func _on_shop_closed():
	plant_target = null
	enhance_target = null

# ────────────────────────────────────────────────────────
#  Working the land (public so the smoke test can drive them)
# ────────────────────────────────────────────────────────

# Plow a virgin grass cell (creating the tile). With the Wide Plow research a
# 3x3 patch is broken at once, spending one plow use per tile actually tilled.
func plow_cell(c: Vector2i) -> bool:
	if plow_uses() <= 0:
		_popup("The plow is broken — the town tool shed sells new ones", Color.ORANGE_RED)
		return false
	var radius = plow_radius()
	if radius <= 0:
		if not is_farmable_cell(c):
			return false
		return plow_tile(_ensure_tile(c))
	var any := false
	for dr in range(-radius, radius + 1):
		for dc in range(-radius, radius + 1):
			if plow_uses() <= 0:
				break
			var nc = Vector2i(c.x + dc, c.y + dr)
			if not is_farmable_cell(nc):
				continue
			var t = _ensure_tile(nc)
			if t.state == FarmTile.TState.UNPLOWED and not t.has_sprinkler:
				if plow_tile(t):
					any = true
			else:
				_drop_tile(t)  # nothing to do here — don't leave an empty node
	return any

func plow_tile(tile: FarmTile) -> bool:
	if plow_uses() <= 0:
		_popup("The plow is broken — the town tool shed sells new ones", Color.ORANGE_RED)
		return false
	if not tile.plow():
		return false
	SaveDataManager.farm["plow_uses"] = plow_uses() - 1
	_sync_tiles()
	if plow_uses() <= 0:
		_popup("CRACK! The plow gave out on that one", Color.ORANGE_RED)
	else:
		_popup("Soil plowed — ready for a seed", Color.LIGHT_GREEN)
	if SaveDataManager.settings.get("particle_effects", true):
		Fx.burst(self, tile.position, Color(0.46, 0.32, 0.18), 10, 160.0)
	return true

func place_sprinkler_cell(c: Vector2i) -> bool:
	if sprinkler_stock() <= 0 or not is_farmable_cell(c):
		return false
	return place_sprinkler(_ensure_tile(c))

func place_sprinkler(tile: FarmTile) -> bool:
	if sprinkler_stock() <= 0 or tile.has_sprinkler:
		return false
	if tile.state == FarmTile.TState.PLANTED or tile.state == FarmTile.TState.READY:
		_popup("There's a crop in the way!", Color.ORANGE_RED)
		return false
	tile.has_sprinkler = true
	SaveDataManager.farm["sprinkler_stock"] = sprinkler_stock() - 1
	_sync_tiles()
	_popup("Sprinkler placed — it waters the tiles around it", Color(0.5, 0.8, 1.0))
	return true

func pickup_sprinkler(tile: FarmTile) -> bool:
	if not tile.has_sprinkler:
		return false
	tile.has_sprinkler = false
	SaveDataManager.farm["sprinkler_stock"] = sprinkler_stock() + 1
	_popup("Sprinkler packed up", Color(0.5, 0.8, 1.0))
	# if it sat on never-plowed ground, the cell goes back to plain grass
	_drop_tile(tile)
	_sync_tiles()
	return true

func plant_on(tile: FarmTile, id: String) -> bool:
	if SaveDataManager.item_count("seeds", id) <= 0:
		_popup("No %s seeds!" % GameData.potato_by_id(id).get("name", id), Color.ORANGE_RED)
		return false
	if not tile.plant(id):
		_popup("That soil needs plowing first!", Color.ORANGE_RED)
		return false
	SaveDataManager.add_item("seeds", id, -1)
	_sync_tiles()
	_popup("Planted %s" % GameData.potato_by_id(id).get("name", id), Color.LIGHT_GREEN)
	return true

func fill_water():
	SaveDataManager.farm["water"] = 4
	SaveDataManager.save_game()
	_popup("Watering can filled!", Color(0.5, 0.8, 1.0))

func _water_tile(tile: FarmTile):
	var water = int(SaveDataManager.farm.get("water", 0))
	if water <= 0 or tile.watered:
		return
	SaveDataManager.farm["water"] = water - 1
	tile.water()
	_sync_tiles()
	_popup("Watered — growing fast!", Color(0.5, 0.8, 1.0))

func _harvest_tile(tile: FarmTile):
	var id = tile.potato_id
	var data = GameData.potato_by_id(id)
	var n = tile.harvest(rng) + int(SaveDataManager.research_bonus("bonus_yield"))
	SaveDataManager.add_item("spuds", id, n)
	# harvesting yields a trickle of research points (rare crops give more)
	SaveDataManager.add_research_points(3 if data.get("rare", false) else 1)
	_sync_tiles()
	_popup("+%d %s!" % [n, data.get("name", id)], Color.GOLD if data.get("rare", false) else Color.LIGHT_GREEN)
	if SaveDataManager.settings.get("particle_effects", true):
		if data.get("rare", false):
			Fx.sparkle(self, tile.position)
		else:
			Fx.burst(self, tile.position + Vector2(0, -10), Color(data.get("color", "#b87333")), 12, 180.0)
	AudioManager.play_sfx("coin_collect")

# Spends one fertilizer charge on a planted tile; one application per crop
func apply_enhancer(tile: FarmTile, id: String) -> bool:
	if SaveDataManager.item_count("items", id) <= 0:
		return false
	var e = GameData.enhancer_by_id(id)
	if not tile.enhance(float(e.get("boost", 1.0)), int(e.get("bonus_yield", 0))):
		_popup("Already fertilized!", Color.ORANGE_RED)
		return false
	SaveDataManager.add_item("items", id, -1)
	_sync_tiles()
	_popup("%s worked into the soil! (%d charges left)" % [e.get("name", id), SaveDataManager.item_count("items", id)], Color(0.55, 0.95, 0.4))
	if SaveDataManager.settings.get("particle_effects", true):
		Fx.sparkle(self, tile.position)
	return true

# ────────────────────────────────────────────────────────
#  Market truck — load spuds, ship them, coins + RP come back later
# ────────────────────────────────────────────────────────

func _truck() -> Dictionary:
	return SaveDataManager.farm.get("truck", {})

func truck_capacity() -> int:
	return 20 + int(SaveDataManager.research_bonus("truck_capacity"))

func truck_trip_seconds() -> float:
	return maxf(20.0, 120.0 + SaveDataManager.research_bonus("truck_trip_delta"))

func truck_price_mult() -> float:
	return 1.0 + SaveDataManager.research_bonus("truck_price_mult")

func truck_cargo_count() -> int:
	var n = 0
	for v in _truck().get("cargo", {}).values():
		n += int(v)
	return n

func truck_status() -> String:
	return str(_truck().get("status", "idle"))

func truck_load(id: String) -> bool:
	var tr = _truck()
	if tr.get("status", "idle") != "idle":
		return false
	if SaveDataManager.item_count("spuds", id) <= 0 or truck_cargo_count() >= truck_capacity():
		return false
	var cargo: Dictionary = tr.get("cargo", {})
	cargo[id] = int(cargo.get(id, 0)) + 1
	tr["cargo"] = cargo
	SaveDataManager.farm["truck"] = tr
	SaveDataManager.add_item("spuds", id, -1)  # also saves
	return true

func truck_load_all():
	var added := 0
	for p in GameData.farmable_potatoes():
		while SaveDataManager.item_count("spuds", p["id"]) > 0 and truck_cargo_count() < truck_capacity():
			if not truck_load(p["id"]):
				break
			added += 1
	if added > 0:
		_popup("Loaded %d spuds onto the truck" % added, Color.LIGHT_GREEN)
	elif truck_cargo_count() >= truck_capacity():
		_popup("The truck is full!", Color(0.85, 0.7, 0.4))

func truck_send() -> bool:
	var tr = _truck()
	if tr.get("status", "idle") != "idle" or truck_cargo_count() <= 0:
		_popup("Load some spuds first!", Color.ORANGE_RED)
		return false
	var coins = 0
	var rp = 0
	for id in tr.get("cargo", {}):
		var cnt = int(tr["cargo"][id])
		coins += int(round(cnt * int(GameData.potato_by_id(id).get("sell_value", 0)) * truck_price_mult()))
		rp += cnt
	tr["pending_coins"] = coins
	tr["pending_rp"] = maxi(1, rp / 5)   # a research point per 5 spuds shipped
	tr["return_at"] = Time.get_unix_time_from_system() + truck_trip_seconds()
	tr["status"] = "away"
	SaveDataManager.farm["truck"] = tr
	SaveDataManager.save_game()
	_popup("Truck off to market — back in %ds" % int(truck_trip_seconds()), Color.GOLD)
	AudioManager.play_sfx("coin_collect")
	open_shop = ""
	return true

# Wall-clock based, so a truck sent before quitting still arrives on return.
func truck_tick():
	var tr = _truck()
	if tr.get("status", "") != "away":
		return
	if Time.get_unix_time_from_system() < float(tr.get("return_at", 0.0)):
		return
	var coins = int(tr.get("pending_coins", 0))
	var rp = int(tr.get("pending_rp", 0))
	# reset the truck atomically before paying out, so we can't double-deposit
	SaveDataManager.farm["truck"] = {"status": "idle", "cargo": {}, "return_at": 0.0,
			"pending_coins": 0, "pending_rp": 0}
	if coins > 0:
		SaveDataManager.add_coins(coins)
	if rp > 0:
		SaveDataManager.add_research_points(rp)
	SaveDataManager.save_game()
	_popup("Truck's back! +%d coins, +%d research" % [coins, rp], Color.GOLD)
	AudioManager.play_sfx("level_complete")

func _truck_station():
	if truck_status() == "away":
		var left = int(float(_truck().get("return_at", 0.0)) - Time.get_unix_time_from_system())
		prompt = "Truck is at market — back in %ds" % maxi(0, left)
		prompt_action = Callable()
	else:
		prompt = "[E] Load the market truck"
		prompt_action = _open_truck

# ────────────────────────────────────────────────────────
#  Research shed
# ────────────────────────────────────────────────────────

func has_research(id: String) -> bool:
	return SaveDataManager.has_research(id)

func plow_radius() -> int:
	return int(SaveDataManager.research_bonus("plow_radius"))

func sprinkler_reach() -> int:
	return 1 + int(SaveDataManager.research_bonus("sprinkler_reach"))

# A node is buyable once every prerequisite is owned and it isn't owned yet
func research_available(node: Dictionary) -> bool:
	if has_research(node.get("id", "")):
		return false
	for req in node.get("requires", []):
		if not has_research(req):
			return false
	return true

# The actionable frontier: not-yet-owned nodes whose prerequisites are met,
# in data order, so the overlay's [1..N] indices stay stable.
func research_menu_nodes() -> Array:
	return GameData.research_nodes().filter(research_available)

func can_afford_research(node: Dictionary) -> bool:
	return SaveDataManager.wallet() >= int(node.get("cost_coins", 0)) \
			and SaveDataManager.research_points() >= int(node.get("cost_rp", 0))

func buy_research(id: String) -> bool:
	var node = GameData.research_by_id(id)
	if node.is_empty() or not research_available(node):
		return false
	if not can_afford_research(node):
		_popup("Need %d coins + %d research" % [int(node.get("cost_coins", 0)), int(node.get("cost_rp", 0))], Color.ORANGE_RED)
		return false
	SaveDataManager.spend_coins(int(node.get("cost_coins", 0)))
	SaveDataManager.add_research_points(-int(node.get("cost_rp", 0)))
	SaveDataManager.unlock_research(id)
	_popup("Researched: %s!" % node.get("name", id), Color.GOLD)
	AudioManager.play_sfx("level_complete")
	return true

# ── auto-farming: sprinklers and researched gear work the land on a slow tick ──

func _neighbours(tile: FarmTile) -> Array:
	var out: Array = []
	var r = sprinkler_reach()
	for dr in range(-r, r + 1):
		for dc in range(-r, r + 1):
			if dr == 0 and dc == 0:
				continue
			var k = "%d:%d" % [tile.col + dc, tile.row + dr]
			if tile_map.has(k):
				out.append(tile_map[k])
	return out

func _auto_farm():
	var changed := false
	# each placed sprinkler waters the tiles around it
	for tile in tiles:
		if not tile.has_sprinkler:
			continue
		for n in _neighbours(tile):
			if n.state == FarmTile.TState.PLANTED and not n.watered:
				n.water()
				changed = true
	if SaveDataManager.research_flag("auto_harvest"):
		for tile in tiles:
			if tile.state == FarmTile.TState.READY:
				_harvest_tile(tile)  # syncs the save itself
				break  # one per tick, so popups stay readable
	if SaveDataManager.research_flag("auto_seed"):
		for tile in tiles:
			if tile.has_sprinkler or tile.state != FarmTile.TState.PLOWED:
				continue
			var last = tile.last_potato_id
			if last == "" or SaveDataManager.item_count("seeds", last) <= 0:
				continue
			if not (last in SaveDataManager.unlocked_crops()) and not (last in GameData.STARTER_CROPS):
				continue
			SaveDataManager.add_item("seeds", last, -1)
			tile.plant(last)
			changed = true
			break  # one per tick
	if changed:
		_sync_tiles()

func _open_plant_menu(tile: FarmTile):
	plant_target = tile
	open_shop = "plant"

func _open_truck():
	open_shop = "truck"

func _open_research():
	open_shop = "research"

func _goto_town():
	WorldController.travel_spawn = "from_farm"
	WorldController.carry_day_t = day_t
	get_tree().change_scene_to_file("res://scenes/Town/TownScene.tscn")

func _nap():
	day_t = 0.2
	_popup("Good morning!", Color(1.0, 0.9, 0.5))

func _sync_tiles():
	var d = {}
	for tile in tiles:
		var td = tile.to_dict()
		if not td.is_empty():
			d[tile.key()] = td
	SaveDataManager.farm["tiles"] = d
	SaveDataManager.save_game()
