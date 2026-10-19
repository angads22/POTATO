extends Node

# Headless town smoke test: walks the chef to each station and checks its
# prompt, opens the seed stall (Farm Book → Catalog) and the tool shed (Farm
# Book → Tools) with E, and buys a knife at the knife stand (a Chef-XP-gated
# knife is refused). The kitchen, concert and farm-gate prompts are asserted
# but never pressed — a scene change would free this test root.
# NOTE: writes to the user:// save like a real session would; give it a fresh
# user:// (XDG_DATA_HOME).
#
#   godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600

const FE = preload("res://scripts/farm/FarmEconomy.gd")

var frames := 0
var town
var fails: Array[String] = []

func _ready():
	var f: Dictionary = FE.new_farm()
	f["wallet"] = 20000
	SaveDataManager.farm = f
	town = load("res://scenes/Town/TownScene.tscn").instantiate()
	add_child(town)

func _check(cond: bool, what: String):
	if not cond:
		fails.append(what)

func _station(id: String) -> Dictionary:
	for s in town.stations:
		if s["id"] == id:
			return s
	return {}

func _goto(id: String):
	town.player.position = _station(id)["pos"]

func _process(_delta):
	frames += 1
	match frames:
		10:
			_goto("seeds")
		12:
			_check(town.prompt == _station("seeds")["text"], "seed stall prompt appears (%s)" % town.prompt)
			_tap(KEY_E)
		14:
			_check(town.book.open and town.book.tab == "catalog", "[E] at the seed stall opens the Catalog (%s)" % town.book.tab)
			town.book.close()
			_goto("tools")
		16:
			_check(town.prompt == _station("tools")["text"], "tool shed prompt appears (%s)" % town.prompt)
			_tap(KEY_E)
		18:
			_check(town.book.open and town.book.tab == "tools", "[E] at the tool shed opens Tools (%s)" % town.book.tab)
			town.book.close()
			_goto("knives")
		20:
			_check(town.prompt == _station("knives")["text"], "knife stand prompt appears (%s)" % town.prompt)
			_tap(KEY_E)
		22:
			_check(town.open_shop == "knives", "[E] opens the knife stand")
			_knives()
			_tap(KEY_ESCAPE)
		24:
			_check(town.open_shop == "", "[ESC] closes the knife stand")
			_goto("kitchen")
		26:
			_check(town.prompt == "[E] Enter the championship kitchen", "kitchen prompt appears (%s)" % town.prompt)
			_goto("gate")
		28:
			_check(town.prompt == "[E] Take the road back to the farm", "farm gate prompt appears (%s)" % town.prompt)
			_goto("concert")
		30:
			_check(town.prompt == "[E] Take the stage: play a CONCERT", "concert hall prompt appears (%s)" % town.prompt)
		34:
			_finish()

func _knives():
	var w := SaveDataManager.wallet()
	var cost := int(GameData.knife_by_id("paring").get("cost", 0))
	_check(town.buy_or_equip_knife("paring"), "knife purchase succeeds")
	_check(SaveDataManager.farm.get("equipped_knife", "") == "paring", "knife auto-equips")
	_check(SaveDataManager.wallet() == w - cost, "knife costs %d c" % cost)
	var gated := ""
	for k in GameData.knives():
		if int(k.get("unlock_xp", 0)) > SaveDataManager.career_xp():
			gated = str(k["id"])
			break
	if gated != "":
		w = SaveDataManager.wallet()
		_check(not town.buy_or_equip_knife(gated) and SaveDataManager.wallet() == w,
				"%s is locked behind Chef XP" % gated)

func _finish():
	if fails.is_empty():
		print("TOWN SMOKE OK — stalls open the Farm Book, knife stand trades, kitchen, concert hall and farm gate in place")
		get_tree().quit(0)
	else:
		print("TOWN SMOKE FAIL:")
		for f in fails:
			print("  - " + f)
		get_tree().quit(1)

func _tap(key: Key):
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		get_tree().root.push_input(ev, true)
