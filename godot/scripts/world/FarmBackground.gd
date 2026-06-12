extends Node2D
class_name FarmBackground

# The farm backdrop: striped pasture, dirt paths, the farmhouse, a well, a
# pond, fenced crop fields and a tree line — all procedural, like the rest
# of the game. The market stalls and the championship kitchen live in town
# now (TownBackground); a gate in the east hedge leads there. Geometry
# constants here are the single source of truth; FarmController reads them
# for collision and interaction points.

const WORLD = Vector2(2560, 1440)

const HOUSE_WALL = Rect2(310, 270, 260, 150)
const WELL_POS = Vector2(1560, 460)
const POND_C = Vector2(2230, 1230)
const POND_R = Vector2(250, 135)
const TOWN_GATE_POS = Vector2(2470, 870)  # hedge gap on the east edge

const PATHS = [
	[Vector2(440, 430), Vector2(560, 540), Vector2(1240, 540), Vector2(1560, 500)],
	[Vector2(1240, 540), Vector2(1180, 660), Vector2(1140, 745)],
	[Vector2(1560, 500), Vector2(1648, 455)],
	[Vector2(1240, 540), Vector2(1220, 800), Vector2(1200, 1010)],
	[Vector2(1560, 500), Vector2(2000, 660), Vector2(2330, 820), Vector2(2480, 870)],
]

const TREE_POSITIONS = [
	Vector2(170, 560), Vector2(150, 900), Vector2(220, 1240),
	Vector2(380, 1340), Vector2(1920, 760), Vector2(2440, 990),
	Vector2(820, 320), Vector2(1240, 240), Vector2(1450, 140),
	Vector2(2480, 330), Vector2(2380, 1060), Vector2(1980, 800),
	Vector2(2160, 970), Vector2(650, 170)
]

var t := 0.0
var night01 := 0.0  # 0 = noon, 1 = midnight; set each frame by the controller

var _tufts: Array = []    # {pos, ph}
var _flowers: Array = []  # {pos, col}
var _rocks: Array = []
var _fences: Array = []   # {rect, gate} derived from fields.json

# Fence rect around a field grid: tile art is 130×90 on 140×110 cells,
# plus a 20 px margin
static func field_rect(fd: Dictionary) -> Rect2:
	var cell = GameData.field_cell()
	var origin = Vector2(float(fd["origin"][0]), float(fd["origin"][1]))
	return Rect2(origin.x - 85, origin.y - 65,
			(int(fd["cols"]) - 1) * cell.x + 170, (int(fd["rows"]) - 1) * cell.y + 130)

func _ready():
	z_index = -1
	for fd in GameData.fields():
		_fences.append({"rect": field_rect(fd), "gate": str(fd.get("gate", ""))})
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

# Keeps grass decorations off the house, the crop fields and the pond
func _on_clear_ground(p: Vector2) -> bool:
	if HOUSE_WALL.grow(50).has_point(p):
		return false
	for f in _fences:
		if f.rect.grow(10).has_point(p):
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
	for f in _fences:
		_draw_field_fence(f.rect, f.gate)
	_draw_house()
	_draw_well()
	for i in range(TREE_POSITIONS.size()):
		_draw_tree(TREE_POSITIONS[i], 1.0 + 0.25 * sin(i * 2.4), float(i))
	_draw_town_gate()
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

# Rail-and-post fence around a crop field, with a gate gap on one side.
# Purely decorative — the player walks through it like the original field
# fence did.
func _draw_field_fence(r: Rect2, gate: String):
	var rail = Color(0.55, 0.4, 0.24)
	var post = Color(0.45, 0.32, 0.18)
	var gap = 130.0
	var gx0 = r.get_center().x - gap / 2.0
	var gx1 = r.get_center().x + gap / 2.0
	var gy0 = r.get_center().y - gap / 2.0
	var gy1 = r.get_center().y + gap / 2.0
	# horizontal rail pairs (top, bottom)
	for side in ["top", "bottom"]:
		for off in [0.0, 14.0]:
			var y = r.position.y + off if side == "top" else r.end.y - off - 5
			if gate == side:
				draw_rect(Rect2(r.position.x, y, gx0 - r.position.x, 5), rail)
				draw_rect(Rect2(gx1, y, r.end.x - gx1, 5), rail)
			else:
				draw_rect(Rect2(r.position.x, y, r.size.x, 5), rail)
	# vertical picket pairs (left, right)
	for side in ["left", "right"]:
		var x = r.position.x if side == "left" else r.end.x
		var y = r.position.y
		while y < r.end.y:
			if not (gate == side and y > gy0 and y < gy1):
				draw_rect(Rect2(x - 2, y, 5, 18), rail)
				draw_rect(Rect2(x - 2, y + 32, 5, 18), rail)
			y += 50
	# posts every 100 px along the perimeter
	for x in range(int(r.position.x), int(r.end.x) + 1, 100):
		if not (gate == "top" and x > gx0 and x < gx1):
			draw_rect(Rect2(x - 4, r.position.y - 8, 8, 30), post)
		if not (gate == "bottom" and x > gx0 and x < gx1):
			draw_rect(Rect2(x - 4, r.end.y - 8, 8, 30), post)
	for y in range(int(r.position.y), int(r.end.y) + 1, 100):
		if not (gate == "left" and y > gy0 and y < gy1):
			draw_rect(Rect2(r.position.x - 4, y - 8, 8, 30), post)
		if not (gate == "right" and y > gy0 and y < gy1):
			draw_rect(Rect2(r.end.x - 4, y - 8, 8, 30), post)

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

# Road stub and signpost where the east hedge opens toward town
func _draw_town_gate():
	draw_rect(Rect2(WORLD.x - 120, 830, 120, 80), Color(0.55, 0.42, 0.26))
	draw_rect(Rect2(WORLD.x - 120, 838, 120, 64), Color(0.66, 0.52, 0.33))
	var sp = Vector2(2392, 800)
	draw_rect(Rect2(sp.x - 4, sp.y - 52, 8, 56), Color(0.45, 0.32, 0.18))
	draw_rect(Rect2(sp.x - 42, sp.y - 78, 84, 30), Color(0.55, 0.4, 0.24))
	draw_rect(Rect2(sp.x - 42, sp.y - 78, 84, 4), Color(0.65, 0.5, 0.3))
	var font = ThemeDB.fallback_font
	var label = "TOWN >"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, Vector2(sp.x - ls.x / 2, sp.y - 56), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.8))

func _draw_hedge_border():
	var hedge = Color(0.16, 0.3, 0.14)
	draw_rect(Rect2(0, 0, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, WORLD.y - 36, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, 0, 36, WORLD.y), hedge)
	# east hedge leaves a gap for the town gate
	draw_rect(Rect2(WORLD.x - 36, 0, 36, 800), hedge)
	draw_rect(Rect2(WORLD.x - 36, 940, 36, WORLD.y - 940), hedge)
	for x in range(45, int(WORLD.x), 90):
		draw_circle(Vector2(x, 36), 16.0, hedge)
		draw_circle(Vector2(x, WORLD.y - 36), 16.0, hedge)
	for y in range(45, int(WORLD.y), 90):
		draw_circle(Vector2(36, y), 16.0, hedge)
		if y < 790 or y > 950:
			draw_circle(Vector2(WORLD.x - 36, y), 16.0, hedge)
