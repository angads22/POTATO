extends Node2D
class_name WorldController

# Shared base for the walkable overworld scenes (the farm and the town):
# player movement against rect blockers, a smoothed camera, the day-night
# cycle, the proximity prompt with [E]/[F] routing, the shop overlay state
# and the floating popup/banner feedback. Subclasses build their map in
# _build_world(), set prompts in _scan_interactions(), and share the economy
# actions below so the same shops can be driven from either map (and from
# the smoke tests).

const PLAYER_SPEED = 290.0
const DAY_LENGTH = 180.0   # seconds for a full day-night cycle
const POPUP_LIFE = 1.4

# Set by travel gates just before change_scene_to_file so the destination
# scene knows where to put the player and what time of day it is.
static var travel_spawn := ""
static var carry_day_t := -1.0

var player: FarmerVisual
var camera: Camera2D
var hud: WorldHUD
var tint: ColorRect
var world_bg               # background node exposing a night01 property
var rng := RandomNumberGenerator.new()

var world_size := Vector2(2560, 1440)
var day_t := 0.18          # start mid-morning (0.25 = noon, 0.75 = midnight)
var night01 := 0.0
var prompt := ""
var prompt_action := Callable()
var open_shop := ""        # "", "seeds", "knives", "tools" (+ farm extras: plant, enhance, truck, research)
var popups: Array = []
var banner_text := ""
var banner_age := 99.0

# Rects the player can't walk through (buildings, stands, the well)
var blockers: Array = []

# ── subclass hooks ──

func _world_size() -> Vector2:
	return Vector2(2560, 1440)

func _spawn_point() -> Vector2:
	return world_size / 2.0

func _build_world():
	pass

func _scan_interactions():
	pass

func _tick(_delta: float):
	pass

# [F] while walking — the farm uses it for fertilizer and sprinklers
func _on_alt_interact():
	pass

# shop overlay was closed with ESC
func _on_shop_closed():
	pass

# ── lifecycle ──

func _ready():
	rng.randomize()
	AudioManager.play_music("menu")
	world_size = _world_size()
	if carry_day_t >= 0.0:
		day_t = carry_day_t
		carry_day_t = -1.0

	_build_world()

	player = FarmerVisual.new()
	player.position = _spawn_point()
	player.z_index = 2
	add_child(player)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world_size.x)
	camera.limit_bottom = int(world_size.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)
	camera.make_current()

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
	hud = WorldHUD.new()
	hud.ctrl = self
	hud_layer.add_child(hud)
	add_child(hud_layer)

func _process(delta):
	# day-night cycle
	day_t = fposmod(day_t + delta / DAY_LENGTH, 1.0)
	night01 = (1.0 - cos((day_t - 0.25) * TAU)) * 0.5
	if world_bg != null:
		world_bg.night01 = night01
	tint.color.a = night01 * 0.45

	if open_shop == "":
		_move_player(delta)
	else:
		player.moving = false
	player.carrying_water = int(SaveDataManager.farm.get("water", 0)) > 0

	_tick(delta)
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
		target.x = clampf(target.x, 60, world_size.x - 60)
		target.y = clampf(target.y, 70, world_size.y - 50)
		if _walkable(target):
			player.position = target
			return

func _walkable(p: Vector2) -> bool:
	for r in blockers:
		if r.has_point(p):
			return false
	return true

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.keycode == KEY_ESCAPE:
		if open_shop != "":
			open_shop = ""
			_on_shop_closed()
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return

	if open_shop != "":
		_shop_input(event.keycode)
		return

	if event.keycode == KEY_E or event.keycode == KEY_SPACE:
		if prompt_action.is_valid():
			prompt_action.call()
	elif event.keycode == KEY_F:
		_on_alt_interact()

# Numeric hotkeys inside the store overlays both maps share; the farm
# overrides this to add its plant/enhance menus.
func _shop_input(key: Key):
	var idx = key - KEY_1  # 0-based row number
	match open_shop:
		"seeds":
			var farmables = plantable_potatoes()
			if idx >= 0 and idx < farmables.size():
				buy_seed(farmables[idx]["id"])
		"knives":
			var knives = GameData.knives()
			if idx >= 0 and idx < knives.size():
				buy_or_equip_knife(knives[idx]["id"])
		"tools":
			# tools first, then fertilizers, numbered straight through
			var tools = GameData.tools()
			var enhancers = GameData.enhancers()
			if idx >= 0 and idx < tools.size():
				buy_tool(tools[idx]["id"])
			elif idx >= tools.size() and idx < tools.size() + enhancers.size():
				buy_enhancer(enhancers[idx - tools.size()]["id"])

# ────────────────────────────────────────────────────────
#  Economy actions (public so the smoke tests can drive them)
# ────────────────────────────────────────────────────────

# Farmable varieties the player may currently plant/buy (starter crops plus
# anything unlocked in the Research Shed). Seed shop + plant menu use this;
# the sell/inventory side keeps the full farmable list so owned spuds always
# stay sellable.
func plantable_potatoes() -> Array:
	return GameData.unlocked_potatoes(SaveDataManager.unlocked_crops())

func buy_seed(id: String) -> bool:
	var cost = int(GameData.potato_by_id(id).get("seed_cost", 9999))
	if not SaveDataManager.spend_coins(cost):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	SaveDataManager.add_item("seeds", id, 1)
	_popup("Bought a %s seed" % GameData.potato_by_id(id).get("name", id), Color.LIGHT_GREEN)
	AudioManager.play_sfx("coin_collect")
	return true

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

# ── tools: the wearing plow, placeable sprinklers, global gear ──

func owns_tool(id: String) -> bool:
	return id in SaveDataManager.farm.get("tools", [])

func plow_uses() -> int:
	return int(SaveDataManager.farm.get("plow_uses", 0))

func sprinkler_stock() -> int:
	return int(SaveDataManager.farm.get("sprinkler_stock", 0))

func sprinklers_placed() -> int:
	var n = 0
	for v in SaveDataManager.farm.get("tiles", {}).values():
		if v is Dictionary and v.get("sprinkler", false):
			n += 1
	return n

# Each replacement plow costs more than the last
func plow_cost() -> int:
	var pd = GameData.tool_by_id("plow")
	return int(pd.get("base_cost", 150)) \
			+ int(pd.get("cost_step", 100)) * int(SaveDataManager.farm.get("plows_bought", 0))

func buy_plow() -> bool:
	if plow_uses() > 0:
		_popup("Your plow still has life in it!", Color(0.7, 0.65, 0.55))
		return false
	if not SaveDataManager.spend_coins(plow_cost()):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	var pd = GameData.tool_by_id("plow")
	# research "plow_durability" upgrades apply to the next plow you buy
	var dur = int(pd.get("durability", 10)) + int(SaveDataManager.research_bonus("plow_durability"))
	SaveDataManager.farm["plow_uses"] = dur
	SaveDataManager.farm["plows_bought"] = int(SaveDataManager.farm.get("plows_bought", 0)) + 1
	SaveDataManager.save_game()
	_popup("New plow — good for %d tiles!" % plow_uses(), Color.GOLD)
	AudioManager.play_sfx("level_complete")
	return true

func buy_sprinkler() -> bool:
	var sd = GameData.tool_by_id("sprinkler")
	if not SaveDataManager.spend_coins(int(sd.get("cost", 250))):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	SaveDataManager.farm["sprinkler_stock"] = sprinkler_stock() + 1
	SaveDataManager.save_game()
	_popup("Sprinkler bought — place it on a farm tile with [F]", Color.LIGHT_GREEN)
	AudioManager.play_sfx("coin_collect")
	return true

func buy_tool(id: String) -> bool:
	# the plow and sprinklers have their own purchase rules
	if id == "plow":
		return buy_plow()
	if id == "sprinkler":
		return buy_sprinkler()
	if owns_tool(id):
		_popup("Already installed!", Color(0.7, 0.65, 0.55))
		return false
	var tool_data = GameData.tool_by_id(id)
	if not SaveDataManager.spend_coins(int(tool_data.get("cost", 99999))):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	var owned: Array = SaveDataManager.farm.get("tools", [])
	owned.append(id)
	SaveDataManager.farm["tools"] = owned
	SaveDataManager.save_game()
	_popup("%s installed!" % tool_data.get("name", id), Color.GOLD)
	AudioManager.play_sfx("level_complete")
	return true

# Fertilizers come as multi-charge bags; the items inventory counts charges
func buy_enhancer(id: String) -> bool:
	var e = GameData.enhancer_by_id(id)
	if not SaveDataManager.spend_coins(int(e.get("cost", 9999))):
		_popup("Not enough coins!", Color.ORANGE_RED)
		return false
	var charges = int(e.get("charges", 1))
	SaveDataManager.add_item("items", id, charges)
	_popup("Bought %s — %d charges" % [e.get("name", id), charges], Color.LIGHT_GREEN)
	AudioManager.play_sfx("coin_collect")
	return true

func owned_enhancers() -> Array:
	return GameData.enhancers().filter(
		func(e): return SaveDataManager.item_count("items", e["id"]) > 0)

func _total_enhancers() -> int:
	var total = 0
	for n in SaveDataManager.farm.get("items", {}).values():
		total += int(n)
	return total

func _total_seeds() -> int:
	var total = 0
	for n in SaveDataManager.farm.get("seeds", {}).values():
		total += int(n)
	return total

# ── feedback ──

func _popup(text: String, color: Color):
	popups.append({"text": text, "color": color, "age": 0.0})

func _show_banner(text: String):
	banner_text = text
	banner_age = 0.0
