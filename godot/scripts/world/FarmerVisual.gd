extends Node2D
class_name FarmerVisual

# The player: a potato in a chef's toque. Hops while walking, breathes
# while idle, flips to face its travel direction, and shows the watering
# can in hand whenever there's water in it.

var walk_t := 0.0
var idle_t := 0.0
var moving := false
var face := 1.0  # 1 = right, -1 = left
var carrying_water := false

func _process(delta):
	if moving:
		walk_t += delta * 10.0
	else:
		walk_t = 0.0
		idle_t += delta
	queue_redraw()

func _draw():
	var hop = absf(sin(walk_t)) * 7.0 if moving else 0.0
	var breathe = 1.0 + (0.0 if moving else sin(idle_t * 2.0) * 0.02)

	# ground shadow shrinks as the hop lifts off
	draw_set_transform(Vector2(0, 36), 0.0, Vector2(1.0 - hop * 0.01, 0.35))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# feet alternate while walking
	var step = sin(walk_t) * 5.0 if moving else 0.0
	for side in [-1.0, 1.0]:
		draw_set_transform(Vector2(side * 11.0, 32.0 + side * step), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 8.0, Color(0.4, 0.26, 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2(0, -hop), 0.0, Vector2(face * breathe, 2.0 - breathe))

	# potato body
	var body = Color(0.78, 0.55, 0.3)
	var pts = PackedVector2Array()
	for i in range(25):
		var a = TAU * i / 24.0
		var lump = 1.0 + 0.06 * sin(a * 3.0) + 0.04 * sin(a * 5.0)
		pts.append(Vector2(cos(a) * 24.0 * lump, sin(a) * 31.0 * lump))
	draw_colored_polygon(pts, body)
	var outline = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, body.darkened(0.45), 2.5, true)
	for s in [Vector2(-12, 8), Vector2(14, 2), Vector2(-4, 18)]:
		draw_circle(s, 3.0, body.darkened(0.3))

	# arms
	draw_circle(Vector2(-24, 2), 6.0, body.darkened(0.1))
	draw_circle(Vector2(24, 2), 6.0, body.darkened(0.1))
	if carrying_water:
		draw_rect(Rect2(26, -6, 18, 14), Color(0.55, 0.62, 0.68))
		draw_line(Vector2(44, -2), Vector2(54, -8), Color(0.55, 0.62, 0.68), 4.0)
		draw_arc(Vector2(35, -8), 8.0, PI, TAU, 10, Color(0.45, 0.52, 0.58), 3.0)

	# face
	draw_circle(Vector2(-7, -10), 4.5, Color.WHITE)
	draw_circle(Vector2(7, -10), 4.5, Color.WHITE)
	draw_circle(Vector2(-6, -10), 2.2, Color(0.15, 0.1, 0.05))
	draw_circle(Vector2(8, -10), 2.2, Color(0.15, 0.1, 0.05))
	draw_arc(Vector2(0, -2), 6.0, 0.3, PI - 0.3, 10, Color(0.3, 0.18, 0.08), 2.0)
	draw_circle(Vector2(-14, -2), 3.5, Color(0.9, 0.55, 0.4, 0.35))
	draw_circle(Vector2(14, -2), 3.5, Color(0.9, 0.55, 0.4, 0.35))

	# chef's toque
	draw_rect(Rect2(-15, -34, 30, 9), Color(0.96, 0.95, 0.92))
	draw_circle(Vector2(-9, -38), 8.0, Color.WHITE)
	draw_circle(Vector2(0, -42), 9.5, Color.WHITE)
	draw_circle(Vector2(9, -38), 8.0, Color.WHITE)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
