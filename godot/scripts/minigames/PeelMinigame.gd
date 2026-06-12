extends MinigameBase
class_name PeelMinigame

# Peel — tap to start the rising peel gauge, tap again to lock it inside
# the green band. Overfilling ruins the potato.

const GAUGE_X = 920.0
const GAUGE_Y = 160.0
const GAUGE_W = 90.0
const GAUGE_H = 360.0
const FILL_TIME = 1.6     # seconds for the gauge to rise bottom→top
const TIMEOUT = 6.0

var fill: float = 0.0     # 0..1, rises from the bottom
var started: bool = false
var locked: bool = false
var band_centre: float = 0.7
var band_half: float = 0.09

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	fill = 0.0
	started = false
	locked = false
	band_centre = randf_range(0.55, 0.85)

func _process(delta):
	if not is_active or locked:
		return

	if started:
		fill += delta / FILL_TIME
		if fill >= 1.0:
			locked = true
			cut_result.quality = "FAIL"
			cut_result.animation_trigger = "peel_fail"
			end_minigame()
	elif elapsed() > TIMEOUT:
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if locked:
		return
	if not started:
		started = true
	else:
		locked = true
		var q = judge(abs(fill - band_centre), band_half * 0.33, band_half * 0.66, band_half)
		cut_result.quality = q
		cut_result.score_multiplier = multiplier_for(q)
		cut_result.animation_trigger = "peel_" + q.to_lower()
		end_minigame()

func _draw():
	if not is_active:
		return

	# frame + background
	draw_rect(Rect2(GAUGE_X - 4, GAUGE_Y - 4, GAUGE_W + 8, GAUGE_H + 8), Color(0.35, 0.28, 0.18), false, 2.0)
	draw_rect(Rect2(GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H), Color(0.09, 0.08, 0.1))

	# target band (gauge coordinates run top-down, fill runs bottom-up)
	var band_top = GAUGE_Y + GAUGE_H * (1.0 - (band_centre + band_half))
	draw_rect(Rect2(GAUGE_X, band_top, GAUGE_W, GAUGE_H * band_half * 2.0), Color(0.25, 0.75, 0.3, 0.55))

	# rising peel fill
	var fh = GAUGE_H * clampf(fill, 0.0, 1.0)
	draw_rect(Rect2(GAUGE_X, GAUGE_Y + GAUGE_H - fh, GAUGE_W, fh), Color(0.62, 0.42, 0.24, 0.9))

	# lock line
	if started:
		var line_y = GAUGE_Y + GAUGE_H * (1.0 - clampf(fill, 0.0, 1.0))
		draw_rect(Rect2(GAUGE_X - 8, line_y - 2, GAUGE_W + 16, 4), Color.CYAN if locked else Color.WHITE)

	if not started:
		draw_hint("[SPACE] Tap to start peeling...")
	else:
		draw_hint("[SPACE] Tap again to lock it in the green band!")
