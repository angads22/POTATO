extends Node2D
class_name WorldHUD

# Overworld overlay UI shared by the farm and the town, on a CanvasLayer so it
# ignores the camera and the night tint. This base draws the town's HUD (the
# wallet, the icon buttons, the bottom bar), the interaction prompt, the
# rising popups, the entry banner, the knife-stand overlay and the Farm Book
# drawer; FarmHud extends it with the farm's goal card, field signs and Pip's
# note. Every clickable thing is registered in `regions` (HitRegions) while it
# is drawn, so the controller's click routing asks regions.hit(pos).
#
# The static icon helpers below draw into any CanvasItem (the Farm Book uses
# them too): the default font has no ★ ▸ → ✓ ✕ ● ≡ or emoji, so every icon is
# a polygon, arc or line.
#
# Redraw only on change (design §7.6): the HUD repaints when its cheap
# signature changes (wallet, prompt, popups, drawer state, zoom, camera...),
# when the controller marks it dirty (inputs, actions, settles), at the rate
# its animations need while something animates (popups, banner, wallet roll;
# farm: the butterfly, the Bumper ring, the note's count-up), and otherwise at
# IDLE_HZ so countdown text keeps ticking. `redraws` counts _draw calls (test
# hook). The farm's bouncing RIPE! signs are a child layer moved by its
# transform, so they cost no redraws.

var ctrl  # WorldController
var regions := HitRegions.new()

const INK := Color(0.98, 0.95, 0.85)
const INK_DIM := Color(0.78, 0.73, 0.64)
const INK_MUTED := Color(0.58, 0.53, 0.47)
const GOLD := Color(1.0, 0.84, 0.3)
const GOLD_DK := Color(0.85, 0.68, 0.3)
const PANEL_BG := Color(0.18, 0.12, 0.07, 0.9)
const PANEL_DEEP := Color(0.13, 0.09, 0.05, 0.97)
const GOOD := Color(0.6, 0.92, 0.5)
const WARN := Color(1.0, 0.55, 0.25)       # refusals, short of coins

const BOTTOM_Y := 648.0
const BOTTOM_BTN := Vector2(132, 56)
const IDLE_HZ := 4.0
const POPUP_STEP := 40.0

static var _styles := {}

var redraws := 0
var _dirty := true
var _sig: Array = []
var _since := 0.0

func mark_dirty():
	_dirty = true

func _process(delta):
	if ctrl == null:
		return
	_since += delta
	var hz := anim_hz()
	var sig := signature()
	if _dirty or sig != _sig or hz >= 60.0 or _since >= 1.0 / maxf(IDLE_HZ, hz):
		_dirty = false
		_sig = sig
		_since = 0.0
		queue_redraw()

# Everything (cheap) the HUD's picture depends on besides animation time.
func signature() -> Array:
	var b = ctrl.book
	var cam: Vector2 = ctrl.camera.get_screen_center_position() if ctrl.camera != null else Vector2.ZERO
	return [ctrl.wallet_display(), ctrl.prompt, ctrl.popups.size(), ctrl.open_shop, ctrl.shop_sel,
			b != null and b.open, b.mode if b != null else "", b.tab if b != null else "", b.sel if b != null else 0,
			b.scroll if b != null else 0, b.field if b != null else 0, b.armed_view() if b != null else false,
			snappedf(ctrl.zoom_now, 0.001), cam.round(), AudioManager.sound_enabled, ctrl.overview,
			ctrl.banner_age < ctrl.BANNER_LIFE]

# Redraws per second the current animations need (0 = none, >= 60 = every frame).
func anim_hz() -> float:
	if not ctrl.popups.is_empty() or ctrl.banner_age < ctrl.BANNER_LIFE or ctrl._roll_t < 1.0:
		return 60.0
	return 0.0

func _draw():
	if ctrl == null:
		return
	redraws += 1
	regions.begin()
	var font := ThemeDB.fallback_font
	_draw_hud(font)
	_draw_prompt(font)
	_draw_overlays(font)
	_draw_modal(font)
	_draw_popups(font)
	_draw_banner(font)

# ── town HUD (FarmHud overrides) ──

func _draw_hud(font: Font):
	draw_wallet_panel(self, font, Rect2(10, 8, 280, 56), ctrl.wallet_display(), "")
	_draw_icon_buttons(["sound", "zoom", "book", "menu"])
	_draw_bottom_bar(font, [["book_bar", "B", "Farm Book"], ["zoom_bar", "Z", "Zoom"],
			["sound_bar", "M", "Sound" if AudioManager.sound_enabled else "Muted"], ["menu_bar", "Esc", "Menu"]])

# Top-right row of 56x56 icon buttons, right-aligned at x 1270. Ids in
# `inert` are drawn dimmed and not clickable (the farm's arrange mode).
func _draw_icon_buttons(ids: Array, inert: Array = []):
	var x := 1270.0 - ids.size() * 62.0 + 6.0
	for id in ids:
		var r := Rect2(x, 12, 56, 56)
		icon_button(self, r, id, ctrl)
		if id in inert:
			draw_rect(r, Color(0.08, 0.06, 0.04, 0.6))
		else:
			regions.add(r, "btn:" + str(id))
		x += 62.0

# Bottom bar: [key label] buttons centred on the screen. items: [id, key, label]
# (+ optional enabled flag, + optional inert flag: drawn disabled, not clickable).
func _draw_bottom_bar(font: Font, items: Array):
	var w := items.size() * (BOTTOM_BTN.x + 8.0) - 8.0
	var x := 640.0 - w * 0.5
	for it in items:
		var enabled: bool = it[3] if it.size() > 3 else true
		var inert: bool = it[4] if it.size() > 4 else false
		var r := Rect2(x, BOTTOM_Y, BOTTOM_BTN.x, BOTTOM_BTN.y)
		key_button(self, font, r, str(it[1]), str(it[2]), enabled and not inert)
		if not inert:
			regions.add(r, "btn:" + str(it[0]))
		x += BOTTOM_BTN.x + 8.0

# The prompt bar is also a button: a click does exactly what [E] does (and it
# swallows the click, so it never falls through to the field underneath).
func _draw_prompt(font: Font):
	if ctrl.prompt == "" or ctrl.ui_blocking():
		return
	var text: String = fit(font, ctrl.prompt, 19, 900)
	var ps := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	var r := Rect2(640 - ps.x / 2 - 18, 594, ps.x + 36, 44)
	panel(self, r, PANEL_BG)
	draw_string(font, Vector2(r.position.x + 18, r.position.y + 29), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, INK)
	regions.add(r, "prompt")

func _draw_overlays(font: Font):
	if ctrl.open_shop == "knives":
		_draw_knife_overlay(font)
	if ctrl.book != null and ctrl.book.open:
		ctrl.book.draw(self, font)

# The farm draws Pip's note here.
func _draw_modal(_font: Font):
	pass

# Popups (the main sound-off feedback) stack in fixed POPUP_STEP slots, the
# newest on top, and only fade (no drift), so two never overlap. Where they
# sit: under the goal card normally; left of the open drawer; above the knife
# stand's panel (the town's top bar is free there) while it is open.
func popup_layout() -> Dictionary:
	if ctrl.open_shop != "":
		return {"cx": 660.0, "y0": 40.0, "max_w": 700.0, "n": 2}
	if ctrl.book != null and ctrl.book.open:
		return {"cx": 430.0, "y0": 238.0, "max_w": 800.0, "n": 4}
	return {"cx": 640.0, "y0": 238.0, "max_w": 1100.0, "n": 4}

func _draw_popups(font: Font):
	var lay := popup_layout()
	var cx: float = lay["cx"]
	var stack := 0
	for k in range(ctrl.popups.size() - 1, -1, -1):
		var p: Dictionary = ctrl.popups[k]
		var frac: float = clampf(p.age / ctrl.POPUP_LIFE, 0.0, 1.0)
		var alpha := 1.0 - frac * frac
		var col: Color = p.color
		col.a = alpha
		var size := 24
		var text: String = fit(font, str(p.text), size, lay["max_w"])
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var py: float = lay["y0"] + stack * POPUP_STEP
		stack += 1
		var back := Rect2(cx - ts.x / 2 - 14, py - 26, ts.x + 28, 36)
		draw_rect(back, Color(0.08, 0.05, 0.03, 0.62 * alpha))
		draw_string(font, Vector2(cx + 2 - ts.x / 2, py + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, alpha * 0.6))
		draw_string(font, Vector2(cx - ts.x / 2, py), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		if stack >= int(lay["n"]):
			break

func _draw_banner(font: Font):
	if ctrl.banner_age >= ctrl.BANNER_LIFE:
		return
	var life: float = ctrl.BANNER_LIFE
	var alpha: float = 1.0 if ctrl.banner_age < life - 0.6 else (life - ctrl.banner_age) / 0.6
	var sub: String = ctrl.banner_sub
	var h := 110.0 if sub == "" else 142.0
	var y0 := 290.0
	draw_rect(Rect2(0, y0, 1280, h), Color(0.07, 0.12, 0.04, 0.72 * alpha))
	draw_rect(Rect2(0, y0, 1280, 4), Color(GOLD_DK.r, GOLD_DK.g, GOLD_DK.b, alpha))
	draw_rect(Rect2(0, y0 + h - 4, 1280, 4), Color(GOLD_DK.r, GOLD_DK.g, GOLD_DK.b, alpha))
	var title: String = fit(font, ctrl.banner_text, 52, 1220)
	var bs := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52)
	draw_string(font, Vector2(643 - bs.x / 2, y0 + 73), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0, 0, 0, 0.5 * alpha))
	draw_string(font, Vector2(640 - bs.x / 2, y0 + 70), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1.0, 0.85, 0.3, alpha))
	if sub != "":
		var st: String = fit(font, sub, 22, 1200)
		var ss := font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(font, Vector2(640 - ss.x / 2, y0 + 112), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.92, 0.82, alpha))

# ── knife stand overlay (town) ──

const SHOP_PANEL := Rect2(320, 96, 640, 540)

func _draw_knife_overlay(font: Font):
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.5))
	var pnl := SHOP_PANEL
	panel(self, pnl, PANEL_DEEP)
	draw_string(font, Vector2(pnl.position.x + 28, pnl.position.y + 44), "KNIFE STAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, GOLD)
	var wt := "%s c" % NumFmt.coins(SaveDataManager.wallet())
	var ws := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	icon_coin(self, Vector2(pnl.end.x - 92 - ws.x, pnl.position.y + 37), 9.0)
	draw_string(font, Vector2(pnl.end.x - 78 - ws.x, pnl.position.y + 43), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	var close := Rect2(pnl.end.x - 56, pnl.position.y + 10, 46, 46)
	close_button(self, close)
	regions.add(close, "shop:close")

	var y := pnl.position.y + 70.0
	var i := 0
	var owned_list: Array = SaveDataManager.farm.get("owned_knives", [])
	var equipped: String = SaveDataManager.farm.get("equipped_knife", "butter")
	for k in GameData.knives():
		i += 1
		var row := Rect2(pnl.position.x + 20, y, pnl.size.x - 40, 58)
		var owned: bool = k["id"] in owned_list
		var cost := int(k["cost"])
		var need_xp := int(k.get("unlock_xp", 0))
		var rank_locked: bool = not owned and SaveDataManager.career_xp() < need_xp
		var can := owned or (not rank_locked and SaveDataManager.wallet() >= cost)
		var sel: bool = ctrl.shop_sel == i - 1
		panel(self, row, Color(0.3, 0.22, 0.12, 0.95) if sel else Color(0.2, 0.14, 0.08, 0.9),
				GOLD if sel else Color(0.85, 0.68, 0.3, 0.35))
		regions.add(row, "knife:" + str(k["id"]), k["id"])
		var col := INK if can else INK_MUTED
		var bx := row.position.x + 30
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 9, y + 14), Vector2(bx + 9, y + 14),
				Vector2(bx, y + 42)]), Color(str(k.get("color", "#d0d0d0"))))
		draw_rect(Rect2(bx - 4, y + 6, 8, 9), Color(0.35, 0.22, 0.12))
		draw_string(font, Vector2(row.position.x + 56, y + 26), "%d  %s" % [i, k["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		draw_string(font, Vector2(row.position.x + 56, y + 46), "score ×%.2f" % float(k["damage"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK_DIM)
		var status := ""
		var scol := GOLD
		if k["id"] == equipped:
			status = "EQUIPPED"
			scol = GOOD
		elif owned:
			status = "owned · equip"
		elif rank_locked:
			status = "needs %s Chef XP" % NumFmt.coins(need_xp)
			scol = Color(0.8, 0.6, 0.5)
		else:
			status = "%s c" % NumFmt.coins(cost)
			scol = GOLD if can else INK_MUTED
		var ss := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, Vector2(row.end.x - ss.x - 16, y + 36), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, scol)
		y += 62.0
	var hint := "Click a knife or press 1-%d  ·  arrows + Enter  ·  Esc closes" % GameData.knives().size()
	var hs := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(font, Vector2(640 - hs.x / 2, pnl.end.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK_DIM)

# ════════════════════════════════════════════ static drawing helpers

static func fit(font: Font, text: String, size: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return text
	var s := text
	while s.length() > 1 and font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "…"

static func text_w(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

static func style(bg: Color, border := Color(0.85, 0.68, 0.3, 0.6), radius := 10, bw := 2) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d" % [bg.to_html(), border.to_html(), radius, bw]
	if _styles.has(key):
		return _styles[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	_styles[key] = sb
	return sb

static func panel(ci: CanvasItem, r: Rect2, bg := PANEL_BG, border := Color(0.85, 0.68, 0.3, 0.6), radius := 10):
	style(bg, border, radius).draw(ci.get_canvas_item(), r)

# A labelled button: a key cap on the left (when key != "") and the label.
static func key_button(ci: CanvasItem, font: Font, r: Rect2, key: String, label: String, enabled := true,
		hot := false):
	var bg := Color(0.24, 0.16, 0.09, 0.95) if enabled else Color(0.16, 0.13, 0.11, 0.85)
	if hot:
		bg = Color(0.42, 0.3, 0.1, 0.97)
	panel(ci, r, bg, GOLD if hot else Color(0.85, 0.68, 0.3, 0.7 if enabled else 0.25))
	var col := INK if enabled else INK_MUTED
	var x := r.position.x + 10.0
	if key != "":
		var kw := maxf(26.0, text_w(font, key, 14) + 12.0)
		keycap(ci, font, Rect2(x, r.get_center().y - 13, kw, 26), key, enabled)
		x += kw + 7.0
	var lbl := fit(font, label, 15, r.end.x - x - 6)
	ci.draw_string(font, Vector2(x, r.get_center().y + 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

static func keycap(ci: CanvasItem, font: Font, r: Rect2, key: String, enabled := true):
	panel(ci, r, Color(0.92, 0.86, 0.72) if enabled else Color(0.5, 0.46, 0.4), Color(0.4, 0.3, 0.18), 5)
	var w := text_w(font, key, 14)
	ci.draw_string(font, Vector2(r.get_center().x - w / 2, r.get_center().y + 5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.22, 0.14, 0.06))

# A plain text button (centred label) used by drawers and the note.
static func text_button(ci: CanvasItem, font: Font, r: Rect2, label: String, size := 16, primary := false,
		enabled := true, selected := false):
	var bg := Color(0.24, 0.16, 0.09, 0.95)
	if primary:
		bg = Color(0.55, 0.38, 0.1, 0.98)
	if not enabled:
		bg = Color(0.17, 0.14, 0.12, 0.9)
	var border := GOLD if (selected or primary) else Color(0.85, 0.68, 0.3, 0.55 if enabled else 0.2)
	panel(ci, r, bg, border, 8)
	if selected:
		ci.draw_rect(r.grow(3), Color(1.0, 0.9, 0.5, 0.8), false, 2.0)
	var lbl := fit(font, label, size, r.size.x - 12)
	var w := text_w(font, lbl, size)
	ci.draw_string(font, Vector2(r.get_center().x - w / 2, r.get_center().y + size * 0.36), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK if enabled else INK_MUTED)

static func close_button(ci: CanvasItem, r: Rect2):
	panel(ci, r, Color(0.3, 0.14, 0.1, 0.95), Color(0.85, 0.68, 0.3, 0.6), 8)
	icon_cross(ci, r.get_center(), 9.0, INK)

# One of the top-right icon buttons: sound, zoom, book, menu.
static func icon_button(ci: CanvasItem, r: Rect2, id: String, c):
	panel(ci, r, PANEL_BG)
	var cc := r.get_center()
	match id:
		"sound":
			icon_speaker(ci, cc, 13.0, not AudioManager.sound_enabled, INK)
		"zoom":
			icon_zoom(ci, cc, 14.0, c != null and c.is_overview(), INK)
		"book":
			icon_book(ci, cc, 14.0, INK)
		"menu":
			icon_menu(ci, cc, 13.0, INK)

static func draw_wallet_panel(ci: CanvasItem, font: Font, r: Rect2, wallet: int, sub: String):
	panel(ci, r, PANEL_BG)
	icon_coin(ci, Vector2(r.position.x + 28, r.position.y + 27 if sub != "" else r.get_center().y), 14.0)
	var ty := r.position.y + 37 if sub != "" else r.get_center().y + 9
	ci.draw_string(font, Vector2(r.position.x + 52, ty), NumFmt.coins(wallet), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	if sub != "":
		ci.draw_string(font, Vector2(r.position.x + 12, r.end.y - 9), fit(font, sub, 13, r.size.x - 20),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_DIM)

# ── icons ──

static func icon_coin(ci: CanvasItem, c: Vector2, r: float):
	ci.draw_circle(c, r, Color(0.95, 0.78, 0.25))
	ci.draw_arc(c, r, 0, TAU, 20, Color(0.7, 0.52, 0.1), maxf(1.5, r * 0.18))
	ci.draw_arc(c, r * 0.58, 0, TAU, 16, Color(0.8, 0.62, 0.15), maxf(1.2, r * 0.13))

static func star_points(c: Vector2, r: float, inner := 0.45) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts

static func icon_star(ci: CanvasItem, c: Vector2, r: float, col := Color(1.0, 0.82, 0.2), outline := true):
	var pts := star_points(c, r)
	ci.draw_colored_polygon(pts, col)
	if outline:
		var o := pts.duplicate()
		o.append(pts[0])
		ci.draw_polyline(o, col.darkened(0.45), maxf(1.0, r * 0.14), true)

static func icon_droplet(ci: CanvasItem, c: Vector2, r: float, col := Color(0.45, 0.75, 0.98)):
	ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.75, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.72, r * 0.2), c + Vector2(r * 0.72, r * 0.2),
			c + Vector2(0, -r * 1.1)]), col)
	ci.draw_circle(c + Vector2(-r * 0.25, r * 0.35), r * 0.2, Color(1, 1, 1, 0.6))

static func icon_check(ci: CanvasItem, c: Vector2, s: float, col := GOOD, w := 3.0):
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(-s * 0.3, s * 0.7), c + Vector2(s, -s * 0.75)]),
			col, w, true)

static func icon_cross(ci: CanvasItem, c: Vector2, s: float, col := INK, w := 3.0):
	ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w, true)
	ci.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, w, true)

# A solid triangle pointing along dir (an arrow head).
static func icon_tri(ci: CanvasItem, c: Vector2, s: float, dir: Vector2, col := INK):
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([c + d * s, c - d * s * 0.7 + n * s * 0.85, c - d * s * 0.7 - n * s * 0.85]), col)

static func icon_speaker(ci: CanvasItem, c: Vector2, s: float, muted: bool, col := INK):
	ci.draw_rect(Rect2(c.x - s, c.y - s * 0.38, s * 0.55, s * 0.76), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.38), c + Vector2(s * 0.15, -s),
			c + Vector2(s * 0.15, s), c + Vector2(-s * 0.5, s * 0.38)]), col)
	if muted:
		icon_cross(ci, c + Vector2(s * 0.72, 0), s * 0.32, Color(1.0, 0.5, 0.35), 2.5)
	else:
		ci.draw_arc(c + Vector2(s * 0.2, 0), s * 0.5, -0.9, 0.9, 8, col, 2.0)
		ci.draw_arc(c + Vector2(s * 0.2, 0), s * 0.9, -0.9, 0.9, 10, col, 2.0)

# Four corner brackets; arrows point out when the next press zooms out.
static func icon_zoom(ci: CanvasItem, c: Vector2, s: float, overview: bool, col := INK):
	var k := s * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * s, sy * s)
			ci.draw_line(p, p - Vector2(sx * k, 0), col, 2.5)
			ci.draw_line(p, p - Vector2(0, sy * k), col, 2.5)
	if overview:
		ci.draw_circle(c, s * 0.28, col)          # overview: a dot (press to zoom in)
	else:
		ci.draw_rect(Rect2(c.x - s * 0.42, c.y - s * 0.3, s * 0.84, s * 0.6), col, false, 2.0)

static func icon_book(ci: CanvasItem, c: Vector2, s: float, col := INK):
	var cover := Color(0.62, 0.3, 0.2)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.75), c + Vector2(0, -s * 0.55),
			c + Vector2(0, s * 0.85), c + Vector2(-s, s * 0.65)]), cover)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s * 0.75), c + Vector2(0, -s * 0.55),
			c + Vector2(0, s * 0.85), c + Vector2(s, s * 0.65)]), cover.lightened(0.12))
	for k in 3:
		var y := -s * 0.3 + k * s * 0.32
		ci.draw_line(c + Vector2(-s * 0.78, y), c + Vector2(-s * 0.18, y + s * 0.1), col, 1.5)
		ci.draw_line(c + Vector2(s * 0.18, y + s * 0.1), c + Vector2(s * 0.78, y), col, 1.5)
	ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(0, s * 0.85), col, 2.0)

static func icon_menu(ci: CanvasItem, c: Vector2, s: float, col := INK):
	for k in 3:
		var y := c.y - s * 0.6 + k * s * 0.6
		ci.draw_line(Vector2(c.x - s, y), Vector2(c.x + s, y), col, 3.0)

static func icon_lock(ci: CanvasItem, c: Vector2, s: float, col := INK_DIM):
	ci.draw_rect(Rect2(c.x - s * 0.6, c.y - s * 0.1, s * 1.2, s * 0.9), col)
	ci.draw_arc(c + Vector2(0, -s * 0.1), s * 0.42, PI, TAU, 10, col, maxf(1.5, s * 0.22))

static func icon_pin(ci: CanvasItem, c: Vector2, s: float, filled: bool, col := INK):
	var head := c + Vector2(0, -s * 0.35)
	if filled:
		ci.draw_circle(head, s * 0.5, Color(0.92, 0.3, 0.25))
	else:
		ci.draw_arc(head, s * 0.5, 0, TAU, 14, col, 2.0)
	ci.draw_line(head + Vector2(0, s * 0.5), c + Vector2(0, s), col, 2.0)

static func icon_hut(ci: CanvasItem, c: Vector2, s: float, roof := Color(0.75, 0.3, 0.22), wall := Color(0.82, 0.68, 0.45)):
	ci.draw_rect(Rect2(c.x - s * 0.75, c.y - s * 0.25, s * 1.5, s * 1.0), wall)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.2), c + Vector2(s, -s * 0.2),
			c + Vector2(0, -s * 1.05)]), roof)
	ci.draw_rect(Rect2(c.x - s * 0.22, c.y + s * 0.2, s * 0.44, s * 0.55), Color(0.35, 0.22, 0.12))

static func icon_potato(ci: CanvasItem, c: Vector2, r: float, col: Color):
	ci.draw_set_transform(c, -0.3, Vector2(1.0, 0.78))
	ci.draw_circle(Vector2.ZERO, r, col)
	ci.draw_arc(Vector2.ZERO, r, 0, TAU, 16, col.darkened(0.45), maxf(1.0, r * 0.16))
	ci.draw_circle(Vector2(-r * 0.35, -r * 0.2), r * 0.13, col.darkened(0.3))
	ci.draw_circle(Vector2(r * 0.3, r * 0.25), r * 0.11, col.darkened(0.3))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func icon_moon(ci: CanvasItem, c: Vector2, r: float, bg: Color):
	ci.draw_circle(c, r, Color(0.95, 0.92, 0.7))
	ci.draw_circle(c + Vector2(r * 0.45, -r * 0.3), r * 0.85, bg)

static func icon_wheat(ci: CanvasItem, c: Vector2, s: float, col := Color(0.92, 0.75, 0.3)):
	ci.draw_line(c + Vector2(0, s), c + Vector2(0, -s), col.darkened(0.2), 2.0)
	for k in 3:
		var y := -s * 0.7 + k * s * 0.45
		for sx in [-1.0, 1.0]:
			ci.draw_set_transform(c + Vector2(sx * s * 0.28, y), sx * 0.6, Vector2(1.0, 0.5))
			ci.draw_circle(Vector2.ZERO, s * 0.3, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func icon_butterfly(ci: CanvasItem, c: Vector2, s: float, flap: float, col := Color(1.0, 0.78, 0.25)):
	var w := 0.35 + 0.65 * absf(flap)
	for sx in [-1.0, 1.0]:
		ci.draw_set_transform(c + Vector2(sx * s * 0.5 * w, -s * 0.25), 0.0, Vector2(w, 1.0))
		ci.draw_circle(Vector2.ZERO, s * 0.55, col)
		ci.draw_set_transform(c + Vector2(sx * s * 0.4 * w, s * 0.35), 0.0, Vector2(w, 1.0))
		ci.draw_circle(Vector2.ZERO, s * 0.36, col.darkened(0.15))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(0, s * 0.6), Color(0.25, 0.15, 0.08), maxf(1.5, s * 0.16))
	ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(-s * 0.3, -s * 0.95), Color(0.25, 0.15, 0.08), 1.2)
	ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(s * 0.3, -s * 0.95), Color(0.25, 0.15, 0.08), 1.2)

# "z z" drawn as two little zig-zags (no font glyph needed, scales freely).
static func icon_zz(ci: CanvasItem, c: Vector2, s: float, col := Color(0.85, 0.9, 1.0)):
	for k in 2:
		var o := c + Vector2(k * s * 1.1, -k * s * 0.9)
		var z := s * (1.0 - k * 0.25)
		ci.draw_polyline(PackedVector2Array([o + Vector2(-z * 0.5, -z * 0.5), o + Vector2(z * 0.5, -z * 0.5),
				o + Vector2(-z * 0.5, z * 0.5), o + Vector2(z * 0.5, z * 0.5)]), col, maxf(1.5, z * 0.22))

# A horizontal progress bar with an optional ring of gold at the fill end.
static func progress_bar(ci: CanvasItem, r: Rect2, frac: float, fill := Color(0.55, 0.85, 0.4)):
	ci.draw_rect(r, Color(0.08, 0.06, 0.04, 0.9))
	var f := clampf(frac, 0.0, 1.0)
	if f > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), fill)
	ci.draw_rect(r, Color(0.85, 0.68, 0.3, 0.6), false, 1.5)
