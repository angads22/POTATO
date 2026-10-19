extends Node2D
class_name TownBackground

# The town backdrop: a cobbled plaza with a fountain at its heart, the
# championship kitchen at the head of the square, the seed stall and tool
# shed (storefronts that open the Farm Book), the knife stand, a couple of
# cottages for dressing and the Concert Hall bandstand on the south side. All
# procedural, like the rest of the game. Geometry constants here are the
# single source of truth; TownController reads them for collision, clicks and
# interaction points. A gate in the west hedge leads back to the farm.
# night01 follows the real local clock (set by the controller).

const WORLD = Vector2(1920, 1080)

const KITCHEN_WALL = Rect2(810, 150, 300, 170)
const SEED_STAND = Rect2(330, 380, 140, 115)
const KNIFE_STAND = Rect2(1450, 380, 140, 115)
const TOOL_STAND = Rect2(330, 760, 150, 115)
const FOUNTAIN_C = Vector2(960, 580)
const COTTAGE_A = Rect2(120, 150, 220, 140)
const COTTAGE_B = Rect2(1560, 140, 220, 140)
const CONCERT_HALL = Rect2(800, 880, 320, 140)  # was the boarded "coming soon" lot
const FARM_GATE_POS = Vector2(110, 560)  # hedge gap on the west edge

const STREETS = [
	[Vector2(60, 560), Vector2(960, 580)],
	[Vector2(960, 580), Vector2(960, 360)],
	[Vector2(960, 580), Vector2(420, 510)],
	[Vector2(960, 580), Vector2(1500, 510)],
	[Vector2(960, 580), Vector2(430, 880)],
	[Vector2(960, 580), Vector2(1480, 870)],
	[Vector2(960, 580), Vector2(960, 860)],
]

const LAMP_POSTS = [
	Vector2(760, 470), Vector2(1160, 470), Vector2(760, 720), Vector2(1160, 720)
]

const TREE_POSITIONS = [
	Vector2(170, 950), Vector2(560, 170), Vector2(1340, 160),
	Vector2(1780, 560), Vector2(1750, 950), Vector2(420, 620),
	Vector2(1500, 630), Vector2(120, 380)
]

var t := 0.0
var night01 := 0.0  # 0 = noon, 1 = midnight; set each frame by the controller

var _tufts: Array = []
var _flowers: Array = []

func _ready():
	z_index = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x70A7  # stable decoration layout across sessions
	var flower_cols = [Color(0.95, 0.85, 0.3), Color(0.9, 0.5, 0.6), Color(0.85, 0.85, 0.95)]
	for i in range(140):
		var p = Vector2(rng.randf_range(70, WORLD.x - 70), rng.randf_range(70, WORLD.y - 70))
		if _on_clear_ground(p):
			_tufts.append({"pos": p, "ph": rng.randf() * TAU})
	for i in range(40):
		var p = Vector2(rng.randf_range(80, WORLD.x - 80), rng.randf_range(80, WORLD.y - 80))
		if _on_clear_ground(p):
			_flowers.append({"pos": p, "col": flower_cols[rng.randi() % flower_cols.size()]})

# Keeps grass decorations off the buildings and the plaza
func _on_clear_ground(p: Vector2) -> bool:
	for r in [KITCHEN_WALL.grow(50), SEED_STAND.grow(25), KNIFE_STAND.grow(25),
			TOOL_STAND.grow(25), COTTAGE_A.grow(40), COTTAGE_B.grow(40),
			CONCERT_HALL.grow(20)]:
		if r.has_point(p):
			return false
	return p.distance_to(FOUNTAIN_C) > 240.0

var _acc := 0.0

# Grass sway and the fountain only need ~20 redraws a second (the backdrop is
# the biggest canvas item in the scene).
func _process(delta):
	t += delta
	_acc += delta
	if _acc >= 1.0 / 20.0:
		_acc = 0.0
		queue_redraw()

func _draw():
	_draw_grass()
	_draw_streets()
	_draw_plaza()
	_draw_cottage(COTTAGE_A, Color(0.55, 0.45, 0.6))
	_draw_cottage(COTTAGE_B, Color(0.4, 0.5, 0.62))
	_draw_kitchen()
	_draw_stall(SEED_STAND, Color(0.3, 0.65, 0.35), "SEEDS")
	_draw_stall(KNIFE_STAND, Color(0.55, 0.6, 0.7), "KNIVES")
	_draw_stall(TOOL_STAND, Color(0.4, 0.55, 0.8), "TOOLS")
	_draw_fountain()
	for lp in LAMP_POSTS:
		_draw_lamp(lp)
	_draw_concert_hall()
	for i in range(TREE_POSITIONS.size()):
		_draw_tree(TREE_POSITIONS[i], 1.0 + 0.2 * sin(i * 2.1), float(i))
	_draw_farm_gate()
	_draw_hedge_border()

func _draw_grass():
	for i in range(0, int(WORLD.y), 120):
		var shade = Color(0.42, 0.62, 0.3) if (i / 120) % 2 == 0 else Color(0.38, 0.58, 0.27)
		draw_rect(Rect2(0, i, WORLD.x, 120), shade)
	for f in _flowers:
		var p: Vector2 = f.pos
		for k in range(4):
			var a = k * TAU / 4.0
			draw_circle(p + Vector2(cos(a), sin(a)) * 4.0, 3.0, f.col)
		draw_circle(p, 2.6, Color(0.98, 0.8, 0.25))
	for tf in _tufts:
		var p: Vector2 = tf.pos
		var sway = sin(t * 1.8 + tf.ph) * 2.5
		var col = Color(0.3, 0.5, 0.22)
		draw_line(p, p + Vector2(-4 + sway, -11), col, 2.0)
		draw_line(p, p + Vector2(sway, -14), col, 2.0)
		draw_line(p, p + Vector2(4 + sway, -10), col, 2.0)

func _draw_streets():
	for path in STREETS:
		var pts = PackedVector2Array(path)
		draw_polyline(pts, Color(0.52, 0.5, 0.46), 54.0)
		draw_polyline(pts, Color(0.62, 0.6, 0.55), 44.0)

func _draw_plaza():
	# cobbled circle under the fountain
	draw_circle(FOUNTAIN_C, 210.0, Color(0.52, 0.5, 0.46))
	draw_circle(FOUNTAIN_C, 198.0, Color(0.62, 0.6, 0.55))
	for ring in [70.0, 120.0, 170.0]:
		draw_arc(FOUNTAIN_C, ring, 0, TAU, 48, Color(0.52, 0.5, 0.46), 2.0)
	var n = 14
	for i in range(n):
		var a = i * TAU / n
		draw_line(FOUNTAIN_C + Vector2(cos(a), sin(a)) * 40.0,
				FOUNTAIN_C + Vector2(cos(a), sin(a)) * 196.0, Color(0.52, 0.5, 0.46, 0.5), 1.5)

func _draw_fountain():
	var c = FOUNTAIN_C
	# stone basin
	draw_set_transform(c, 0.0, Vector2(1.0, 0.8))
	draw_circle(Vector2.ZERO, 64.0, Color(0.6, 0.6, 0.62))
	draw_circle(Vector2.ZERO, 52.0, Color(0.3, 0.5, 0.66))
	for i in range(10):
		var a = i * TAU / 10.0
		draw_arc(Vector2.ZERO, 58.0, a, a + 0.45, 6, Color(0.45, 0.45, 0.48), 4.0)
	# shimmer
	for i in range(3):
		var ph = t * 0.9 + i * 2.0
		draw_arc(Vector2(8 * sin(ph), 0), 20.0 + 12.0 * i, PI * 0.15, PI * 0.6, 8,
				Color(1, 1, 1, 0.3 + 0.12 * sin(ph * 2.0)), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# centre spout and arcing jets
	draw_rect(Rect2(c.x - 7, c.y - 46, 14, 40), Color(0.55, 0.55, 0.58))
	draw_circle(Vector2(c.x, c.y - 48), 9.0, Color(0.62, 0.62, 0.65))
	for side in [-1.0, 1.0]:
		for i in range(4):
			var f = fposmod(t * 0.9 + i * 0.25, 1.0)
			var jx = side * (10.0 + 26.0 * f)
			var jy = -48.0 + 50.0 * f * f - 14.0 * f
			draw_circle(c + Vector2(jx, jy), 2.6 - f, Color(0.62, 0.85, 1.0, 0.9 - f * 0.5))

func _draw_lamp(p: Vector2):
	var glow = clampf(night01 * 1.6, 0.0, 1.0)
	draw_set_transform(p + Vector2(3, 2), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(p.x - 3, p.y - 74, 6, 76), Color(0.2, 0.22, 0.26))
	draw_rect(Rect2(p.x - 9, p.y - 92, 18, 20), Color(0.25, 0.27, 0.3))
	var pane = Color(0.85, 0.85, 0.7).lerp(Color(1.0, 0.85, 0.4), glow)
	draw_rect(Rect2(p.x - 6, p.y - 89, 12, 14), pane)
	if glow > 0.3:
		draw_circle(Vector2(p.x, p.y - 82), 22.0, Color(1.0, 0.85, 0.4, 0.13 * glow))

func _window_color() -> Color:
	# panes go from daylight blue to a warm lit glow as night falls
	return Color(0.65, 0.78, 0.9).lerp(Color(1.0, 0.85, 0.4), clampf(night01 * 1.5, 0.0, 1.0))

func _draw_cottage(w: Rect2, wall: Color):
	draw_rect(w, wall)
	for y in range(int(w.position.y) + 22, int(w.end.y), 22):
		draw_rect(Rect2(w.position.x, y, w.size.x, 2), wall.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(w.position.x - 20, w.position.y), Vector2(w.end.x + 20, w.position.y),
		Vector2(w.get_center().x, w.position.y - 78)
	]), Color(0.32, 0.2, 0.12))
	draw_rect(Rect2(w.get_center().x - 22, w.end.y - 70, 44, 70), Color(0.32, 0.2, 0.1))
	draw_circle(Vector2(w.get_center().x + 12, w.end.y - 36), 3.5, Color(0.85, 0.68, 0.3))
	for wx in [w.position.x + 24, w.end.x - 64]:
		draw_rect(Rect2(wx - 4, w.position.y + 32, 48, 44), Color(0.4, 0.25, 0.15))
		draw_rect(Rect2(wx, w.position.y + 36, 40, 36), _window_color())
		draw_rect(Rect2(wx + 18, w.position.y + 36, 3, 36), Color(0.4, 0.25, 0.15))

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
			for i in range(2):
				var px = r.position.x + 18 + i * 36
				draw_rect(Rect2(px, r.position.y + 16, 24, 32), Color(0.92, 0.88, 0.78))
				draw_circle(Vector2(px + 12, r.position.y + 30), 7.0, Color(0.72, 0.45, 0.2).lightened(i * 0.25))
			WorldHUD.icon_book(self, Vector2(r.position.x + 108, r.position.y + 30), 13.0)
		"KNIVES":
			for i in range(3):
				var px = r.position.x + 26 + i * 36
				draw_colored_polygon(PackedVector2Array([
					Vector2(px, r.position.y + 14), Vector2(px + 14, r.position.y + 14),
					Vector2(px + 7, r.position.y + 44)
				]), Color(0.85, 0.87, 0.92))
				draw_rect(Rect2(px + 3, r.position.y + 6, 8, 9), Color(0.35, 0.22, 0.12))
		"TOOLS":
			# a hoe, a sprinkler head and the Farm Book on the board
			var cx = r.position.x + 22
			draw_line(Vector2(cx, r.position.y + 48), Vector2(cx + 22, r.position.y + 12), Color(0.6, 0.45, 0.28), 4.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx + 16, r.position.y + 8), Vector2(cx + 34, r.position.y + 14),
				Vector2(cx + 28, r.position.y + 24)
			]), Color(0.85, 0.55, 0.3))
			var sc = Vector2(r.position.x + 78, r.position.y + 34)
			draw_line(sc + Vector2(0, 14), sc + Vector2(0, -6), Color(0.66, 0.72, 0.78), 4.0)
			draw_circle(sc + Vector2(0, -8), 6.0, Color(0.66, 0.72, 0.78))
			draw_arc(sc + Vector2(0, -8), 13.0, -2.6, -0.5, 8, Color(0.5, 0.8, 1.0), 2.5)
			WorldHUD.icon_book(self, Vector2(r.position.x + 120, r.position.y + 30), 12.0)
	# name plate
	var font = ThemeDB.fallback_font
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, Vector2(r.get_center().x - ls.x / 2, r.end.y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.8))

# The Concert Hall: a bandstand on the plaza's south side where Concert mode
# lives. The marquee bulbs chase and the potato band bobs in time with the
# town's music (the beat clock), and the bulbs glow brighter after dark.
func _draw_concert_hall():
	var r: Rect2 = CONCERT_HALL
	var beat := AudioManager.music_beat()
	var on_beat := beat >= 0.0
	var pulse := exp(-fposmod(beat, 1.0) * 5.0) if on_beat else 0.0
	# backdrop + stage platform
	draw_rect(Rect2(r.position.x, r.position.y + 20, r.size.x, r.size.y - 20), Color(0.28, 0.16, 0.3))
	draw_rect(Rect2(r.position.x + 8, r.position.y + 28, r.size.x - 16, r.size.y - 60), Color(0.36, 0.2, 0.38))
	draw_rect(Rect2(r.position.x - 6, r.end.y - 34, r.size.x + 12, 34), Color(0.55, 0.36, 0.2))
	draw_rect(Rect2(r.position.x - 6, r.end.y - 34, r.size.x + 12, 6), Color(0.7, 0.5, 0.3))
	for i in range(7):
		var x := r.position.x + i * (r.size.x + 12) / 7.0 - 6
		draw_line(Vector2(x, r.end.y - 28), Vector2(x, r.end.y), Color(0.45, 0.28, 0.15), 2.0)
	# speaker stacks either side, cones thumping on the beat
	for sx: float in [r.position.x + 22, r.end.x - 22]:
		draw_rect(Rect2(sx - 18, r.position.y + 50, 36, 56), Color(0.12, 0.1, 0.12))
		draw_circle(Vector2(sx, r.position.y + 66), 9.0 + pulse * 2.0, Color(0.3, 0.28, 0.32))
		draw_circle(Vector2(sx, r.position.y + 92), 6.0 + pulse * 1.5, Color(0.3, 0.28, 0.32))
	# the potato band: drummer, guitarist, singer — hopping on the beat
	var band = [[r.position.x + 95, Color(0.78, 0.55, 0.3), 0.0], [r.get_center().x, Color(0.86, 0.72, 0.42), 0.5],
			[r.end.x - 95, Color(0.66, 0.4, 0.55), 0.25]]
	for m in band:
		var hop: float = absf(sin((beat + float(m[2])) * PI)) * 7.0 if on_beat else 0.0
		var c := Vector2(float(m[0]), r.end.y - 52 - hop)
		var mc: Color = m[1]
		draw_set_transform(c, 0.0, Vector2(1.0, 0.85))
		draw_circle(Vector2.ZERO, 16.0, mc)
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 20, mc.darkened(0.45), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(c + Vector2(-5, -3), 2.2, Color(0.15, 0.1, 0.05))
		draw_circle(c + Vector2(5, -3), 2.2, Color(0.15, 0.1, 0.05))
	# drum kit + mic stand props
	draw_circle(Vector2(r.position.x + 95, r.end.y - 34), 11.0, Color(0.85, 0.85, 0.9))
	draw_line(Vector2(r.end.x - 75, r.end.y - 34), Vector2(r.end.x - 75, r.end.y - 72), Color(0.3, 0.3, 0.32), 2.0)
	# scalloped awning, like the market stalls but in show colours
	var aw := Rect2(r.position.x - 10, r.position.y, r.size.x + 20, 26)
	for i in range(8):
		var sw := aw.size.x / 8.0
		var col := Color(0.55, 0.2, 0.5) if i % 2 == 0 else Color(0.95, 0.78, 0.3)
		draw_rect(Rect2(aw.position.x + i * sw, aw.position.y, sw, aw.size.y), col)
		draw_circle(Vector2(aw.position.x + i * sw + sw / 2, aw.end.y), sw / 2, col)
	# marquee sign with chasing bulbs
	var font = ThemeDB.fallback_font
	var label = "CONCERT HALL"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	var sign_r := Rect2(r.get_center().x - ls.x / 2 - 18, r.position.y - 34, ls.x + 36, 34)
	draw_rect(sign_r, Color(0.2, 0.1, 0.12))
	draw_rect(sign_r, Color(0.95, 0.78, 0.3), false, 2.0)
	draw_string(font, Vector2(sign_r.get_center().x - ls.x / 2, sign_r.end.y - 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.86, 0.4))
	var bulbs := 14
	var lit := posmod(floori(beat * 2.0), bulbs) if on_beat else -1
	for i in bulbs:
		var u := float(i) / (bulbs - 1)
		var bp := Vector2(sign_r.position.x + u * sign_r.size.x, sign_r.position.y - 4)
		var glow := 0.35 + 0.65 * night01
		var on := lit >= 0 and (i % 3 == lit % 3)
		var col := Color(1.0, 0.85, 0.4, 0.95) if on else Color(0.6, 0.45, 0.25, 0.6)
		if on and night01 > 0.2:
			draw_circle(bp, 7.0, Color(1.0, 0.8, 0.35, 0.25 * glow))
		draw_circle(bp, 3.0, col)
	# a note drifting up from the stage now and then
	if on_beat:
		var ph := fposmod(beat / 4.0, 1.0)
		var nx := r.get_center().x + sin(beat) * 40.0
		var np := Vector2(nx, r.position.y + 14 - ph * 60.0)
		var ncol := Color(1.0, 0.9, 0.6, 1.0 - ph)
		draw_circle(np, 4.5, ncol)
		draw_line(np + Vector2(4, 0), np + Vector2(4, -16), ncol, 2.0)
		draw_line(np + Vector2(4, -16), np + Vector2(10, -11), ncol, 2.0)

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

# Road stub and signpost where the west hedge opens toward the farm
func _draw_farm_gate():
	draw_rect(Rect2(0, 520, 110, 80), Color(0.55, 0.42, 0.26))
	draw_rect(Rect2(0, 528, 110, 64), Color(0.66, 0.52, 0.33))
	var sp = Vector2(168, 490)
	draw_rect(Rect2(sp.x - 4, sp.y - 52, 8, 56), Color(0.45, 0.32, 0.18))
	draw_rect(Rect2(sp.x - 42, sp.y - 78, 84, 30), Color(0.55, 0.4, 0.24))
	draw_rect(Rect2(sp.x - 42, sp.y - 78, 84, 4), Color(0.65, 0.5, 0.3))
	var font = ThemeDB.fallback_font
	var label = "FARM"
	var ls = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
	draw_string(font, Vector2(sp.x - ls.x / 2 + 8, sp.y - 57), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.9, 0.8))
	draw_colored_polygon(PackedVector2Array([Vector2(sp.x - ls.x / 2 + 2, sp.y - 72), Vector2(sp.x - ls.x / 2 - 12, sp.y - 64),
			Vector2(sp.x - ls.x / 2 + 2, sp.y - 56)]), Color(0.95, 0.9, 0.8))

func _draw_hedge_border():
	var hedge = Color(0.16, 0.3, 0.14)
	draw_rect(Rect2(0, 0, WORLD.x, 36), hedge)
	draw_rect(Rect2(0, WORLD.y - 36, WORLD.x, 36), hedge)
	# west hedge leaves a gap for the farm gate
	draw_rect(Rect2(0, 0, 36, 480), hedge)
	draw_rect(Rect2(0, 640, 36, WORLD.y - 640), hedge)
	draw_rect(Rect2(WORLD.x - 36, 0, 36, WORLD.y), hedge)
	for x in range(45, int(WORLD.x), 90):
		draw_circle(Vector2(x, 36), 16.0, hedge)
		draw_circle(Vector2(x, WORLD.y - 36), 16.0, hedge)
	for y in range(45, int(WORLD.y), 90):
		if y < 470 or y > 650:
			draw_circle(Vector2(36, y), 16.0, hedge)
		draw_circle(Vector2(WORLD.x - 36, y), 16.0, hedge)
