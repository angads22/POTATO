extends Node2D
class_name PotatoVisual

# Procedurally drawn potato — no image assets needed, so the palette comes
# straight from the data tables. Idle bob, split-in-two and binned-drop
# animations; golden potatoes glow, rotten ones grow stink lines.

enum State { IDLE, SPLIT, BINNED, GONE }

const BODY_W = 105.0   # horizontal radius
const BODY_H = 75.0    # vertical radius
const ANIM_LEN = 0.9
const SPAWN_LEN = 0.55  # drop-in plus landing squash

var body_color: Color = Color(0.72, 0.45, 0.2)
var is_golden: bool = false
var is_rotten: bool = false
var state: State = State.GONE
var anim_t: float = 0.0
var bob_t: float = 0.0
var spawn_t: float = 99.0
var spots: Array = []

func setup(potato: Dictionary):
	body_color = Color(potato.get("color", "#b87333"))
	is_golden = potato.get("rare", false)
	is_rotten = potato.get("rotten", false)
	state = State.IDLE
	anim_t = 0.0
	spawn_t = 0.0
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
	spawn_t += delta
	if state == State.SPLIT or state == State.BINNED:
		anim_t += delta
		if anim_t > ANIM_LEN:
			state = State.GONE
	queue_redraw()

func _draw():
	if state == State.GONE:
		return

	# soft ground shadow that the bob lifts off of
	if state == State.IDLE:
		var bob01 = (sin(bob_t * 2.2) + 1.0) * 0.5
		var sh_scale = 1.0 - bob01 * 0.08
		var sh_alpha = 0.22
		if spawn_t < 0.3:  # shadow grows as the potato falls toward it
			sh_scale *= 0.5 + 0.5 * (spawn_t / 0.3)
			sh_alpha *= 0.4 + 0.6 * (spawn_t / 0.3)
		draw_set_transform(Vector2(0, BODY_H + 22), 0.0, Vector2(sh_scale, 0.3 * sh_scale))
		draw_circle(Vector2.ZERO, BODY_W * 0.95, Color(0, 0, 0, sh_alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_golden and state == State.IDLE:
		var glow = 0.16 + 0.08 * sin(bob_t * 5.0)
		draw_circle(Vector2.ZERO, BODY_W * 1.45, Color(1.0, 0.85, 0.2, glow))

	match state:
		State.IDLE:
			# drop in from above, squash on landing, then settle into the bob
			var off = Vector2(0, sin(bob_t * 2.2) * 5.0)
			var sc = Vector2.ONE
			if spawn_t < SPAWN_LEN:
				if spawn_t < 0.3:
					var f = spawn_t / 0.3
					off = Vector2(0, -320.0 * (1.0 - f * f))
					sc = Vector2(0.92, 1.12)  # stretched while falling
				else:
					var k = (spawn_t - 0.3) / (SPAWN_LEN - 0.3)
					var squash = (1.0 - k) * sin(k * PI)
					off = Vector2.ZERO
					sc = Vector2(1.0 + 0.28 * squash, 1.0 - 0.24 * squash)
			_draw_body(off, 0.0, 0, sc)
		State.SPLIT:
			var sep = anim_t * 150.0
			var drop = anim_t * anim_t * 260.0
			_draw_body(Vector2(-sep, drop), -anim_t * 0.7, -1)
			_draw_body(Vector2(sep, drop), anim_t * 0.7, 1)
		State.BINNED:
			_draw_body(Vector2(0, anim_t * anim_t * 700.0), anim_t * 2.5, 0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# side: 0 = whole potato, -1 = left half, 1 = right half
func _draw_body(offset: Vector2, rot: float, side: int, body_scale: Vector2 = Vector2.ONE):
	draw_set_transform(offset, rot, body_scale)

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

	# outline so the body reads against the board
	var outline = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, body_color.darkened(0.45), 3.0, true)

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
