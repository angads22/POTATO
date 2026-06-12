extends Node2D
class_name FarmPlot

# One tilled plot in the farm field. Growth is measured against the wall
# clock (planted_at is a unix timestamp), so crops keep growing while the
# game is closed. Watering cuts the remaining grow time roughly in half;
# a growth enhancer (boost < 1.0) stacks on top and can add bonus yield.
# Locked plots are overgrown ground waiting to be bought.

enum PState { EMPTY, PLANTED, READY }

const WATER_FACTOR = 0.55

var index := 0
var state := PState.EMPTY
var potato_id := ""
var planted_at := 0.0
var watered := false
var locked := false
var boost := 1.0          # growth-time multiplier from an enhancer (1.0 = none)
var bonus_yield := 0      # extra potatoes at harvest from an enhancer
var last_potato_id := ""  # what grew here last — the Auto-Seeder replants it
var t := 0.0

func plant(id: String):
	potato_id = id
	last_potato_id = id
	planted_at = Time.get_unix_time_from_system()
	watered = false
	boost = 1.0
	bonus_yield = 0
	state = PState.PLANTED

func water():
	watered = true

# Apply a growth enhancer; one per crop
func enhance(factor: float, extra_yield: int) -> bool:
	if state != PState.PLANTED or boost < 1.0:
		return false
	boost = factor
	bonus_yield = extra_yield
	return true

# 0..1 maturity; READY state is derived from this so it also survives reloads
func progress() -> float:
	if state == PState.EMPTY:
		return 0.0
	var grow = float(GameData.potato_by_id(potato_id).get("grow_time", 30))
	if watered:
		grow *= WATER_FACTOR
	grow *= boost
	return clampf((Time.get_unix_time_from_system() - planted_at) / grow, 0.0, 1.0)

# Returns the number of potatoes pulled; resets the plot
func harvest(rng: RandomNumberGenerator) -> int:
	var yield_range: Array = GameData.potato_by_id(potato_id).get("yield", [2, 3])
	var n = rng.randi_range(int(yield_range[0]), int(yield_range[1])) + bonus_yield
	state = PState.EMPTY
	potato_id = ""
	watered = false
	boost = 1.0
	bonus_yield = 0
	return n

func to_dict() -> Dictionary:
	if state == PState.EMPTY:
		# remember what grew here so the Auto-Seeder survives reloads
		return {"last": last_potato_id} if last_potato_id != "" else {}
	return {
		"potato_id": potato_id, "planted_at": planted_at, "watered": watered,
		"boost": boost, "bonus_yield": bonus_yield, "last": last_potato_id
	}

func from_dict(d: Dictionary):
	if d.is_empty():
		return
	last_potato_id = str(d.get("last", ""))
	if not d.has("potato_id"):
		return
	potato_id = d["potato_id"]
	planted_at = float(d["planted_at"])
	watered = bool(d.get("watered", false))
	boost = float(d.get("boost", 1.0))
	bonus_yield = int(d.get("bonus_yield", 0))
	state = PState.PLANTED

func _process(delta):
	t += delta
	if state == PState.PLANTED and progress() >= 1.0:
		state = PState.READY
	queue_redraw()

func _draw():
	if locked:
		_draw_locked()
		return

	# soil bed — darker when watered
	var soil = StyleBoxFlat.new()
	soil.bg_color = Color(0.36, 0.24, 0.13) if watered else Color(0.46, 0.32, 0.18)
	soil.set_corner_radius_all(16)
	soil.border_color = soil.bg_color.darkened(0.3)
	soil.set_border_width_all(3)
	soil.draw(get_canvas_item(), Rect2(-65, -45, 130, 90))
	for i in range(3):
		draw_rect(Rect2(-52, -26 + i * 24, 104, 3), soil.bg_color.darkened(0.22))
	if watered and state == PState.PLANTED:
		for i in range(3):
			draw_circle(Vector2(-34 + i * 34, 32), 2.5, Color(0.5, 0.75, 0.95, 0.8))

	# enhancer sparkles drift up from boosted soil
	if boost < 1.0 and state == PState.PLANTED:
		for i in range(3):
			var rise = fposmod(t * 14.0 + i * 21.0, 46.0)
			var sx = -30.0 + i * 30.0 + sin(t * 2.0 + i) * 4.0
			draw_circle(Vector2(sx, 26.0 - rise), 2.2,
					Color(0.55, 0.95, 0.4, 0.8 * (1.0 - rise / 46.0)))

	match state:
		PState.PLANTED:
			_draw_growing(progress())
		PState.READY:
			_draw_ready()

func _draw_locked():
	# untilled, weed-choked ground with a little rope marker
	var soil = StyleBoxFlat.new()
	soil.bg_color = Color(0.4, 0.45, 0.26)
	soil.set_corner_radius_all(16)
	soil.border_color = Color(0.34, 0.38, 0.22)
	soil.set_border_width_all(3)
	soil.draw(get_canvas_item(), Rect2(-65, -45, 130, 90))
	for i in range(6):
		var wx = -50.0 + (i % 3) * 45.0 + (8.0 if i > 2 else 0.0)
		var wy = -22.0 + (i / 3) * 36.0
		var sway = sin(t * 1.6 + i) * 2.0
		var weed = Color(0.32, 0.42, 0.2)
		draw_line(Vector2(wx, wy + 12), Vector2(wx - 5 + sway, wy - 8), weed, 2.0)
		draw_line(Vector2(wx, wy + 12), Vector2(wx + sway, wy - 12), weed, 2.0)
		draw_line(Vector2(wx, wy + 12), Vector2(wx + 5 + sway, wy - 7), weed, 2.0)
	# rope corners
	for c in [Vector2(-58, -38), Vector2(58, -38), Vector2(-58, 38), Vector2(58, 38)]:
		draw_circle(c, 4.0, Color(0.7, 0.6, 0.4))

func _draw_growing(p: float):
	var sway = sin(t * 2.0 + index) * 2.0
	var h = 12.0 + p * 30.0
	var stem = Color(0.32, 0.55, 0.24)
	draw_circle(Vector2(0, 4), 9.0, Color(0.4, 0.28, 0.15))  # seed mound
	draw_line(Vector2(0, 2), Vector2(sway, 2 - h), stem, 3.0)
	# leaf pairs appear as the plant matures
	var leaves = 1 + int(p * 3.0)
	for i in range(leaves):
		var ly = 2 - h * (0.35 + 0.2 * i)
		var lx = sway * 0.7
		var side = 1 if i % 2 == 0 else -1
		draw_set_transform(Vector2(lx + side * 8, ly), side * 0.5, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 7.0 + p * 4.0, stem.lightened(0.12 * i))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ready():
	var data = GameData.potato_by_id(potato_id)
	var body = Color(data.get("color", "#b87333"))
	# pulsing "harvest me" ring
	draw_arc(Vector2.ZERO, 58.0 + sin(t * 3.0) * 4.0, 0, TAU, 40, Color(1.0, 0.9, 0.4, 0.5), 3.0)
	# bushy top
	var sway = sin(t * 2.0 + index) * 2.5
	for off in [Vector2(-14, -26), Vector2(14, -24), Vector2(0, -38)]:
		draw_circle(off + Vector2(sway, 0), 16.0, Color(0.28, 0.5, 0.22))
	draw_circle(Vector2(sway - 6, -42), 8.0, Color(0.38, 0.6, 0.3))
	# potatoes peeking out of the soil
	for i in range(3):
		var px = -26.0 + i * 26.0
		draw_circle(Vector2(px, 14 + 3 * sin(i * 2.0)), 11.0, body)
		draw_arc(Vector2(px, 14 + 3 * sin(i * 2.0)), 11.0, 0, TAU, 16, body.darkened(0.4), 2.0)
	if data.get("rare", false):
		for i in range(3):
			var a = t * 2.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 34.0, -20 + sin(a) * 22.0), 2.5, Color(1.0, 0.9, 0.4, 0.8))
