extends WorldController
class_name FarmController

# The farm: walk the chef potato around the homestead, plow the fields tile
# by tile, plant and water crops, and haul the harvest through the east gate
# into town to sell. Three fenced fields unlock section by section for
# escalating sums; wild tiles must be plowed (the plow wears out) before a
# seed goes in, and harvested soil stays plowed. Coins persist in
# SaveDataManager.farm and flow both ways — slicing runs bank coins, the
# farm grows potatoes, and better knives multiply slicing scores.

var bg: FarmBackground
var fireflies: CPUParticles2D
var tiles: Array[FarmTile] = []
var tile_map: Dictionary = {}      # "field:row:col" -> FarmTile
var sections: Array = []           # flattened section dicts in unlock order
var plant_target: FarmTile = null
var enhance_target: FarmTile = null
var prompt_tile: FarmTile = null   # tile the current prompt refers to
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
	]

	_build_fields()

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

# Build the tile grid for every field, restored from the save so crops kept
# growing while away
func _build_fields():
	var saved: Dictionary = SaveDataManager.farm.get("tiles", {})
	var cell = GameData.field_cell()
	var owned = sections_owned()
	var section_i = 0
	var fields = GameData.fields()
	for f in range(fields.size()):
		var fd: Dictionary = fields[f]
		var origin = Vector2(float(fd["origin"][0]), float(fd["origin"][1]))
		var sec_of = {}
		for s in fd.get("sections", []):
			sections.append(s)
			for srow in range(int(s["rows"][0]), int(s["rows"][1]) + 1):
				for scol in range(int(s["cols"][0]), int(s["cols"][1]) + 1):
					sec_of[Vector2i(scol, srow)] = section_i
			section_i += 1
		for row in range(int(fd["rows"])):
			for col in range(int(fd["cols"])):
				var tile := FarmTile.new()
				tile.field = f
				tile.row = row
				tile.col = col
				tile.section = sec_of.get(Vector2i(col, row), 999)
				tile.position = origin + Vector2(col * cell.x, row * cell.y)
				tile.locked = tile.section >= owned
				if saved.get(tile.key()) is Dictionary:
					tile.from_dict(saved[tile.key()])
				add_child(tile)
				tiles.append(tile)
				tile_map[tile.key()] = tile

func _tick(delta):
	fireflies.emitting = night01 > 0.5
	# auto-farming gear works the fields every couple of seconds
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
	if open_shop != "":
		return

	# nearest tile first — they sit inside the fences away from the stations
	var best_d = 90.0
	var best_tile: FarmTile = null
	for tile in tiles:
		var d = player.position.distance_to(tile.position)
		if d < best_d:
			best_d = d
			best_tile = tile
	if best_tile:
		_set_tile_prompt(best_tile)
		return

	var stations = [
		{"pos": FarmBackground.WELL_POS + Vector2(0, 50), "r": 110.0,
			"text": "[E] Draw water — refill the can", "act": fill_water},
		{"pos": Vector2(FarmBackground.HOUSE_WALL.get_center().x, FarmBackground.HOUSE_WALL.end.y + 25), "r": 100.0,
			"text": "[E] Nap until morning", "act": _nap},
		{"pos": FarmBackground.TOWN_GATE_POS, "r": 120.0,
			"text": "[E] Take the road into town", "act": _goto_town},
	]
	for s in stations:
		if player.position.distance_to(s.pos) < s.r:
			prompt = s.text
			prompt_action = s.act
			return

func _set_tile_prompt(tile: FarmTile):
	prompt_tile = tile
	if tile.locked:
		if tile.section == sections_owned():
			prompt = "[E] Buy this stretch of land — %d coins" % section_price(tile.section)
			prompt_action = func(): buy_section()
		else:
			prompt = "Overgrown ground — buy the nearer sections first"
		return
	if tile.has_sprinkler:
		prompt = "Sprinkler — waters the 8 tiles around it  ·  [F] Pick up"
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
	if prompt_tile == null or prompt_tile.locked:
		return
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

func _shop_input(key: Key):
	var idx = key - KEY_1  # 0-based row number
	match open_shop:
		"plant":
			var farmables = GameData.farmable_potatoes()
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
		_:
			super._shop_input(key)

func _on_shop_closed():
	plant_target = null
	enhance_target = null

# ────────────────────────────────────────────────────────
#  Working the land (public so the smoke test can drive them)
# ────────────────────────────────────────────────────────

func sections_owned() -> int:
	return int(SaveDataManager.farm.get("sections_owned", 1))

func section_price(si: int) -> int:
	if si < 0 or si >= sections.size():
		return 0
	return int(sections[si].get("price", 0))

func buy_section() -> bool:
	var si = sections_owned()
	if si >= sections.size():
		return false
	if not SaveDataManager.spend_coins(section_price(si)):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	SaveDataManager.farm["sections_owned"] = si + 1
	SaveDataManager.save_game()
	for tile in tiles:
		if tile.section == si:
			tile.locked = false
	_popup("New land! Break it in with the plow", Color.GOLD)
	if SaveDataManager.settings.get("particle_effects", true):
		for tile in tiles:
			if tile.section == si:
				Fx.burst(self, tile.position, Color(0.46, 0.32, 0.18), 6, 140.0)
				break
	AudioManager.play_sfx("level_complete")
	return true

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

func place_sprinkler(tile: FarmTile) -> bool:
	if sprinkler_stock() <= 0 or tile.locked or tile.has_sprinkler:
		return false
	if tile.state == FarmTile.TState.PLANTED or tile.state == FarmTile.TState.READY:
		_popup("There's a crop in the way!", Color.ORANGE_RED)
		return false
	tile.has_sprinkler = true
	SaveDataManager.farm["sprinkler_stock"] = sprinkler_stock() - 1
	_sync_tiles()
	_popup("Sprinkler placed — it waters the 8 tiles around it", Color(0.5, 0.8, 1.0))
	return true

func pickup_sprinkler(tile: FarmTile) -> bool:
	if not tile.has_sprinkler:
		return false
	tile.has_sprinkler = false
	SaveDataManager.farm["sprinkler_stock"] = sprinkler_stock() + 1
	_sync_tiles()
	_popup("Sprinkler packed up", Color(0.5, 0.8, 1.0))
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
	var n = tile.harvest(rng)
	SaveDataManager.add_item("spuds", id, n)
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

# ── auto-farming: sprinklers and owned gear work the fields on a slow tick ──

func _neighbours(tile: FarmTile) -> Array:
	var out: Array = []
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var k = "%d:%d:%d" % [tile.field, tile.row + dr, tile.col + dc]
			if tile_map.has(k):
				out.append(tile_map[k])
	return out

func _auto_farm():
	var changed := false
	# each placed sprinkler waters the 8 tiles around it
	for tile in tiles:
		if not tile.has_sprinkler or tile.locked:
			continue
		for n in _neighbours(tile):
			if not n.locked and n.state == FarmTile.TState.PLANTED and not n.watered:
				n.water()
				changed = true
	if owns_tool("harvest_drone"):
		for tile in tiles:
			if not tile.locked and tile.state == FarmTile.TState.READY:
				_harvest_tile(tile)  # syncs the save itself
				break  # one per tick, so popups stay readable
	if owns_tool("auto_seeder"):
		for tile in tiles:
			if tile.locked or tile.has_sprinkler or tile.state != FarmTile.TState.PLOWED:
				continue
			if tile.last_potato_id == "" or SaveDataManager.item_count("seeds", tile.last_potato_id) <= 0:
				continue
			SaveDataManager.add_item("seeds", tile.last_potato_id, -1)
			tile.plant(tile.last_potato_id)
			changed = true
			break  # one per tick
	if changed:
		_sync_tiles()

func _open_plant_menu(tile: FarmTile):
	plant_target = tile
	open_shop = "plant"

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
