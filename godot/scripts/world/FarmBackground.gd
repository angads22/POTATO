extends Node2D
class_name FarmBackground

# The Spudling Acres backdrop (design §5.2): a farmyard strip across the top
# (the farmhouse, the well, the pond, the kitchen garden, hay bales and a tree
# line), one dirt path at y = 620 dividing the yard from the six fenced
# fields below, and the east gate to town. The fields themselves, their huts
# and the Greenhouse (where the truck and research shed used to stand) are
# FarmField nodes drawn above this layer; field rects, the Greenhouse rect and
# the fence-socket midpoints come from farm.json through FarmView. The fence
# sockets and their sprinklers are drawn here, in the gaps between fields.
#
# The farmhouse has four art tiers (Cabin, Cottage, House, Manor) that follow
# farm.up.house, and Prize Strain ribbons hang on its wall. night01 (real
# local clock) is set by the controller each frame.

const WORLD = Vector2(2560, 1600)

# Farmhouse footprint (the Manor fills it; smaller tiers sit inside) and the
# spot in front of its door where [E] opens the Book on the Helpers tab.
const HOUSE_WALL = Rect2(140, 160, 300, 190)
const HOUSE_DOOR = Vector2(290, 392)
const WELL_POS = Vector2(780, 330)
const POND_C = Vector2(2200, 360)
const POND_R = Vector2(220, 120)
const GARDEN_RECT = Rect2(470, 410, 220, 130)
const HAY_POS = Vector2(600, 262)
const TOWN_GATE_POS = Vector2(2470, 620)  # hedge gap at the east end of the path
const FROM_TOWN_SPAWN = Vector2(2390, 620)

# The main track plus a short path from the farmhouse door down to it.
const PATHS = [
	[Vector2(90, 620), Vector2(2470, 620)],
	[Vector2(290, 360), Vector2(290, 620)],
]
const PATH_CLEARANCE := 34.0

const TREE_POSITIONS = [
	Vector2(80, 110), Vector2(520, 116), Vector2(960, 100), Vector2(1880, 112),
	Vector2(2360, 130), Vector2(1040, 548), Vector2(2480, 470), Vector2(1860, 548)
]

var t := 0.0
var night01 := 0.0  # 0 = day, 1 = deep night; set each frame by the controller

var _tufts: Array = []    # {pos, ph}
var _flowers: Array = []  # {pos, col}
var _rocks: Array = []
var _dapples: Array = []  # {pos, r, col}
var _field_rects: Array = []

func _ready():
	z_index = -1
	for i in FarmView.field_count():
		_field_rects.append(FarmView.field_rect(i).grow(26))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xFA12  # stable decoration layout across sessions
	var dapple_cols = [
		Color(0.46, 0.66, 0.33, 0.35), Color(0.36, 0.55, 0.26, 0.35),
		Color(0.5, 0.7, 0.36, 0.28),
	]
	for i in range(150):
		var p = Vector2(rng.randf_range(40, WORLD.x - 40), rng.randf_range(40, WORLD.y - 40))
		_dapples.append({"pos": p, "r": rng.randf_range(60.0, 150.0),
				"col": dapple_cols[rng.randi() % dapple_cols.size()]})
	var flower_cols = [Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.6), Color(0.85, 0.85, 0.95)]
	for i in range(320):
		var p = Vector2(rng.randf_range(70, WORLD.x - 70), rng.randf_range(70, WORLD.y - 70))
		if _on_clear_ground(p):
			_tufts.append({"pos": p, "ph": rng.randf() * TAU})
	for i in range(90):
		var p = Vector2(rng.randf_range(80, WORLD.x - 80), rng.randf_range(80, WORLD.y - 80))
		if _on_clear_ground(p):
			_flowers.append({"pos": p, "col": flower_cols[rng.randi() % flower_cols.size()]})
	for i in range(16):
		var p = Vector2(rng.randf_range(100, WORLD.x - 100), rng.randf_range(100, WORLD.y - 100))
		if _on_clear_ground(p):
			_rocks.append(p)

# Keeps grass decorations off the buildings, fields, pond, garden and paths.
func _on_clear_ground(p: Vector2) -> bool:
	if HOUSE_WALL.grow(50).has_point(p) or GARDEN_RECT.grow(8).has_point(p):
		return false
	for r in _field_rects:
		if r.has_point(p):
			return false
	for i in FarmView.field_count():
		if FarmView.hut_rect(i).grow(10).has_point(p):
			return false
	if on_path(p):
		return false
	var d = (p - POND_C) / (POND_R * 1.3)
	return d.length() > 1.0

static func on_path(p: Vector2, clearance := PATH_CLEARANCE) -> bool:
	return path_distance(p) <= clearance

static func path_distance(p: Vector2) -> float:
	var best := INF
	for path in PATHS:
		for i in range(path.size() - 1):
			best = minf(best, _segment_distance(p, path[i], path[i + 1]))
	return best

static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var tt := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * tt)

var _acc := 0.0

# The backdrop only animates grass, water and sprinkler spray, so 30 redraws
# a second are plenty (it is the biggest canvas item in the scene).
func _process(delta):
	t += delta
	_acc += delta
	if _acc >= 1.0 / 30.0:
		_acc = 0.0
		queue_redraw()

func _draw():
	var farm: Dictionary = SaveDataManager.farm
	_draw_grass()
	_draw_paths()
	_draw_kitchen_garden()
	_draw_pond()
	_draw_hay()
	_draw_well()
	_draw_house(farm)
	_draw_sockets(farm)
	for i in range(TREE_POSITIONS.size()):
		_draw_tree(TREE_POSITIONS[i], 1.0 + 0.2 * sin(i * 2.4), float(i))
	_draw_town_gate()
	_draw_hedge_border()

func _draw_grass():
	for i in range(0, int(WORLD.y), 120):
		var shade = Color(0.42, 0.62, 0.3) if (i / 120) % 2 == 0 else Color(0.38, 0.58, 0.27)
		draw_rect(Rect2(0, i, WORLD.x, 120), shade)
	for d in _dapples:
		draw_circle(d.pos, d.r, d.col)
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
	var grass_edge := Color(0.3, 0.46, 0.22, 0.5)
	var gravel := Color(0.5, 0.38, 0.23)
	var earth := Color(0.62, 0.48, 0.30)
	var worn := Color(0.7, 0.57, 0.37)
	for path in PATHS:
		draw_polyline(PackedVector2Array(path), grass_edge, 60.0)
	for k in PATHS.size():
		var path: Array = PATHS[k]
		var wd := 1.0 if k == 0 else 0.7
		var pts = PackedVector2Array(path)
		draw_polyline(pts, gravel, 52.0 * wd)
		draw_polyline(pts, earth, 44.0 * wd)
		draw_polyline(pts, worn, 20.0 * wd)
		for i in range(path.size()):
			draw_circle(path[i], 22.0 * wd, earth)
			draw_circle(path[i], 10.0 * wd, worn)
	var grng := RandomNumberGenerator.new()
	grng.seed = 0x6A77
	for path in PATHS:
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var steps := int(a.distance_to(b) / 26.0)
			for s in range(steps):
				var base := a.lerp(b, float(s) / maxf(1.0, steps))
				var off := Vector2(grng.randf_range(-14, 14), grng.randf_range(-14, 14))
				var shade: Color = gravel.darkened(0.12) if (s % 2 == 0) else worn.lightened(0.05)
				draw_circle(base + off, grng.randf_range(1.5, 3.0), shade)

func _draw_pond():
	draw_set_transform(POND_C, 0.0, Vector2(1.0, POND_R.y / POND_R.x))
	draw_circle(Vector2.ZERO, POND_R.x + 18, Color(0.72, 0.64, 0.45))
	draw_circle(Vector2.ZERO, POND_R.x, Color(0.2, 0.4, 0.55))
	draw_circle(Vector2.ZERO, POND_R.x * 0.7, Color(0.25, 0.48, 0.64))
	draw_circle(Vector2.ZERO, POND_R.x * 0.4, Color(0.32, 0.56, 0.72))
	for i in range(4):
		var ph = t * 0.7 + i * 1.7
		var rr = POND_R.x * (0.35 + 0.5 * (0.5 + 0.5 * sin(ph * 0.6)))
		draw_arc(Vector2(20 * sin(ph), 0), rr, PI * 0.1, PI * 0.5, 12, Color(1, 1, 1, 0.25 + 0.15 * sin(ph * 2.0)), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(3):
		var lp = POND_C + Vector2(-120 + i * 95, -20 + 28 * sin(i * 2.1) + sin(t * 0.8 + i) * 3.0)
		draw_circle(lp, 16.0, Color(0.3, 0.55, 0.3))
		draw_colored_polygon(PackedVector2Array([lp, lp + Vector2(18, -7), lp + Vector2(18, 7)]), Color(0.25, 0.48, 0.64))
	for i in range(5):
		var rp = POND_C + Vector2(-POND_R.x + 14 + i * 26, POND_R.y * 0.5 + 10)
		var sway = sin(t * 1.5 + i) * 3.0
		draw_line(rp, rp + Vector2(sway, -42), Color(0.32, 0.5, 0.24), 3.0)
		draw_rect(Rect2(rp.x + sway - 3, rp.y - 54, 6, 14), Color(0.45, 0.3, 0.16))

func _window_color() -> Color:
	return Color(0.65, 0.78, 0.9).lerp(Color(1.0, 0.85, 0.4), clampf(night01 * 1.5, 0.0, 1.0))

func _window(r: Rect2, frame: Color):
	draw_rect(r.grow(4), frame)
	draw_rect(r, _window_color())
	draw_rect(Rect2(r.get_center().x - 1.5, r.position.y, 3, r.size.y), frame)
	draw_rect(Rect2(r.position.x, r.get_center().y - 1.5, r.size.x, 3), frame)

func _smoke(base: Vector2):
	for i in range(3):
		var rise = fposmod(t * 22.0 + i * 34.0, 100.0)
		draw_circle(Vector2(base.x + sin(t + i) * 6.0, base.y - rise), 8.0 + rise * 0.1,
				Color(0.9, 0.9, 0.92, 0.5 * (1.0 - rise / 100.0)))

func _door(c: Vector2, w: float, h: float, col := Color(0.32, 0.2, 0.1)):
	draw_rect(Rect2(c.x - w / 2, c.y - h, w, h), col)
	draw_circle(Vector2(c.x + w * 0.28, c.y - h * 0.5), 3.5, Color(0.85, 0.68, 0.3))

# Four art tiers inside HOUSE_WALL: Cabin, Cottage (porch), House (second
# storey + chimney), Manor (wings, columns, lit garden lamps).
func _draw_house(farm: Dictionary):
	var tier := FarmView.house_tier(farm) if farm.has("up") else 0
	var cx := HOUSE_WALL.get_center().x
	var base_y := HOUSE_WALL.end.y
	# soft ground shadow
	draw_set_transform(Vector2(cx, base_y + 4), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 120.0 + tier * 22.0, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match tier:
		0:
			var w := Rect2(cx - 95, base_y - 105, 190, 105)
			draw_rect(w, Color(0.55, 0.36, 0.2))
			for y in range(int(w.position.y) + 6, int(w.end.y), 15):
				draw_rect(Rect2(w.position.x, y, w.size.x, 11), Color(0.6, 0.4, 0.22))
				draw_circle(Vector2(w.position.x, y + 5.5), 6.0, Color(0.68, 0.5, 0.3))
				draw_circle(Vector2(w.end.x, y + 5.5), 6.0, Color(0.68, 0.5, 0.3))
			draw_colored_polygon(PackedVector2Array([Vector2(w.position.x - 18, w.position.y), Vector2(w.end.x + 18, w.position.y),
					Vector2(cx, w.position.y - 70)]), Color(0.36, 0.24, 0.14))
			_window(Rect2(w.position.x + 24, w.position.y + 24, 36, 30), Color(0.38, 0.24, 0.12))
			_door(Vector2(cx + 30, base_y), 40, 66)
			_ribbons(farm, Vector2(w.end.x - 46, w.position.y + 18))
		1:
			var w := Rect2(cx - 120, base_y - 125, 240, 125)
			draw_rect(w, Color(0.92, 0.86, 0.72))
			draw_rect(Rect2(w.position.x, w.end.y - 12, w.size.x, 12), Color(0.72, 0.64, 0.5))
			draw_colored_polygon(PackedVector2Array([Vector2(w.position.x - 22, w.position.y), Vector2(w.end.x + 22, w.position.y),
					Vector2(cx, w.position.y - 84)]), Color(0.7, 0.3, 0.22))
			draw_rect(Rect2(w.end.x - 62, w.position.y - 64, 22, 46), Color(0.5, 0.3, 0.22))
			_smoke(Vector2(w.end.x - 51, w.position.y - 72))
			_window(Rect2(w.position.x + 26, w.position.y + 26, 40, 34), Color(0.5, 0.36, 0.2))
			_window(Rect2(w.end.x - 66, w.position.y + 26, 40, 34), Color(0.5, 0.36, 0.2))
			# porch: a little roof on two posts, flower boxes
			draw_rect(Rect2(cx - 62, base_y - 58, 124, 10), Color(0.6, 0.28, 0.2))
			draw_rect(Rect2(cx - 58, base_y - 48, 7, 48), Color(0.95, 0.92, 0.85))
			draw_rect(Rect2(cx + 51, base_y - 48, 7, 48), Color(0.95, 0.92, 0.85))
			_door(Vector2(cx, base_y), 40, 58, Color(0.42, 0.26, 0.14))
			for fx in [w.position.x + 26, w.end.x - 66]:
				draw_rect(Rect2(fx - 2, w.position.y + 62, 44, 8), Color(0.5, 0.32, 0.18))
				for k in 4:
					draw_circle(Vector2(fx + 4 + k * 11, w.position.y + 60), 4.0, [Color(0.95, 0.5, 0.55), Color(0.98, 0.85, 0.3)][k % 2])
			_ribbons(farm, Vector2(cx - 14, w.position.y + 8))
		2:
			var w := Rect2(cx - 130, base_y - 170, 260, 170)
			draw_rect(w, Color(0.62, 0.3, 0.22))
			for y in range(int(w.position.y) + 22, int(w.end.y), 22):
				draw_rect(Rect2(w.position.x, y, w.size.x, 2), Color(0.5, 0.23, 0.17))
			draw_rect(Rect2(w.position.x, w.position.y + 78, w.size.x, 6), Color(0.85, 0.8, 0.7))   # storey trim
			draw_colored_polygon(PackedVector2Array([Vector2(w.position.x - 24, w.position.y), Vector2(w.end.x + 24, w.position.y),
					Vector2(cx, w.position.y - 90)]), Color(0.32, 0.2, 0.12))
			draw_rect(Rect2(w.end.x - 66, w.position.y - 80, 26, 58), Color(0.4, 0.25, 0.18))
			_smoke(Vector2(w.end.x - 53, w.position.y - 88))
			for wx in [w.position.x + 30, cx - 18, w.end.x - 66]:
				_window(Rect2(wx, w.position.y + 22, 36, 38), Color(0.4, 0.25, 0.15))
			_window(Rect2(w.position.x + 30, w.position.y + 104, 40, 40), Color(0.4, 0.25, 0.15))
			_window(Rect2(w.end.x - 70, w.position.y + 104, 40, 40), Color(0.4, 0.25, 0.15))
			_door(Vector2(cx, base_y), 48, 76)
			_ribbons(farm, Vector2(cx - 30, w.position.y + 88))
		_:
			# the Manor: stone centre block, two lower wings, columns, lamps
			var wing_l := Rect2(HOUSE_WALL.position.x, base_y - 110, 70, 110)
			var wing_r := Rect2(HOUSE_WALL.end.x - 70, base_y - 110, 70, 110)
			for wr in [wing_l, wing_r]:
				draw_rect(wr, Color(0.86, 0.84, 0.8))
				draw_colored_polygon(PackedVector2Array([Vector2(wr.position.x - 6, wr.position.y), Vector2(wr.end.x + 6, wr.position.y),
						Vector2(wr.get_center().x, wr.position.y - 40)]), Color(0.3, 0.32, 0.42))
				_window(Rect2(wr.position.x + 17, wr.position.y + 34, 36, 40), Color(0.45, 0.42, 0.4))
			var w := Rect2(cx - 90, base_y - 185, 180, 185)
			draw_rect(w, Color(0.93, 0.91, 0.86))
			for y in range(int(w.position.y) + 26, int(w.end.y), 26):
				draw_rect(Rect2(w.position.x, y, w.size.x, 2), Color(0.8, 0.78, 0.72))
			draw_colored_polygon(PackedVector2Array([Vector2(w.position.x - 16, w.position.y), Vector2(w.end.x + 16, w.position.y),
					Vector2(cx, w.position.y - 70)]), Color(0.26, 0.28, 0.38))
			for chx in [w.position.x + 18, w.end.x - 40]:
				draw_rect(Rect2(chx, w.position.y - 56, 22, 50), Color(0.55, 0.5, 0.48))
			_smoke(Vector2(w.end.x - 29, w.position.y - 64))
			for wx in [w.position.x + 22, w.end.x - 58]:
				_window(Rect2(wx, w.position.y + 22, 36, 44), Color(0.45, 0.42, 0.4))
			# portico: pediment + four columns + double door
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 70, base_y - 96), Vector2(cx + 70, base_y - 96),
					Vector2(cx, base_y - 126)]), Color(0.97, 0.96, 0.92))
			for k in 4:
				draw_rect(Rect2(cx - 64 + k * 40, base_y - 96, 10, 96), Color(0.98, 0.97, 0.94))
			_door(Vector2(cx - 13, base_y), 26, 70, Color(0.35, 0.18, 0.12))
			_door(Vector2(cx + 13, base_y), 26, 70, Color(0.35, 0.18, 0.12))
			_ribbons(farm, Vector2(cx - 40, w.position.y + 84))
			# lit garden lamps either side of the door path
			for lx in [cx - 46, cx + 46]:
				var lp := Vector2(lx, base_y + 40)
				draw_rect(Rect2(lp.x - 2, lp.y - 34, 4, 34), Color(0.2, 0.2, 0.22))
				draw_circle(lp + Vector2(0, -38), 6.0, Color(1.0, 0.85, 0.45).lerp(Color(1.0, 0.95, 0.7), night01))
				if night01 > 0.2:
					draw_circle(lp + Vector2(0, -38), 20.0, Color(1.0, 0.85, 0.4, 0.18 * night01))
	# name plate on a post by the path
	var font = ThemeDB.fallback_font
	var label := FarmView.house_name(tier).to_upper()
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var pp := Vector2(HOUSE_DOOR.x + 58, HOUSE_DOOR.y + 8)
	draw_rect(Rect2(pp.x - 3, pp.y - 30, 6, 34), Color(0.45, 0.32, 0.18))
	GameHUD.panel_style(Color(0.2, 0.14, 0.08, 0.95)).draw(get_canvas_item(), Rect2(pp.x - ls.x / 2 - 10, pp.y - 56, ls.x + 20, 28))
	draw_string(font, Vector2(pp.x - ls.x / 2, pp.y - 36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.98, 0.9, 0.7))

# Prize Strain ribbons pinned in a row on the farmhouse wall.
func _ribbons(farm: Dictionary, at: Vector2):
	if not farm.has("up"):
		return
	var x := at.x
	var n := 0
	for rb in FarmView.ribbons(farm):
		for k in int(rb["tier"]):
			var c := Vector2(x, at.y + (n % 2) * 3)
			var col := FarmView.ribbon_color(k + 1)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 2), c + Vector2(-1, 2), c + Vector2(-5, 13)]), col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([c + Vector2(1, 2), c + Vector2(4, 2), c + Vector2(5, 13)]), col.darkened(0.25))
			draw_circle(c, 5.0, col)
			x += 12.0
			n += 1
			if n >= 10:
				return

func _draw_well():
	var c = WELL_POS
	draw_rect(Rect2(c.x - 46, c.y - 78, 9, 70), Color(0.42, 0.29, 0.16))
	draw_rect(Rect2(c.x + 37, c.y - 78, 9, 70), Color(0.42, 0.29, 0.16))
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - 62, c.y - 72), Vector2(c.x + 62, c.y - 72), Vector2(c.x, c.y - 112)
	]), Color(0.55, 0.25, 0.18))
	draw_line(Vector2(c.x, c.y - 72), Vector2(c.x, c.y - 28), Color(0.75, 0.68, 0.5), 3.0)
	draw_rect(Rect2(c.x - 11, c.y - 30, 22, 16), Color(0.5, 0.34, 0.18))
	draw_set_transform(c, 0.0, Vector2(1.0, 0.75))
	draw_circle(Vector2.ZERO, 50.0, Color(0.55, 0.55, 0.55))
	draw_circle(Vector2.ZERO, 36.0, Color(0.12, 0.16, 0.22))
	for i in range(9):
		var a = i * TAU / 9.0
		draw_arc(Vector2.ZERO, 43.0, a, a + 0.5, 6, Color(0.4, 0.4, 0.42), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hay():
	for k in 3:
		var p := HAY_POS + Vector2(k * 58 - (k / 2) * 86, -(k / 2) * 34)
		draw_set_transform(p + Vector2(4, 22), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 34.0, Color(0, 0, 0, 0.15))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(p.x - 30, p.y - 20, 60, 40), Color(0.86, 0.72, 0.36))
		for s in 4:
			draw_line(Vector2(p.x - 26, p.y - 14 + s * 9), Vector2(p.x + 26, p.y - 12 + s * 9), Color(0.74, 0.6, 0.28), 2.0)
		draw_rect(Rect2(p.x - 14, p.y - 20, 4, 40), Color(0.55, 0.4, 0.2))
		draw_rect(Rect2(p.x + 10, p.y - 20, 4, 40), Color(0.55, 0.4, 0.2))

# Fence sockets in the gaps between fields: a stone pad and post, plus the
# sprinkler head (with spray toward both fields) where one is placed.
func _draw_sockets(farm: Dictionary):
	var placed: Array = farm.get("sprinklers", [])
	for s in FarmView.sockets():
		var p := FarmView.socket_pos(s)
		var pr: Array = FarmView.socket_fields(s)
		var horiz := absf(FarmView.field_rect(pr[0]).get_center().y - FarmView.field_rect(pr[1]).get_center().y) < 1.0
		draw_set_transform(p + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 24.0, Color(0.55, 0.53, 0.5))
		draw_circle(Vector2.ZERO, 18.0, Color(0.64, 0.62, 0.58))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# a short pipe stub toward each field
		var a := Vector2(1, 0) if horiz else Vector2(0, 1)
		draw_line(p - a * 30, p + a * 30, Color(0.45, 0.47, 0.5), 5.0)
		if s in placed:
			var metal := Color(0.66, 0.72, 0.78)
			draw_line(p + Vector2(0, 8), p + Vector2(0, -22), metal, 6.0)
			draw_circle(p + Vector2(0, -24), 9.0, metal)
			draw_circle(p + Vector2(0, -24), 4.0, Color(0.35, 0.55, 0.75))
			for k in 2:
				var side := -1.0 if k == 0 else 1.0
				var dirv := a * side
				var ang := dirv.angle()
				var sw := sin(t * 2.2 + k) * 0.35
				draw_arc(p + Vector2(0, -20), 46.0, ang - 0.5 + sw, ang + 0.5 + sw, 10, Color(0.5, 0.8, 1.0, 0.75), 3.0)
				draw_arc(p + Vector2(0, -20), 70.0, ang - 0.35 + sw, ang + 0.35 + sw, 10, Color(0.5, 0.8, 1.0, 0.45), 2.5)
				var drop := p + Vector2(0, -20) + Vector2(cos(ang + sw), sin(ang + sw)) * (40.0 + fposmod(t * 60.0 + k * 20.0, 50.0))
				draw_circle(drop, 3.0, Color(0.55, 0.82, 1.0, 0.8))
		else:
			draw_rect(Rect2(p.x - 5, p.y - 16, 10, 22), Color(0.5, 0.36, 0.22))
			draw_circle(p + Vector2(0, -17), 6.0, Color(0.6, 0.44, 0.27))

func _draw_tree(pos: Vector2, s: float, ph: float):
	var sway = sin(t * 0.8 + ph) * 3.0 * s
	draw_set_transform(pos + Vector2(8, 6) * s, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 48.0 * s, Color(0, 0, 0, 0.16))
	draw_circle(Vector2.ZERO, 38.0 * s, Color(0, 0, 0, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(pos.x - 9 * s, pos.y - 60 * s, 18 * s, 62 * s), Color(0.42, 0.28, 0.16))
	draw_rect(Rect2(pos.x - 9 * s, pos.y - 60 * s, 6 * s, 62 * s), Color(0.34, 0.22, 0.12))
	for o in [Vector2(-28, -70), Vector2(28, -68), Vector2(0, -92), Vector2(-8, -52), Vector2(12, -54)]:
		draw_circle(pos + Vector2(sway, 0) + o * s, 30.0 * s, Color(0.18, 0.36, 0.15))
	draw_circle(pos + Vector2(sway - 26 * s, -78 * s), 34 * s, Color(0.24, 0.45, 0.2))
	draw_circle(pos + Vector2(sway + 26 * s, -76 * s), 32 * s, Color(0.27, 0.48, 0.22))
	draw_circle(pos + Vector2(sway, -100 * s), 36 * s, Color(0.3, 0.52, 0.24))
	draw_circle(pos + Vector2(sway + 6 * s, -64 * s), 26 * s, Color(0.28, 0.5, 0.23))
	draw_circle(pos + Vector2(sway - 12 * s, -108 * s), 16 * s, Color(0.4, 0.62, 0.32))
	draw_circle(pos + Vector2(sway + 18 * s, -94 * s), 11 * s, Color(0.45, 0.66, 0.35))
	draw_circle(pos + Vector2(sway - 24 * s, -84 * s), 9 * s, Color(0.43, 0.64, 0.34))

func _draw_kitchen_garden():
	var r = GARDEN_RECT
	draw_rect(Rect2(r.position.x + 6, r.position.y + 8, r.size.x, r.size.y), Color(0, 0, 0, 0.12))
	var soil = Rect2(r.position.x + 10, r.position.y + 10, r.size.x - 20, r.size.y - 20)
	draw_rect(soil, Color(0.43, 0.3, 0.18))
	for i in range(2):
		var ry = soil.position.y + 16 + i * 46
		draw_rect(Rect2(soil.position.x + 8, ry, soil.size.x - 16, 26), Color(0.5, 0.35, 0.2))
		draw_rect(Rect2(soil.position.x + 8, ry, soil.size.x - 16, 4), Color(0.6, 0.45, 0.27))
		for k in range(5):
			var vx = soil.position.x + 24 + k * (soil.size.x - 48) / 4.0
			var vy = ry + 14
			var sway = sin(t * 1.3 + k + i) * 1.5
			for leaf in [Vector2(-6, 0), Vector2(6, 0), Vector2(0, -7)]:
				draw_circle(Vector2(vx + leaf.x + sway, vy + leaf.y), 5.0, Color(0.3, 0.55, 0.26))
			draw_circle(Vector2(vx + sway, vy), 3.0, Color(0.85, 0.55, 0.3))
	var fence = Color(0.82, 0.78, 0.68)
	var fence_dk = Color(0.62, 0.58, 0.48)
	draw_rect(Rect2(r.position.x, r.position.y + 6, r.size.x, 4), fence_dk)
	draw_rect(Rect2(r.position.x, r.position.y + 22, r.size.x, 4), fence_dk)
	draw_rect(Rect2(r.position.x, r.end.y - 12, r.size.x, 4), fence_dk)
	for px in range(int(r.position.x), int(r.end.x) + 1, 26):
		var post = Vector2(px, r.position.y)
		draw_rect(Rect2(post.x - 3, post.y, 6, r.size.y), fence)
		draw_colored_polygon(PackedVector2Array([
			Vector2(post.x - 3, post.y), Vector2(post.x + 3, post.y), Vector2(post.x, post.y - 8)
		]), fence)

func _draw_town_gate():
	draw_rect(Rect2(WORLD.x - 120, 580, 120, 80), Color(0.55, 0.42, 0.26))
	draw_rect(Rect2(WORLD.x - 120, 588, 120, 64), Color(0.66, 0.52, 0.33))
	var sp = Vector2(2392, 552)
	draw_rect(Rect2(sp.x - 4, sp.y - 52, 8, 56), Color(0.45, 0.32, 0.18))
	draw_rect(Rect2(sp.x - 46, sp.y - 80, 92, 32), Color(0.55, 0.4, 0.24))
	draw_rect(Rect2(sp.x - 46, sp.y - 80, 92, 4), Color(0.65, 0.5, 0.3))
	var font = ThemeDB.fallback_font
	var label = "TOWN"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2(sp.x - ls.x / 2 - 8, sp.y - 57), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.9, 0.8))
	draw_colored_polygon(PackedVector2Array([Vector2(sp.x + ls.x / 2 - 2, sp.y - 72), Vector2(sp.x + ls.x / 2 + 12, sp.y - 64),
			Vector2(sp.x + ls.x / 2 - 2, sp.y - 56)]), Color(0.95, 0.9, 0.8))

func _draw_hedge_border():
	var hedge = Color(0.16, 0.3, 0.14)
	draw_rect(Rect2(0, 0, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, WORLD.y - 36, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, 0, 36, WORLD.y), hedge)
	draw_rect(Rect2(WORLD.x - 36, 0, 36, 560), hedge)
	draw_rect(Rect2(WORLD.x - 36, 690, 36, WORLD.y - 690), hedge)
	for x in range(45, int(WORLD.x), 90):
		draw_circle(Vector2(x, 36), 16.0, hedge)
		draw_circle(Vector2(x, WORLD.y - 36), 16.0, hedge)
	for y in range(45, int(WORLD.y), 90):
		draw_circle(Vector2(36, y), 16.0, hedge)
		if y < 550 or y > 700:
			draw_circle(Vector2(WORLD.x - 36, y), 16.0, hedge)
