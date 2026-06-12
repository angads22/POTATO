extends Node2D
class_name KitchenBackground

# The shared kitchen backdrop: gradient tile wall, plank counter and a
# butcher-block cutting board. Drawn once; add with z_index = -1 so it sits
# behind the owning scene's own _draw().

const WALL_H = 420.0
const SCREEN = Vector2(1280, 720)

# Where the cutting board sits (under the gameplay potato at 640,330)
var show_board: bool = true
var board_rect := Rect2(400, 250, 480, 220)

func _ready():
	z_index = -1

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
