extends WorldController
class_name FarmController

# Spudling Acres (design §2, §5, §7): six fenced fields of 12 plots plus the
# Greenhouse, one verb (Tend) per whole field, Spudlings that work while
# you're away, Pip's note on return, the Farm Book and the Next Goal. All
# economy lives in FarmEconomy (pure, static); this scene only reads
# SaveDataManager.farm (fresh every tick), calls FarmEconomy actions with
# FarmClock time, reacts to their events and asks for a debounced save.
#
# Routing (WorldController.handle_input): Pip's note (modal) -> HUD hit
# regions -> the drawer -> the world. Keys (§7.1): WASD/arrows move; E/Space
# tend the field you stand in or use the station you stand at; F field card
# of that field; 1-7 field card from anywhere; T Tend All; B Farm Book;
# Q buy the Next Goal; G catch the butterfly; Z zoom; M mute; Esc closes the
# drawer/note, else back to the menu. Mouse: click a ripe or empty field to
# tend it, a growing or unowned one (or any field sign) for its card; click
# the butterfly, a hut, the farmhouse or the gate; wheel / pinch / two-finger
# scroll zoom between overview (0.45) and follow (1.0).

const CATCH_RADIUS := 60.0

var bg: FarmBackground
var fields: Array = []           # FarmField x7 (index = field index)
var critters: FarmCritters
var fireflies: CPUParticles2D
var views: Array = []            # FarmEconomy.field_view per field, refreshed every frame
var note_open := false
var note: Dictionary = {}        # {report}: what the open note shows
var pending_collect := false     # "Change plans first" left ripe fields: T / [Collect] tends them
var arrange: Dictionary = {}     # sprinkler arrange mode: {active, field, mode, sel, from, was_overview}
var hud_dirty := true
var last_result: Dictionary = {} # the last FarmEconomy action result (test hook)
var _note_t := 0.0
var _note_tick := 0.0

func _ready():
	var f := farm()
	if not FarmView.started(f):
		# first visit (or a freshly migrated farm): stamp the clock
		FarmEconomy.start(f, now_ms(), tz())
		SaveDataManager.request_farm_save()
	super._ready()
	settle_now()
	_refresh_views()
	if FarmView.note_pending(farm(), now_ms()):
		open_note()
	else:
		_show_banner("SPUDLING ACRES", _welcome_sub())
	_check_achievements()

func _welcome_sub() -> String:
	var g := FarmEconomy.next_goal(farm(), now_ms())
	if g["kind"] == "tutorial":
		return "%s: %s" % [g["label"], g["hint"]]
	return "Fields, Spudlings and the Farm Book: click anything!"

func _world_size() -> Vector2:
	return FarmBackground.WORLD

func _spawn_point() -> Vector2:
	if WorldController.travel_spawn == "from_town":
		WorldController.travel_spawn = ""
		return FarmBackground.FROM_TOWN_SPAWN
	return FarmBackground.HOUSE_DOOR + Vector2(0, 70)

func _make_hud() -> WorldHUD:
	return FarmHud.new()

func overview_zoom() -> float:
	return float(FarmEconomy.cfg()["start"].get("zoom", 0.45))

func _initial_overview() -> bool:
	var ui = farm().get("ui", {})
	var z := float(ui.get("zoom", overview_zoom())) if ui is Dictionary else overview_zoom()
	return z < 0.7

func _on_zoom_changed():
	var f := farm()
	if not f.has("ui") or not (f["ui"] is Dictionary):
		f["ui"] = {}
	f["ui"]["zoom"] = overview_zoom() if overview else FOLLOW_ZOOM
	SaveDataManager.request_farm_save()

func _build_world():
	bg = FarmBackground.new()
	add_child(bg)
	world_bg = bg
	for i in FarmEconomy.FIELDS:
		var ff := FarmField.new()
		ff.setup(i)
		add_child(ff)
		fields.append(ff)
	critters = FarmCritters.new()
	critters.ctrl = self
	add_child(critters)
	blockers = [
		FarmBackground.HOUSE_WALL.grow(4),
		Rect2(FarmBackground.WELL_POS - Vector2(55, 45), Vector2(110, 90)),
	]
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
	_refresh_stations()

func _walkable(p: Vector2) -> bool:
	if not super._walkable(p):
		return false
	var f := farm()
	for i in FarmEconomy.FIELDS:
		if f["fields"][i]["hut"] and FarmView.hut_rect(i).grow(-8).has_point(p):
			return false
	var d = (p - FarmBackground.POND_C) / (FarmBackground.POND_R + Vector2(28, 30))
	return d.length() > 1.0

# ── per-frame ──

func _tick(delta: float):
	var f := farm()
	var now := now_ms()
	_refresh_views()
	critters.tick(delta, f, now)
	if critters.bf_active and not note_open and player.position.distance_to(critters.bf_pos) <= CATCH_RADIUS:
		catch_butterfly()
	fireflies.emitting = night01 > 0.5
	_refresh_stations()
	if note_open:
		_note_t += delta
		var coins := int(note.get("report", {}).get("coins", 0))
		if coins > 0 and _note_t < 1.2:
			_note_tick -= delta
			if _note_tick <= 0.0:
				_note_tick = 0.25
				AudioManager.play_sfx("coin_tick")

func _refresh_views():
	var f := farm()
	if not f.has("fields"):
		return
	var now := now_ms()
	var screen := Rect2(-40, -40, 1360, 800)
	views.resize(FarmEconomy.FIELDS)
	for i in FarmEconomy.FIELDS:
		views[i] = FarmEconomy.field_view(f, i, now)
		if i < fields.size():
			fields[i].refresh(views[i], field_screen_rect(i).intersects(screen))

func _on_settle(res: Dictionary):
	if not res.is_empty():
		hud_dirty = true

func _refresh_stations():
	stations = [
		{"id": "house", "pos": FarmBackground.HOUSE_DOOR, "r": 95.0, "rect": FarmBackground.HOUSE_WALL,
			"text": "[E] The %s: hire and upgrade Spudlings (Farm Book)" % FarmView.house_name(FarmView.house_tier(farm())),
			"act": func(): open_book("helpers")},
		{"id": "gate", "pos": FarmBackground.TOWN_GATE_POS, "r": 120.0, "rect": Rect2(2400, 540, 160, 150),
			"text": "[E] Take the road into town", "act": goto_town},
	]
	var f := farm()
	for i in FarmEconomy.FIELDS:
		if f["fields"][i]["owned"] and f["fields"][i]["hut"]:
			var idx := i
			stations.append({"id": "hut:%d" % i, "pos": FarmView.hut_pos(i) + Vector2(0, 40), "r": 70.0,
				"rect": FarmView.hut_rect(i),
				"text": "[E] %s's hut: %s card" % [str(views[i]["hut_name"]) if views.size() > i else "Spudling",
						FarmView.field_name(i)],
				"act": func(): open_field_card(idx)})

# ── geometry helpers (test hooks) ──

func field_screen_rect(i: int) -> Rect2:
	return world_rect_to_screen(FarmView.field_rect(i))

func field_at(world_pos: Vector2, pad := 18.0) -> int:
	for i in FarmEconomy.FIELDS:
		if FarmView.field_rect(i).grow(pad).has_point(world_pos):
			return i
	return -1

func socket_screen_pos(s: String) -> Vector2:
	return world_to_screen(FarmView.socket_pos(s))

func player_present() -> bool:
	return FarmEconomy.is_present(farm(), now_ms())

func ui_blocking() -> bool:
	return super.ui_blocking() or note_open or arrange_active()

# ── prompt ──

func _scan_interactions():
	super._scan_interactions()
	if prompt != "" or ui_blocking():
		return
	var i := field_at(player.position)
	if i < 0 or views.size() <= i:
		return
	var v: Dictionary = views[i]
	var nm := FarmView.field_name(i)
	if not v["owned"]:
		prompt = "%s is for sale (%s c) · [E] or [F] details" % [nm, NumFmt.coins(int(v["cost"]))] if int(v["cost"]) >= 0 \
				else "%s · [F] details" % nm
		prompt_action = func(): open_field_card(i)
	elif v["ripe"]:
		prompt = "[E] Tend %s: %s is ripe!  ·  [F] Field card" % [nm, FarmView.crop_name(str(v["crop"]))]
		prompt_action = func(): tend_field(i)
	elif v["empty"]:
		var plan := str(v["plan"])
		var seed := 12 * int(FarmEconomy.crop_info(plan).get("seed", 0))
		prompt = "[E] Plant %s with %s (%s)  ·  [F] Field card" % [nm, FarmView.crop_name(plan),
				"free" if seed == 0 else NumFmt.coins(seed) + " c"]
		prompt_action = func(): tend_field(i)
	else:
		prompt = "%s · %s · ready at %s (in %s)  ·  [F] Field card" % [nm, FarmView.crop_name(str(v["crop"])),
				NumFmt.clock(int(v["ready_at_ms"]), tz()), NumFmt.dur(int(v["left_ms"]) / 1000.0)]
		prompt_action = func(): tend_field(i)

# ── input ──

# Pip's note owns every input while it is open (and doesn't stamp presence:
# its buttons do, through Collect / note_input). An input that ends an
# absence of report_min_s or more while the scene is open opens the note
# and is consumed.
func _modal_input(event: InputEvent) -> bool:
	if note_open:
		if event is InputEventKey:
			if event.echo:
				return true
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					collect()
				KEY_ESCAPE:
					close_note_change_plans()
				KEY_M:
					toggle_mute()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			match (hud as FarmHud).note_regions.hit_id(event.position):
				"note:collect":
					collect()
				"note:change":
					close_note_change_plans()
		return true
	var f := farm()
	var now := now_ms()
	if FarmView.started(f) and FarmView.idle_ms(f, now) >= FarmView.report_min_ms():
		FarmEconomy.settle(f, now, tz())
		if FarmView.note_pending(f, now):
			open_note()
			return true
	return false

func _key_input(event: InputEventKey):
	if arrange_active():
		_arrange_key(event)
		return
	super._key_input(event)

func _scene_key(event: InputEventKey) -> bool:
	var k := event.keycode
	match k:
		KEY_F:
			var i := field_at(player.position)
			if i < 0:
				_popup("Stand in a field for F, or press 1-7", WorldHUD.INK_DIM)
			elif book.is_card() and book.field == i:
				book.close()
			else:
				open_field_card(i)
		KEY_T:
			tend_all()
		KEY_B:
			if book.open and book.mode == "book":
				book.close()
				AudioManager.play_sfx("menu_back")
			else:
				open_book("")
		KEY_Q:
			buy_goal()
		KEY_G:
			catch_butterfly()
		_:
			var idx := int(k) - KEY_1
			if idx >= 0 and idx < FarmEconomy.FIELDS:
				open_field_card(idx)
			else:
				return false
	return true

func escape():
	if arrange_active():
		cancel_arrange()
	else:
		super.escape()

func _on_hud(id: String, data) -> bool:
	match id:
		"btn:book", "btn:book_bar":
			if book.open and book.mode == "book":
				book.close()
				AudioManager.play_sfx("menu_back")
			else:
				open_book("")
		"btn:tend_all":
			tend_all()
		"goal":
			goal_click()
		"bf:catch", "bf:arrow":
			catch_butterfly()
		"arrange:cancel":
			cancel_arrange()
		_:
			if id.begins_with("sign:"):
				field_click(int(data))
			elif id.begins_with("socket:"):
				arrange_pick(str(data))
			else:
				return false
	return true

func _world_click(world_pos: Vector2, screen_pos: Vector2) -> bool:
	if arrange_active():
		return true
	if critters.bf_active and world_pos.distance_to(critters.bf_pos) <= maxf(44.0, 30.0 / zoom_now):
		catch_butterfly()
		return true
	if super._world_click(world_pos, screen_pos):
		return true
	var i := field_at(world_pos, 10.0)
	if i >= 0:
		field_click(i)
		return true
	return false

# ── field actions ──

# A click on a field (or its sign): tend a ripe or empty field, otherwise
# open its card. Acts at any distance; the avatar turns and swings.
func field_click(i: int):
	if views.size() <= i:
		_refresh_views()
	var v: Dictionary = views[i]
	if v["owned"] and (v["empty"] or v["ripe"]):
		tend_field(i)
	else:
		open_field_card(i)

func open_field_card(i: int):
	arrange = {}
	book.open_card(i)
	face_toward(FarmView.field_rect(i).get_center())
	AudioManager.play_sfx("menu_select")

func tend_field(i: int) -> Dictionary:
	face_toward(FarmView.field_rect(i).get_center())
	var res := FarmEconomy.tend(farm(), i, now_ms(), tz())
	last_result = res
	_after_action(res)
	if res["ok"]:
		_tend_feedback(res, false)
	elif res.has("ready_at_ms"):
		_popup(str(res["msg"]), WorldHUD.INK_DIM)
	else:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

func tend_all() -> Dictionary:
	if pending_collect:
		return collect()
	var res := FarmEconomy.tend_all(farm(), now_ms(), tz())
	last_result = res
	_after_action(res)
	if not res["ok"]:
		_popup(str(res["msg"]), WorldHUD.WARN)
	elif int(res.get("tended", 0)) == 0:
		_popup("Nothing to tend: every field is growing", WorldHUD.INK_DIM)
	else:
		_tend_feedback(res, true)
	return res

# Pip's note [Collect]: FarmEconomy.collect (take_report + a Tend All that
# needs no hoe), the coin shower, and the welcome butterfly it schedules.
func collect() -> Dictionary:
	var res := FarmEconomy.collect(farm(), now_ms(), tz())
	last_result = res
	note_open = false
	pending_collect = false
	_after_action(res)
	_tend_feedback(res, true)
	AudioManager.play_sfx("coin_collect")
	return res

# Pip's note [Change plans first]: the note closes WITHOUT collecting (the
# report is read, the absence ends; ripe fields stay ripe, nothing rots), and
# the card of the first ripe field opens. T / the [Collect] button tends later.
func close_note_change_plans():
	var f := farm()
	note_open = false
	# stamp first (its settle closes the absence into the report), then read
	# and clear the report, so no new note is pending until the next absence
	note_real_input()
	FarmEconomy.take_report(f)
	SaveDataManager.request_farm_save()
	hud_dirty = true
	_refresh_views()
	var first := -1
	for i in FarmEconomy.FIELDS:
		if views[i]["owned"] and views[i]["ripe"]:
			first = i
			break
	pending_collect = first >= 0
	open_field_card(maxi(0, first))

func _tend_feedback(res: Dictionary, many: bool):
	var harvested := 0
	var planted := 0
	var gold := false
	var golden := false
	for rec in res.get("fields", []):
		if str(rec["crop"]) != "":
			harvested += 1
			critters.pop_field(int(rec["field"]), int(rec["coins"]), rec["stars"])
			if 2 in rec["stars"]:
				gold = true
			if bool(FarmEconomy.crop_info(str(rec["crop"])).get("rare", false)):
				golden = true
		elif str(rec["planted"]) != "":
			planted += 1
			critters.pop_text(FarmView.field_rect(int(rec["field"])).get_center(), "planted %s" % FarmView.crop_name(str(rec["planted"])))
	if harvested > 0:
		AudioManager.play_sfx_varied("harvest", 0.08)
		if gold:
			AudioManager.play_sfx("star")
		if golden:
			AudioManager.play_sfx("golden")
	elif planted > 0:
		AudioManager.play_sfx_varied("tend_pop", 0.08)
	if many and harvested + planted > 0:
		var coins := int(res.get("coins", 0))
		if coins > 0:
			_popup("+%s c · %d field%s tended" % [NumFmt.coins(coins), harvested + planted, "" if harvested + planted == 1 else "s"], WorldHUD.GOLD)

func _after_action(res: Dictionary):
	hud_dirty = true
	super._after_action(res)
	_refresh_views()

# ── goal, butterfly ──

func buy_goal() -> Dictionary:
	var res := farm_buy_goal()
	last_result = res
	return res

func goal_click():
	var g := FarmEconomy.next_goal(farm(), now_ms())
	if g["can_buy"]:
		buy_goal()
		return
	match str(g["kind"]):
		"page":
			open_book("catalog")
		"done":
			open_book("soil")
		"tutorial":
			if str(g["item"]) == "":
				if str(g["id"]).begins_with("page") or int(g["step"]) >= 6:
					open_book("catalog")
				else:
					_popup(str(g["hint"]), WorldHUD.INK_DIM)
			else:
				_popup(str(g["locked_reason"]) if str(g["locked_reason"]) != "" else "Needs %s c more" % NumFmt.coins(int(g["cost"]) - SaveDataManager.wallet()), WorldHUD.WARN)
		_:
			book.show_row(str(g["id"]))
			AudioManager.play_sfx("menu_select")
			if str(g["locked_reason"]) != "":
				_popup(str(g["locked_reason"]), WorldHUD.WARN)
			elif int(g["cost"]) > SaveDataManager.wallet():
				_popup("Needs %s c more" % NumFmt.coins(int(g["cost"]) - SaveDataManager.wallet()), WorldHUD.WARN)

# G, a click or walking into it. forced_outcome is a test hook (skips the due check).
func catch_butterfly(forced_outcome := "") -> Dictionary:
	var f := farm()
	var now := now_ms()
	if forced_outcome == "" and not FarmEconomy.butterfly_due(f, now):
		_popup("No butterfly right now: they visit every few minutes", WorldHUD.INK_DIM)
		return {"ok": false, "msg": "No butterfly"}
	var where: Vector2 = critters.bf_pos if critters.bf_active else player.position
	face_toward(where)
	var res := FarmEconomy.catch_butterfly(f, now, false, forced_outcome)
	last_result = res
	_after_action(res)
	if res["ok"]:
		critters.bf_active = false
		AudioManager.play_sfx("butterfly_catch")
		_popup(FarmView.butterfly_text(str(res["outcome"]), int(res["coins"])), WorldHUD.GOLD)
		critters.pop_text(where, "caught!")
	return res

# ── Pip's note ──

func open_note():
	note = {"report": FarmView.peek_report(farm())}
	note_open = true
	_note_t = 0.0
	_note_tick = 0.0
	book.close()
	arrange = {}
	AudioManager.play_sfx("note_open")

# The note's lines: [{icon, text}], counting the coin line up over 1.2 s.
func note_lines() -> Array:
	var rep: Dictionary = note.get("report", {})
	var out: Array = []
	var helpers: Array = rep.get("helpers", [])
	var baskets := int(rep.get("baskets", 0))
	if baskets > 0:
		var shown := int(round(int(rep.get("coins", 0)) * clampf(_note_t / 1.2, 0.0, 1.0)))
		var picks: Dictionary = rep.get("picks", {})
		var keys := picks.keys()
		keys.sort_custom(func(a, b): return int(picks[a]) > int(picks[b]))
		var parts: PackedStringArray = []
		for c in keys:
			parts.append("%s ×%d" % [FarmView.crop_name(str(c)), int(picks[c])])
		out.append({"icon": "potato", "text": "We picked %d basket%s while you were gone: +%s c (%s)" % [baskets,
				"" if baskets == 1 else "s", NumFmt.coins(shown), ", ".join(parts)]})
	if not helpers.is_empty():
		var who := _names(helpers)
		var worked := int(rep.get("worked_ms", 0)) / 1000
		var away := int(rep.get("away_ms", 0)) / 1000
		if bool(rep.get("napped", false)):
			out.append({"icon": "moon", "text": "%s worked %s of your %s, then napped. A bigger farmhouse covers more." % [who,
					NumFmt.dur(worked), NumFmt.dur(away)]})
		elif worked > 0:
			out.append({"icon": "moon", "text": "%s worked %s while you were away." % [who, NumFmt.dur(worked)]})
	var ripe := int(rep.get("ripe", 0))
	if ripe > 0:
		out.append({"icon": "wheat", "text": "%d field%s ripe and waiting (≈ +%s c)" % [ripe, " is" if ripe == 1 else "s are",
				NumFmt.coins(int(rep.get("waiting_coins", 0)))]})
	else:
		out.append({"icon": "wheat", "text": "Every field is still growing."})
	var pages: Array = rep.get("pages", [])
	if not pages.is_empty():
		var cat := FarmEconomy.catalog_view(farm())
		var p := int(pages[-1])
		out.append({"icon": "book", "text": "New Catalog page: %s!" % FarmView.crop_name(str(cat[p - 1]["crop"]))})
	else:
		for pg in FarmEconomy.catalog_view(farm()):
			if pg["current"]:
				for nd in pg["needs"]:
					if int(nd["have"]) < int(nd["need"]):
						out.append({"icon": "book", "text": "%s page: %s / %s %s" % [FarmView.crop_name(str(pg["crop"])),
								NumFmt.coins(int(nd["have"])), NumFmt.coins(int(nd["need"])), nd["name"]]})
						break
				break
	var mig = rep.get("migration", {})
	if mig is Dictionary and not mig.is_empty():
		out.append({"icon": "star", "text": "The farm got a makeover! Refunded %s c for retired gear; your crops, unlocks and Spudlings came with you." % NumFmt.coins(int(mig.get("refund", 0)))})
	return out

static func _names(helpers: Array) -> String:
	if helpers.size() == 1:
		return str(helpers[0])
	if helpers.size() == 2:
		return "%s and %s" % [helpers[0], helpers[1]]
	if helpers.size() == 3:
		return "%s, %s and %s" % [helpers[0], helpers[1], helpers[2]]
	return "%s and %d friends" % [helpers[0], helpers.size() - 1]

# ── sprinkler arrange mode ──

func arrange_active() -> bool:
	return bool(arrange.get("active", false))

# mode: "place" (one in stock), "buy" (buy one at the chosen socket), "move".
func begin_arrange(i: int, mode: String):
	var f := farm()
	var mine := FarmView.sockets_of(i)
	var sel := ""
	var from := ""
	if mode == "move":
		for s in f["sprinklers"]:
			if s in mine:
				from = s
				break
		if from == "" and not f["sprinklers"].is_empty():
			from = str(f["sprinklers"][0])
		sel = from
	else:
		for s in mine:
			if not s in f["sprinklers"]:
				sel = s
				break
		if sel == "":
			sel = str(FarmView.sockets()[0])
	arrange = {"active": true, "field": i, "mode": mode, "sel": sel, "from": from, "was_overview": overview}
	book.close()
	set_overview(true, true)
	AudioManager.play_sfx("menu_select")

func arrange_hint() -> String:
	var m := str(arrange.get("mode", ""))
	if str(arrange.get("from", "")) != "":
		return "Now click a free socket to move the sprinkler from fence %s" % arrange["from"]
	match m:
		"buy":
			return "Buy a sprinkler (%s c): click a fence socket · it waters both fields" % NumFmt.coins(FarmView.sprinkler_cost(farm()))
		"move":
			return "Click a placed sprinkler, then a free socket"
	return "Click a fence socket for your sprinkler · it waters both fields"

func arrange_pick(s: String) -> Dictionary:
	if not arrange_active():
		return {"ok": false}
	var f := farm()
	arrange["sel"] = s
	if s in f["sprinklers"]:
		arrange["from"] = "" if str(arrange.get("from", "")) == s else s
		AudioManager.play_sfx("menu_move")
		return {"ok": true, "picked": s}
	var res: Dictionary
	var from := str(arrange.get("from", ""))
	if from != "":
		res = FarmEconomy.place_sprinkler(f, s, from, now_ms(), tz())
		_after_action(res)
	elif FarmView.sprinklers_in_stock(f) > 0:
		res = FarmEconomy.place_sprinkler(f, s, "", now_ms(), tz())
		_after_action(res)
	else:
		res = farm_buy("sprinkler", s)
	last_result = res
	if res["ok"]:
		AudioManager.play_sfx_varied("tend_pop", 0.05)
		_end_arrange()
	elif from != "" or FarmView.sprinklers_in_stock(f) > 0:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

func cancel_arrange():
	if arrange_active():
		AudioManager.play_sfx("menu_back")
		_end_arrange()

func _end_arrange():
	var i := int(arrange.get("field", 0))
	var was: bool = arrange.get("was_overview", true)
	arrange = {}
	set_overview(was, true)
	book.open_card(i)

func _arrange_key(event: InputEventKey):
	if event.echo and not event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	var socks := FarmView.sockets()
	var k := socks.find(str(arrange.get("sel", "")))
	match event.keycode:
		KEY_LEFT, KEY_UP, KEY_A, KEY_W:
			arrange["sel"] = socks[posmod(k - 1, socks.size())]
			AudioManager.play_sfx("menu_move")
		KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S, KEY_TAB:
			arrange["sel"] = socks[posmod(k + 1, socks.size())]
			AudioManager.play_sfx("menu_move")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			arrange_pick(str(arrange["sel"]))
		KEY_ESCAPE:
			cancel_arrange()
		KEY_M:
			toggle_mute()

# ── travel ──

func goto_town():
	WorldController.travel_spawn = "from_farm"
	AudioManager.play_sfx("gate")
	get_tree().change_scene_to_file("res://scenes/Town/TownScene.tscn")
