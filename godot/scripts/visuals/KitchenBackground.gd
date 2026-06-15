extends Node2D
class_name KitchenBackground

# The shared kitchen backdrop: gradient tile wall, plank counter and a
# butcher-block cutting board, plus living touches — a window with drifting
# clouds, a swaying utensil rail and a steaming pot. Add with z_index = -1
# so it sits behind the owning scene's own _draw().

const WALL_H = 420.0
const SCREEN = Vector2(1280, 720)

# Where the cutting board sits (under the gameplay potato at 640,330)
var show_board: bool = true
var show_window: bool = true
var t := 0.0

# Championship stage tier (1..6). The kitchen escalates with it: the wall
# cools from a homely cream toward a grand-arena violet, and bunting, a roaring
# crowd and spotlights fade in as the stages climb. Tier 1 is the untouched
# look used by the menu, farm/town and game-over screens.
var tier: int = 1

var board_rect := Rect2(400, 250, 480, 220)

func _ready():
	z_index = -1

func _process(delta):
	t += delta
	queue_redraw()

# 0 at tier 1, 1 at tier 6 — how far the kitchen has escalated.
func _grandeur() -> float:
	return clampf((tier - 1) / 5.0, 0.0, 1.0)

func _draw():
	var f := _grandeur()
	var wall_base := Color(0.93, 0.87, 0.78).lerp(Color(0.5, 0.42, 0.66), f)
	# wall — vertical gradient in horizontal bands
	for i in range(8):
		var t = i / 8.0
		draw_rect(Rect2(0, t * WALL_H, SCREEN.x, WALL_H / 8.0 + 1.0), wall_base.darkened(t * 0.12))

	# tile grout lines
	for y in range(60, int(WALL_H), 60):
		draw_rect(Rect2(0, y, SCREEN.x, 2), Color(0.8, 0.74, 0.66, 0.5))
	for x in range(0, int(SCREEN.x) + 1, 80):
		draw_rect(Rect2(x, 0, 2, WALL_H), Color(0.8, 0.74, 0.66, 0.35))

	# bunting + roaring crowd on the wall (faded in by tier), behind the counter
	if f > 0.0:
		_draw_arena_back(f)

	# counter edge highlight then walnut planks
	draw_rect(Rect2(0, WALL_H - 6, SCREEN.x, 6), Color(0.32, 0.2, 0.1))
	draw_rect(Rect2(0, WALL_H, SCREEN.x, SCREEN.y - WALL_H), Color(0.5, 0.33, 0.18))
	for i in range(1, 6):
		draw_rect(Rect2(0, WALL_H + i * 60, SCREEN.x, 3), Color(0.4, 0.26, 0.14))
	# staggered plank joints
	for i in range(5):
		var jy = WALL_H + i * 60
		var jx = 160.0 + float((i * 467) % 960)
		draw_rect(Rect2(jx, jy, 3, 60), Color(0.4, 0.26, 0.14, 0.8))

	if show_window:
		_draw_window()
	_draw_utensil_rail()
	_draw_steaming_pot()

	# crossing spotlights + championship sign over the whole scene (top tiers)
	if f > 0.0:
		_draw_arena_front(f)

	# butcher-block cutting board with drop shadow
	if show_board:
		var board = StyleBoxFlat.new()
		board.bg_color = Color(0.76, 0.58, 0.36)
		board.set_corner_radius_all(26)
		board.shadow_color = Color(0, 0, 0, 0.3)
		board.shadow_size = 12
		board.shadow_offset = Vector2(0, 8)
		board.border_color = Color(0.6, 0.44, 0.26)
		board.set_border_width_all(5)
		board.draw(get_canvas_item(), board_rect)
		# board grain
		for i in range(1, 4):
			var gy = board_rect.position.y + board_rect.size.y * i / 4.0
			draw_rect(Rect2(board_rect.position.x + 20, gy, board_rect.size.x - 40, 2), Color(0.6, 0.44, 0.26, 0.5))

# Window onto the garden, with a sun and clouds drifting past
func _draw_window():
	var win = Rect2(84, 130, 230, 140)
	# frame + sill
	draw_rect(win.grow(10), Color(0.42, 0.28, 0.16))
	draw_rect(Rect2(win.position.x - 18, win.end.y + 8, win.size.x + 36, 12), Color(0.5, 0.34, 0.2))
	# sky gradient
	draw_rect(win, Color(0.55, 0.75, 0.92))
	draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.55, win.size.x, win.size.y * 0.45), Color(0.65, 0.82, 0.94))
	# rolling hills as a polygon strip, so they stay inside the panes
	var hills = PackedVector2Array([Vector2(win.position.x, win.end.y)])
	for i in range(13):
		var hx = win.position.x + win.size.x * i / 12.0
		hills.append(Vector2(hx, win.end.y - 28.0 - 16.0 * sin(i * 0.9) - 8.0 * sin(i * 1.7)))
	hills.append(Vector2(win.end.x, win.end.y))
	draw_colored_polygon(hills, Color(0.45, 0.62, 0.35))
	# sun
	draw_circle(Vector2(win.end.x - 50, win.position.y + 34), 16.0, Color(1.0, 0.9, 0.5))
	# drifting clouds, clipped by hand against the frame
	for i in range(2):
		var cx = win.position.x + fposmod(t * 11.0 + i * 140.0, win.size.x + 70.0) - 35.0
		var cy = win.position.y + 36 + i * 34
		for blob in [Vector2(0, 0), Vector2(-18, 6), Vector2(18, 6)]:
			var bp = Vector2(cx, cy) + blob
			if bp.x > win.position.x + 8 and bp.x < win.end.x - 8:
				draw_circle(bp, 13.0, Color(1, 1, 1, 0.85))
	# cross bars
	draw_rect(Rect2(win.position.x + win.size.x / 2 - 4, win.position.y, 8, win.size.y), Color(0.42, 0.28, 0.16))
	draw_rect(Rect2(win.position.x, win.position.y + win.size.y / 2 - 4, win.size.x, 8), Color(0.42, 0.28, 0.16))

# Hanging spatula, ladle and whisk that sway gently
func _draw_utensil_rail():
	draw_rect(Rect2(560, 26, 380, 7), Color(0.3, 0.2, 0.12))
	draw_circle(Vector2(566, 30), 6.0, Color(0.22, 0.15, 0.09))
	draw_circle(Vector2(934, 30), 6.0, Color(0.22, 0.15, 0.09))
	var steel = Color(0.62, 0.64, 0.68)
	var wood = Color(0.4, 0.26, 0.14)
	for i in range(3):
		var hx = 630.0 + i * 120.0
		draw_circle(Vector2(hx, 33), 4.0, Color(0.22, 0.15, 0.09))
		draw_set_transform(Vector2(hx, 36), sin(t * 1.3 + i * 2.1) * 0.07, Vector2.ONE)
		match i:
			0:  # spatula
				draw_rect(Rect2(-3, 0, 6, 52), wood)
				draw_rect(Rect2(-12, 52, 24, 26), steel)
				for sx in range(-6, 10, 6):
					draw_rect(Rect2(sx, 56, 2, 18), Color(0.5, 0.52, 0.56))
			1:  # ladle
				draw_rect(Rect2(-3, 0, 6, 56), steel)
				draw_circle(Vector2(0, 64), 14.0, steel)
				draw_circle(Vector2(-3, 61), 7.0, Color(0.75, 0.77, 0.8))
			2:  # whisk
				draw_rect(Rect2(-3, 0, 6, 34), wood)
				for w in range(3):
					var spread = 8.0 + w * 5.0
					draw_arc(Vector2(0, 52), spread, -PI * 0.85, -PI * 0.15, 10, steel, 2.0)
					draw_arc(Vector2(0, 52), spread, PI * 0.15, PI * 0.85, 10, steel, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Bunting and a bobbing crowd that fade in with the tier, drawn on the wall
# so the counter (drawn next) crops the crowd to peeking heads.
func _draw_arena_back(f: float):
	# bunting strung across the top (from tier 2)
	if f >= 0.2:
		var ba := clampf((f - 0.2) / 0.2, 0.0, 1.0)
		var cols := [Color(0.9, 0.2, 0.2), Color(0.95, 0.78, 0.2), Color(0.95, 0.95, 0.95)]
		var n := 16
		var prev := Vector2(0, 8.0 + 12.0)
		for i in range(n):
			var x0 := SCREEN.x * i / float(n)
			var x1 := SCREEN.x * (i + 1) / float(n)
			var sag := 12.0 + 6.0 * sin(i * 0.7 + t * 1.2)
			var top := 8.0 + sag
			draw_line(prev, Vector2(x0, top), Color(0.2, 0.15, 0.1, 0.7 * ba), 2.0)
			prev = Vector2(x1, top)
			var c: Color = cols[i % cols.size()]
			c.a = 0.92 * ba
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0, top), Vector2(x1, top), Vector2((x0 + x1) * 0.5, top + 22.0)]), c)
	# packed crowd peeking over the back counter (from tier 3)
	if f >= 0.4:
		var ca := clampf((f - 0.4) / 0.2, 0.0, 1.0)
		var head_c := Color(0.15, 0.11, 0.2, 0.85 * ca)
		for row in range(2):
			var ry := WALL_H - 24.0 - row * 20.0
			var off := row * 13.0
			var idx := 0
			var x := off
			while x < SCREEN.x + 26.0:
				var bob := sin(t * 3.0 + idx * 0.9 + row * 1.7) * 3.0
				draw_rect(Rect2(x - 13, ry + bob + 6, 26, 26), head_c)
				draw_circle(Vector2(x, ry + bob), 12.0, head_c)
				x += 26.0
				idx += 1

# Crossing spotlights and a golden trophy for the grandest stages (tier 5+).
func _draw_arena_front(f: float):
	if f < 0.8:
		return
	var sa := clampf((f - 0.8) / 0.2, 0.0, 1.0)
	var sweep := sin(t * 0.7) * 60.0
	var beam := Color(1.0, 0.95, 0.7, 0.06 * sa)
	draw_colored_polygon(PackedVector2Array([
		Vector2(120, 0), Vector2(160, 0),
		Vector2(660 + sweep, WALL_H), Vector2(500 + sweep, WALL_H)]), beam)
	draw_colored_polygon(PackedVector2Array([
		Vector2(SCREEN.x - 160, 0), Vector2(SCREEN.x - 120, 0),
		Vector2(780 - sweep, WALL_H), Vector2(620 - sweep, WALL_H)]), beam)
	# trophy gleaming on the left of the counter
	var tx := 250.0
	var ty := WALL_H + 72.0
	var gold := Color(1.0, 0.82, 0.3, sa)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tx - 20, ty - 44), Vector2(tx + 20, ty - 44),
		Vector2(tx + 12, ty - 16), Vector2(tx - 12, ty - 16)]), gold)
	draw_arc(Vector2(tx - 20, ty - 36), 9, PI * 0.5, PI * 1.5, 8, gold, 3.0)
	draw_arc(Vector2(tx + 20, ty - 36), 9, -PI * 0.5, PI * 0.5, 8, gold, 3.0)
	draw_rect(Rect2(tx - 4, ty - 16, 8, 12), gold)
	draw_rect(Rect2(tx - 16, ty - 4, 32, 8), gold)
	var g := 0.5 + 0.5 * sin(t * 3.0)
	draw_circle(Vector2(tx - 8, ty - 34), 3.0, Color(1, 1, 1, 0.7 * sa * g))

# A pot simmering on the counter, off to the right
func _draw_steaming_pot():
	var px = 1090.0
	var py = 470.0
	# steam wisps rise and fade
	for i in range(3):
		var rise = fposmod(t * 26.0 + i * 38.0, 110.0)
		var wob = sin(t * 2.0 + i * 1.8 + rise * 0.05) * 8.0
		draw_circle(Vector2(px + 20 + wob + i * 14, py - 14 - rise), 9.0 + rise * 0.06,
				Color(0.95, 0.95, 0.97, 0.4 * (1.0 - rise / 110.0)))
	# body, rim, handles, lid
	draw_rect(Rect2(px - 12, py - 6, 104, 58), Color(0.35, 0.37, 0.42))
	draw_rect(Rect2(px - 12, py - 6, 104, 10), Color(0.5, 0.52, 0.58))
	draw_rect(Rect2(px - 22, py + 2, 10, 8), Color(0.3, 0.32, 0.36))
	draw_rect(Rect2(px + 92, py + 2, 10, 8), Color(0.3, 0.32, 0.36))
	draw_rect(Rect2(px - 4, py - 14, 88, 8), Color(0.45, 0.47, 0.52))
	draw_circle(Vector2(px + 40, py - 16), 6.0, Color(0.3, 0.32, 0.36))
	# highlight
	draw_rect(Rect2(px - 2, py + 8, 8, 38), Color(0.55, 0.57, 0.62, 0.5))
