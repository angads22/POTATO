extends Node2D
class_name FarmTile

# One cell in the open farm grid. Wild ground must be plowed (the plow wears
# out) before a seed goes in; harvested soil stays plowed. Growth is measured
# against the wall clock (planted_at is a unix timestamp), so crops keep
# growing while the game is closed. Watering cuts the remaining grow time
# roughly in half; a fertilizer charge (boost < 1.0) stacks on top and can
# add bonus yield. A tile can instead host a placed sprinkler, which waters
# the tiles around it. Tiles are sparse — one exists only once a cell is
# plowed or holds a sprinkler; plain grass has no tile node.

enum TState { UNPLOWED, PLOWED, PLANTED, READY }

const WATER_FACTOR = 0.55

var row := 0              # open-grid coordinates
var col := 0
var state := TState.UNPLOWED
var has_sprinkler := false
var potato_id := ""
var planted_at := 0.0
var watered := false
var boost := 1.0          # growth-time multiplier from fertilizer (1.0 = none)
var bonus_yield := 0      # extra potatoes at harvest from fertilizer
var last_potato_id := ""  # what grew here last — the Auto-Seeder replants it
var t := 0.0

func key() -> String:
	return "%d:%d" % [col, row]

func plow() -> bool:
	if has_sprinkler or state != TState.UNPLOWED:
		return false
	state = TState.PLOWED
	return true

func plant(id: String) -> bool:
	if has_sprinkler or state != TState.PLOWED:
		return false
	potato_id = id
	last_potato_id = id
	planted_at = Time.get_unix_time_from_system()
	watered = false
	boost = 1.0
	bonus_yield = 0
	state = TState.PLANTED
	return true

func water():
	watered = true

# Apply a fertilizer charge; one per crop
func enhance(factor: float, extra_yield: int) -> bool:
	if state != TState.PLANTED or boost < 1.0:
		return false
	boost = factor
	bonus_yield = extra_yield
	return true

# 0..1 maturity; READY state is derived from this so it also survives reloads
func progress() -> float:
	if state != TState.PLANTED and state != TState.READY:
		return 0.0
	var grow = float(GameData.potato_by_id(potato_id).get("grow_time", 30))
	if watered:
		grow *= WATER_FACTOR
	grow *= boost
	grow *= SaveDataManager.grow_time_mult()   # research "Soil Science" speeds growth
	return clampf((Time.get_unix_time_from_system() - planted_at) / grow, 0.0, 1.0)

# Returns the number of potatoes pulled; the soil stays plowed for replanting
func harvest(rng: RandomNumberGenerator) -> int:
	var yield_range: Array = GameData.potato_by_id(potato_id).get("yield", [2, 3])
	var n = rng.randi_range(int(yield_range[0]), int(yield_range[1])) + bonus_yield
	state = TState.PLOWED
	potato_id = ""
	watered = false
	boost = 1.0
	bonus_yield = 0
	return n

func to_dict() -> Dictionary:
	if has_sprinkler:
		# keep the plowed flag so picking the sprinkler back up doesn't
		# cost plow uses again
		return {"sprinkler": true, "plowed": state != TState.UNPLOWED}
	match state:
		TState.UNPLOWED:
			return {}
		TState.PLOWED:
			if last_potato_id != "":
				return {"plowed": true, "last": last_potato_id}
			return {"plowed": true}
		_:
			return {
				"plowed": true, "potato_id": potato_id, "planted_at": planted_at,
				"watered": watered, "boost": boost, "bonus_yield": bonus_yield,
				"last": last_potato_id
			}

func from_dict(d: Dictionary):
	if d.is_empty():
		return
	if d.get("plowed", false):
		state = TState.PLOWED
	has_sprinkler = bool(d.get("sprinkler", false))
	last_potato_id = str(d.get("last", ""))
	if has_sprinkler or not d.has("potato_id"):
		return
	potato_id = str(d["potato_id"])
	planted_at = float(d["planted_at"])
	watered = bool(d.get("watered", false))
	boost = float(d.get("boost", 1.0))
	bonus_yield = int(d.get("bonus_yield", 0))
	state = TState.PLANTED

func _process(delta):
	t += delta
	if state == TState.PLANTED and progress() >= 1.0:
		state = TState.READY
	queue_redraw()

func _draw():
	if state == TState.UNPLOWED:
		_draw_unplowed()
	else:
		_draw_soil_bed()
	if has_sprinkler:
		_draw_sprinkler()
		return

	match state:
		TState.PLANTED:
			_draw_growing(progress())
		TState.READY:
			_draw_ready()

# Plowed soil bed — darker when watered
func _draw_soil_bed():
	var soil = StyleBoxFlat.new()
	soil.bg_color = Color(0.36, 0.24, 0.13) if watered else Color(0.46, 0.32, 0.18)
	soil.set_corner_radius_all(16)
	soil.border_color = soil.bg_color.darkened(0.3)
	soil.set_border_width_all(3)
	soil.draw(get_canvas_item(), Rect2(-65, -45, 130, 90))
	for i in range(3):
		draw_rect(Rect2(-52, -26 + i * 24, 104, 3), soil.bg_color.darkened(0.22))
	if watered and state == TState.PLANTED:
		for i in range(3):
			draw_circle(Vector2(-34 + i * 34, 32), 2.5, Color(0.5, 0.75, 0.95, 0.8))

	# fertilizer sparkles drift up from boosted soil
	if boost < 1.0 and state == TState.PLANTED:
		for i in range(3):
			var rise = fposmod(t * 14.0 + i * 21.0, 46.0)
			var sx = -30.0 + i * 30.0 + sin(t * 2.0 + i) * 4.0
			draw_circle(Vector2(sx, 26.0 - rise), 2.2,
					Color(0.55, 0.95, 0.4, 0.8 * (1.0 - rise / 46.0)))

# Owned but unbroken ground: flat dry dirt with pebbles and grass stubble,
# visibly different from the furrowed plowed bed
func _draw_unplowed():
	var dirt = StyleBoxFlat.new()
	dirt.bg_color = Color(0.5, 0.46, 0.28)
	dirt.set_corner_radius_all(16)
	dirt.border_color = dirt.bg_color.darkened(0.18)
	dirt.set_border_width_all(2)
	dirt.draw(get_canvas_item(), Rect2(-65, -45, 130, 90))
	for i in range(4):
		var px = -44.0 + (i % 2) * 60.0 + (i / 2) * 18.0
		var py = -18.0 + (i / 2) * 34.0
		draw_circle(Vector2(px, py), 3.5, Color(0.58, 0.55, 0.42))
	for i in range(3):
		var sx = -34.0 + i * 34.0
		var sway = sin(t * 1.4 + i + col) * 1.5
		var stub = Color(0.42, 0.5, 0.26)
		draw_line(Vector2(sx, 18), Vector2(sx - 3 + sway, 6), stub, 2.0)
		draw_line(Vector2(sx, 18), Vector2(sx + 3 + sway, 8), stub, 2.0)

func _draw_sprinkler():
	# tripod base, riser pipe and head
	var metal = Color(0.62, 0.68, 0.74)
	for side in [-1.0, 1.0]:
		draw_line(Vector2(0, -14), Vector2(side * 13, 8), metal.darkened(0.25), 3.0)
	draw_circle(Vector2(0, 8), 4.0, metal.darkened(0.35))
	draw_line(Vector2(0, 8), Vector2(0, -18), metal, 5.0)
	draw_circle(Vector2(0, -20), 7.0, metal)
	draw_circle(Vector2(0, -20), 3.0, Color(0.35, 0.55, 0.7))
	# sweeping spray arcs hint at the 8-tile coverage
	for i in range(2):
		var a = t * 1.8 + i * PI
		draw_arc(Vector2(0, -6), 34.0, a, a + 1.1, 10, Color(0.45, 0.75, 0.95, 0.75), 3.0)
		draw_arc(Vector2(0, -6), 52.0, a + 0.35, a + 1.0, 10, Color(0.45, 0.75, 0.95, 0.4), 2.5)
		var drop = Vector2(cos(a + 0.55), sin(a + 0.55)) * 58.0
		draw_circle(Vector2(0, -6) + drop * Vector2(1.0, 0.7), 2.4, Color(0.5, 0.8, 1.0, 0.7))

func _draw_growing(p: float):
	var sway = sin(t * 2.0 + row + col) * 2.0
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
	var sway = sin(t * 2.0 + row + col) * 2.5
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
