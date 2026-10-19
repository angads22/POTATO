extends Node

# Review screenshots (not a CI test). Stages the menu, the kitchen, a fresh
# Spudling Acres, a mid-game farm built through FarmEconomy calls (deeds, huts,
# farmhouse, hoes, sprinklers, Soil, a Prize Strain, plans on every field),
# its follow zoom, a field card, the Farm Book, Pip's note after an absence,
# the farm at night and in the pixel / hyperreal styles, and the town (square,
# knife stand, Farm Book from the seed stall). Scenes are instantiated as
# children so this node survives every swap; the farm clock is frozen
# (FarmClock.frozen_ms) and the zone pinned to UTC, so every run is the same.
# Run under a virtual display:
#   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . res://tests/Screenshot.tscn
# Writes /tmp/shot_*.png (or into the folder given as `-- --out=DIR`):
#   shot_menu, shot_gameplay, shot_farm_fresh, shot_farm, shot_farm_follow,
#   shot_farm_card, shot_farm_book, shot_farm_note, shot_farm_night,
#   shot_farm_pixel, shot_farm_hyperreal, shot_town, shot_town_knives,
#   shot_town_book
# The current slot's farm is swapped for the staged ones in memory and put
# back at the end (the farm scenes flush their save on exit, so a scratch
# user:// via XDG_DATA_HOME is still the safest way to run it).

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FV = preload("res://scripts/farm/FarmView.gd")
const Clock = preload("res://scripts/farm/FarmClock.gd")

const T0 := 1792319400000          # 2026-10-18 10:30 UTC (a weekday morning)
const HOUR := 3600000
const DAY := 86400000

var out_dir := "/tmp/"
var current
var saved: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _run() -> void:
	var farm0: Dictionary = SaveDataManager.farm.duplicate(true)
	Clock.reset()
	Clock.tz_override = 0
	Clock.frozen_ms = T0
	await _menu_and_kitchen()
	await _fresh_farm()
	await _mid_farm()
	await _town()
	if current != null:
		current.queue_free()
		await frames(2)
	StyleManager.apply(StyleManager.current())
	SaveDataManager.farm = farm0
	SaveDataManager.save_farm()
	Clock.reset()
	print("SHOTS: %d saved in %s" % [saved.size(), out_dir])
	get_tree().quit(0)

# ════════════════════════════════════════════ helpers

func frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + "shot_%s.png" % name
	img.save_png(path)
	saved.append(path)
	print("saved " + path)

func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_tree().root.push_input(ev, true)
	await frames(2)

func swap_to(path: String) -> void:
	if current != null:
		current.queue_free()
		await frames(2)
	current = load(path).instantiate()
	add_child(current)
	await frames(3)

# A world scene with its entry banner hidden and the camera snapped.
func open_world(path: String) -> void:
	await swap_to(path)
	current.snap_camera()
	current.banner_age = 99.0
	current.popups.clear()
	await frames(6)

# ════════════════════════════════════════════ menu + kitchen

func _menu_and_kitchen() -> void:
	await swap_to("res://scenes/MainMenu.tscn")
	await frames(40)
	await snap("menu")
	current.queue_free()
	current = null
	await frames(2)
	GameManager.start_game("championship")
	GameManager.current_state.lives = 2
	GameManager.current_state.score = 4280
	GameManager.current_state.combo = 7
	await swap_to("res://scenes/Gameplay/GameplayScene.tscn")
	await frames(90)
	await snap("gameplay")
	GameManager.current_state.is_running = false

# ════════════════════════════════════════════ a fresh farm

func _fresh_farm() -> void:
	SaveDataManager.farm = FE.new_farm()
	await open_world("res://scenes/Farm/FarmScene.tscn")
	await snap("farm_fresh")

# ════════════════════════════════════════════ a mid-game farm

# Built with FarmEconomy calls only: the first half of the Catalog shipped,
# then whatever the Book sells from that point (a refused buy is only printed).
func _mid_farm() -> void:
	var cfg := FE.cfg()
	var f := FE.new_farm()
	var t := T0 - 2 * DAY
	FE.start(f, t, 0)
	f["wallet"] = 1000000000
	# one hand-planted, hand-harvested field: the tutorial's first steps
	FE.tend(f, 0, t, 0)
	t += int(f["fields"][0]["grow_eff_ms"])
	FE.tend(f, 0, t, 0)
	var cat: Array = cfg["catalog"]
	for p in cat.size() / 2 + 1:
		for c in cat[p]["needs"]:
			f["shipped"][c] = maxi(int(f["shipped"].get(c, 0)), int(cat[p]["needs"][c]))
	FE.settle(f, t, 0)
	for it in [["deed", 1], ["deed", 3], ["deed", 4], ["hut", 0], ["hut", 1], ["hut", 3], ["house", null],
			["house", null], ["tool", null], ["tool", null], ["sprinkler", "1-2"], ["sprinkler", "4-5"],
			["soil", null], ["soil", null], ["soil", null], ["share", null], ["quick", null]]:
		var r := FE.buy(f, it[0], it[1], t, 0)
		if not r["ok"]:
			print("buy %s refused: %s" % [str(it), r["msg"]])
	var unl: Array = f["unlocked"]
	var strain := str(unl[mini(2, unl.size() - 1)])
	if not FE.buy(f, "strain", strain, t, 0)["ok"]:
		print("strain %s refused" % strain)
	# plans: the longest unlocked crops on the hand fields, short ones on the huts
	var by_grow: Array = unl.duplicate()
	by_grow.sort_custom(func(a, b): return int(FE.crop_info(a)["grow_ms"]) < int(FE.crop_info(b)["grow_ms"]))
	var plans := {0: by_grow[mini(1, by_grow.size() - 1)], 1: by_grow[mini(2, by_grow.size() - 1)],
			3: by_grow[0], 4: by_grow[-1]}
	for i in plans:
		FE.set_plan(f, i, str(plans[i]), t, 0)
	# planted at staggered times so the fields show every growth stage
	t = T0 - 50 * 60000
	FE.tend(f, 4, t, 0)
	t = T0 - 12 * 60000
	FE.tend(f, 1, t, 0)
	FE.tend(f, 3, t, 0)
	t = T0 - 3 * 60000
	FE.tend(f, 0, t, 0)
	FE.note_input(f, T0, 0)
	FE.take_report(f)
	f["wallet"] = 23456
	f["ui"]["zoom"] = float(cfg["start"]["zoom"])
	f["buffs"]["next_butterfly_ms"] = T0 + DAY
	SaveDataManager.farm = f
	await open_world("res://scenes/Farm/FarmScene.tscn")
	await snap("farm")
	# follow zoom near Field 2
	current.player.position = FV.field_rect(1).get_center() + Vector2(-200, -40)
	current.set_overview(false, true)
	current.snap_camera()
	await frames(6)
	await snap("farm_follow")
	current.set_overview(true, true)
	current.snap_camera()
	# a field card (Field 1, growing) and the Farm Book (Helpers)
	current.open_field_card(0)
	await frames(4)
	await snap("farm_card")
	current.open_book("helpers")
	await frames(4)
	await snap("farm_book")
	current.book.close()
	await frames(2)
	# Pip's note after three hours away (the first key opens it), counted up
	Clock.frozen_ms = T0 + 3 * HOUR
	await frames(2)
	await key(KEY_H)
	if not current.note_open:
		print("note did not open (no news?)")
		current.open_note()
	current._note_t = 5.0
	current.hud.mark_dirty()
	await frames(4)
	await snap("farm_note")
	await key(KEY_ENTER)
	current.popups.clear()
	current.banner_age = 99.0
	await frames(6)
	# 22:00 the same day: the night tint, lit windows, fireflies
	Clock.frozen_ms = T0 + int(11.5 * HOUR)
	current.player.position = FV.field_rect(0).get_center()
	await key(KEY_H)
	if current.note_open:
		await key(KEY_ENTER)
	current.popups.clear()
	current.banner_age = 99.0
	await frames(8)
	await snap("farm_night")
	# styles, by day
	Clock.frozen_ms = T0 + 4 * HOUR
	await frames(2)
	await key(KEY_H)
	if current.note_open:
		await key(KEY_ENTER)
	current.popups.clear()
	current.banner_age = 99.0
	await frames(4)
	StyleManager.apply("pixel")
	await frames(4)
	await snap("farm_pixel")
	StyleManager.apply("hyperreal")
	await frames(4)
	await snap("farm_hyperreal")
	StyleManager.apply("classic")
	await frames(2)

# ════════════════════════════════════════════ the town

func _town() -> void:
	await open_world("res://scenes/Town/TownScene.tscn")
	current.player.position = Vector2(700, 560)
	current.snap_camera()
	current.banner_age = 99.0
	await frames(6)
	await snap("town")
	current.open_knives()
	await frames(4)
	await snap("town_knives")
	current.close_shop()
	current.open_book("catalog")
	await frames(4)
	await snap("town_book")
	current.book.close()
