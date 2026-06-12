extends Node2D
class_name PotatoVisual

# Procedurally drawn potato — no image assets needed, so the palette comes
# straight from the data tables. Idle bob, split-in-two and binned-drop
# animations; golden potatoes glow, rotten ones grow stink lines.

enum State { IDLE, SPLIT, BINNED, GONE }

const BODY_W = 105.0   # horizontal radius
const BODY_H = 75.0    # vertical radius
const ANIM_LEN = 0.9

var body_color: Color = Color(0.72, 0.45, 0.2)
var is_golden: bool = false
var is_rotten: bool = false
var state: State = State.GONE
var anim_t: float = 0.0
var bob_t: float = 0.0
var spots: Array = []

func setup(potato: Dictionary):
	body_color = Color(potato.get("color", "#b87333"))
	is_golden = potato.get("rare", false)
	is_rotten = potato.get("rotten", false)
	state = State.IDLE
	anim_t = 0.0
	spots.clear()
	for i in range(6):
		spots.append(Vector2(randf_range(-0.55, 0.55), randf_range(-0.5, 0.5)))
	queue_redraw()

func split():
	state = State.SPLIT
	anim_t = 0.0

func bin():
	state = State.BINNED
	anim_t = 0.0

func _process(delta):
	bob_t += delta
	if state == State.SPLIT or state == State.BINNED:
		anim_t += delta
		if anim_t > ANIM_LEN:
			state = State.GONE
	queue_redraw()

func _draw():
	if state == State.GONE:
		return

	if is_golden and state == State.IDLE:
		var glow = 0.16 + 0.08 * sin(bob_t * 5.0)
		draw_circle(Vector2.ZERO, BODY_W * 1.45, Color(1.0, 0.85, 0.2, glow))

	match state:
		State.IDLE:
			_draw_body(Vector2(0, sin(bob_t * 2.2) * 5.0), 0.0, 0)
		State.SPLIT:
			var sep = anim_t * 150.0
			var drop = anim_t * anim_t * 260.0
			_draw_body(Vector2(-sep, drop), -anim_t * 0.7, -1)
			_draw_body(Vector2(sep, drop), anim_t * 0.7, 1)
		State.BINNED:
			_draw_body(Vector2(0, anim_t * anim_t * 700.0), anim_t * 2.5, 0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# side: 0 = whole potato, -1 = left half, 1 = right half
func _draw_body(offset: Vector2, rot: float, side: int):
	draw_set_transform(offset, rot, Vector2.ONE)

	var start = 0.0
	var sweep = TAU
	var steps = 32
	if side == -1:
		start = PI * 0.5
		sweep = PI
		steps = 17
	elif side == 1:
		start = -PI * 0.5
		sweep = PI
		steps = 17

	# lumpy ellipse outline — the polygon auto-closes across the cut edge
	var pts = PackedVector2Array()
	for i in range(steps + 1):
		var a = start + sweep * i / steps
		var lump = 1.0 + 0.07 * sin(a * 3.0) + 0.04 * sin(a * 5.0)
		pts.append(Vector2(cos(a) * BODY_W * lump, sin(a) * BODY_H * lump))
	draw_colored_polygon(pts, body_color)

	if side != 0:
		# pale flesh showing along the cut edge
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, -BODY_H), Vector2(side * 10.0, 0), Vector2(0, BODY_H)
		]), Color(0.95, 0.9, 0.7))
	else:
		# highlight + eye spots
		draw_circle(Vector2(-BODY_W * 0.3, -BODY_H * 0.35), 14.0, Color(1, 1, 1, 0.18))
		var spot_col = Color(0.25, 0.35, 0.15) if is_rotten else body_color.darkened(0.35)
		for s in spots:
			draw_circle(Vector2(s.x * BODY_W, s.y * BODY_H), 5.0, spot_col)
		if is_rotten:
			for i in range(3):
				var x = -30.0 + i * 30.0
				draw_arc(Vector2(x, -BODY_H - 18.0), 9.0, PI, TAU, 8, Color(0.5, 0.7, 0.3, 0.8), 2.5)
