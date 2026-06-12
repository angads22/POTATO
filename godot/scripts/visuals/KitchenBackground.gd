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

var board_rect := Rect2(400, 250, 480, 220)

func _ready():
	z_index = -1

func _process(delta):
	t += delta
	queue_redraw()

func _draw():
	# wall — vertical gradient in horizontal bands
	for i in range(8):
		var t = i / 8.0
		draw_rect(Rect2(0, t * WALL_H, SCREEN.x, WALL_H / 8.0 + 1.0), Color(0.93, 0.87, 0.78).darkened(t * 0.12))

	# tile grout lines
	for y in range(60, int(WALL_H), 60):
		draw_rect(Rect2(0, y, SCREEN.x, 2), Color(0.8, 0.74, 0.66, 0.5))
	for x in range(0, int(SCREEN.x) + 1, 80):
		draw_rect(Rect2(x, 0, 2, WALL_H), Color(0.8, 0.74, 0.66, 0.35))

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
