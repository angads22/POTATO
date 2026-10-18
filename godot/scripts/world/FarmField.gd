extends Node2D
class_name FarmField

# One field slot (design §5.2): Fields 1-6 and the Greenhouse (index 6). It
# draws the fence, the 4x3 plots from FarmEconomy.field_view (empty soil,
# three growing stages, ripe potatoes with a bob and a "harvest me" ring), the
# Greenhouse glass, the FOR SALE stakes of an unowned slot, the hut with its
# Spudling's name and "z z" when napping, a droplet on watered fields and a
# drawn star on a Favorite-locked crop.
#
# The controller passes a fresh field_view every frame (refresh); the node
# redraws only when its stage bucket changes, or ~30 times a second for the
# ripe bob while it is on screen (design §7.6). StyleBoxFlats are cached.

var index := 0
var rect := Rect2()
var view: Dictionary = {}
var on_screen := true
var redraws := 0           # test hook: how often _draw ran
var t := 0.0
var _bucket := ""
var _bob_acc := 0.0

static var _sb := {}

const PLOT := Vector2(140, 110)

func setup(i: int):
	index = i
	rect = FarmView.field_rect(i)
	position = rect.position

# Stage bucket: everything a redraw depends on except the ripe bob.
func bucket_of(v: Dictionary) -> String:
	return "%s|%s|%d|%s|%s|%s|%s|%s|%d|%s" % [v.get("owned"), v.get("crop"), int(v.get("stage", 0)), v.get("hut"),
			v.get("napping"), v.get("watered"), v.get("fav"), v.get("hut_name"), int(v.get("cost", -1)),
			str(v.get("locked_reason", "")) != ""]

func refresh(v: Dictionary, visible_now: bool):
	view = v
	on_screen = visible_now
	var b := bucket_of(v)
	if b != _bucket:
		_bucket = b
		queue_redraw()

func _process(delta):
	t += delta
	if view.get("ripe", false) and on_screen:
		_bob_acc += delta
		if _bob_acc >= 1.0 / 30.0:
			_bob_acc = 0.0
			queue_redraw()

static func _style(key: String, bg: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	if _sb.has(key):
		return _sb[key]
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	_sb[key] = s
	return s

func _draw():
	redraws += 1
	if view.is_empty():
		return
	var gh: bool = view.get("greenhouse", false)
	if not view["owned"]:
		if gh:
			_draw_greenhouse_lot()
		else:
			_draw_for_sale()
		return
	# tilled base under the plots
	_style("base", Color(0.36, 0.25, 0.14), Color(0.28, 0.19, 0.1), 14, 3).draw(get_canvas_item(),
			Rect2(Vector2(-6, -6), rect.size + Vector2(12, 12)))
	var cols := int(rect.size.x / PLOT.x)
	var rows := int(rect.size.y / PLOT.y)
	var stage := int(view["stage"])
	var crop: String = view["crop"]
	for r in rows:
		for c in cols:
			var pc := Vector2(PLOT.x * (c + 0.5), PLOT.y * (r + 0.5))
			_draw_soil_bed(pc, view["watered"] and stage > 0)
			if stage >= 1 and stage <= 3:
				_draw_growing(pc, stage, c + r * cols)
			elif stage == 4:
				_draw_ready(pc, crop, c + r * cols)
	if gh:
		_draw_glass()
	else:
		_draw_fence()
	if view["ripe"]:
		# the "harvest me" ring around the whole field (shape, not just colour)
		var pulse := 0.5 + 0.5 * sin(t * 3.0)
		draw_rect(Rect2(Vector2(-14, -14), rect.size + Vector2(28, 28)), Color(1.0, 0.88, 0.35, 0.45 + 0.4 * pulse), false, 5.0)
	if view["fav"] and crop != "":
		_flag_star(Vector2(18, -26))
	if view["watered"]:
		WorldHUD.icon_droplet(self, Vector2(rect.size.x - 20, -24), 11.0)
	_draw_hut()

# ── plots (ported from FarmTile) ──

func _draw_soil_bed(pc: Vector2, watered: bool):
	_style("shadow", Color(0, 0, 0, 0.18), Color(0, 0, 0, 0), 16, 0).draw(get_canvas_item(), Rect2(pc + Vector2(-62, -39), Vector2(130, 90)))
	var bg := Color(0.36, 0.24, 0.13) if watered else Color(0.46, 0.32, 0.18)
	_style("wet" if watered else "dry", bg, bg.darkened(0.3), 16, 3).draw(get_canvas_item(), Rect2(pc + Vector2(-65, -45), Vector2(130, 90)))
	for i in range(3):
		var fy = -26 + i * 24
		draw_rect(Rect2(pc + Vector2(-52, fy), Vector2(104, 3)), bg.darkened(0.28))
		draw_rect(Rect2(pc + Vector2(-52, fy - 3), Vector2(104, 2)), bg.lightened(0.16))
	if watered:
		for i in range(3):
			draw_circle(pc + Vector2(-34 + i * 34, 32), 2.5, Color(0.5, 0.75, 0.95, 0.8))

func _draw_growing(pc: Vector2, stage: int, k: int):
	var p := (stage - 0.5) / 3.0
	var sway := sin(k * 1.7) * 2.0
	var h := 12.0 + p * 30.0
	var stem := Color(0.32, 0.55, 0.24)
	draw_circle(pc + Vector2(0, 4), 9.0, Color(0.4, 0.28, 0.15))
	draw_line(pc + Vector2(0, 2), pc + Vector2(sway, 2 - h), stem, 3.0)
	var leaves := stage
	for i in range(leaves):
		var ly := 2 - h * (0.35 + 0.2 * i)
		var side := 1 if i % 2 == 0 else -1
		draw_set_transform(pc + Vector2(sway * 0.7 + side * 8, ly), side * 0.5, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 7.0 + p * 4.0, stem.lightened(0.12 * i))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ready(pc: Vector2, crop: String, k: int):
	var info := FarmEconomy.crop_info(crop)
	var body := Color(str(info.get("color", "#b87333")))
	var bob := sin(t * 3.0 + k * 0.6) * 3.0
	var sway := sin(t * 2.0 + k) * 2.0
	for off in [Vector2(-14, -26), Vector2(14, -24), Vector2(0, -38)]:
		draw_circle(pc + off + Vector2(sway, 0), 16.0, Color(0.28, 0.5, 0.22))
	draw_circle(pc + Vector2(sway - 6, -42), 8.0, Color(0.38, 0.6, 0.3))
	for i in range(3):
		var pp := pc + Vector2(-26.0 + i * 26.0, 14 + 3 * sin(i * 2.0) - absf(bob) * (1.0 if i == 1 else 0.6))
		draw_circle(pp, 11.0, body)
		draw_arc(pp, 11.0, 0, TAU, 16, body.darkened(0.4), 2.0)
	if info.get("rare", false):
		for i in range(3):
			var a := t * 2.0 + i * TAU / 3.0 + k
			draw_circle(pc + Vector2(cos(a) * 34.0, -20 + sin(a) * 22.0), 2.5, Color(1.0, 0.9, 0.4, 0.85))

# ── fence, glass, for-sale lot ──

func _draw_fence():
	var wood := Color(0.62, 0.46, 0.28)
	var wood_dk := Color(0.45, 0.32, 0.18)
	var r := Rect2(Vector2(-16, -16), rect.size + Vector2(32, 32))
	var gate_a := r.get_center().x - 40.0
	var gate_b := r.get_center().x + 40.0
	# rails (a gap in the top rail is the gate)
	for off in [6.0, 18.0]:
		draw_line(Vector2(r.position.x, r.position.y + off), Vector2(gate_a, r.position.y + off), wood_dk, 3.0)
		draw_line(Vector2(gate_b, r.position.y + off), Vector2(r.end.x, r.position.y + off), wood_dk, 3.0)
		draw_line(Vector2(r.position.x, r.end.y - 24 + off), Vector2(r.end.x, r.end.y - 24 + off), wood_dk, 3.0)
		draw_line(Vector2(r.position.x + off - 12, r.position.y), Vector2(r.position.x + off - 12, r.end.y), wood_dk, 3.0)
		draw_line(Vector2(r.end.x - off + 12, r.position.y), Vector2(r.end.x - off + 12, r.end.y), wood_dk, 3.0)
	var x := r.position.x
	while x <= r.end.x + 0.5:
		if x < gate_a - 4 or x > gate_b + 4 or absf(x - gate_a) < 6 or absf(x - gate_b) < 6:
			_post(Vector2(x, r.position.y), wood)
		_post(Vector2(x, r.end.y - 18), wood)
		x += 70.0
	var y := r.position.y + 70.0
	while y < r.end.y - 30:
		_post(Vector2(r.position.x, y), wood)
		_post(Vector2(r.end.x, y), wood)
		y += 70.0
	_post(Vector2(gate_a, r.position.y), wood.lightened(0.1))
	_post(Vector2(gate_b, r.position.y), wood.lightened(0.1))

func _post(p: Vector2, col: Color):
	draw_rect(Rect2(p.x - 4, p.y - 8, 8, 30), col)
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 4, p.y - 8), Vector2(p.x + 4, p.y - 8), Vector2(p.x, p.y - 14)]), col.lightened(0.15))

func _draw_glass():
	var r := Rect2(Vector2(-14, -14), rect.size + Vector2(28, 28))
	draw_rect(r, Color(0.75, 0.92, 1.0, 0.13))
	var frame := Color(0.92, 0.96, 1.0, 0.9)
	draw_rect(r, frame, false, 5.0)
	var x := r.position.x + 70.0
	while x < r.end.x - 10:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.92, 0.96, 1.0, 0.45), 2.0)
		x += 70.0
	draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(0.92, 0.96, 1.0, 0.35), 2.0)
	# roof ridge with glints
	draw_rect(Rect2(r.position.x - 6, r.position.y - 18, r.size.x + 12, 14), Color(0.85, 0.92, 0.98))
	for k in 6:
		var gx := r.position.x + 40 + k * 90.0 + fposmod(t * 30.0, 90.0) * 0.0
		draw_line(Vector2(gx, r.position.y + 10), Vector2(gx + 30, r.position.y + 40), Color(1, 1, 1, 0.35), 3.0)

func _draw_for_sale():
	var r := Rect2(Vector2.ZERO, rect.size)
	draw_rect(r, Color(0.36, 0.55, 0.26, 0.35))
	var stake := Color(0.55, 0.4, 0.24)
	var rope := Color(0.85, 0.78, 0.6, 0.85)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := int(a.distance_to(b) / 24.0)
		for s in n:
			if s % 2 == 0:
				draw_line(a.lerp(b, float(s) / n), a.lerp(b, float(s + 1) / n), rope, 3.0)
	for c in corners:
		draw_rect(Rect2(c.x - 5, c.y - 26, 10, 32), stake)
		draw_rect(Rect2(c.x - 5, c.y - 26, 10, 6), Color(0.95, 0.4, 0.3))
	# wild weeds
	for k in 9:
		var p := Vector2(60 + (k * 137) % 460, 50 + (k * 89) % 240)
		for s in 3:
			draw_line(p, p + Vector2(-6 + s * 6, -14 + absf(s - 1) * 4), Color(0.3, 0.48, 0.2), 3.0)
	# an empty sign board on a post in the middle (the HUD sign carries the text)
	var sc := r.get_center()
	draw_rect(Rect2(sc.x - 5, sc.y - 10, 10, 60), stake)
	draw_rect(Rect2(sc.x - 70, sc.y - 52, 140, 52), Color(0.78, 0.66, 0.44))
	draw_rect(Rect2(sc.x - 70, sc.y - 52, 140, 52), Color(0.5, 0.36, 0.2), false, 4.0)
	WorldHUD.icon_coin(self, Vector2(sc.x, sc.y - 26), 13.0)

func _draw_greenhouse_lot():
	var r := Rect2(Vector2.ZERO, rect.size)
	var dash := Color(0.92, 0.95, 1.0, 0.5)
	var n := int(r.size.x / 30.0)
	for s in n:
		if s % 2 == 0:
			var xa := r.position.x + s * 30.0
			draw_line(Vector2(xa, 0), Vector2(xa + 30, 0), dash, 3.0)
			draw_line(Vector2(xa, r.end.y), Vector2(xa + 30, r.end.y), dash, 3.0)
	var m := int(r.size.y / 30.0)
	for s in m:
		if s % 2 == 0:
			draw_line(Vector2(0, s * 30.0), Vector2(0, s * 30.0 + 30), dash, 3.0)
			draw_line(Vector2(r.end.x, s * 30.0), Vector2(r.end.x, s * 30.0 + 30), dash, 3.0)
	draw_rect(r.grow(-30), Color(0.6, 0.6, 0.6, 0.18))
	for k in 4:
		draw_rect(Rect2(40 + k * 150, r.end.y - 34, 60, 18), Color(0.62, 0.6, 0.56))

# ── hut + Spudling badges ──

func _draw_hut():
	var hp := FarmView.hut_pos(index) - position
	if not view["hut"]:
		# an empty hut spot: a trodden dirt patch with a little stake
		draw_set_transform(hp + Vector2(0, 26), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 40.0, Color(0.5, 0.4, 0.25, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(hp.x - 3, hp.y - 4, 6, 30), Color(0.55, 0.4, 0.24))
		return
	var k := int(SaveDataManager.farm["fields"][index].get("hut_k", 0)) if SaveDataManager.farm.has("fields") else 0
	var hat := FarmView.hut_hat(k)
	draw_set_transform(hp + Vector2(4, 34), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 46.0, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(hp.x - 36, hp.y - 12, 72, 46), Color(0.78, 0.62, 0.4))
	for y in range(int(hp.y - 4), int(hp.y + 34), 10):
		draw_line(Vector2(hp.x - 36, y), Vector2(hp.x + 36, y), Color(0.66, 0.5, 0.3), 2.0)
	draw_colored_polygon(PackedVector2Array([hp + Vector2(-46, -10), hp + Vector2(46, -10), hp + Vector2(0, -52)]), hat)
	draw_line(hp + Vector2(-46, -10), hp + Vector2(0, -52), hat.darkened(0.3), 3.0)
	draw_line(hp + Vector2(46, -10), hp + Vector2(0, -52), hat.darkened(0.3), 3.0)
	# round-topped door
	draw_rect(Rect2(hp.x - 11, hp.y + 8, 22, 26), Color(0.35, 0.22, 0.12))
	draw_circle(hp + Vector2(0, 8), 11.0, Color(0.35, 0.22, 0.12))
	# name plate
	var font := ThemeDB.fallback_font
	var nm := str(view["hut_name"])
	var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_style("plate", Color(0.22, 0.15, 0.08, 0.95), Color(0.85, 0.68, 0.3, 0.7), 6, 2).draw(get_canvas_item(),
			Rect2(hp.x - w / 2 - 8, hp.y + 38, w + 16, 26))
	draw_string(font, Vector2(hp.x - w / 2, hp.y + 57), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.98, 0.92, 0.75))
	if view["napping"]:
		WorldHUD.icon_zz(self, hp + Vector2(26, -58), 12.0)

func _flag_star(p: Vector2):
	draw_line(p + Vector2(0, 24), p + Vector2(0, -14), Color(0.5, 0.36, 0.2), 3.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -14), p + Vector2(34, -4), p + Vector2(0, 8)]), Color(0.95, 0.94, 0.88))
	WorldHUD.icon_star(self, p + Vector2(12, -3), 7.0)
