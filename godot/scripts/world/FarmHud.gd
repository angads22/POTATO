extends WorldHUD
class_name FarmHud

# The farm HUD (design §7.2), at 1280x720:
#   top-left   wallet (rolling) + "here ~X/min · away ~Y/min"
#   top-centre Next Goal card (label, progress bar, ETA / check-ins, Q hint;
#              click = buy when affordable) with the Market Favorite chip, an
#              active Bumper countdown chip and, while a butterfly is out, a
#              "Butterfly! click or G" chip with its countdown ring under it
#              (centred left of the drawer while the drawer is open)
#   top-right  drawn icon buttons: sound, zoom, book, menu
#   bottom     [T Tend All] [B Farm Book] [Z Zoom] [M Sound] [Esc Menu]
#   world      screen-space field signs over each field's projected rect
#              (crop + time left, a bouncing RIPE! with a ring, + plant,
#              FOR SALE · price, hut badge, Favorite star, droplet), the
#              butterfly's catch target and its edge arrow (drawn after the
#              drawer and kept clear of it), the sprinkler arrange overlay, and
#              Pip's note (the only modal).
# Region ids (test hooks, all in screen space via regions.rect_of(id)):
#   btn:sound btn:zoom btn:book btn:menu btn:tend_all btn:book_bar btn:zoom_bar
#   btn:sound_bar btn:menu_bar goal prompt sign:<0..6> bf:catch bf:arrow bf:chip
#   socket:<1-2..> arrange:cancel  ·  note_regions: note:collect note:change
# Arrange mode is modal: only sound, zoom, menu, the sockets and Cancel are
# registered (the Book, goal and Tend All are drawn dimmed).

var note_regions := HitRegions.new()

var _rates_at := -100000
var _rate_here := 0.0
var _rate_away := 0.0
var _goal: Dictionary = {}
var _goal_at := -100000

func signature() -> Array:
	var sig := super.signature()
	var a: Dictionary = ctrl.arrange
	sig.append_array([ctrl.note_open, bool(a.get("active", false)), str(a.get("sel", "")), str(a.get("from", "")),
			ctrl.critters != null and ctrl.critters.bf_active, ctrl.pending_collect, ctrl.hud_dirty])
	return sig

func anim_hz() -> float:
	var hz := super.anim_hz()
	if hz >= 60.0:
		return hz
	if ctrl.note_open and ctrl._note_t < 1.4:
		return 60.0                       # the coin line counts up
	if ctrl.critters != null and ctrl.critters.bf_active:
		return 30.0                       # chip ring, edge arrow flap
	var f: Dictionary = SaveDataManager.farm
	if f.has("buffs") and int(f["buffs"].get("bumper_until_ms", 0)) > FarmClock.now_ms():
		hz = 15.0                         # Bumper chip ring
	return hz

func _draw_hud(font: Font):
	var f: Dictionary = SaveDataManager.farm
	var now := FarmClock.now_ms()
	var arranging: bool = ctrl.arrange_active()
	_refresh_cache(f, now)
	_draw_signs(font, f, now)
	_draw_wallet(font, f, now)
	_draw_goal(font, f, now, not arranging)
	if arranging:
		draw_rect(Rect2(320, 8, 640, 64), Color(0.08, 0.06, 0.04, 0.55))     # inert while arranging
	_draw_chips(font, f, now)
	_draw_icon_buttons(["sound", "zoom", "book", "menu"], ["book"] if arranging else [])
	var tend_lbl := "Collect" if ctrl.pending_collect else "Tend All"
	var tend_ok: bool = ctrl.pending_collect or FarmEconomy.has_tend_all(f)
	_draw_bottom_bar(font, [["tend_all", "T", tend_lbl, tend_ok, arranging], ["book_bar", "B", "Farm Book", true, arranging],
			["zoom_bar", "Z", "Zoom"], ["sound_bar", "M", "Sound" if AudioManager.sound_enabled else "Muted"],
			["menu_bar", "Esc", "Menu"]])

func _refresh_cache(f: Dictionary, now: int):
	if not f.has("fields"):
		return
	if absi(now - _rates_at) > 500 or ctrl.hud_dirty:
		_rates_at = now
		_rate_here = FarmEconomy.rate_here(f) * 60.0
		_rate_away = FarmEconomy.rate_away(f, FarmEconomy.typical_absence_s(f, now)) * 60.0
		_goal = FarmEconomy.next_goal(f, now)
		ctrl.hud_dirty = false

# ── wallet + rates ──

func _draw_wallet(font: Font, _f: Dictionary, _now: int):
	var sub := "here ~%s/min · away ~%s/min" % [NumFmt.compact(maxf(0.0, _rate_here)), NumFmt.compact(maxf(0.0, _rate_away))]
	draw_wallet_panel(self, font, Rect2(10, 8, 300, 64), ctrl.wallet_display(), sub)

# ── Next Goal card ──

func goal() -> Dictionary:
	return _goal

func _draw_goal(font: Font, _f: Dictionary, _now: int, clickable := true):
	var r := Rect2(320, 8, 640, 64)
	var g := _goal
	if g.is_empty():
		return
	var can: bool = g.get("can_buy", false)
	panel(self, r, Color(0.24, 0.17, 0.07, 0.94) if can else PANEL_BG, GOLD if can else Color(0.85, 0.68, 0.3, 0.6))
	if clickable:
		regions.add(r, "goal")
	var kind := str(g["kind"])
	var tag := "NEXT"
	match kind:
		"tutorial":
			tag = "GOAL %d/6" % int(g["step"])
		"pinned":
			tag = "PINNED"
		"done":
			tag = "DONE"
	var tag_w := text_w(font, tag, 12) + 14
	panel(self, Rect2(r.position.x + 10, r.position.y + 10, tag_w, 22), Color(0.55, 0.38, 0.1, 0.95), GOLD, 6)
	draw_string(font, Vector2(r.position.x + 17, r.position.y + 26), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	if kind == "pinned":
		icon_pin(self, Vector2(r.position.x + tag_w + 22, r.position.y + 21), 7.0, true)
	var label: String = str(g["label"]) if kind != "done" else "Every page and purchase done: Soil and Strains keep going!"
	var lx := r.position.x + tag_w + (36.0 if kind == "pinned" else 22.0)
	draw_string(font, Vector2(lx, r.position.y + 27), fit(font, label, 17, r.end.x - lx - 60), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	# Q key cap (lit when Q would buy it)
	keycap(self, font, Rect2(r.end.x - 44, r.position.y + 10, 30, 26), "Q", can)
	if can:
		draw_string(font, Vector2(r.end.x - 98, r.position.y + 28), "buy", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	# line 2: progress or the hint
	var y2 := r.position.y + 50
	var target := int(g.get("target", 0))
	var prog := int(g.get("progress", 0))
	var x := r.position.x + 14
	if kind == "tutorial" and target <= 1 and str(g.get("item", "")) == "":
		# a live line beats the static farm.json hint: next_goal gives an eta
		# (Field 1's) only for the harvest step, so say "Russet on Field 1 ·
		# ready in 39s" or "Field 1 is ripe"; the hint shows when there is none
		var hint := str(g.get("hint", ""))
		if int(g.get("eta_s", -1)) >= 0:
			hint = _field1_line(int(g["eta_s"]))
		draw_string(font, Vector2(x, y2 + 4), fit(font, hint, 14, r.size.x - 30), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_DIM)
		return
	var why := str(g.get("locked_reason", ""))
	if why != "" and str(g.get("item", "")) != "":
		# a pinned row that is still locked: show the lock and its own progress
		# text, never a (full) coin bar next to a refusal
		icon_lock(self, Vector2(x + 8, y2), 8.0, Color(1.0, 0.66, 0.4))
		draw_string(font, Vector2(x + 24, y2 + 4), fit(font, why, 14, r.size.x - 50), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1.0, 0.66, 0.4))
		return
	if target > 0:
		progress_bar(self, Rect2(x, y2 - 7, 220, 12), float(prog) / float(target), GOLD if str(g.get("item", "")) != "" else GOOD)
		x += 228
		var cnt := "%s / %s" % [NumFmt.coins(prog), NumFmt.coins(target)]
		draw_string(font, Vector2(x, y2 + 4), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
		x += text_w(font, cnt, 14) + 14
	var eta := _eta_text(g)
	if eta != "":
		draw_string(font, Vector2(x, y2 + 4), fit(font, eta, 14, r.end.x - x - 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_DIM)

# The tutorial harvest step's line: "Russet on Field 1 · ready in 39s", or
# "Field 1 is ripe: click it or press E on it".
func _field1_line(eta_s: int) -> String:
	var nm := FarmView.field_name(0)
	var v: Dictionary = ctrl.views[0] if not ctrl.views.is_empty() else {}
	if eta_s <= 0 or bool(v.get("ripe", false)):
		return "%s is ripe: click it or press E on it" % nm
	var left := int(v.get("left_ms", eta_s * 1000)) / 1000.0
	return "%s on %s · ready in %s" % [FarmView.crop_name(str(v.get("crop", ""))), nm, NumFmt.dur(left)]

func _eta_text(g: Dictionary) -> String:
	if g.get("can_buy", false):
		return "ready to buy: Q or click"
	var why := str(g.get("locked_reason", ""))
	if why != "" and str(g.get("item", "")) != "":
		return why
	var eta := int(g.get("eta_s", -1))
	if eta < 0:
		return str(g.get("hint", ""))
	if eta == 0:
		return ""
	var s := "~%s" % NumFmt.dur(eta)
	var n := int(g.get("checkins", 0))
	if n > 1:
		s += " · ≈ %d check-ins" % n
	return s

# ── chips: Market Favorite (today + tomorrow), active Bumper ──

# The chip row sits under the goal card, centred on it; while the drawer is
# open it is centred in the free span left of the drawer (320..850) so the
# Bumper ring and the butterfly chip (the sound-off twins) stay visible. A
# chip that doesn't fit gets its short text; the Favorite chip goes last.
const CHIP_Y := 78.0

func _draw_chips(font: Font, f: Dictionary, now: int):
	if not f.has("buffs"):
		return
	var tzs := FarmClock.tz_s()
	var today := FarmView.favorite_today(now, tzs)
	var tmrw := FarmView.favorite_tomorrow(now, tzs)
	var fav_short := "%s ×%s today" % [FarmView.crop_name(today), NumFmt.compact(FarmView.fav_mult())]
	var fav_txt := fav_short
	if not today in f["unlocked"]:
		fav_txt = "%s (Catalog page %d) ×%s today" % [FarmView.crop_name(today), int(FarmEconomy.crop_info(today).get("page", 0)),
				NumFmt.compact(FarmView.fav_mult())]
	fav_txt += " · tomorrow %s" % FarmView.crop_name(tmrw)
	var chips: Array = []
	var cr = ctrl.critters
	if cr != null and cr.bf_active:
		chips.append({"kind": "bf", "text": "Butterfly! Click here or press G", "short": "Butterfly! Click or G",
				"frac": float(cr.bf_life01)})
	var bump := int(f["buffs"].get("bumper_until_ms", 0)) - now
	if bump > 0:
		var btxt := "Bumper ×2 · %s" % NumFmt.dur(bump / 1000.0)
		chips.append({"kind": "bumper", "text": btxt, "short": btxt,
				"frac": bump / float(int(FarmEconomy.cfg()["butterflies"].get("bumper_s", 30)) * 1000)})
	chips.append({"kind": "fav", "text": fav_txt, "short": fav_short})
	var span := Rect2(320, 0, 530, 0) if ctrl.book.open else Rect2(320, 0, 640, 0)
	# full texts, then short ones, then drop the Favorite chip
	for attempt in 3:
		var total := 0.0
		for c in chips:
			c["w"] = text_w(font, str(c["text"] if attempt == 0 else c["short"]), 14) + 44
			c["t"] = c["text"] if attempt == 0 else c["short"]
			total += float(c["w"]) + 8
		if total - 8 <= span.size.x or chips.size() <= 1:
			break
		if attempt == 1 and chips[-1]["kind"] == "fav":
			chips.pop_back()
	var total2 := 0.0
	for c in chips:
		total2 += float(c["w"]) + 8
	var x := span.get_center().x - (total2 - 8) / 2.0
	for c in chips:
		var r := Rect2(x, CHIP_Y, float(c["w"]), 30)
		var is_bf: bool = c["kind"] == "bf"
		panel(self, r, Color(0.3, 0.2, 0.06, 0.95) if is_bf else Color(0.16, 0.11, 0.06, 0.88),
				GOLD if is_bf else Color(0.85, 0.68, 0.3, 0.45), 15)
		var ic := Vector2(r.position.x + 18, r.get_center().y)
		match str(c["kind"]):
			"fav":
				icon_star(self, ic, 9.0)
			"bf":
				icon_butterfly(self, ic, 10.0, sin(Time.get_ticks_msec() / 90.0), Color(0.6, 0.85, 1.0) if cr.bf_welcome else Color(1.0, 0.78, 0.25))
				draw_arc(ic, 13.0, -PI / 2, -PI / 2 + TAU * clampf(float(c["frac"]), 0, 1), 20, GOLD, 2.0)
			_:
				icon_butterfly(self, ic, 9.0, sin(Time.get_ticks_msec() / 60.0))
				draw_arc(ic, 13.0, -PI / 2, -PI / 2 + TAU * clampf(float(c["frac"]), 0, 1), 20, GOLD, 2.0)
		draw_string(font, Vector2(r.position.x + 34, r.position.y + 20), str(c["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				GOLD if is_bf else INK)
		if is_bf:
			regions.add(r, "bf:chip")         # a still, 44 px+ target (padded) for trackpads
		x += float(c["w"]) + 8

# ── field signs (screen space over each field's projected rect) ──

func _draw_signs(font: Font, f: Dictionary, _now: int):
	_ripe_specs = []
	if not f.has("fields") or ctrl.views.is_empty() or ctrl.arrange_active():
		_sync_ripe_layer()
		return
	var screen := Rect2(0, 0, 1280, 720)
	var zoom_small: bool = ctrl.zoom_now < 0.7
	var size := 15 if zoom_small else 18
	for i in FarmEconomy.FIELDS:
		var v: Dictionary = ctrl.views[i]
		var fr: Rect2 = ctrl.field_screen_rect(i)
		if not fr.intersects(screen):
			continue
		var main := ""
		var col := INK
		var dot := Color(0, 0, 0, 0)
		var ripe := false
		if not v["owned"]:
			var cost := int(v["cost"])
			main = ("GREENHOUSE · %s" if v["greenhouse"] else "FOR SALE · %s") % (NumFmt.coins(cost) if cost >= 0 else "—")
			col = Color(1.0, 0.9, 0.6)
		elif v["empty"]:
			main = "+ plant %s" % FarmView.crop_name(str(v["plan"]))
			dot = FarmView.crop_color(str(v["plan"]))
			col = Color(0.85, 0.95, 0.75)
		elif v["ripe"]:
			main = "RIPE!"
			ripe = true
			dot = FarmView.crop_color(str(v["crop"]))
			col = Color(1.0, 0.92, 0.45)
		else:
			main = "%s · %s" % [FarmView.crop_name(str(v["crop"])), NumFmt.dur(int(v["left_ms"]) / 1000.0)]
			dot = FarmView.crop_color(str(v["crop"]))
		var badges: Array = []
		if v["owned"] and v["hut"]:
			badges.append("hut")
		if v["owned"] and v["fav"] and not v["empty"]:
			badges.append("fav")
		if v["owned"] and v["watered"]:
			badges.append("drop")
		var locked: bool = not v["owned"] and str(v["locked_reason"]) != ""
		var mw := text_w(font, main, size)
		var name_w := text_w(font, str(v["hut_name"]), 13) if "hut" in badges else 0.0
		var badge_w := 0.0
		for b in badges:
			badge_w += (26.0 + name_w + (18.0 if v["napping"] else 0.0)) if b == "hut" else 22.0
		var lead := 0.0
		if locked:
			lead = 20.0
		elif dot.a > 0:
			lead = 28.0 if ripe else 22.0
		var w := minf(fr.size.x - 8.0, maxf(mw + lead + 24.0, badge_w + 16.0))
		w = maxf(w, 96.0)
		var sy := fr.position.y + 6.0
		# keep signs clear of the goal card and its chips (the Greenhouse in overview)
		if sy < 116.0 and fr.get_center().x > 280.0 and fr.get_center().x < 1000.0:
			sy = maxf(sy, fr.get_center().y - 20.0)
		var sr := Rect2(fr.get_center().x - w / 2, sy, w, 40)
		var full := sr
		if not badges.is_empty():
			full = Rect2(sr.position, Vector2(w, 64))
		if ctrl.book.open and full.intersects(FarmBook.RECT):
			continue
		var bg := Color(0.2, 0.13, 0.06, 0.9)
		if ripe:
			bg = Color(0.4, 0.28, 0.05, 0.94)
		elif not v["owned"]:
			bg = Color(0.32, 0.2, 0.1, 0.9)
		var spec := {"sr": sr, "w": w, "bg": bg, "ripe": ripe, "locked": locked, "dot": dot, "lead": lead, "main": main,
				"size": size, "col": col, "badges": badges, "name_w": name_w, "hut_name": str(v["hut_name"]),
				"napping": bool(v["napping"]), "hut_k": int(f["fields"][i].get("hut_k", 0))}
		if ripe:
			_ripe_specs.append(spec)        # drawn by the bouncing ripe layer
		else:
			draw_sign(self, font, spec)
		if not ctrl.arrange_active():
			# a ripe sign bounces up to RIPE_BOUNCE px: its target covers that too
			regions.add(full.grow_individual(0, RIPE_BOUNCE if ripe else 0.0, 0, 0), "sign:%d" % i, i)
	_sync_ripe_layer()

# One field sign into any canvas item (the HUD itself, or the ripe layer).
static func draw_sign(ci: CanvasItem, font: Font, sp: Dictionary):
	var sr: Rect2 = sp["sr"]
	var size: int = sp["size"]
	var ripe: bool = sp["ripe"]
	var dot: Color = sp["dot"]
	panel(ci, sr, sp["bg"], GOLD if ripe else Color(0.85, 0.68, 0.3, 0.55), 8)
	var tx := sr.position.x + 10
	if sp["locked"]:
		icon_lock(ci, Vector2(tx + 6, sr.get_center().y), 7.0, Color(1.0, 0.8, 0.5))
		tx += 20
	elif dot.a > 0:
		icon_potato(ci, Vector2(tx + 8, sr.get_center().y), 7.5, dot)
		if ripe:
			ci.draw_arc(Vector2(tx + 8, sr.get_center().y), 12.0, 0, TAU, 20, Color(1.0, 0.9, 0.4, 0.9), 2.5)
		tx += float(sp["lead"])
	ci.draw_string(font, Vector2(tx, sr.get_center().y + size * 0.36), fit(font, str(sp["main"]), size, sr.end.x - tx - 6),
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, sp["col"])
	var badges: Array = sp["badges"]
	if badges.is_empty():
		return
	var br := Rect2(sr.position.x + 6, sr.end.y - 2, float(sp["w"]) - 12, 24)
	panel(ci, br, Color(0.14, 0.1, 0.05, 0.88), Color(0.85, 0.68, 0.3, 0.3), 6)
	var bx := br.position.x + 8
	for b in badges:
		match b:
			"hut":
				icon_hut(ci, Vector2(bx + 7, br.get_center().y + 3), 7.0, FarmView.hut_hat(int(sp["hut_k"])))
				ci.draw_string(font, Vector2(bx + 18, br.position.y + 17), str(sp["hut_name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
				bx += 22 + float(sp["name_w"])
				if sp["napping"]:
					icon_zz(ci, Vector2(bx + 4, br.get_center().y + 2), 5.0)
					bx += 18
				bx += 6
			"fav":
				icon_star(ci, Vector2(bx + 7, br.get_center().y), 7.0)
				bx += 20
			"drop":
				icon_droplet(ci, Vector2(bx + 7, br.get_center().y), 6.0)
				bx += 20

# ── the ripe signs' layer ──
# Ripe signs are drawn once (whenever the HUD redraws) into a child layer
# behind the rest of the HUD; their bounce is that layer's position, so a
# bouncing RIPE! costs no HUD redraws (design §7.6).

const RIPE_BOUNCE := 6.0

class SignLayer extends Node2D:
	var specs: Array = []
	var redraws := 0
	func _draw():
		redraws += 1
		var font := ThemeDB.fallback_font
		for sp in specs:
			FarmHud.draw_sign(self, font, sp)

var _ripe_layer: SignLayer
var _ripe_specs: Array = []

func _ready():
	_ripe_layer = SignLayer.new()
	_ripe_layer.show_behind_parent = true
	add_child(_ripe_layer)

func _sync_ripe_layer():
	if _ripe_layer == null:
		return
	if _ripe_layer.specs != _ripe_specs:
		_ripe_layer.specs = _ripe_specs
		_ripe_layer.queue_redraw()
	_ripe_layer.visible = not _ripe_specs.is_empty()

func _process(delta):
	super._process(delta)
	if _ripe_layer != null and _ripe_layer.visible:
		_ripe_layer.position.y = -absf(sin(Time.get_ticks_msec() / 220.0)) * RIPE_BOUNCE

# ── butterfly: catch target on screen, edge arrow off screen ──
# Drawn after the drawer. While the drawer is open its area counts as off
# screen: a butterfly behind it gets the edge arrow, clamped left of the
# drawer, so it is never hidden and never sits over a Buy / Pin button.

const CATCH_R_MIN := 44.0           # catch box half-size floor (88 px at 0.45 zoom)
const ARROW_INNER := Rect2(50, 140, 1180, 450)

func butterfly_inner() -> Rect2:
	if ctrl.book.open:
		return Rect2(ARROW_INNER.position, Vector2(FarmBook.RECT.position.x - 44.0 - ARROW_INNER.position.x, ARROW_INNER.size.y))
	return ARROW_INNER

func _draw_butterfly_target(font: Font):
	var cr = ctrl.critters
	if cr == null or not cr.bf_active:
		return
	var sp: Vector2 = ctrl.world_to_screen(cr.bf_pos)
	var rad := maxf(CATCH_R_MIN, 40.0 * ctrl.zoom_now)
	var box := Rect2(sp - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
	var inner := butterfly_inner()
	var under_drawer: bool = ctrl.book.open and box.intersects(FarmBook.RECT)
	if inner.has_point(sp) and not under_drawer:
		regions.add(box, "bf:catch")
		return
	var c := Vector2(clampf(sp.x, inner.position.x, inner.end.x), clampf(sp.y, inner.position.y, inner.end.y))
	var dir := (sp - c).normalized() if sp.distance_to(c) > 1.0 else Vector2.RIGHT
	var r := Rect2(c - Vector2(30, 30), Vector2(60, 60))
	draw_circle(c, 30.0, Color(0.18, 0.12, 0.06, 0.92))
	draw_arc(c, 30.0, 0, TAU, 28, GOLD, 2.5)
	draw_arc(c, 34.0, -PI / 2, -PI / 2 + TAU * cr.bf_life01, 28, Color(1.0, 0.95, 0.6, 0.9), 3.0)
	icon_butterfly(self, c, 13.0, sin(Time.get_ticks_msec() / 50.0))
	icon_tri(self, c + dir * 40.0, 10.0, dir, GOLD)
	draw_string(font, Vector2(c.x - 9, c.y + 50), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	regions.add(r, "bf:arrow")

# ── overlays: drawer, sprinkler arrange ──

func _draw_overlays(font: Font):
	if ctrl.arrange_active():
		_draw_butterfly_target(font)        # the sockets (registered after) win
		_draw_arrange(font)
		super._draw_overlays(font)
		return
	super._draw_overlays(font)
	_draw_butterfly_target(font)

func _draw_arrange(font: Font):
	var a: Dictionary = ctrl.arrange
	var f: Dictionary = SaveDataManager.farm
	var placed: Array = f["sprinklers"]
	var sel_s := str(a.get("sel", ""))
	var from_s := str(a.get("from", ""))
	# highlight the fields the selected socket would water
	if sel_s != "":
		for fi in FarmView.socket_fields(sel_s):
			draw_rect(ctrl.field_screen_rect(int(fi)).grow(4), Color(0.5, 0.8, 1.0, 0.9), false, 4.0)
	for s in FarmView.sockets():
		var sp: Vector2 = ctrl.world_to_screen(FarmView.socket_pos(s))
		var occupied: bool = s in placed
		var is_sel: bool = s == sel_s
		var r := Rect2(sp - Vector2(26, 26), Vector2(52, 52))
		draw_circle(sp, 26.0, Color(0.1, 0.2, 0.32, 0.85) if occupied else Color(0.15, 0.12, 0.08, 0.75))
		if occupied:
			draw_line(sp + Vector2(0, 10), sp + Vector2(0, -6), Color(0.75, 0.8, 0.86), 4.0)
			draw_circle(sp + Vector2(0, -8), 6.0, Color(0.75, 0.8, 0.86))
			draw_arc(sp + Vector2(0, -6), 14.0, -2.6, -0.5, 10, Color(0.55, 0.85, 1.0), 2.5)
		else:
			draw_line(sp + Vector2(-10, 0), sp + Vector2(10, 0), INK, 3.0)
			draw_line(sp + Vector2(0, -10), sp + Vector2(0, 10), INK, 3.0)
		var ring := Color(0.55, 0.85, 1.0, 0.9)
		if s == from_s:
			ring = Color(1.0, 0.6, 0.3)
		if is_sel:
			ring = GOLD
		draw_arc(sp, 26.0, 0, TAU, 28, ring, 4.0 if (is_sel or s == from_s) else 2.0)
		draw_string(font, Vector2(sp.x - text_w(font, s, 13) / 2, sp.y + 42), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		regions.add(r, "socket:" + s, s)
	# instruction bar + Cancel
	var msg: String = ctrl.arrange_hint()
	var mw := text_w(font, msg, 16)
	var bar := Rect2(640 - (mw + 160) / 2, 116, mw + 160, 48)
	panel(self, bar, Color(0.1, 0.16, 0.24, 0.95), Color(0.55, 0.85, 1.0, 0.8))
	draw_string(font, Vector2(bar.position.x + 16, bar.position.y + 30), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	var cancel := Rect2(bar.end.x - 120, bar.position.y + 2, 114, 44)
	text_button(self, font, cancel, "Cancel (Esc)", 14)
	regions.add(cancel, "arrange:cancel")

# ── Pip's note (modal) ──

func _draw_modal(font: Font):
	note_regions.begin()
	if not ctrl.note_open:
		return
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.45))
	var r := Rect2(340, 140, 600, 400)
	var ink := Color(0.24, 0.15, 0.07)
	panel(self, r.grow(6), Color(0.55, 0.38, 0.2, 0.98), Color(0.35, 0.22, 0.1), 16)
	panel(self, r, Color(0.97, 0.92, 0.78), Color(0.72, 0.56, 0.32), 12)
	# a little torn-paper fringe along the top
	for k in 20:
		draw_circle(Vector2(r.position.x + 15 + k * 30, r.position.y), 6.0, Color(0.97, 0.92, 0.78))
	var n: Dictionary = ctrl.note
	var rep: Dictionary = n.get("report", {})
	var helpers: Array = rep.get("helpers", [])
	var title := "A note from %s" % str(helpers[0]) if not helpers.is_empty() else "While you were away"
	draw_string(font, Vector2(r.position.x + 30, r.position.y + 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var away := int(rep.get("away_ms", 0)) / 1000
	var sub := "you were away %s" % NumFmt.dur(away) if away > 0 else "welcome to Spudling Acres"
	draw_string(font, Vector2(r.position.x + 32, r.position.y + 72), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.45, 0.32, 0.18))
	if not helpers.is_empty():
		FarmBook._spudling_icon(self, Vector2(r.end.x - 52, r.position.y + 50), 20.0, FarmView.hut_hat(0))
	# lines laid out by their real wrapped height (up to 3 rows each); a long
	# note drops to 15 px with tighter gaps so it never runs into the buttons
	var lines: Array = ctrl.note_lines()
	var w := r.size.x - 80
	var avail := (r.end.y - 84.0) - (r.position.y + 96.0)
	var size := 16
	var gap := 12.0
	var heights: Array = []
	for attempt in 2:
		heights.clear()
		var total := 0.0
		for ln in lines:
			var h := font.get_multiline_string_size(str(ln["text"]), HORIZONTAL_ALIGNMENT_LEFT, w, size, NOTE_MAX_ROWS).y
			heights.append(h)
			total += h + gap
		if total - gap <= avail:
			break
		size = 15
		gap = 6.0
	var y := r.position.y + 96.0
	for k in lines.size():
		_note_line(font, Vector2(r.position.x + 30, y), str(lines[k]["icon"]), str(lines[k]["text"]), ink, w, size)
		y += float(heights[k]) + gap
	var collect := Rect2(r.position.x + 70, r.end.y - 74, 200, 56)
	var change := Rect2(r.position.x + 296, r.end.y - 68, 240, 46)
	text_button(self, font, collect, "Collect", 22, true, true, true)
	draw_string(font, Vector2(collect.position.x + 6, collect.end.y + 15), "Enter / Space", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.32, 0.18))
	text_button(self, font, change, "Change plans first", 16)
	draw_string(font, Vector2(change.position.x + 6, change.end.y + 15), "Esc · nothing rots", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.32, 0.18))
	note_regions.add(collect, "note:collect")
	note_regions.add(change, "note:change")

const NOTE_MAX_ROWS := 3

func _note_line(font: Font, p: Vector2, icon: String, text: String, ink: Color, w: float, size := 16):
	var ic := p + Vector2(10, 12)
	match icon:
		"potato":
			icon_potato(self, ic, 10.0, Color(0.78, 0.55, 0.3))
		"moon":
			draw_circle(ic, 10.0, Color(0.85, 0.66, 0.25))
			draw_circle(ic + Vector2(4.5, -3.0), 8.5, Color(0.97, 0.92, 0.78))
		"wheat":
			icon_wheat(self, ic, 11.0)
		"book":
			icon_book(self, ic, 10.0, Color(0.95, 0.9, 0.8))
		"coin":
			icon_coin(self, ic, 10.0)
		"star":
			icon_star(self, ic, 10.0)
	draw_multiline_string(font, Vector2(p.x + 30, p.y + font.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, w, size,
			NOTE_MAX_ROWS, ink)
