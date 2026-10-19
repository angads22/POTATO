extends Node2D
class_name FarmerVisual

# The player: a potato in a chef's toque. Hops while walking, breathes
# while idle, flips to face its travel direction, and swings a little hoe
# (a quick swing/toss) whenever it tends, catches or clicks something, so a
# click at any distance still reads as the farmer doing it.

const SWING_S := 0.32

var walk_t := 0.0
var idle_t := 0.0
var moving := false
var face := 1.0      # 1 = right, -1 = left
var swing_t := 0.0   # > 0 while the swing/toss pose plays
var _acc := 0.0
var _was_active := false

func swing():
	swing_t = SWING_S

func _process(delta):
	if moving:
		walk_t += delta * 10.0
	else:
		walk_t = 0.0
		idle_t += delta
	swing_t = maxf(0.0, swing_t - delta)
	# full rate while walking or swinging; the idle breath is slow, 10 Hz will do
	var active := moving or swing_t > 0.0
	_acc += delta
	if active or _was_active or _acc >= 0.1:
		_acc = 0.0
		queue_redraw()
	_was_active = active

func _draw():
	var hop = absf(sin(walk_t)) * 7.0 if moving else 0.0
	var breathe = 1.0 + (0.0 if moving else sin(idle_t * 2.0) * 0.02)
	var sw := swing_t / SWING_S          # 1 -> 0 over the swing
	var lean := sin(sw * PI) * 0.12      # lean into the swing

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

	draw_set_transform(Vector2(0, -hop), lean * face, Vector2(face * breathe, 2.0 - breathe))

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

	# arms; while swinging, the front arm carries a small hoe through an arc
	draw_circle(Vector2(-24, 2), 6.0, body.darkened(0.1))
	if swing_t > 0.0:
		var ang := lerpf(1.1, -1.4, sw)          # raised -> down in front
		var hand := Vector2(24, 2) + Vector2(cos(ang), sin(ang)) * 8.0
		var tip := hand + Vector2(cos(ang - 0.25), sin(ang - 0.25)) * 30.0
		draw_line(hand, tip, Color(0.55, 0.38, 0.2), 3.5)
		var blade_dir := Vector2(cos(ang + 1.3), sin(ang + 1.3))
		draw_colored_polygon(PackedVector2Array([tip, tip + blade_dir * 11.0, tip + blade_dir * 7.0 + (tip - hand).normalized() * 5.0]),
				Color(0.75, 0.77, 0.82))
		draw_circle(hand, 6.0, body.darkened(0.1))
		# a little toss of dirt at the end of the swing
		if sw < 0.45:
			for k in 3:
				draw_circle(tip + Vector2(6 + k * 5, -4 - k * 4 - (0.45 - sw) * 20.0), 2.2, Color(0.45, 0.3, 0.16, 0.8))
	else:
		draw_circle(Vector2(24, 2), 6.0, body.darkened(0.1))

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
