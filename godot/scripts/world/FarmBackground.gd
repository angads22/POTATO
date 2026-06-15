extends Node2D
class_name FarmBackground

# The farm backdrop: a tidy farmyard strip across the top (the farmhouse, a
# well, a pond, the market truck and the research shed), one straight dirt path
# dividing that strip from a single large open pasture below, and a tree line
# along the very top — all procedural, like the rest of the game. The pasture
# is one free-form plowable grid (no fenced fields); only the open field below
# the path is farmland. The seed/knife/tool stalls and the championship kitchen
# live in town (TownBackground); a gate at the east end of the path leads there.
# Geometry constants here are the single source of truth; FarmController reads
# them for collision and interaction points.

const WORLD = Vector2(2560, 1600)

# ── top farmyard strip: every fixture lives up here, above the dividing path ──
const HOUSE_WALL = Rect2(180, 200, 260, 150)
const WELL_POS = Vector2(900, 360)
const POND_C = Vector2(2200, 360)
const POND_R = Vector2(220, 120)
const TOWN_GATE_POS = Vector2(2470, 620)  # hedge gap at the east end of the path
# market truck in the yard — load spuds here to ship them to market
const TRUCK_RECT = Rect2(1180, 150, 230, 130)
const TRUCK_POS = Vector2(1295, 215)
# research shed in the yard, clear of the house/well/pond
const RESEARCH_WALL = Rect2(1620, 250, 230, 150)
const RESEARCH_POS = Vector2(1735, 325)
# a purely decorative fenced kitchen garden tucked beside the farmhouse (drawn
# in the backdrop layer, below the plowable grid — cosmetic only)
const GARDEN_RECT = Rect2(180, 380, 240, 140)

# One straight dirt track runs the full width, splitting the yard above from the
# open pasture below.
const PATHS = [
	[Vector2(90, 620), Vector2(2470, 620)],
]

# Cells whose centre sits at or above this line are the farmyard, not farmland —
# FarmController refuses to plow there, keeping the field a single clean block
# below the path. Set just above the path band so the path row itself still
# reads as farmland-shaped ground (but stays unplowable, being on the track).
const FIELD_TOP_Y := 580.0

# Plots and grass decorations stay this far (px) clear of a path's centre-line so
# the dirt tracks read as walkways, never as fields. The drawn earth is ~44px
# wide and the soft grass overhang ~60, so 34 keeps tilled soil off the whole
# visible track. FarmController reads this when deciding what's plowable.
const PATH_CLEARANCE := 34.0

# A tree line strung along the very top of the yard, between the buildings.
const TREE_POSITIONS = [
	Vector2(80, 110), Vector2(560, 120), Vector2(1080, 100),
	Vector2(1530, 120), Vector2(2010, 100), Vector2(2360, 130),
	Vector2(740, 470), Vector2(2480, 470)
]

var t := 0.0
var night01 := 0.0  # 0 = noon, 1 = midnight; set each frame by the controller

var _tufts: Array = []    # {pos, ph}
var _flowers: Array = []  # {pos, col}
var _rocks: Array = []
var _dapples: Array = []  # {pos, r, col} — soft layered ground mottling

func _ready():
	z_index = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xFA12  # stable decoration layout across sessions
	# dappled, layered ground: large soft blobs that break up the mown stripes
	var dapple_cols = [
		Color(0.46, 0.66, 0.33, 0.35), Color(0.36, 0.55, 0.26, 0.35),
		Color(0.5, 0.7, 0.36, 0.28),
	]
	for i in range(150):
		var p = Vector2(rng.randf_range(40, WORLD.x - 40), rng.randf_range(40, WORLD.y - 40))
		_dapples.append({"pos": p, "r": rng.randf_range(60.0, 150.0),
				"col": dapple_cols[rng.randi() % dapple_cols.size()]})
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

# Keeps grass decorations off the buildings, the pond, the kitchen garden and
# the dirt paths
func _on_clear_ground(p: Vector2) -> bool:
	if HOUSE_WALL.grow(50).has_point(p):
		return false
	if TRUCK_RECT.grow(30).has_point(p) or RESEARCH_WALL.grow(40).has_point(p):
		return false
	if GARDEN_RECT.grow(8).has_point(p):
		return false
	if on_path(p):
		return false
	var d = (p - POND_C) / (POND_R * 1.3)
	return d.length() > 1.0

# ── path geometry (FarmController uses this to keep plots off the tracks) ──

# True when a point sits on (or within `clearance` of) any dirt path.
static func on_path(p: Vector2, clearance := PATH_CLEARANCE) -> bool:
	return path_distance(p) <= clearance

# Distance from a point to the nearest dirt-path centre-line (INF if no paths).
static func path_distance(p: Vector2) -> float:
	var best := INF
	for path in PATHS:
		for i in range(path.size() - 1):
			best = minf(best, _segment_distance(p, path[i], path[i + 1]))
	return best

# Shortest distance from point p to the line segment a→b.
static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var tt := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * tt)

func _process(delta):
	t += delta
	queue_redraw()

func _draw():
	_draw_grass()
	_draw_paths()
	_draw_kitchen_garden()
	_draw_pond()
	_draw_house()
	_draw_well()
	_draw_truck()
	_draw_research_shed()
	for i in range(TREE_POSITIONS.size()):
		_draw_tree(TREE_POSITIONS[i], 1.0 + 0.25 * sin(i * 2.4), float(i))
	_draw_town_gate()
	_draw_hedge_border()

func _draw_grass():
	# mown-stripe bands
	for i in range(0, int(WORLD.y), 120):
		var shade = Color(0.42, 0.62, 0.3) if (i / 120) % 2 == 0 else Color(0.38, 0.58, 0.27)
		draw_rect(Rect2(0, i, WORLD.x, 120), shade)
	# dappled, layered ground — soft mottled blobs over the stripes for depth
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

# Soft-edged connected dirt paths: a soft grass-overhang halo, a gravel base,
# a lighter worn centre rut, rounded joints at every vertex, and a scatter of
# gravel speckles — Stardew-style packed-earth tracks.
func _draw_paths():
	var grass_edge := Color(0.3, 0.46, 0.22, 0.5)  # darker green overhang
	var gravel := Color(0.5, 0.38, 0.23)
	var earth := Color(0.62, 0.48, 0.30)
	var worn := Color(0.7, 0.57, 0.37)
	# pass 1: grass overhang halo (slightly wider, soft green) under everything
	for path in PATHS:
		var pts = PackedVector2Array(path)
		draw_polyline(pts, grass_edge, 60.0)
	# pass 2: gravel base, then packed earth, then a worn lighter centre rut
	for path in PATHS:
		var pts = PackedVector2Array(path)
		draw_polyline(pts, gravel, 52.0)
		draw_polyline(pts, earth, 44.0)
		draw_polyline(pts, worn, 20.0)
		# rounded joints so corners read as smooth bends, not mitred cuts
		for i in range(path.size()):
			draw_circle(path[i], 22.0, earth)
			draw_circle(path[i], 10.0, worn)
	# gravel speckle — stable per-frame via a fixed-seed walk along each path
	var grng := RandomNumberGenerator.new()
	grng.seed = 0x6A77  # stable gravel speckle layout across frames
	for path in PATHS:
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var steps := int(a.distance_to(b) / 26.0)
			for s in range(steps):
				var base := a.lerp(b, float(s) / maxf(1.0, steps))
				var off := Vector2(grng.randf_range(-16, 16), grng.randf_range(-16, 16))
				var shade: Color = gravel.darkened(0.12) if (s % 2 == 0) else worn.lightened(0.05)
				draw_circle(base + off, grng.randf_range(1.5, 3.0), shade)

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

# The market truck: a little flatbed parked by the top hedge. Load spuds here
# and send it off to market. Drawn static; the prompt conveys away/back status.
func _draw_truck():
	var r = TRUCK_RECT
	# ground shadow
	draw_set_transform(Vector2(r.get_center().x, r.end.y + 6), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, r.size.x * 0.55, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# cargo bed + slatted side
	var bed = Rect2(r.position.x, r.position.y + 36, r.size.x - 78, r.size.y - 70)
	draw_rect(bed, Color(0.55, 0.4, 0.24))
	for i in range(4):
		draw_rect(Rect2(bed.position.x, bed.position.y + 8 + i * 16, bed.size.x, 4), Color(0.45, 0.32, 0.18))
	# crates of potatoes in the bed
	for i in range(2):
		var cx = bed.position.x + 26 + i * 60
		draw_rect(Rect2(cx, bed.position.y + 10, 44, 30), Color(0.5, 0.35, 0.2))
		for k in range(3):
			draw_circle(Vector2(cx + 10 + k * 12, bed.position.y + 16), 6.0, Color(0.78, 0.55, 0.3))
	# cab
	var cab = Rect2(r.end.x - 76, r.position.y + 18, 76, r.size.y - 52)
	draw_rect(cab, Color(0.82, 0.32, 0.26))
	draw_rect(Rect2(cab.position.x + 8, cab.position.y + 10, 48, 34), Color(0.6, 0.78, 0.9))  # windshield
	draw_rect(Rect2(cab.position.x + 4, cab.end.y - 10, cab.size.x - 8, 8), Color(0.6, 0.22, 0.18))  # bumper
	# wheels
	for wx in [r.position.x + 40, r.end.x - 110, r.end.x - 34]:
		draw_circle(Vector2(wx, r.end.y - 14), 17.0, Color(0.12, 0.12, 0.14))
		draw_circle(Vector2(wx, r.end.y - 14), 7.0, Color(0.5, 0.5, 0.54))
	# "MARKET" placard on a post
	var sp = Vector2(r.position.x - 4, r.position.y - 6)
	draw_rect(Rect2(sp.x - 2, sp.y - 40, 6, 46), Color(0.45, 0.32, 0.18))
	draw_rect(Rect2(sp.x - 44, sp.y - 64, 96, 28), Color(0.85, 0.68, 0.3))
	var font = ThemeDB.fallback_font
	var label = "MARKET"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(sp.x + 4 - ls.x / 2, sp.y - 44), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.2, 0.13, 0.06))

# The research shed: a workshop where coins + research points buy upgrades.
func _draw_research_shed():
	var w = RESEARCH_WALL
	# walls with vertical board siding
	draw_rect(w, Color(0.52, 0.58, 0.5))
	for x in range(int(w.position.x) + 20, int(w.end.x), 20):
		draw_rect(Rect2(x, w.position.y, 2, w.size.y), Color(0.42, 0.48, 0.4))
	# corrugated gable roof
	draw_colored_polygon(PackedVector2Array([
		Vector2(w.position.x - 18, w.position.y), Vector2(w.end.x + 18, w.position.y),
		Vector2(w.get_center().x, w.position.y - 64)
	]), Color(0.36, 0.4, 0.46))
	# door + window
	draw_rect(Rect2(w.get_center().x - 24, w.end.y - 70, 48, 70), Color(0.3, 0.26, 0.2))
	draw_rect(Rect2(w.position.x + 22, w.position.y + 30, 46, 40), Color(0.4, 0.36, 0.3))
	draw_rect(Rect2(w.position.x + 26, w.position.y + 34, 38, 32), _window_color())
	# a flask + gear sign
	var sc = Vector2(w.end.x - 48, w.position.y + 50)
	draw_circle(sc, 13.0, Color(0.7, 0.72, 0.78))
	for k in range(6):
		var a = k * TAU / 6.0
		draw_circle(sc + Vector2(cos(a), sin(a)) * 13.0, 3.5, Color(0.7, 0.72, 0.78))
	draw_circle(sc, 5.0, Color(0.45, 0.62, 0.75))
	# name plate
	var font = ThemeDB.fallback_font
	GameHUD.panel_style(Color(0.2, 0.24, 0.2, 0.95)).draw(get_canvas_item(), Rect2(w.get_center().x - 84, w.end.y + 6, 168, 30))
	var label = "RESEARCH SHED"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, Vector2(w.get_center().x - ls.x / 2, w.end.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.95, 0.7))

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

# Lusher layered tree: a soft ground shadow, a tapered trunk, a darker canopy
# base, mid-tone billows, then sun-dappled highlight tufts on top.
func _draw_tree(pos: Vector2, s: float, ph: float):
	var sway = sin(t * 0.8 + ph) * 3.0 * s
	# elongated soft ground shadow
	draw_set_transform(pos + Vector2(8, 6) * s, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 48.0 * s, Color(0, 0, 0, 0.16))
	draw_circle(Vector2.ZERO, 38.0 * s, Color(0, 0, 0, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# tapered trunk with a touch of bark shading
	draw_rect(Rect2(pos.x - 9 * s, pos.y - 60 * s, 18 * s, 62 * s), Color(0.42, 0.28, 0.16))
	draw_rect(Rect2(pos.x - 9 * s, pos.y - 60 * s, 6 * s, 62 * s), Color(0.34, 0.22, 0.12))
	# dark canopy underlayer for depth
	for o in [Vector2(-28, -70), Vector2(28, -68), Vector2(0, -92), Vector2(-8, -52), Vector2(12, -54)]:
		draw_circle(pos + Vector2(sway, 0) + o * s, 30.0 * s, Color(0.18, 0.36, 0.15))
	# mid-tone billows
	draw_circle(pos + Vector2(sway - 26 * s, -78 * s), 34 * s, Color(0.24, 0.45, 0.2))
	draw_circle(pos + Vector2(sway + 26 * s, -76 * s), 32 * s, Color(0.27, 0.48, 0.22))
	draw_circle(pos + Vector2(sway, -100 * s), 36 * s, Color(0.3, 0.52, 0.24))
	draw_circle(pos + Vector2(sway + 6 * s, -64 * s), 26 * s, Color(0.28, 0.5, 0.23))
	# sun-dappled highlight tufts
	draw_circle(pos + Vector2(sway - 12 * s, -108 * s), 16 * s, Color(0.4, 0.62, 0.32))
	draw_circle(pos + Vector2(sway + 18 * s, -94 * s), 11 * s, Color(0.45, 0.66, 0.35))
	draw_circle(pos + Vector2(sway - 24 * s, -84 * s), 9 * s, Color(0.43, 0.64, 0.34))

# Decorative fenced kitchen garden beside the farmhouse — picket fence, tilled
# beds and a few leafy veg. Backdrop only (the real plowable grid draws above).
func _draw_kitchen_garden():
	var r = GARDEN_RECT
	# soft drop shadow + tilled soil patch
	draw_rect(Rect2(r.position.x + 6, r.position.y + 8, r.size.x, r.size.y), Color(0, 0, 0, 0.12))
	var soil = Rect2(r.position.x + 10, r.position.y + 10, r.size.x - 20, r.size.y - 20)
	draw_rect(soil, Color(0.43, 0.3, 0.18))
	# raised rows with furrow highlights
	for i in range(3):
		var ry = soil.position.y + 16 + i * 46
		draw_rect(Rect2(soil.position.x + 8, ry, soil.size.x - 16, 26), Color(0.5, 0.35, 0.2))
		draw_rect(Rect2(soil.position.x + 8, ry, soil.size.x - 16, 4), Color(0.6, 0.45, 0.27))
		# leafy veg tufts along each row
		for k in range(5):
			var vx = soil.position.x + 24 + k * (soil.size.x - 48) / 4.0
			var vy = ry + 14
			var sway = sin(t * 1.3 + k + i) * 1.5
			for leaf in [Vector2(-6, 0), Vector2(6, 0), Vector2(0, -7)]:
				draw_circle(Vector2(vx + leaf.x + sway, vy + leaf.y), 5.0, Color(0.3, 0.55, 0.26))
			draw_circle(Vector2(vx + sway, vy), 3.0, Color(0.85, 0.55, 0.3))
	# picket fence around the plot (posts + two rails), with a gap as a gate
	var fence = Color(0.82, 0.78, 0.68)
	var fence_dk = Color(0.62, 0.58, 0.48)
	draw_rect(Rect2(r.position.x, r.position.y + 6, r.size.x, 4), fence_dk)
	draw_rect(Rect2(r.position.x, r.position.y + 22, r.size.x, 4), fence_dk)
	draw_rect(Rect2(r.position.x, r.end.y - 12, r.size.x, 4), fence_dk)
	for px in range(int(r.position.x), int(r.end.x) + 1, 26):
		# leave a gate gap near the middle of the bottom edge
		var post = Vector2(px, r.position.y)
		draw_rect(Rect2(post.x - 3, post.y, 6, r.size.y), fence)
		draw_colored_polygon(PackedVector2Array([
			Vector2(post.x - 3, post.y), Vector2(post.x + 3, post.y), Vector2(post.x, post.y - 8)
		]), fence)

# Road stub and signpost where the east hedge opens toward town (east end of path)
func _draw_town_gate():
	draw_rect(Rect2(WORLD.x - 120, 580, 120, 80), Color(0.55, 0.42, 0.26))
	draw_rect(Rect2(WORLD.x - 120, 588, 120, 64), Color(0.66, 0.52, 0.33))
	var sp = Vector2(2392, 552)
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
	# east hedge leaves a gap for the town gate at the end of the path
	draw_rect(Rect2(WORLD.x - 36, 0, 36, 560), hedge)
	draw_rect(Rect2(WORLD.x - 36, 690, 36, WORLD.y - 690), hedge)
	for x in range(45, int(WORLD.x), 90):
		draw_circle(Vector2(x, 36), 16.0, hedge)
		draw_circle(Vector2(x, WORLD.y - 36), 16.0, hedge)
	for y in range(45, int(WORLD.y), 90):
		draw_circle(Vector2(36, y), 16.0, hedge)
		if y < 550 or y > 700:
			draw_circle(Vector2(WORLD.x - 36, y), 16.0, hedge)
