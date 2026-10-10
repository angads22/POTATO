extends MinigameBase
class_name JulienneMinigame

# Julienne — land two cuts on the same track; scored as the worse.
# After the first cut the sweep doubles in speed (phase-continuous, so the
# cursor never jumps): an on-beat first cut lines the second up exactly two
# beats later, on the next downbeat — chop on 3, chop on 1.

const PERFECT_W = 0.025
const GREAT_W = 0.06
const GOOD_W = 0.12
const SWEEP_BEATS = 4.0
const FAST_SWEEP_BEATS = 2.0
const SECOND_CUT_BEATS = 3.0
const TIMEOUT_BEATS = 12.0

const QUALITY_ORDER = ["PERFECT", "GREAT", "GOOD", "MISS"]

var cursor: float = 0.0
var first_quality: String = ""
var first_cursor: float = -1.0
var second_deadline: float = 0.0   # in beats since landing
var done: bool = false

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	cursor = 0.0
	set_sweep(SWEEP_BEATS)
	first_quality = ""
	first_cursor = -1.0
	done = false

func _process(_delta):
	if not is_active or done:
		return
	cursor = sweep_cursor()
	if first_quality != "" and beats() > second_deadline:
		done = true
		cut_result.quality = "MISS"
		end_minigame()
	elif first_quality == "" and beats() > TIMEOUT_BEATS:
		done = true
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if done:
		return
	cursor = sweep_cursor()
	var q = judge(abs(cursor - 0.5), PERFECT_W, GREAT_W, GOOD_W)

	if first_quality == "":
		# First cut: remember it, speed up, start the follow-up window
		first_quality = q
		first_cursor = cursor
		change_sweep(FAST_SWEEP_BEATS)
		second_deadline = maxf(0.0, beats()) + SECOND_CUT_BEATS
		AudioManager.play_sfx_varied("cut_good", 0.05, -6.0)
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
			Vector2(px - 6, TRACK_Y - 18), Vector2(px + 6, TRACK_Y - 18), Vector2(px, TRACK_Y - 7)
		]), Color.CYAN)

	if first_quality == "":
		draw_hint("[SPACE] Julienne — two cuts! Land the first on beat 3...")
	else:
		draw_hint("[SPACE] ...and the second on the downbeat! (scored as the worse)")
