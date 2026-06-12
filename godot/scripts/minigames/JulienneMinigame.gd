extends MinigameBase
class_name JulienneMinigame

# Julienne — land two quick cuts on the same track; scored as the worse.
# After the first cut the cursor speeds up and a second must land within
# the follow-up window.

const PERFECT_W = 0.025
const GREAT_W = 0.06
const GOOD_W = 0.12
const SECOND_CUT_WINDOW = 1.2
const TIMEOUT = 6.0

const QUALITY_ORDER = ["PERFECT", "GREAT", "GOOD", "MISS"]

var cursor: float = 0.0
var dir: float = 1.0
var speed: float = 0.6
var first_quality: String = ""
var first_cursor: float = -1.0
var second_deadline: float = 0.0
var done: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	cursor = 0.0
	dir = 1.0
	speed = 0.6
	first_quality = ""
	first_cursor = -1.0
	done = false

func _process(delta):
	if not is_active or done:
		return
	cursor += dir * speed * delta
	if cursor >= 1.0:
		cursor = 1.0
		dir = -1.0
	elif cursor <= 0.0:
		cursor = 0.0
		dir = 1.0

	if first_quality != "" and elapsed() > second_deadline:
		done = true
		cut_result.quality = "MISS"
		end_minigame()
	elif first_quality == "" and elapsed() > TIMEOUT:
		done = true
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if done:
		return
	var q = judge(abs(cursor - 0.5), PERFECT_W, GREAT_W, GOOD_W)

	if first_quality == "":
		# First cut: remember it, speed up, start the follow-up clock
		first_quality = q
		first_cursor = cursor
		speed *= 1.35
		second_deadline = elapsed() + SECOND_CUT_WINDOW
	else:
		# Second cut: score as the worse of the two
		done = true
		var worse = maxi(QUALITY_ORDER.find(first_quality), QUALITY_ORDER.find(q))
		cut_result.quality = QUALITY_ORDER[worse]
		cut_result.score_multiplier = multiplier_for(cut_result.quality)
		cut_result.animation_trigger = "julienne_" + cut_result.quality.to_lower()
		end_minigame()

func _draw():
	if not is_active:
		return
	draw_timing_track(cursor, PERFECT_W, GREAT_W, GOOD_W, done)

	# marker showing where the first cut landed
	if first_cursor >= 0.0:
		var px = TRACK_X + first_cursor * TRACK_W
		draw_colored_polygon(PackedVector2Array([
			Vector2(px - 6, TRACK_Y + TRACK_H + 14), Vector2(px + 6, TRACK_Y + TRACK_H + 14), Vector2(px, TRACK_Y + TRACK_H + 3)
		]), Color.CYAN)

	if first_quality == "":
		draw_hint("[SPACE] Julienne — two cuts! Land the first...")
	else:
		draw_hint("[SPACE] Now the second — quick! (scored as the worse)")
