extends RefCounted
class_name FarmBook

# The right-side drawer (design §7.2): the FARM BOOK (six tabs: Land,
# Helpers, Tools, Soil & Strains, Catalog, Stats) and the FIELD CARD (plan
# picker, Spudling line, sprinkler line, Replant now). It owns no farm state:
# it reads SaveDataManager.farm through FarmEconomy every time it draws, and
# every button calls back into its controller (WorldController.farm_buy /
# farm_pin / farm_set_plan / farm_replant; the farm adds tend_field and
# begin_arrange), so the town's seed stall and tool shed reuse it as is.
#
# Drawing goes into the HUD's canvas item (draw(ci, font)); every button is
# registered in `regions` with a stable id (test hooks):
#   close · tab:<land|helpers|tools|soil|catalog|stats> · scroll:up/down
#   row:<row id> · buy:<row id> · pin:<row id>          (book rows, e.g. buy:hut:0)
#   card:prev · card:next · plan:<crop> · card:hire · card:sprinkler
#   card:tend · card:replant · card:deed                 (field card)

const RECT := Rect2(860, 76, 410, 560)
const TABS := ["land", "helpers", "tools", "soil", "catalog", "stats"]
const TAB_LABELS := {"land": "Land", "helpers": "Helpers", "tools": "Tools", "soil": "Soil",
		"catalog": "Catalog", "stats": "Stats"}
const TAB_TITLES := {"land": "Land", "helpers": "Helpers", "tools": "Tools", "soil": "Soil & Strains",
		"catalog": "Seed Catalog", "stats": "Stats"}
const ROW_W := 380.0
const ROW_H := 76.0
const ROW_STEP := 80.0
const LIST_TOP := 220.0
const VISIBLE_ROWS := 5
const PLAN_STEP := 46.0

var ctrl                       # WorldController
var open := false
var mode := "book"             # "book" | "card"
var tab := "land"
var sel := 0                   # book: row index in the tab · card: focus index
var scroll := 0                # book: first visible row
var field := 0                 # field card index (0..6)
var regions := HitRegions.new()

var _all_rows: Array = []
var _rows_at := -100000
var _dirty := true

# ── open / close ──

func open_book(t := ""):
	open = true
	mode = "book"
	if t != "" and t in TABS:
		tab = t
	sel = 0
	scroll = 0
	invalidate()

func open_card(i: int):
	open = true
	mode = "card"
	field = clampi(i, 0, FarmEconomy.FIELDS - 1)
	sel = _card_focus_default()
	invalidate()

func close():
	open = false

func is_card() -> bool:
	return open and mode == "card"

func contains(pos: Vector2) -> bool:
	return open and RECT.has_point(pos)

func invalidate():
	_dirty = true

# ── data ──

func _farm() -> Dictionary:
	return SaveDataManager.farm

func all_rows() -> Array:
	var now := FarmClock.now_ms()
	if _dirty or absi(now - _rows_at) > 1000:
		_all_rows = FarmEconomy.book(_farm(), now, FarmClock.tz_s())
		_rows_at = now
		_dirty = false
	return _all_rows

func rows() -> Array:
	var out: Array = []
	for r in all_rows():
		if r["tab"] == tab:
			out.append(r)
	return out

func row_by_id(id: String) -> Dictionary:
	for r in all_rows():
		if r["id"] == id:
			return r
	return {}

# Open the Book on a row's tab with that row selected (Next Goal card click).
func show_row(id: String) -> bool:
	var r := row_by_id(id)
	if r.is_empty():
		return false
	open_book(str(r["tab"]))
	var rs := rows()
	for k in rs.size():
		if rs[k]["id"] == id:
			sel = k
	_keep_visible(rs.size())
	return true

func _keep_visible(n: int):
	sel = clampi(sel, 0, maxi(0, n - 1))
	if sel < scroll:
		scroll = sel
	elif sel >= scroll + VISIBLE_ROWS:
		scroll = sel - VISIBLE_ROWS + 1
	scroll = clampi(scroll, 0, maxi(0, n - VISIBLE_ROWS))

func scroll_by(dir: int):
	if mode != "book":
		return
	var n := rows().size()
	scroll = clampi(scroll + dir, 0, maxi(0, n - VISIBLE_ROWS))
	sel = clampi(sel, scroll, mini(n - 1, scroll + VISIBLE_ROWS - 1))

# Screen rect of a visible row's part ("row", "buy", "pin"): test hook.
func row_rect(id: String, part := "buy") -> Rect2:
	return regions.rect_of("%s:%s" % [part, id])

# ── field card focus list ──

func _card_items() -> Array:
	var f := _farm()
	var i := field
	var out: Array = []
	if not f["fields"][i]["owned"]:
		out.append("card:deed")
		return out
	for c in FarmEconomy.crops():
		out.append("plan:" + str(c))
	out.append("card:hire")
	out.append("card:sprinkler")
	if bool(sprinkler_state().get("can_move", false)):
		out.append("card:sprinkler_move")
	out.append("card:tend")
	out.append("card:replant")
	return out

func _card_focus_default() -> int:
	var items := _card_items()
	var plan: String = str(_farm()["fields"][field]["plan"])
	var k := items.find("plan:" + plan)
	return maxi(0, k)

# ════════════════════════════════════════════ input

func key(event: InputEventKey) -> bool:
	if not open:
		return false
	var k := event.keycode
	if mode == "card":
		return _card_key(k, event.shift_pressed)
	match k:
		KEY_LEFT:
			_set_tab(posmod(TABS.find(tab) - 1, TABS.size()))
		KEY_RIGHT:
			_set_tab(posmod(TABS.find(tab) + 1, TABS.size()))
		KEY_TAB:
			_set_tab(posmod(TABS.find(tab) + (-1 if event.shift_pressed else 1), TABS.size()))
		KEY_UP:
			sel -= 1
			_keep_visible(rows().size())
		KEY_DOWN:
			sel += 1
			_keep_visible(rows().size())
		KEY_ENTER, KEY_KP_ENTER:
			var rs := rows()
			if sel >= 0 and sel < rs.size():
				ctrl.farm_buy(str(rs[sel]["id"]), null)
		KEY_P:
			var rs2 := rows()
			if sel >= 0 and sel < rs2.size():
				ctrl.farm_pin(str(rs2[sel]["id"]))
		KEY_SPACE:
			pass                          # Space never acts while a drawer is open
		_:
			var idx := int(k) - KEY_1
			if idx >= 0 and idx < TABS.size():
				_set_tab(idx)
			else:
				return false
	return true

func _set_tab(idx: int):
	tab = TABS[idx]
	sel = 0
	scroll = 0
	AudioManager.play_sfx("menu_move")

func _card_key(k: Key, _shift: bool) -> bool:
	var items := _card_items()
	match k:
		KEY_UP:
			sel = posmod(sel - 1, items.size())
		KEY_DOWN, KEY_TAB:
			sel = posmod(sel + 1, items.size())
		KEY_LEFT:
			open_card(posmod(field - 1, FarmEconomy.FIELDS))
		KEY_RIGHT:
			open_card(posmod(field + 1, FarmEconomy.FIELDS))
		KEY_ENTER, KEY_KP_ENTER:
			if sel >= 0 and sel < items.size():
				activate(str(items[sel]))
		KEY_SPACE:
			pass
		_:
			var idx := int(k) - KEY_1
			if idx >= 0 and idx < FarmEconomy.FIELDS:
				open_card(idx)
			else:
				return false
	return true

func click(pos: Vector2) -> bool:
	var h := regions.hit(pos)
	if h.is_empty():
		return RECT.has_point(pos)      # a click on the drawer's background is still ours
	activate(str(h["id"]))
	return true

# Run a region id (buttons, rows, tabs) as if it were clicked.
func activate(id: String):
	if id == "close":
		close()
		AudioManager.play_sfx("menu_back")
	elif id.begins_with("tab:"):
		var t := id.substr(4)
		if t in TABS:
			_set_tab(TABS.find(t))
	elif id == "scroll:up":
		scroll_by(-1)
	elif id == "scroll:down":
		scroll_by(1)
	elif id.begins_with("row:"):
		var rs := rows()
		for k in rs.size():
			if rs[k]["id"] == id.substr(4):
				sel = k
	elif id.begins_with("buy:"):
		_select_id(id.substr(4))
		ctrl.farm_buy(id.substr(4), null)
	elif id.begins_with("pin:"):
		_select_id(id.substr(4))
		ctrl.farm_pin(id.substr(4))
	elif id == "card:prev":
		open_card(posmod(field - 1, FarmEconomy.FIELDS))
	elif id == "card:next":
		open_card(posmod(field + 1, FarmEconomy.FIELDS))
	elif id.begins_with("plan:"):
		_focus(id)
		var crop := id.substr(5)
		var opt := _plan_option(crop)
		if not opt.is_empty() and not bool(opt["unlocked"]):
			ctrl._popup(str(opt["locked_reason"]), WorldHUD.WARN)
		elif str(_farm()["fields"][field]["plan"]) != crop:
			ctrl.farm_set_plan(field, crop)
	elif id == "card:hire":
		_focus(id)
		if _farm()["fields"][field]["hut"]:
			ctrl._popup("%s already has a Spudling" % FarmView.field_name(field), WorldHUD.INK_DIM)
		else:
			ctrl.farm_buy("hut", field)
	elif id == "card:sprinkler":
		_focus(id)
		_sprinkler_action()
	elif id == "card:sprinkler_move":
		_focus(id)
		if ctrl.has_method("begin_arrange") and not _farm()["sprinklers"].is_empty():
			ctrl.begin_arrange(field, "move")
	elif id == "card:tend":
		_focus(id)
		if ctrl.has_method("tend_field"):
			ctrl.tend_field(field)
	elif id == "card:replant":
		_focus(id)
		ctrl.farm_replant(field)
	elif id == "card:deed":
		if field == FarmEconomy.GREENHOUSE:
			ctrl.farm_buy("greenhouse", null)
		else:
			ctrl.farm_buy("deed", field)

func _select_id(row_id: String):
	var rs := rows()
	for k in rs.size():
		if rs[k]["id"] == row_id:
			sel = k

func _focus(id: String):
	var k := _card_items().find(id)
	if k >= 0:
		sel = k

func _plan_option(crop: String) -> Dictionary:
	for o in FarmEconomy.plan_options(_farm(), field, FarmClock.now_ms(), FarmClock.tz_s()):
		if o["crop"] == crop:
			return o
	return {}

# What the sprinkler button does right now (and its label).
func sprinkler_state() -> Dictionary:
	var f := _farm()
	var i := field
	if i == FarmEconomy.GREENHOUSE:
		return {"kind": "none", "label": "", "text": "Under glass: always watered (grow ×%.2f)" % float(FarmEconomy.cfg()["greenhouse"]["grow_mult"])}
	var mine: Array = []
	for s in f["sprinklers"]:
		if i in FarmView.socket_fields(s):
			mine.append(s)
	var text := "Watered by fence %s" % ", ".join(PackedStringArray(mine)) if not mine.is_empty() else "Not watered"
	var can_move: bool = not f["sprinklers"].is_empty()
	if FarmView.sprinklers_in_stock(f) > 0:
		return {"kind": "place", "label": "Place sprinkler", "text": text, "can_move": can_move}
	var cost := FarmView.sprinkler_cost(f)
	var page := FarmView.sprinkler_page(f)
	if cost >= 0:
		if int(f["page"]) < page:
			return {"kind": "locked", "label": "", "text": text + " · sprinklers at Catalog page %d" % page,
					"why": "Sprinklers unlock at Catalog page %d" % page, "can_move": false}
		return {"kind": "buy", "label": "Buy sprinkler · %s" % NumFmt.coins(cost), "text": text, "cost": cost,
				"can_move": can_move}
	if can_move:
		return {"kind": "move", "label": "Move a sprinkler", "text": text, "can_move": false}
	return {"kind": "none", "label": "", "text": text, "can_move": false}

func _sprinkler_action():
	var st := sprinkler_state()
	match str(st["kind"]):
		"place", "buy", "move":
			if ctrl.has_method("begin_arrange"):
				ctrl.begin_arrange(field, str(st["kind"]))
		"locked":
			ctrl._popup(str(st["why"]), WorldHUD.WARN)

# ════════════════════════════════════════════ drawing

func draw(ci: CanvasItem, font: Font):
	regions.begin()
	WorldHUD.panel(ci, RECT, WorldHUD.PANEL_DEEP, Color(0.85, 0.68, 0.3, 0.8), 12)
	var close_r := Rect2(RECT.end.x - 54, RECT.position.y + 4, 46, 46)
	if mode == "card":
		_draw_card(ci, font)
	else:
		_draw_book(ci, font)
	WorldHUD.close_button(ci, close_r)
	regions.add(close_r, "close")

func _draw_book(ci: CanvasItem, font: Font):
	var f := _farm()
	var now := FarmClock.now_ms()
	var x0 := RECT.position.x
	var y0 := RECT.position.y
	WorldHUD.icon_book(ci, Vector2(x0 + 28, y0 + 24), 13.0)
	ci.draw_string(font, Vector2(x0 + 50, y0 + 30), "FARM BOOK", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, WorldHUD.GOLD)
	ci.draw_string(font, Vector2(x0 + 14, y0 + 47), WorldHUD.fit(font, _week_line(f, now), 12, 336),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK_DIM)
	# tabs
	var tw := (RECT.size.x - 16.0 - 5.0 * 3.0) / 6.0
	for k in TABS.size():
		var t: String = TABS[k]
		var r := Rect2(x0 + 8 + k * (tw + 3.0), y0 + 54, tw, 44)
		var on := t == tab
		WorldHUD.panel(ci, r, Color(0.36, 0.25, 0.1, 0.98) if on else Color(0.2, 0.14, 0.08, 0.95),
				WorldHUD.GOLD if on else Color(0.85, 0.68, 0.3, 0.35), 7)
		var lbl: String = TAB_LABELS[t]
		var w := WorldHUD.text_w(font, lbl, 14)
		ci.draw_string(font, Vector2(r.get_center().x - w / 2, r.position.y + 20), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				WorldHUD.GOLD if on else WorldHUD.INK_DIM)
		ci.draw_string(font, Vector2(r.get_center().x - 3, r.position.y + 37), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				WorldHUD.INK_MUTED)
		regions.add(r, "tab:" + t)
	ci.draw_string(font, Vector2(x0 + 16, y0 + 124), TAB_TITLES[tab], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, WorldHUD.INK)
	match tab:
		"catalog":
			_draw_catalog(ci, font, f)
		"stats":
			_draw_stats(ci, font, f, now)
		_:
			_draw_rows(ci, font, f)

func _week_line(f: Dictionary, now: int) -> String:
	if not FarmView.started(f):
		return "Your last 7 days: no visits yet"
	if not FarmView.history_ready(f, now):
		return "Guessing your week for now: here %d%% · away %s" % [FarmView.here_pct(f, now),
				NumFmt.dur(FarmEconomy.typical_absence_s(f, now))]
	return "Your last 7 days: here %d%% · typical absence %s" % [FarmView.here_pct(f, now),
			NumFmt.dur(FarmEconomy.typical_absence_s(f, now))]

func _draw_rows(ci: CanvasItem, font: Font, f: Dictionary):
	var rs := rows()
	_keep_visible(rs.size())
	var x0 := RECT.position.x + 15
	if rs.is_empty():
		var msg := "Everything here is bought. Nice farm!"
		ci.draw_string(font, Vector2(x0 + 4, LIST_TOP + 30), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, WorldHUD.INK_DIM)
		return
	# scroll arrows on the section header line
	if rs.size() > VISIBLE_ROWS:
		var up := Rect2(RECT.end.x - 104, RECT.position.y + 100, 44, 44)
		var dn := Rect2(RECT.end.x - 54, RECT.position.y + 100, 44, 44)
		WorldHUD.panel(ci, up, Color(0.22, 0.15, 0.08, 0.95) if scroll > 0 else Color(0.15, 0.12, 0.1, 0.8), Color(0.85, 0.68, 0.3, 0.4), 7)
		WorldHUD.panel(ci, dn, Color(0.22, 0.15, 0.08, 0.95) if scroll < rs.size() - VISIBLE_ROWS else Color(0.15, 0.12, 0.1, 0.8), Color(0.85, 0.68, 0.3, 0.4), 7)
		WorldHUD.icon_tri(ci, up.get_center(), 9.0, Vector2.UP, WorldHUD.INK if scroll > 0 else WorldHUD.INK_MUTED)
		WorldHUD.icon_tri(ci, dn.get_center(), 9.0, Vector2.DOWN, WorldHUD.INK if scroll < rs.size() - VISIBLE_ROWS else WorldHUD.INK_MUTED)
		regions.add(up, "scroll:up")
		regions.add(dn, "scroll:down")
		var more := "%d-%d of %d" % [scroll + 1, mini(rs.size(), scroll + VISIBLE_ROWS), rs.size()]
		ci.draw_string(font, Vector2(RECT.end.x - 104 - WorldHUD.text_w(font, more, 12) - 8, RECT.position.y + 126), more,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK_MUTED)
	for k in range(scroll, mini(rs.size(), scroll + VISIBLE_ROWS)):
		var y := LIST_TOP + (k - scroll) * ROW_STEP
		_draw_row(ci, font, f, rs[k], Rect2(x0, y, ROW_W, ROW_H), k == sel)

func _draw_row(ci: CanvasItem, font: Font, f: Dictionary, r: Dictionary, rr: Rect2, selected: bool):
	var id: String = r["id"]
	WorldHUD.panel(ci, rr, Color(0.3, 0.21, 0.1, 0.97) if selected else Color(0.19, 0.13, 0.07, 0.95),
			WorldHUD.GOLD if selected else Color(0.85, 0.68, 0.3, 0.3), 8)
	regions.add(rr, "row:" + id)
	var tx := rr.position.x + 10
	var tw := ROW_W - 10.0 - 118.0
	var name_col := WorldHUD.INK if not r["locked"] else WorldHUD.INK_DIM
	if r["pinned"]:
		WorldHUD.icon_pin(ci, Vector2(tx + 6, rr.position.y + 14), 8.0, true)
		tx += 16
		tw -= 16
	ci.draw_string(font, Vector2(tx, rr.position.y + 20), WorldHUD.fit(font, str(r["name"]), 15, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_col)
	tx = rr.position.x + 10
	tw = ROW_W - 10.0 - 118.0
	ci.draw_string(font, Vector2(tx, rr.position.y + 37), WorldHUD.fit(font, str(r["effect"]), 12, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK_DIM)
	var lines := row_detail(f, r)
	if r["locked"]:
		# a lock reason gets both detail lines ("Catalog page 3: ship 480 Red · 312/480")
		ci.draw_multiline_string(font, Vector2(tx, rr.position.y + 53), lines[0], HORIZONTAL_ALIGNMENT_LEFT, tw, 12, 2, lines[2])
	else:
		ci.draw_string(font, Vector2(tx, rr.position.y + 53), WorldHUD.fit(font, lines[0], 12, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lines[2])
	if lines[1] != "" and not r["locked"]:
		ci.draw_string(font, Vector2(tx, rr.position.y + 68), WorldHUD.fit(font, lines[1], 12, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lines[3])
	# [Buy] shows the price; [Pin] a push-pin (filled when pinned)
	var buy := Rect2(rr.end.x - 112, rr.position.y + 16, 62, 44)
	var can: bool = r["can_buy"]
	WorldHUD.panel(ci, buy, Color(0.5, 0.36, 0.1, 0.98) if can else Color(0.2, 0.16, 0.12, 0.92),
			WorldHUD.GOLD if can else Color(0.85, 0.68, 0.3, 0.3), 7)
	ci.draw_string(font, Vector2(buy.get_center().x - WorldHUD.text_w(font, "BUY", 11) / 2, buy.position.y + 16), "BUY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK if can else WorldHUD.INK_MUTED)
	var cost := NumFmt.coins(int(r["cost"]))
	var cs := 15 if WorldHUD.text_w(font, cost, 15) < 56 else 12
	ci.draw_string(font, Vector2(buy.get_center().x - WorldHUD.text_w(font, cost, cs) / 2, buy.position.y + 36), cost,
			HORIZONTAL_ALIGNMENT_LEFT, -1, cs, WorldHUD.GOLD if can else WorldHUD.INK_MUTED)
	regions.add(buy, "buy:" + id)
	var pin := Rect2(rr.end.x - 46, rr.position.y + 16, 40, 44)
	WorldHUD.panel(ci, pin, Color(0.22, 0.15, 0.08, 0.95), Color(0.85, 0.68, 0.3, 0.4), 7)
	WorldHUD.icon_pin(ci, pin.get_center() + Vector2(0, 2), 10.0, r["pinned"])
	regions.add(pin, "pin:" + id)

# The two detail lines of a row: [line1, line2, colour1, colour2]. Rate
# lines read "+38/min here · +12/min away" then "≈ 3h 10m payback for you";
# rows that change no income get a plain description (lead ruling 2).
func row_detail(f: Dictionary, r: Dictionary) -> Array:
	var green := Color(0.62, 0.9, 0.5)
	if r["locked"]:
		return [str(r["locked_reason"]), "", Color(1.0, 0.66, 0.4), green]
	var item: String = r["item"]
	var dh: float = float(r["d_here"]) * 60.0
	var da: float = float(r["d_away"]) * 60.0
	var pb: float = float(r["payback_s"])
	if item == "tool" and bool(_next_tool(f).get("tend_all", false)):
		return ["Tend All: one press tends every field", "T or the Tend All button", WorldHUD.INK, WorldHUD.INK_DIM]
	if item in ["share", "quick", "house"] and int(f["up"]["huts"]) == 0:
		return ["Helps once you hire a Spudling", "Spudlings work only while you're away", WorldHUD.INK, WorldHUD.INK_DIM]
	if item == "strain" and absf(dh) < 1e-6 and absf(da) < 1e-6:
		return ["No %s harvests lately" % FarmView.crop_name(str(r["arg"])), "Its value shows once you grow it", WorldHUD.INK, WorldHUD.INK_DIM]
	var gains := "%s here · %s away" % [NumFmt.rate(dh), NumFmt.rate(da)]
	if pb < 0.0:
		return [gains, "no gain for your schedule", green, WorldHUD.INK_MUTED]
	return [gains, "≈ %s payback for you" % NumFmt.dur(pb), green, WorldHUD.GOLD]

func _next_tool(f: Dictionary) -> Dictionary:
	var tools: Array = FarmEconomy.cfg()["tools"]
	var nx := int(f["up"]["tool"]) + 1
	return tools[nx] if nx < tools.size() else {}

func _draw_catalog(ci: CanvasItem, font: Font, f: Dictionary):
	var x0 := RECT.position.x + 15
	var y := RECT.position.y + 140.0
	var pages := FarmEconomy.catalog_view(f)
	var step := minf(78.0, (RECT.end.y - 12.0 - y) / maxf(1.0, pages.size()))
	for pg in pages:
		var r := Rect2(x0, y, ROW_W, step - 6.0)
		var done: bool = pg["done"]
		var cur: bool = pg["current"]
		WorldHUD.panel(ci, r, Color(0.24, 0.17, 0.08, 0.96) if cur else Color(0.17, 0.12, 0.07, 0.93),
				WorldHUD.GOLD if cur else Color(0.85, 0.68, 0.3, 0.3), 8)
		var crop: String = pg["crop"]
		var col := FarmView.crop_color(crop) if (done or cur) else Color(0.32, 0.3, 0.28)
		WorldHUD.icon_potato(ci, Vector2(r.position.x + 24, r.position.y + 24), 13.0, col)
		var title := "Page %d · %s" % [int(pg["page"]), FarmView.crop_name(crop) if (done or cur) else "???"]
		ci.draw_string(font, Vector2(r.position.x + 46, r.position.y + 21), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				WorldHUD.INK if (done or cur) else WorldHUD.INK_MUTED)
		if done:
			WorldHUD.icon_check(ci, Vector2(r.end.x - 22, r.position.y + 17), 7.0)
			ci.draw_string(font, Vector2(r.position.x + 46, r.position.y + 40), WorldHUD.fit(font, "\"%s\"" % pg["text"], 12, ROW_W - 60),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.8, 0.62))
			var also := _also_text(pg["also"])
			if also != "" and step > 62:
				ci.draw_string(font, Vector2(r.position.x + 46, r.position.y + 56), WorldHUD.fit(font, also, 11, ROW_W - 60),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK_MUTED)
		elif cur:
			var by := r.position.y + 30.0
			for nd in pg["needs"]:
				var have := int(nd["have"])
				var need := int(nd["need"])
				WorldHUD.progress_bar(ci, Rect2(r.position.x + 46, by, 150, 10), float(have) / maxf(1.0, need))
				ci.draw_string(font, Vector2(r.position.x + 204, by + 10), WorldHUD.fit(font, "%s / %s %s" % [NumFmt.coins(mini(have, need)),
						NumFmt.coins(need), nd["name"]], 12, ROW_W - 214), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK)
				by += 15.0
			var also2 := _also_text(pg["also"])
			if also2 != "" and by + 12 < r.end.y:
				ci.draw_string(font, Vector2(r.position.x + 46, by + 10), WorldHUD.fit(font, also2, 11, ROW_W - 60),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK_MUTED)
		else:
			WorldHUD.icon_lock(ci, Vector2(r.end.x - 22, r.position.y + 20), 8.0)
			ci.draw_string(font, Vector2(r.position.x + 46, r.position.y + 40), "Ship crops to turn the page",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK_MUTED)
		y += step

func _also_text(also: Array) -> String:
	var parts: PackedStringArray = []
	for a in also:
		match str(a):
			"sprinklers": parts.append("Sprinklers")
			"quick": parts.append("Quick Hands")
			"iron": parts.append("Iron Hoe")
			"strains": parts.append("Prize Strains")
			"greenhouse": parts.append("Greenhouse deed")
			"gold": parts.append("Gold Hoe")
			_: parts.append(str(a).capitalize())
	return ("Also unlocks: " + ", ".join(parts)) if not parts.is_empty() else ""

func _draw_stats(ci: CanvasItem, font: Font, f: Dictionary, now: int):
	var x := RECT.position.x + 18
	var y := RECT.position.y + 150.0
	var st: Dictionary = f["stats"]
	var shipped := 0
	for c in f["shipped"]:
		shipped += int(f["shipped"][c])
	var hand := int(st.get("hand_coins", 0))
	var spud := int(st.get("spud_coins", 0))
	var penny := int(st.get("penny_coins", 0))
	var tot := maxi(1, hand + spud + penny)
	var lines := [
		["Lifetime coins", NumFmt.coins(int(st.get("lifetime_coins", 0)))],
		["Plots shipped", NumFmt.coins(shipped)],
		["By hand", "%s c (%d%%)" % [NumFmt.coins(hand), int(round(100.0 * hand / tot))]],
		["By Spudlings", "%s c (%d%%)" % [NumFmt.coins(spud), int(round(100.0 * spud / tot))]],
		["Lucky Pennies", "%s c" % NumFmt.coins(penny)],
		["Butterflies · stars", "%d · %s" % [int(st.get("butterflies", 0)), NumFmt.coins(int(st.get("stars", 0)))]],
		["Farmhouse", "%s · %s shifts" % [FarmView.house_name(FarmView.house_tier(f)), NumFmt.dur(FarmView.shift_s(f))]],
		["Soil · hoe", "L%d · %s" % [int(f["up"]["soil"]), ctrl._tool_name(int(f["up"]["tool"]))]],
		["Here (7 days)", "%d%% · typical absence %s" % [FarmView.here_pct(f, now), NumFmt.dur(FarmEconomy.typical_absence_s(f, now))]],
	]
	for ln in lines:
		ci.draw_string(font, Vector2(x, y), str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WorldHUD.INK_DIM)
		ci.draw_string(font, Vector2(x + 150, y), WorldHUD.fit(font, str(ln[1]), 14, 220), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WorldHUD.INK)
		y += 24.0
	y += 6.0
	ci.draw_string(font, Vector2(x, y), "Ribbons", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WorldHUD.INK_DIM)
	var rib := FarmView.ribbons(f)
	if rib.is_empty():
		ci.draw_string(font, Vector2(x + 150, y), "none yet (Prize Strains)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WorldHUD.INK_MUTED)
		y += 26.0
	else:
		var rx := x + 150.0
		for rb in rib:
			for t in int(rb["tier"]):
				_ribbon(ci, Vector2(rx, y - 6), FarmView.ribbon_color(t + 1))
				rx += 13.0
			WorldHUD.icon_potato(ci, Vector2(rx + 4, y - 5), 6.0, FarmView.crop_color(str(rb["crop"])))
			rx += 20.0
			if rx > RECT.end.x - 30:
				rx = x + 150.0
				y += 22.0
		y += 26.0
	ci.draw_string(font, Vector2(x, y), "Shipped by crop", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WorldHUD.INK_DIM)
	y += 6.0
	var col := 0
	for c in FarmEconomy.crops():
		var n := int(f["shipped"].get(c, 0))
		var cx := x + col * 190.0
		WorldHUD.icon_potato(ci, Vector2(cx + 8, y + 12), 6.5, FarmView.crop_color(c))
		ci.draw_string(font, Vector2(cx + 20, y + 17), WorldHUD.fit(font, "%s %s" % [FarmView.crop_name(c), NumFmt.coins(n)], 13, 168),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WorldHUD.INK if n > 0 else WorldHUD.INK_MUTED)
		col += 1
		if col == 2:
			col = 0
			y += 19.0

static func _ribbon(ci: CanvasItem, c: Vector2, col: Color):
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 2), c + Vector2(-1, 2), c + Vector2(-5, 12)]), col.darkened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(1, 2), c + Vector2(4, 2), c + Vector2(5, 12)]), col.darkened(0.2))
	ci.draw_circle(c, 5.0, col)
	ci.draw_circle(c, 2.0, col.lightened(0.4))

# ── field card ──

func _draw_card(ci: CanvasItem, font: Font):
	var f := _farm()
	var now := FarmClock.now_ms()
	var tzs := FarmClock.tz_s()
	var i := field
	var v := FarmEconomy.field_view(f, i, now)
	var x0 := RECT.position.x
	var y0 := RECT.position.y
	var items := _card_items()
	sel = clampi(sel, 0, items.size() - 1)
	var focus: String = items[sel] if not items.is_empty() else ""
	# header: [<] title / status [>]
	var prev := Rect2(x0 + 6, y0 + 4, 44, 46)
	var next := Rect2(x0 + 302, y0 + 4, 44, 46)
	for pr in [[prev, "card:prev", Vector2.LEFT], [next, "card:next", Vector2.RIGHT]]:
		WorldHUD.panel(ci, pr[0], Color(0.22, 0.15, 0.08, 0.95), Color(0.85, 0.68, 0.3, 0.4), 7)
		WorldHUD.icon_tri(ci, (pr[0] as Rect2).get_center(), 9.0, pr[2])
		regions.add(pr[0], pr[1])
	var title := "%s  ·  key %d" % [v["name"], i + 1]
	ci.draw_string(font, Vector2(x0 + 58, y0 + 24), WorldHUD.fit(font, title, 18, 238), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, WorldHUD.GOLD)
	ci.draw_string(font, Vector2(x0 + 58, y0 + 44), WorldHUD.fit(font, card_status(f, v, tzs), 12, 240),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WorldHUD.INK)
	if not v["owned"]:
		_draw_for_sale(ci, font, f, v, focus)
		return
	# plan picker: 7 rows of 380x44
	var y := y0 + 56.0
	ci.draw_string(font, Vector2(x0 + 16, y + 12), "PLAN · what Tend plants next", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK_MUTED)
	y += 16.0
	var plan: String = v["plan"]
	for o in FarmEconomy.plan_options(f, i, now, tzs):
		var r := Rect2(x0 + 15, y, ROW_W, 44)
		var id := "plan:" + str(o["crop"])
		var is_plan: bool = o["crop"] == plan
		var foc := id == focus
		var bg := Color(0.32, 0.24, 0.1, 0.97) if is_plan else Color(0.18, 0.12, 0.07, 0.93)
		WorldHUD.panel(ci, r, bg, WorldHUD.GOLD if (foc or is_plan) else Color(0.85, 0.68, 0.3, 0.25), 8)
		if foc:
			ci.draw_rect(r.grow(2), Color(1.0, 0.9, 0.5, 0.7), false, 2.0)
		regions.add(r, id)
		var unlocked: bool = o["unlocked"]
		WorldHUD.icon_potato(ci, Vector2(r.position.x + 20, r.get_center().y), 11.0,
				Color(str(o["color"])) if unlocked else Color(0.3, 0.28, 0.26))
		var name_x := r.position.x + 40
		if is_plan:
			WorldHUD.icon_check(ci, Vector2(r.position.x + 20, r.get_center().y), 6.0, Color(1, 1, 1, 0.9), 2.5)
		ci.draw_string(font, Vector2(name_x, r.position.y + 19), str(o["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				WorldHUD.INK if unlocked else WorldHUD.INK_MUTED)
		var sub := ""
		if unlocked:
			sub = "%s grow · seed %s" % [NumFmt.dur(int(o["grow_ms"]) / 1000.0), "free" if int(o["seed_cost"]) == 0 else NumFmt.coins(int(o["seed_cost"]))]
		else:
			sub = "Catalog page %d" % int(o["page"])
		ci.draw_string(font, Vector2(name_x, r.position.y + 36), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK_DIM)
		if unlocked:
			var right := "ready at %s · +%s net" % [NumFmt.clock(int(o["ready_at_ms"]), tzs), NumFmt.coins(int(o["net"]))]
			var rw := WorldHUD.text_w(font, right, 13)
			ci.draw_string(font, Vector2(r.end.x - rw - 10, r.position.y + 27), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(0.95, 0.88, 0.6))
			if o["fav"]:
				WorldHUD.icon_star(ci, Vector2(r.end.x - rw - 24, r.position.y + 22), 8.0)
		else:
			WorldHUD.icon_lock(ci, Vector2(r.end.x - 20, r.get_center().y), 8.0)
		y += PLAN_STEP
	# Spudling line
	y += 2.0
	var hut_r := Rect2(x0 + 15, y, ROW_W, 44)
	if v["hut"]:
		WorldHUD.panel(ci, hut_r, Color(0.16, 0.2, 0.1, 0.9), Color(0.6, 0.85, 0.4, 0.4), 8)
		var k := int(f["fields"][i].get("hut_k", 0))
		_spudling_icon(ci, Vector2(hut_r.position.x + 20, hut_r.get_center().y + 2), 11.0, FarmView.hut_hat(k))
		ci.draw_multiline_string(font, Vector2(hut_r.position.x + 40, hut_r.position.y + 17),
				FarmView.hut_line(f, i, now, tzs), HORIZONTAL_ALIGNMENT_LEFT, ROW_W - 48, 12, 2, WorldHUD.INK)
		regions.add(hut_r, "card:hire")
	else:
		var hc := FarmEconomy.cost_of(f, "hut", i)
		var label := "Hire a Spudling · %s" % NumFmt.coins(hc) if hc >= 0 else "Every Spudling is hired"
		var nm := _next_spudling_name(f)
		if hc >= 0 and nm != "":
			label = "Hire %s · %s" % [nm, NumFmt.coins(hc)]
		WorldHUD.text_button(ci, font, hut_r, label, 15, hc >= 0 and SaveDataManager.wallet() >= hc, hc >= 0,
				focus == "card:hire")
		regions.add(hut_r, "card:hire")
	y += 48.0
	# sprinkler line
	var spr := sprinkler_state()
	var sr := Rect2(x0 + 15, y, ROW_W, 44)
	WorldHUD.panel(ci, sr, Color(0.12, 0.16, 0.2, 0.9), Color(0.5, 0.75, 0.95, 0.35), 8)
	if v["watered"]:
		WorldHUD.icon_droplet(ci, Vector2(sr.position.x + 18, sr.get_center().y), 8.0)
	var btn_w := (166.0 if spr["label"] != "" else 0.0) + (72.0 if spr.get("can_move", false) else 0.0)
	var stext := str(spr["text"])
	if btn_w > 200.0:
		stext = stext.replace("Watered by fence ", "Watered by ")
	ci.draw_string(font, Vector2(sr.position.x + 34, sr.position.y + 27), WorldHUD.fit(font, stext, 13,
			ROW_W - 40 - btn_w), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WorldHUD.INK)
	if spr["label"] != "":
		var b := Rect2(sr.end.x - 166, sr.position.y, 166, 44)
		var en: bool = spr["kind"] != "buy" or SaveDataManager.wallet() >= int(spr.get("cost", 0))
		WorldHUD.text_button(ci, font, b, str(spr["label"]), 13, spr["kind"] == "place", en, focus == "card:sprinkler")
		regions.add(b, "card:sprinkler")
	else:
		regions.add(sr, "card:sprinkler")
	if spr.get("can_move", false):
		var mb := Rect2(sr.end.x - btn_w, sr.position.y, 68, 44)
		WorldHUD.text_button(ci, font, mb, "Move", 13, false, true, focus == "card:sprinkler_move")
		regions.add(mb, "card:sprinkler_move")
	y += 48.0
	# Tend now / Replant now
	var growing: bool = not v["empty"] and not v["ripe"]
	var tr := Rect2(x0 + 15, y, 186, 44)
	var rr := Rect2(x0 + 209, y, 186, 44)
	var tend_lbl := "Harvest + replant" if v["ripe"] else ("Plant %s" % FarmView.crop_name(plan) if v["empty"] else "Growing…")
	WorldHUD.text_button(ci, font, tr, tend_lbl, 14, not growing, not growing, focus == "card:tend")
	regions.add(tr, "card:tend")
	var rp_lbl := "Replant now · +%s c" % NumFmt.coins(int(v["refund"])) if growing else "Replant now"
	WorldHUD.text_button(ci, font, rr, rp_lbl, 14, false, growing, focus == "card:replant")
	regions.add(rr, "card:replant")
	var hint := "Click a crop to plan it · Enter picks · arrows move · Esc closes"
	ci.draw_string(font, Vector2(x0 + 16, RECT.end.y - 8), WorldHUD.fit(font, hint, 11, ROW_W), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldHUD.INK_MUTED)

# Status under the card title: "ripe", "ready at 10:52 (in 23m)", "empty".
func card_status(f: Dictionary, v: Dictionary, tzs: int) -> String:
	if not v["owned"]:
		return "for sale" if int(v["cost"]) >= 0 else "not for sale"
	var crop := FarmView.crop_name(str(v["crop"]))
	if v["empty"]:
		return "empty · Tend plants %s" % FarmView.crop_name(str(v["plan"]))
	if v["ripe"]:
		return "%s is ripe" % crop
	return "%s · ready %s (in %s)" % [crop, NumFmt.clock(int(v["ready_at_ms"]), tzs), NumFmt.dur(int(v["left_ms"]) / 1000.0)]

func _next_spudling_name(f: Dictionary) -> String:
	var names: Array = FarmEconomy.cfg()["huts"].get("names", [])
	var k := int(f["up"]["huts"])
	return str(names[k]) if k < names.size() else ""

func _draw_for_sale(ci: CanvasItem, font: Font, f: Dictionary, v: Dictionary, focus: String):
	var x0 := RECT.position.x + 15
	var y := RECT.position.y + 90.0
	var gh: bool = v["greenhouse"]
	var lines: Array = []
	if gh:
		lines = ["The Greenhouse: a 7th field under glass.", "Crops grow ×%.2f here, always watered." % float(FarmEconomy.cfg()["greenhouse"]["grow_mult"]),
				"It can take a Spudling hut too."]
	else:
		lines = ["12 plots, already tilled and fenced.", "A deed's price depends on how many fields", "you own, not which one: pick your layout.",
				"Sprinklers sit on the fences between fields."]
	if gh:
		_glass_icon(ci, Vector2(x0 + 30, y + 26))
	else:
		WorldHUD.icon_hut(ci, Vector2(x0 + 30, y + 30), 22.0, Color(0.6, 0.4, 0.25), Color(0.85, 0.75, 0.55))
	var ly := y + 6.0
	for ln in lines:
		ci.draw_string(font, Vector2(x0 + 66, ly + 12), str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WorldHUD.INK)
		ly += 22.0
	y = ly + 26.0
	var cost := int(v["cost"])
	var why: String = str(v["locked_reason"])
	var br := Rect2(x0, y, ROW_W, 56)
	if cost >= 0:
		var lbl := ("Build the Greenhouse · %s" if gh else "Buy this field · %s") % NumFmt.coins(cost)
		WorldHUD.text_button(ci, font, br, lbl, 18, why == "" and SaveDataManager.wallet() >= cost, why == "", focus == "card:deed")
		regions.add(br, "card:deed")
		y += 66.0
		if why != "":
			WorldHUD.icon_lock(ci, Vector2(x0 + 10, y + 6), 8.0, Color(1.0, 0.66, 0.4))
			ci.draw_multiline_string(font, Vector2(x0 + 26, y + 12), why, HORIZONTAL_ALIGNMENT_LEFT, ROW_W - 30, 14, 2, Color(1.0, 0.66, 0.4))
		elif SaveDataManager.wallet() < cost:
			ci.draw_string(font, Vector2(x0 + 4, y + 12), "Needs %s c more" % NumFmt.coins(cost - SaveDataManager.wallet()),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.66, 0.4))
	else:
		ci.draw_string(font, Vector2(x0 + 4, y + 20), "No more deeds for now.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, WorldHUD.INK_DIM)

func _glass_icon(ci: CanvasItem, c: Vector2):
	ci.draw_rect(Rect2(c.x - 22, c.y - 10, 44, 30), Color(0.7, 0.9, 1.0, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-26, -10), c + Vector2(26, -10), c + Vector2(0, -28)]), Color(0.75, 0.92, 1.0, 0.6))
	ci.draw_rect(Rect2(c.x - 22, c.y - 10, 44, 30), Color(0.9, 0.95, 1.0), false, 2.0)

static func _spudling_icon(ci: CanvasItem, c: Vector2, r: float, hat: Color):
	WorldHUD.icon_potato(ci, c, r, Color(0.82, 0.62, 0.36))
	ci.draw_rect(Rect2(c.x - r * 0.75, c.y - r * 1.05, r * 1.5, r * 0.32), hat)
	ci.draw_circle(c + Vector2(0, -r * 1.05), r * 0.5, hat)
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.1), r * 0.12, Color(0.15, 0.1, 0.05))
	ci.draw_circle(c + Vector2(r * 0.3, -r * 0.1), r * 0.12, Color(0.15, 0.1, 0.05))
