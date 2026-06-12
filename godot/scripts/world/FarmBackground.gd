extends Node2D
class_name FarmBackground

# The open-world farm backdrop: striped pasture, dirt paths, farmhouse,
# championship kitchen, market/seed/knife stands, a well, a pond and a
# tree line — all procedural, like the rest of the game. Geometry constants
# here are the single source of truth; FarmController reads them for
# collision and interaction points.

const WORLD = Vector2(2560, 1440)

const HOUSE_WALL = Rect2(310, 270, 260, 150)
const KITCHEN_WALL = Rect2(1970, 250, 300, 170)
const SEED_STAND = Rect2(1290, 700, 140, 115)
const KNIFE_STAND = Rect2(1800, 560, 140, 115)
const MARKET = Rect2(1730, 1000, 200, 135)
const WELL_POS = Vector2(1560, 460)
const POND_C = Vector2(2230, 1230)
const POND_R = Vector2(250, 135)
const FENCE = Rect2(495, 560, 700, 460)

const PATHS = [
	[Vector2(440, 430), Vector2(560, 540), Vector2(1240, 540), Vector2(1560, 500)],
	[Vector2(1240, 540), Vector2(1250, 800), Vector2(1330, 820)],
	[Vector2(1560, 500), Vector2(1900, 450), Vector2(2120, 440)],
	[Vector2(1560, 500), Vector2(1680, 780), Vector2(1810, 1010)],
]

const TREE_POSITIONS = [
	Vector2(170, 560), Vector2(150, 900), Vector2(220, 1240),
	Vector2(700, 1300), Vector2(1150, 1180), Vector2(1500, 1320),
	Vector2(820, 320), Vector2(1240, 240), Vector2(1650, 180),
	Vector2(2420, 560), Vector2(2380, 880), Vector2(1980, 800),
	Vector2(2160, 970), Vector2(650, 170)
]

var t := 0.0
var night01 := 0.0  # 0 = noon, 1 = midnight; set each frame by FarmController

var _tufts: Array = []    # {pos, ph}
var _flowers: Array = []  # {pos, col}
var _rocks: Array = []

func _ready():
	z_index = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xFA12  # stable decoration layout across sessions
	var flower_cols = [Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.6), Color(0.85, 0.85, 0.95)]
	for i in range(280):
		var p = Vector2(rng.randf_range(70, WORLD.x - 70), rng.randf_range(70, WORLD.y - 70))
		if _on_clear_ground(p):
			_tufts.append({"pos": p, "ph": rng.randf() * TAU})
	for i in range(70):
		var p = Vector2(rng.randf_range(80, WORLD.x - 80), rng.randf_range(80, WORLD.y - 80))
		if _on_clear_ground(p):
			_flowers.append({"pos": p, "col": flower_cols[rng.randi() % flower_cols.size()]})
	for i in range(14):
		var p = Vector2(rng.randf_range(100, WORLD.x - 100), rng.randf_range(100, WORLD.y - 100))
		if _on_clear_ground(p):
			_rocks.append(p)

# Keeps grass decorations off buildings, the plot field and the pond
func _on_clear_ground(p: Vector2) -> bool:
	for r in [HOUSE_WALL.grow(50), KITCHEN_WALL.grow(50), SEED_STAND.grow(25),
			KNIFE_STAND.grow(25), MARKET.grow(25), FENCE]:
		if r.has_point(p):
			return false
	var d = (p - POND_C) / (POND_R * 1.3)
	return d.length() > 1.0

func _process(delta):
	t += delta
	queue_redraw()

func _draw():
	_draw_grass()
	_draw_paths()
	_draw_pond()
	_draw_fence()
	_draw_house()
	_draw_kitchen()
	_draw_stall(SEED_STAND, Color(0.3, 0.65, 0.35), "SEEDS")
	_draw_stall(KNIFE_STAND, Color(0.55, 0.6, 0.7), "KNIVES")
	_draw_stall(MARKET, Color(0.85, 0.4, 0.3), "MARKET")
	_draw_well()
	for i in range(TREE_POSITIONS.size()):
		_draw_tree(TREE_POSITIONS[i], 1.0 + 0.25 * sin(i * 2.4), float(i))
	_draw_hedge_border()

func _draw_grass():
	# mown-stripe bands
	for i in range(0, int(WORLD.y), 120):
		var shade = Color(0.42, 0.62, 0.3) if (i / 120) % 2 == 0 else Color(0.38, 0.58, 0.27)
		draw_rect(Rect2(0, i, WORLD.x, 120), shade)
	for f in _flowers:
		var p: Vector2 = f.pos
		for k in range(4):
			var a = k * TAU / 4.0
			draw_circle(p + Vector2(cos(a), sin(a)) * 4.0, 3.0, f.col)
		draw_circle(p, 2.6, Color(0.98, 0.8, 0.25))
	for r in _rocks:
		draw_circle(r + Vector2(2, 2), 9.0, Color(0, 0, 0, 0.18))
		draw_circle(r, 9.0, Color(0.6, 0.6, 0.58))
		draw_circle(r - Vector2(2, 3), 4.5, Color(0.72, 0.72, 0.7))
	for tf in _tufts:
		var p: Vector2 = tf.pos
		var sway = sin(t * 1.8 + tf.ph) * 2.5
		var col = Color(0.3, 0.5, 0.22)
		draw_line(p, p + Vector2(-4 + sway, -11), col, 2.0)
		draw_line(p, p + Vector2(sway, -14), col, 2.0)
		draw_line(p, p + Vector2(4 + sway, -10), col, 2.0)

func _draw_paths():
	for path in PATHS:
		var pts = PackedVector2Array(path)
		draw_polyline(pts, Color(0.55, 0.42, 0.26), 54.0)
		draw_polyline(pts, Color(0.66, 0.52, 0.33), 44.0)
	# worn patches at the junctions
	for c in [Vector2(1240, 540), Vector2(1560, 500)]:
		draw_circle(c, 30.0, Color(0.66, 0.52, 0.33))

func _draw_pond():
	# sandy rim, then layered water
	draw_set_transform(POND_C, 0.0, Vector2(1.0, POND_R.y / POND_R.x))
	draw_circle(Vector2.ZERO, POND_R.x + 18, Color(0.72, 0.64, 0.45))
	draw_circle(Vector2.ZERO, POND_R.x, Color(0.2, 0.4, 0.55))
	draw_circle(Vector2.ZERO, POND_R.x * 0.7, Color(0.25, 0.48, 0.64))
	draw_circle(Vector2.ZERO, POND_R.x * 0.4, Color(0.32, 0.56, 0.72))
	# drifting shimmer arcs
	for i in range(4):
		var ph = t * 0.7 + i * 1.7
		var rr = POND_R.x * (0.35 + 0.5 * (0.5 + 0.5 * sin(ph * 0.6)))
		draw_arc(Vector2(20 * sin(ph), 0), rr, PI * 0.1, PI * 0.5, 12, Color(1, 1, 1, 0.25 + 0.15 * sin(ph * 2.0)), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# lily pads + reeds
	for i in range(3):
		var lp = POND_C + Vector2(-120 + i * 95, -20 + 28 * sin(i * 2.1) + sin(t * 0.8 + i) * 3.0)
		draw_circle(lp, 16.0, Color(0.3, 0.55, 0.3))
		draw_colored_polygon(PackedVector2Array([lp, lp + Vector2(18, -7), lp + Vector2(18, 7)]), Color(0.25, 0.48, 0.64))
	for i in range(5):
		var rp = POND_C + Vector2(-POND_R.x + 14 + i * 26, POND_R.y * 0.5 + 10)
		var sway = sin(t * 1.5 + i) * 3.0
		draw_line(rp, rp + Vector2(sway, -42), Color(0.32, 0.5, 0.24), 3.0)
		draw_rect(Rect2(rp.x + sway - 3, rp.y - 54, 6, 14), Color(0.45, 0.3, 0.16))

func _draw_fence():
	var rail = Color(0.55, 0.4, 0.24)
	var post = Color(0.45, 0.32, 0.18)
	# rails: top, bottom, left, right (gate gap on the right edge)
	draw_rect(Rect2(FENCE.position.x, FENCE.position.y, FENCE.size.x, 5), rail)
	draw_rect(Rect2(FENCE.position.x, FENCE.position.y + 14, FENCE.size.x, 5), rail)
	draw_rect(Rect2(FENCE.position.x, FENCE.end.y - 14, FENCE.size.x, 5), rail)
	draw_rect(Rect2(FENCE.position.x, FENCE.end.y, FENCE.size.x, 5), rail)
	for x in [FENCE.position.x, FENCE.end.x]:
		var is_gate_side = x == FENCE.end.x
		var y = FENCE.position.y
		while y < FENCE.end.y:
			if not (is_gate_side and y > 720 and y < 860):
				draw_rect(Rect2(x - 2, y, 5, 18), rail)
				draw_rect(Rect2(x - 2, y + 32, 5, 18), rail)
			y += 50
	# posts every 100 px along the perimeter
	var step = 100
	for x in range(int(FENCE.position.x), int(FENCE.end.x) + 1, step):
		draw_rect(Rect2(x - 4, FENCE.position.y - 8, 8, 30), post)
		draw_rect(Rect2(x - 4, FENCE.end.y - 8, 8, 30), post)
	for y in range(int(FENCE.position.y), int(FENCE.end.y) + 1, step):
		draw_rect(Rect2(FENCE.position.x - 4, y - 8, 8, 30), post)
		if not (y > 720 and y < 860):
			draw_rect(Rect2(FENCE.end.x - 4, y - 8, 8, 30), post)

func _window_color() -> Color:
	# panes go from daylight blue to a warm lit glow as night falls
	return Color(0.65, 0.78, 0.9).lerp(Color(1.0, 0.85, 0.4), clampf(night01 * 1.5, 0.0, 1.0))

func _draw_house():
	var w = HOUSE_WALL
	# walls with horizontal siding
	draw_rect(w, Color(0.62, 0.3, 0.22))
	for y in range(int(w.position.y) + 22, int(w.end.y), 22):
		draw_rect(Rect2(w.position.x, y, w.size.x, 2), Color(0.5, 0.23, 0.17))
	# gable roof + chimney
	draw_colored_polygon(PackedVector2Array([
		Vector2(w.position.x - 24, w.position.y), Vector2(w.end.x + 24, w.position.y),
		Vector2(w.get_center().x, w.position.y - 95)
	]), Color(0.32, 0.2, 0.12))
	draw_line(Vector2(w.position.x - 24, w.position.y), Vector2(w.get_center().x, w.position.y - 95), Color(0.42, 0.28, 0.17), 5.0)
	draw_rect(Rect2(w.end.x - 60, w.position.y - 82, 26, 56), Color(0.4, 0.25, 0.18))
	# chimney smoke puffs
	for i in range(3):
		var rise = fposmod(t * 22.0 + i * 34.0, 100.0)
		draw_circle(Vector2(w.end.x - 47 + sin(t + i) * 6.0, w.position.y - 90 - rise), 8.0 + rise * 0.1,
				Color(0.9, 0.9, 0.92, 0.5 * (1.0 - rise / 100.0)))
	# door + windows
	draw_rect(Rect2(w.get_center().x - 25, w.end.y - 80, 50, 80), Color(0.32, 0.2, 0.1))
	draw_circle(Vector2(w.get_center().x + 14, w.end.y - 40), 4.0, Color(0.85, 0.68, 0.3))
	for wx in [w.position.x + 28, w.end.x - 72]:
		draw_rect(Rect2(wx - 4, w.position.y + 36, 52, 48), Color(0.4, 0.25, 0.15))
		draw_rect(Rect2(wx, w.position.y + 40, 44, 40), _window_color())
		draw_rect(Rect2(wx + 20, w.position.y + 40, 3, 40), Color(0.4, 0.25, 0.15))

func _draw_kitchen():
	var w = KITCHEN_WALL
	# plaster walls
	draw_rect(w, Color(0.9, 0.84, 0.72))
	draw_rect(Rect2(w.position.x, w.end.y - 14, w.size.x, 14), Color(0.75, 0.68, 0.56))
	# flat roof + gold-striped awning with scalloped edge
	draw_rect(Rect2(w.position.x - 14, w.position.y - 26, w.size.x + 28, 26), Color(0.45, 0.3, 0.16))
	for i in range(8):
		var ax = w.position.x - 14 + i * (w.size.x + 28) / 8.0
		var stripe = Color(0.85, 0.68, 0.3) if i % 2 == 0 else Color(0.95, 0.92, 0.85)
		draw_rect(Rect2(ax, w.position.y - 4, (w.size.x + 28) / 8.0, 16), stripe)
		draw_circle(Vector2(ax + (w.size.x + 28) / 16.0, w.position.y + 12), (w.size.x + 28) / 16.0, stripe)
	# sign
	GameHUD.panel_style(Color(0.25, 0.16, 0.09, 0.95)).draw(get_canvas_item(), Rect2(w.get_center().x - 120, w.position.y + 32, 240, 38))
	var font = ThemeDB.fallback_font
	var label = "SLICE IT! KITCHEN"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 19)
	draw_string(font, Vector2(w.get_center().x - ls.x / 2, w.position.y + 58), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.GOLD)
	# double door + windows
	draw_rect(Rect2(w.get_center().x - 40, w.end.y - 90, 80, 90), Color(0.42, 0.27, 0.14))
	draw_rect(Rect2(w.get_center().x - 2, w.end.y - 90, 4, 90), Color(0.3, 0.19, 0.1))
	for wx in [w.position.x + 30, w.end.x - 80]:
		draw_rect(Rect2(wx - 4, w.end.y - 86, 58, 50), Color(0.55, 0.45, 0.3))
		draw_rect(Rect2(wx, w.end.y - 82, 50, 42), _window_color())

func _draw_stall(r: Rect2, stripe: Color, label: String):
	# back board + counter
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 36), Color(0.5, 0.36, 0.2))
	draw_rect(Rect2(r.position.x - 8, r.end.y - 40, r.size.x + 16, 40), Color(0.42, 0.29, 0.16))
	draw_rect(Rect2(r.position.x - 8, r.end.y - 40, r.size.x + 16, 6), Color(0.58, 0.42, 0.25))
	# awning
	for i in range(5):
		var ax = r.position.x - 12 + i * (r.size.x + 24) / 5.0
		var c = stripe if i % 2 == 0 else Color(0.95, 0.92, 0.85)
		draw_rect(Rect2(ax, r.position.y - 22, (r.size.x + 24) / 5.0, 18), c)
		draw_circle(Vector2(ax + (r.size.x + 24) / 10.0, r.position.y - 4), (r.size.x + 24) / 10.0, c)
	# wares on the back board
	match label:
		"SEEDS":
			for i in range(3):
				var px = r.position.x + 22 + i * 36
				draw_rect(Rect2(px, r.position.y + 16, 24, 32), Color(0.92, 0.88, 0.78))
				draw_circle(Vector2(px + 12, r.position.y + 30), 7.0, Color(0.72, 0.45, 0.2).lightened(i * 0.2))
		"KNIVES":
			for i in range(3):
				var px = r.position.x + 26 + i * 36
				draw_colored_polygon(PackedVector2Array([
					Vector2(px, r.position.y + 14), Vector2(px + 14, r.position.y + 14),
					Vector2(px + 7, r.position.y + 44)
				]), Color(0.85, 0.87, 0.92))
				draw_rect(Rect2(px + 3, r.position.y + 6, 8, 9), Color(0.35, 0.22, 0.12))
		"MARKET":
			for i in range(2):
				var px = r.position.x + 24 + i * 78
				draw_rect(Rect2(px, r.position.y + 14, 56, 36), Color(0.62, 0.46, 0.26))
				for k in range(3):
					draw_circle(Vector2(px + 13 + k * 15, r.position.y + 18), 8.0, Color(0.78, 0.55, 0.3))
	# name plate
	var font = ThemeDB.fallback_font
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, Vector2(r.get_center().x - ls.x / 2, r.end.y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.8))

func _draw_well():
	var c = WELL_POS
	# posts + little gable roof first, so the stone ring overlaps their feet
	draw_rect(Rect2(c.x - 46, c.y - 78, 9, 70), Color(0.42, 0.29, 0.16))
	draw_rect(Rect2(c.x + 37, c.y - 78, 9, 70), Color(0.42, 0.29, 0.16))
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - 62, c.y - 72), Vector2(c.x + 62, c.y - 72), Vector2(c.x, c.y - 112)
	]), Color(0.55, 0.25, 0.18))
	# rope + bucket
	draw_line(Vector2(c.x, c.y - 72), Vector2(c.x, c.y - 28), Color(0.75, 0.68, 0.5), 3.0)
	draw_rect(Rect2(c.x - 11, c.y - 30, 22, 16), Color(0.5, 0.34, 0.18))
	# stone ring
	draw_set_transform(c, 0.0, Vector2(1.0, 0.75))
	draw_circle(Vector2.ZERO, 50.0, Color(0.55, 0.55, 0.55))
	draw_circle(Vector2.ZERO, 36.0, Color(0.12, 0.16, 0.22))
	for i in range(9):
		var a = i * TAU / 9.0
		draw_arc(Vector2.ZERO, 43.0, a, a + 0.5, 6, Color(0.4, 0.4, 0.42), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_tree(pos: Vector2, s: float, ph: float):
	var sway = sin(t * 0.8 + ph) * 3.0 * s
	draw_set_transform(pos + Vector2(6, 4) * s, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 42.0 * s, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(pos.x - 9 * s, pos.y - 60 * s, 18 * s, 62 * s), Color(0.42, 0.28, 0.16))
	draw_circle(pos + Vector2(sway - 26 * s, -78 * s), 34 * s, Color(0.22, 0.42, 0.18))
	draw_circle(pos + Vector2(sway + 26 * s, -76 * s), 32 * s, Color(0.25, 0.46, 0.2))
	draw_circle(pos + Vector2(sway, -100 * s), 36 * s, Color(0.3, 0.52, 0.24))
	draw_circle(pos + Vector2(sway - 12 * s, -108 * s), 16 * s, Color(0.38, 0.6, 0.3))

func _draw_hedge_border():
	var hedge = Color(0.16, 0.3, 0.14)
	draw_rect(Rect2(0, 0, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, WORLD.y - 36, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, 0, 36, WORLD.y), hedge)
	draw_rect(Rect2(WORLD.x - 36, 0, 36, WORLD.y), hedge)
	for x in range(45, int(WORLD.x), 90):
		draw_circle(Vector2(x, 36), 16.0, hedge)
		draw_circle(Vector2(x, WORLD.y - 36), 16.0, hedge)
	for y in range(45, int(WORLD.y), 90):
		draw_circle(Vector2(36, y), 16.0, hedge)
		draw_circle(Vector2(WORLD.x - 36, y), 16.0, hedge)
