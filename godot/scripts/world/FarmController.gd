extends Node2D
class_name FarmController

# Open-world farm hub: walk the chef potato around the homestead, plant and
# water crops, sell the harvest, buy seeds and knives, and enter the
# championship kitchen. Coins persist in SaveDataManager.farm and flow both
# ways — slicing runs bank coins, the farm grows and sells potatoes, and
# better knives multiply slicing scores.

const WORLD = Vector2(2560, 1440)
const PLAYER_SPEED = 290.0
const DAY_LENGTH = 180.0   # seconds for a full day-night cycle
const POPUP_LIFE = 1.4
const PLOT_COLS = 4
const PLOT_ROWS = 3
const PLOT_ORIGIN = Vector2(590, 660)
const PLOT_STEP = Vector2(170, 150)

var player: FarmerVisual
var camera: Camera2D
var bg: FarmBackground
var hud: FarmHUD
var tint: ColorRect
var fireflies: CPUParticles2D
var plots: Array[FarmPlot] = []
var rng := RandomNumberGenerator.new()

var day_t := 0.18          # start mid-morning (0.25 = noon, 0.75 = midnight)
var night01 := 0.0
var prompt := ""
var prompt_action := Callable()
var open_shop := ""        # "", "seeds", "market", "knives", "plant"
var plant_target: FarmPlot = null
var popups: Array = []
var banner_text := ""
var banner_age := 99.0

# Rects the player can't walk through (buildings, stands, the well)
var blockers: Array = []

func _ready():
	rng.randomize()
	AudioManager.play_music("menu")

	bg = FarmBackground.new()
	add_child(bg)

	blockers = [
		FarmBackground.HOUSE_WALL.grow(6),
		FarmBackground.KITCHEN_WALL.grow(6),
		FarmBackground.SEED_STAND.grow(4),
		FarmBackground.KNIFE_STAND.grow(4),
		FarmBackground.MARKET.grow(4),
		Rect2(FarmBackground.WELL_POS - Vector2(55, 45), Vector2(110, 90)),
	]

	# plots, restored from the save so crops kept growing while away
	var saved: Array = SaveDataManager.farm.get("plots", [])
	for row in range(PLOT_ROWS):
		for col in range(PLOT_COLS):
			var plot := FarmPlot.new()
			plot.index = row * PLOT_COLS + col
			plot.position = PLOT_ORIGIN + Vector2(col * PLOT_STEP.x, row * PLOT_STEP.y)
			if plot.index < saved.size() and saved[plot.index] is Dictionary:
				plot.from_dict(saved[plot.index])
			add_child(plot)
			plots.append(plot)

	player = FarmerVisual.new()
	player.position = Vector2(1450, 620)
	player.z_index = 2
	add_child(player)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD.x)
	camera.limit_bottom = int(WORLD.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)
	camera.make_current()

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

	# night tint sits between the world and the HUD
	var tint_layer := CanvasLayer.new()
	tint_layer.layer = 5
	tint = ColorRect.new()
	tint.size = Vector2(1280, 720)
	tint.color = Color(0.04, 0.05, 0.18, 0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_layer.add_child(tint)
	add_child(tint_layer)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud = FarmHUD.new()
	hud.ctrl = self
	hud_layer.add_child(hud)
	add_child(hud_layer)

	_show_banner("POTATO FARM")

func _process(delta):
	# day-night cycle
	day_t = fposmod(day_t + delta / DAY_LENGTH, 1.0)
	night01 = (1.0 - cos((day_t - 0.25) * TAU)) * 0.5
	bg.night01 = night01
	tint.color.a = night01 * 0.45
	fireflies.emitting = night01 > 0.5

	if open_shop == "":
		_move_player(delta)
	else:
		player.moving = false
	player.carrying_water = int(SaveDataManager.farm.get("water", 0)) > 0

	_scan_interactions()

	banner_age += delta
	for p in popups:
		p.age += delta
	popups = popups.filter(func(p): return p.age < POPUP_LIFE)
	hud.queue_redraw()

func _move_player(delta):
	var dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1

	player.moving = dir != Vector2.ZERO
	if dir == Vector2.ZERO:
		return
	if dir.x != 0:
		player.face = signf(dir.x)

	var step = dir.normalized() * PLAYER_SPEED * delta
	# slide along blockers: try the full move, then each axis alone
	for attempt in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		var target = player.position + attempt
		target.x = clampf(target.x, 60, WORLD.x - 60)
		target.y = clampf(target.y, 70, WORLD.y - 50)
		if _walkable(target):
			player.position = target
			return

func _walkable(p: Vector2) -> bool:
	for r in blockers:
		if r.has_point(p):
			return false
	var d = (p - FarmBackground.POND_C) / (FarmBackground.POND_R + Vector2(28, 30))
	return d.length() > 1.0

# ────────────────────────────────────────────────────────
#  Interactions
# ────────────────────────────────────────────────────────

func _scan_interactions():
	prompt = ""
	prompt_action = Callable()
	if open_shop != "":
		return

	# nearest plot first — they sit inside the fence away from the stations
	var best_d = 90.0
	var best_plot: FarmPlot = null
	for plot in plots:
		var d = player.position.distance_to(plot.position)
		if d < best_d:
			best_d = d
			best_plot = plot
	if best_plot:
		_set_plot_prompt(best_plot)
		return

	var stations = [
		{"pos": FarmBackground.WELL_POS + Vector2(0, 50), "r": 110.0,
			"text": "[E] Draw water — refill the can", "act": fill_water},
		{"pos": FarmBackground.SEED_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"text": "[E] Browse the seed shop", "act": func(): open_shop = "seeds"},
		{"pos": FarmBackground.KNIFE_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"text": "[E] Browse the knife stand", "act": func(): open_shop = "knives"},
		{"pos": FarmBackground.MARKET.get_center() + Vector2(0, 80), "r": 130.0,
			"text": "[E] Sell at the market", "act": func(): open_shop = "market"},
		{"pos": Vector2(FarmBackground.KITCHEN_WALL.get_center().x, FarmBackground.KITCHEN_WALL.end.y + 30), "r": 120.0,
			"text": "[E] Enter the championship kitchen", "act": _enter_kitchen},
		{"pos": Vector2(FarmBackground.HOUSE_WALL.get_center().x, FarmBackground.HOUSE_WALL.end.y + 25), "r": 100.0,
			"text": "[E] Nap until morning", "act": _nap},
	]
	for s in stations:
		if player.position.distance_to(s.pos) < s.r:
			prompt = s.text
			prompt_action = s.act
			return

func _set_plot_prompt(plot: FarmPlot):
	match plot.state:
		FarmPlot.PState.EMPTY:
			if _total_seeds() > 0:
				prompt = "[E] Plant a seed"
				prompt_action = func(): _open_plant_menu(plot)
			else:
				prompt = "Empty plot — buy seeds at the seed stand"
		FarmPlot.PState.PLANTED:
			var pct = int(plot.progress() * 100.0)
			var nm = GameData.potato_by_id(plot.potato_id).get("name", "?")
			if not plot.watered and int(SaveDataManager.farm.get("water", 0)) > 0:
				prompt = "[E] Water the %s — %d%% grown" % [nm, pct]
				prompt_action = func(): _water_plot(plot)
			elif plot.watered:
				prompt = "%s growing fast — %d%%" % [nm, pct]
			else:
				prompt = "%s growing — %d%% (fetch water to speed up)" % [nm, pct]
		FarmPlot.PState.READY:
			var nm2 = GameData.potato_by_id(plot.potato_id).get("name", "?")
			prompt = "[E] Harvest the %s!" % nm2
			prompt_action = func(): _harvest_plot(plot)

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_ESCAPE:
		if open_shop != "":
			open_shop = ""
			plant_target = null
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return

	if open_shop != "":
		_shop_input(event.keycode)
		return

	if event.keycode == KEY_E or event.keycode == KEY_SPACE:
		if prompt_action.is_valid():
			prompt_action.call()

func _shop_input(key: Key):
	var idx = key - KEY_1  # 0-based row number
	match open_shop:
		"seeds":
			var farmables = GameData.farmable_potatoes()
			if idx >= 0 and idx < farmables.size():
				buy_seed(farmables[idx]["id"])
		"plant":
			var farmables2 = GameData.farmable_potatoes()
			if idx >= 0 and idx < farmables2.size() and plant_target:
				if plant_on(plant_target, farmables2[idx]["id"]):
					open_shop = ""
					plant_target = null
		"market":
			if key == KEY_A:
				sell_all()
			else:
				var farmables3 = GameData.farmable_potatoes()
				if idx >= 0 and idx < farmables3.size():
					sell_spuds(farmables3[idx]["id"])
		"knives":
			var knives = GameData.knives()
			if idx >= 0 and idx < knives.size():
				buy_or_equip_knife(knives[idx]["id"])

# ────────────────────────────────────────────────────────
#  Economy actions (public so the smoke test can drive them)
# ────────────────────────────────────────────────────────

func buy_seed(id: String) -> bool:
	var cost = int(GameData.potato_by_id(id).get("seed_cost", 9999))
	if not SaveDataManager.spend_coins(cost):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	SaveDataManager.add_item("seeds", id, 1)
	_popup("Bought a %s seed" % GameData.potato_by_id(id).get("name", id), Color.LIGHT_GREEN)
	AudioManager.play_sfx("coin_collect")
	return true

func plant_on(plot: FarmPlot, id: String) -> bool:
	if SaveDataManager.item_count("seeds", id) <= 0:
		_popup("No %s seeds!" % GameData.potato_by_id(id).get("name", id), Color.ORANGE_RED)
		return false
	SaveDataManager.add_item("seeds", id, -1)
	plot.plant(id)
	_sync_plots()
	_popup("Planted %s" % GameData.potato_by_id(id).get("name", id), Color.LIGHT_GREEN)
	return true

func fill_water():
	SaveDataManager.farm["water"] = 4
	SaveDataManager.save_game()
	_popup("Watering can filled!", Color(0.5, 0.8, 1.0))

func _water_plot(plot: FarmPlot):
	var water = int(SaveDataManager.farm.get("water", 0))
	if water <= 0 or plot.watered:
		return
	SaveDataManager.farm["water"] = water - 1
	plot.water()
	_sync_plots()
	_popup("Watered — growing fast!", Color(0.5, 0.8, 1.0))

func _harvest_plot(plot: FarmPlot):
	var id = plot.potato_id
	var data = GameData.potato_by_id(id)
	var n = plot.harvest(rng)
	SaveDataManager.add_item("spuds", id, n)
	_sync_plots()
	_popup("+%d %s!" % [n, data.get("name", id)], Color.GOLD if data.get("rare", false) else Color.LIGHT_GREEN)
	if SaveDataManager.settings.get("particle_effects", true):
		if data.get("rare", false):
			Fx.sparkle(self, plot.position)
		else:
			Fx.burst(self, plot.position + Vector2(0, -10), Color(data.get("color", "#b87333")), 12, 180.0)
	AudioManager.play_sfx("coin_collect")

func sell_spuds(id: String) -> int:
	var n = SaveDataManager.item_count("spuds", id)
	if n <= 0:
		return 0
	var value = n * int(GameData.potato_by_id(id).get("sell_value", 0))
	SaveDataManager.add_item("spuds", id, -n)
	SaveDataManager.add_coins(value)
	_popup("Sold %d for %d coins" % [n, value], Color.GOLD)
	AudioManager.play_sfx("coin_collect")
	return value

func sell_all():
	var total = 0
	for p in GameData.farmable_potatoes():
		var n = SaveDataManager.item_count("spuds", p["id"])
		if n > 0:
			var value = n * int(p.get("sell_value", 0))
			SaveDataManager.add_item("spuds", p["id"], -n)
			SaveDataManager.add_coins(value)
			total += value
	if total > 0:
		_popup("Sold the lot for %d coins!" % total, Color.GOLD)
		AudioManager.play_sfx("coin_collect")

func buy_or_equip_knife(id: String) -> bool:
	var owned: Array = SaveDataManager.farm.get("owned_knives", [])
	var k = GameData.knife_by_id(id)
	if id in owned:
		SaveDataManager.farm["equipped_knife"] = id
		SaveDataManager.save_game()
		_popup("%s equipped (×%.2f score)" % [k.get("name", id), float(k.get("damage", 1.0))], Color.LIGHT_GREEN)
		return true
	if not SaveDataManager.spend_coins(int(k.get("cost", 99999))):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	owned.append(id)
	SaveDataManager.farm["owned_knives"] = owned
	SaveDataManager.farm["equipped_knife"] = id
	SaveDataManager.save_game()
	_popup("%s bought and equipped!" % k.get("name", id), Color.GOLD)
	AudioManager.play_sfx("level_complete")
	return true

func _open_plant_menu(plot: FarmPlot):
	plant_target = plot
	open_shop = "plant"

func _enter_kitchen():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _nap():
	day_t = 0.2
	_popup("Good morning!", Color(1.0, 0.9, 0.5))

func _total_seeds() -> int:
	var total = 0
	for n in SaveDataManager.farm.get("seeds", {}).values():
		total += int(n)
	return total

func _sync_plots():
	var arr = []
	for plot in plots:
		arr.append(plot.to_dict())
	SaveDataManager.farm["plots"] = arr
	SaveDataManager.save_game()

func _popup(text: String, color: Color):
	popups.append({"text": text, "color": color, "age": 0.0})

func _show_banner(text: String):
	banner_text = text
	banner_age = 0.0
