extends MinigameBase
class_name PeelMinigame

# Peel — tap to start the rising peel gauge, tap again to lock it inside
# the green band. Overfilling ruins the potato. The gauge fills over one bar
# of the music, so the band sits on a beat you can count to.

const GAUGE_X = 920.0
const GAUGE_Y = 160.0
const GAUGE_W = 90.0
const GAUGE_H = 360.0
const FILL_BEATS = 4.0    # bottom → top in one bar
const TIMEOUT_BEATS = 12.0

var fill: float = 0.0     # 0..1, rises from the bottom
var started: bool = false
var locked: bool = false
var band_centre: float = 0.7
var band_half: float = 0.09
var _start_beat: float = 0.0

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	fill = 0.0
	started = false
	locked = false
	# park the band on a beat or half-beat of the fill (2.25 .. 3.5 beats in)
	band_centre = [0.5625, 0.625, 0.6875, 0.75, 0.8125, 0.875].pick_random()

func _process(_delta):
	if not is_active or locked:
		return

	if started:
		fill = (beats() - _start_beat) / FILL_BEATS
		if fill >= 1.0:
			locked = true
			cut_result.quality = "FAIL"
			cut_result.animation_trigger = "peel_fail"
			end_minigame()
	elif beats() > TIMEOUT_BEATS:
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if locked:
		return
	if not started:
		started = true
		_start_beat = maxf(0.0, beats())
		AudioManager.play_sfx("peel_start")
	else:
		locked = true
		fill = (beats() - _start_beat) / FILL_BEATS
		var q = judge(abs(fill - band_centre), band_half * 0.33, band_half * 0.66, band_half)
		cut_result.quality = q
		cut_result.score_multiplier = multiplier_for(q)
		cut_result.animation_trigger = "peel_" + q.to_lower()
		end_minigame()

func _draw():
	if not is_active:
		return

	# frame + background
	var pulse := beat_pulse()
	draw_rect(Rect2(GAUGE_X - 4, GAUGE_Y - 4, GAUGE_W + 8, GAUGE_H + 8),
			Color(0.35, 0.28, 0.18).lerp(Color(0.95, 0.78, 0.35), pulse * 0.5), false, 2.0 + pulse)
	draw_rect(Rect2(GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H), Color(0.09, 0.08, 0.1))

	# beat ticks up the side: the fill passes one per beat
	for k in range(1, int(FILL_BEATS)):
		var ty := GAUGE_Y + GAUGE_H * (1.0 - k / FILL_BEATS)
		draw_line(Vector2(GAUGE_X - 10, ty), Vector2(GAUGE_X, ty), Color(0.85, 0.75, 0.55, 0.6), 2.0)

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

	_draw_beat_lamps(TRACK_Y + 40, [])
	if not started:
		draw_hint("[SPACE] Tap to start peeling...")
	else:
		draw_hint("[SPACE] Tap again to lock it in the green band!")
