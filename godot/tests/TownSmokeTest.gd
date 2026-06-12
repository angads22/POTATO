extends Node

# Headless town smoke test: walks the chef around the plaza, drives the seed
# shop through the real keyboard path, sells spuds at the market, and buys a
# knife, a replacement plow, a sprinkler and fertilizer at the stalls. The
# kitchen and farm-gate prompts are asserted but never pressed — a scene
# change would free this test root.
# NOTE: writes to the user:// save like a real session would.
#
#   godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600

var frames := 0
var town
var fails: Array[String] = []
var expected_wallet := 0

func _ready():
	# deterministic starting economy: a harvest to sell and a broken plow
	SaveDataManager.farm = {
		"schema": 2, "wallet": 20000, "seeds": {}, "spuds": {"russet": 5},
		"water": 0, "owned_knives": ["butter"], "equipped_knife": "butter",
		"sections_owned": 1, "tiles": {}, "plow_uses": 0, "plows_bought": 0,
		"sprinkler_stock": 0, "tools": [], "items": {}
	}
	expected_wallet = 20000
	town = load("res://scenes/Town/TownScene.tscn").instantiate()
	add_child(town)

func _check(cond: bool, what: String):
	if not cond:
		fails.append(what)

func _process(_delta):
	frames += 1
	match frames:
		10:
			town.player.position = TownBackground.SEED_STAND.get_center() + Vector2(0, 70)
		12:
			_check(town.prompt == "[E] Browse the seed shop", "seed stand prompt appears")
			_tap(KEY_E)
		14:
			_check(town.open_shop == "seeds", "[E] opens the seed shop")
			_tap(KEY_1)
		16:
			_check(SaveDataManager.item_count("seeds", "russet") == 1, "[1] buys a russet seed")
			expected_wallet -= 10
			_check(SaveDataManager.wallet() == expected_wallet, "seed purchase charges 10 coins")
			_tap(KEY_ESCAPE)
		18:
			_check(town.open_shop == "", "[ESC] closes the shop")
			town.player.position = TownBackground.MARKET.get_center() + Vector2(0, 80)
		20:
			_check(town.prompt == "[E] Sell at the market", "market prompt appears")
			_tap(KEY_E)
		22:
			_check(town.open_shop == "market", "[E] opens the market")
			_tap(KEY_1)
		24:
			expected_wallet += 5 * 6
			_check(SaveDataManager.item_count("spuds", "russet") == 0, "market sells the russet stack")
			_check(SaveDataManager.wallet() == expected_wallet, "sale lands in the wallet")
			_tap(KEY_ESCAPE)
		26:
			_run_stalls()
		30:
			town.player.position = Vector2(TownBackground.KITCHEN_WALL.get_center().x,
					TownBackground.KITCHEN_WALL.end.y + 30)
		32:
			_check(town.prompt == "[E] Enter the championship kitchen", "kitchen prompt appears")
			town.player.position = TownBackground.FARM_GATE_POS
		34:
			_check(town.prompt == "[E] Take the road back to the farm", "farm gate prompt appears")
		40:
			_finish()

# Knife stand and tool shed, driven through the shared economy actions
func _run_stalls():
	_check(town.buy_or_equip_knife("paring"), "knife purchase succeeds")
	expected_wallet -= 150
	_check(SaveDataManager.farm.get("equipped_knife", "") == "paring", "knife auto-equips")

	# the starting plow is broken (0 uses), so a replacement is allowed
	_check(town.plow_cost() == 150, "first replacement plow costs 150")
	_check(town.buy_plow(), "plow purchase succeeds")
	expected_wallet -= 150
	_check(town.plow_uses() == 10, "new plow arrives with 10 uses")
	_check(not town.buy_plow(), "can't buy while the plow still works")
	_check(town.plow_cost() == 250, "plow price escalates per purchase")

	_check(town.buy_sprinkler(), "sprinkler purchase succeeds")
	expected_wallet -= 250
	_check(town.sprinkler_stock() == 1, "sprinkler waits in the pack for the farm")

	_check(town.buy_enhancer("compost"), "fertilizer purchase succeeds")
	expected_wallet -= 90
	_check(SaveDataManager.item_count("items", "compost") == 6, "compost comes with 6 charges")

	_check(SaveDataManager.wallet() == expected_wallet, "wallet math holds across the stalls")

func _finish():
	if fails.is_empty():
		print("TOWN SMOKE OK — stalls trade, kitchen and farm gate in place")
		get_tree().quit(0)
	else:
		print("TOWN SMOKE FAIL:")
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
