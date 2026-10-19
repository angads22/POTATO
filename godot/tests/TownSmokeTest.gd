extends Node

# Headless town smoke test (design §10.5, TownSmokeTest). It drives the REAL
# TownScene with synthetic input (keys and left clicks pushed through
# get_tree().root.push_input in 1280x720 viewport coordinates) on a frozen
# farm clock (FarmClock.frozen_ms), so neither the town's 0.5 s settle nor the
# 30 s SaveDataManager heartbeat can move the wallet behind the test's back.
# Prices and gates are read at runtime (FarmEconomy.cost_of, knives.json via
# GameData), never hard-coded.
#
#   - frozen clock: frames and heartbeats leave the wallet alone; moving the
#     frozen clock lets the heartbeat settle Pip's picks from town (exactly
#     what a pure FarmEconomy.settle on a copy pays)
#   - every station's prompt (seed stall, knife stand, tool shed, kitchen,
#     Concert Hall, farm gate); the kitchen, concert and gate are never
#     pressed (a scene change would free this test root)
#   - the seed stall opens the Farm Book on its Catalog tab, the tool shed on
#     Tools (E up close, the overview tags, a click on the stall from afar);
#     B and the Book button toggle it
#   - the Copper Hoe bought in town (a click on the Tools row's [Buy]) costs
#     FarmEconomy.cost_of("tool")
#   - the knife stand: a key buys (wallet - cost, owned, equipped), a second
#     press only equips, Up/Down + Enter; a short wallet is refused; the
#     santoku is refused below its Chef-XP gate and bought at it by a mouse
#     click on its row; a click outside the panel and Esc close the stand
#   - Esc with nothing open only warns
#
#   godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600
#
# Prints "TOWN SMOKE OK" and exits 0, or "TOWN SMOKE FAIL" plus the failed
# checks and exits 1. It replaces the farm and Chef XP of the current slot
# (the XP is restored at the end); give it a fresh user:// (XDG_DATA_HOME).

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const Clock = preload("res://scripts/farm/FarmClock.gd")
const Fmt = preload("res://scripts/utils/NumFmt.gd")

const T0 := 1767261600000          # 2026-01-01 10:00 UTC (the zone is pinned to UTC)
const HOUR := 3600000

var town
var fails: Array = []
var checks := 0
var mouse_events := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var wall0 := Time.get_ticks_msec()
	var frame0 := Engine.get_process_frames()
	var xp0 := SaveDataManager.career_xp()
	Clock.reset()
	Clock.tz_override = 0
	Clock.frozen_ms = T0
	# a started farm with Pip on Field 1 and your Russet in the ground
	var f := FE.new_farm()
	FE.start(f, T0, 0)
	f["wallet"] = 100000
	_check(FE.buy(f, "hut", 0, T0, 0)["ok"] and FE.tend(f, 0, T0, 0)["ok"], "setup: Pip hired, Field 1 planted")
	f["buffs"]["next_butterfly_ms"] = T0 + 100 * 86400000
	SaveDataManager.farm = f
	SaveDataManager.settings["career_xp"] = 0
	town = load("res://scenes/Town/TownScene.tscn").instantiate()
	add_child(town)
	await frames(3)
	await _frozen_clock()
	await _prompts()
	await _book_stalls()
	await _copper_hoe()
	await _knife_stand()
	await _esc()
	SaveDataManager.settings["career_xp"] = xp0
	SaveDataManager.save_game()
	Clock.reset()
	_finish(Engine.get_process_frames() - frame0, Time.get_ticks_msec() - wall0)

# ════════════════════════════════════════════ helpers

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)
		print("  FAIL ", what)

func _finish(frames_used: int, wall_ms: int) -> void:
	if fails.is_empty():
		print("TOWN SMOKE OK — %d checks, %d frames, %.1f s" % [checks, frames_used, wall_ms / 1000.0])
		get_tree().quit(0)
	else:
		print("TOWN SMOKE FAIL — %d of %d checks failed:" % [fails.size(), checks])
		for x in fails:
			print("  - " + str(x))
		get_tree().quit(1)

func frame() -> void:
	await get_tree().process_frame

func frames(n: int) -> void:
	for k in n:
		await frame()

func farm() -> Dictionary:
	return SaveDataManager.farm

func wallet() -> int:
	return SaveDataManager.wallet()

func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_tree().root.push_input(ev, true)
	await frame()

func click(pos: Vector2) -> void:
	mouse_events += 1
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev, true)
	await frame()

# Click the centre of a drawn hit region (HUD, knife stand or Farm Book).
func click_region(reg, id: String) -> void:
	var r: Rect2 = reg.rect_of(id)
	if r.size == Vector2.ZERO:
		_check(false, "region '%s' is drawn (have %s)" % [id, str(reg.ids())])
		return
	await click(r.get_center())

func popped(prefix: String, color = null) -> bool:
	for p in town.popups:
		if str(p["text"]).begins_with(prefix) and (color == null or p["color"] == color):
			return true
	return false

func popup_texts() -> Array:
	return town.popups.map(func(p): return str(p["text"]))

func goto(id: String) -> Dictionary:
	var st: Dictionary = town.station(id)
	_check(not st.is_empty(), "station '%s' exists" % id)
	if not st.is_empty():
		town.player.position = st["pos"]
	await frames(2)
	return st

func knife(id: String) -> Dictionary:
	return GameData.knife_by_id(id)

func owned(id: String) -> bool:
	return id in farm().get("owned_knives", [])

# ════════════════════════════════════════════ the frozen clock + the heartbeat

func _frozen_clock() -> void:
	print("== frozen farm clock; the heartbeat settles from town")
	var f := farm()
	var w0 := wallet()
	for k in 3:
		SaveDataManager.heartbeat()
		await frames(10)
	_check(wallet() == w0 and int(f["clock"]["last_settle_ms"]) == T0,
			"frozen: 30 frames and 3 heartbeats left the wallet at %d (now %d)" % [w0, wallet()])
	# an hour on: the heartbeat (not the scene) settles Pip's picks
	var exp: Dictionary = f.duplicate(true)
	var er := FE.settle(exp, T0 + HOUR, 0)
	Clock.frozen_ms = T0 + HOUR
	var res: Dictionary = SaveDataManager.heartbeat()
	_check(int(er["picks"]) > 0 and int(res.get("picks", -1)) == int(er["picks"]) and wallet() == int(exp["wallet"]),
			"heartbeat in town: %d picks, wallet %d (pure settle: %d picks, %d)" % [int(res.get("picks", -1)), wallet(),
			int(er["picks"]), int(exp["wallet"])])
	await frames(2)

# ════════════════════════════════════════════ prompts

func _prompts() -> void:
	print("== station prompts (kitchen, concert and gate never pressed)")
	var want := {
		"seeds": "[E] Seed stall: the Seed Catalog (Farm Book)",
		"knives": "[E] Browse the knife stand",
		"tools": "[E] Tool shed: hoes and sprinklers (Farm Book)",
		"kitchen": "[E] Enter the championship kitchen",
		"concert": "[E] Take the stage: play a CONCERT",
		"gate": "[E] Take the road back to the farm",
	}
	for id in want:
		var st: Dictionary = await goto(id)
		_check(town.prompt == str(st.get("text", "?")) and town.prompt == want[id], "%s prompt '%s'" % [id, town.prompt])
		_check(town.hud.regions.has("prompt"), "%s: the prompt bar is drawn (a click target)" % id)
	_check(town.is_inside_tree() and not town.book.open and town.open_shop == "", "nothing was pressed")

# ════════════════════════════════════════════ the seed stall and tool shed open the Farm Book

func _book_stalls() -> void:
	print("== the seed stall and the tool shed open the Farm Book")
	await goto("seeds")
	await key(KEY_E)
	_check(town.book.open and town.book.mode == "book" and town.book.tab == "catalog", "E at the seed stall: Book on Catalog (%s)" % town.book.tab)
	await key(KEY_ESCAPE)
	_check(not town.book.open, "Esc closes the Book")
	await goto("tools")
	await key(KEY_E)
	_check(town.book.open and town.book.tab == "tools", "E at the tool shed: Book on Tools (%s)" % town.book.tab)
	await key(KEY_B)
	_check(not town.book.open, "B closes the Book")
	await key(KEY_B)
	_check(town.book.open and town.book.tab == "tools", "B reopens it on the last tab")
	await key(KEY_ESCAPE)
	await frame()
	await click_region(town.hud.regions, "btn:book_bar")
	_check(town.book.open, "the bar's Farm Book button opens it")
	await key(KEY_ESCAPE)
	# from afar: the overview tags, and a click on the stall itself
	town.player.position = town.station("kitchen")["pos"]
	town.set_overview(true, true)
	town.snap_camera()
	await frames(2)
	await click_region(town.hud.regions, "station:tools")
	_check(town.book.open and town.book.tab == "tools", "a click on the overview's Tool shed tag: Book on Tools")
	await key(KEY_ESCAPE)
	await frame()
	var seeds_at: Vector2 = town.world_to_screen((town.station("seeds")["rect"] as Rect2).get_center())
	_check(town.hud.regions.hit_id(seeds_at) == "", "the seed stall isn't under a HUD button (%s)" % town.hud.regions.hit_id(seeds_at))
	await click(seeds_at)
	_check(town.book.open and town.book.tab == "catalog", "a click on the seed stall from across the square: Book on Catalog")
	await key(KEY_ESCAPE)
	town.set_overview(false, true)
	town.snap_camera()
	await frame()

# ════════════════════════════════════════════ the Copper Hoe from town

func _copper_hoe() -> void:
	print("== the Copper Hoe bought at the tool shed")
	var f := farm()
	await goto("tools")
	await key(KEY_E)
	await frame()
	var cost := FE.cost_of(f, "tool", null)
	var row: Dictionary = town.book.row_by_id("tool")
	_check(cost > 0 and not row.is_empty() and int(row["cost"]) == cost, "Tools row 'tool' at cost_of('tool') = %d c" % cost)
	if wallet() < cost:
		f["wallet"] = cost
		await frame()
	var w := wallet()
	await click_region(town.book.regions, "buy:tool")
	var hoe := str(FE.cfg()["tools"][1]["name"])
	_check(int(f["up"]["tool"]) == 1 and FE.has_tend_all(f) and wallet() == w - cost,
			"a click on [Buy] bought the %s for %d c (wallet %d -> %d)" % [hoe, cost, w, wallet()])
	_check(popped("New hoe: %s" % hoe), "hoe popup (%s)" % str(popup_texts()))
	await key(KEY_ESCAPE)

# ════════════════════════════════════════════ the knife stand

func _knife_stand() -> void:
	print("== the knife stand: keys, a short wallet, the santoku's Chef-XP gate, a click")
	var f := farm()
	var ks: Array = GameData.knives()
	await goto("knives")
	await key(KEY_E)
	_check(town.open_shop == "knives", "E opens the knife stand")
	# the first knife you don't own that needs no XP: its number key buys it
	var k1 := -1
	for i in ks.size():
		if not owned(str(ks[i]["id"])) and int(ks[i].get("unlock_xp", 0)) == 0 and int(ks[i]["cost"]) > 0:
			k1 = i
			break
	_check(k1 >= 0, "a knife without an XP gate to buy")
	if k1 >= 0:
		var id1 := str(ks[k1]["id"])
		var cost1 := int(ks[k1]["cost"])
		if wallet() < cost1:
			f["wallet"] = cost1
		var w := wallet()
		await key(KEY_1 + k1)
		_check(owned(id1) and f["equipped_knife"] == id1 and wallet() == w - cost1,
				"key %d bought the %s for %d c and equipped it" % [k1 + 1, ks[k1]["name"], cost1])
		await key(KEY_1 + k1)
		_check(wallet() == w - cost1 and f["equipped_knife"] == id1, "a second press only equips it (no charge)")
		# Up/Down + Enter: back to the first (owned) knife
		while town.shop_sel != 0:
			await key(KEY_UP)
		await key(KEY_ENTER)
		_check(f["equipped_knife"] == str(ks[0]["id"]) and wallet() == w - cost1, "Up + Enter equipped the %s" % ks[0]["name"])
	# the santoku: refused below its Chef-XP gate, bought at it by a mouse click
	var sk := knife("santoku")
	_check(not sk.is_empty() and int(sk.get("unlock_xp", 0)) > 0, "the santoku has a Chef-XP gate (knives.json)")
	if not sk.is_empty():
		var need := int(sk["unlock_xp"])
		var cost := int(sk["cost"])
		f["wallet"] = cost + 1000
		SaveDataManager.settings["career_xp"] = need - 1
		town.popups.clear()
		await frame()
		var w := wallet()
		await click_region(town.hud.regions, "knife:santoku")
		_check(not owned("santoku") and wallet() == w, "santoku refused at %d Chef XP (needs %d)" % [need - 1, need])
		_check(popped("%s locked: reach %s Chef XP" % [sk["name"], Fmt.coins(need)], WorldHUD.WARN), "…with an orange 'reach N Chef XP' (%s)" % str(popup_texts()))
		SaveDataManager.settings["career_xp"] = need
		await frame()
		await click_region(town.hud.regions, "knife:santoku")
		_check(owned("santoku") and f["equipped_knife"] == "santoku" and wallet() == w - cost,
				"a click on its row bought the santoku at %d Chef XP for %d c" % [need, cost])
	# a short wallet: the next gated knife, XP met, one coin short
	var short := ""
	for k in ks:
		if not owned(str(k["id"])) and int(k["cost"]) > 0:
			short = str(k["id"])
			break
	if short != "":
		var ksh := knife(short)
		SaveDataManager.settings["career_xp"] = maxi(SaveDataManager.career_xp(), int(ksh.get("unlock_xp", 0)))
		f["wallet"] = int(ksh["cost"]) - 1
		town.popups.clear()
		await frame()
		await click_region(town.hud.regions, "knife:" + short)
		_check(not owned(short) and wallet() == int(ksh["cost"]) - 1 and popped("Needs %s c" % Fmt.coins(int(ksh["cost"])), WorldHUD.WARN),
				"the %s is refused one coin short (%s)" % [ksh["name"], str(popup_texts())])
	# a click outside the panel closes the stand; Esc closes it too
	await click(Vector2(WorldHUD.SHOP_PANEL.position.x - 120, WorldHUD.SHOP_PANEL.get_center().y))
	_check(town.open_shop == "", "a click outside the panel closes the knife stand")
	town.open_knives()
	await frame()
	_check(town.hud.regions.has("shop:close"), "the stand's close button is drawn")
	await key(KEY_ESCAPE)
	_check(town.open_shop == "", "Esc closes the knife stand")

# ════════════════════════════════════════════ Esc with nothing open

func _esc() -> void:
	print("== Esc with nothing open")
	town.popups.clear()
	await key(KEY_ESCAPE)
	_check(town.is_inside_tree() and popped("Press Esc again for the menu"), "Esc with nothing open only warns (%s)" % str(popup_texts()))
	town._esc_t = 0.0                     # never let a later Esc leave the scene
