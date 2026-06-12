extends Node2D
class_name RingFx

# Expanding shock-ring flash for PERFECT cuts. Spawn via Fx.ring().

const LIFE = 0.45

var age := 0.0
var color := Color.GOLD

func _process(delta):
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw():
	var f = age / LIFE
	var col = Color(color.r, color.g, color.b, 1.0 - f)
	draw_arc(Vector2.ZERO, 30.0 + f * 140.0, 0, TAU, 48, col, 12.0 * (1.0 - f) + 2.0)
	draw_arc(Vector2.ZERO, 14.0 + f * 90.0, 0, TAU, 40, Color(1, 1, 1, (1.0 - f) * 0.6), 4.0)
