extends Node2D
class_name KnifeVisual

# Procedural cleaver hovering above the potato; chop() swings it down
# through the cut and back up. Position this node at the potato's centre.

const HOVER_LIFT = -150.0
const CHOP_LIFT = -34.0
const CHOP_LEN = 0.16   # seconds down; the upswing takes the same again

var bob_t := 0.0
var chop_t := -1.0      # -1 = idle, otherwise progress through the swing

func _process(delta):
	bob_t += delta
	if chop_t >= 0.0:
		chop_t += delta
		if chop_t > CHOP_LEN * 2.0:
			chop_t = -1.0
	queue_redraw()

func chop():
	chop_t = 0.0

func _draw():
	# hover in counter-phase to the potato bob; swing through on chop
	var lift = HOVER_LIFT + sin(bob_t * 2.2 + PI) * 6.0
	var ang = -0.1
	if chop_t >= 0.0:
		var ph = chop_t / CHOP_LEN
		if ph <= 1.0:
			lift = lerpf(HOVER_LIFT, CHOP_LIFT, ph * ph)   # accelerate down
			ang = lerpf(-0.1, 0.12, ph)
		else:
			lift = lerpf(CHOP_LIFT, HOVER_LIFT, ph - 1.0)  # ease back up
			ang = lerpf(0.12, -0.1, ph - 1.0)

	draw_set_transform(Vector2(0, lift), ang, Vector2.ONE)

	# blade — cleaver silhouette, edge at the bottom
	draw_colored_polygon(PackedVector2Array([
		Vector2(-95, -42), Vector2(58, -42), Vector2(58, 10),
		Vector2(-78, 10), Vector2(-95, -12)
	]), Color(0.82, 0.84, 0.88))
	# brushed-steel band + cutting edge highlight
	draw_rect(Rect2(-86, -34, 136, 6), Color(0.9, 0.91, 0.95))
	draw_rect(Rect2(-78, 6, 136, 4), Color(0.97, 0.97, 1.0))
	# rivets
	draw_circle(Vector2(-58, -16), 4.0, Color(0.6, 0.62, 0.66))
	draw_circle(Vector2(-2, -16), 4.0, Color(0.6, 0.62, 0.66))
	# wooden handle
	draw_colored_polygon(PackedVector2Array([
		Vector2(58, -38), Vector2(128, -34), Vector2(128, -12), Vector2(58, -16)
	]), Color(0.36, 0.22, 0.12))
	draw_colored_polygon(PackedVector2Array([
		Vector2(58, -38), Vector2(128, -34), Vector2(128, -26), Vector2(58, -30)
	]), Color(0.45, 0.28, 0.16))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
