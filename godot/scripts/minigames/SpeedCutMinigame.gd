extends MinigameBase
class_name SpeedCutMinigame

# Speed Cut — a fast double-time sweep (the centre comes round on every
# other beat) while the sweet spot snaps smaller on each beat. Commit early.

const BASE_PERFECT_W = 0.025
const BASE_GREAT_W = 0.06
const BASE_GOOD_W = 0.12
const SWEEP_BEATS = 2.0
const SHRINK_BEATS = 6     # beats until the zones bottom out
const MIN_SCALE = 0.2
const TIMEOUT_BEATS = 8.0

var cursor: float = 0.0
var has_cut: bool = false
var _last_step := -1

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	has_cut = false
	cursor = 0.0
	_last_step = -1
	set_sweep(SWEEP_BEATS)

# shrinks in steps, one per beat — you can hear (and see) it tighten
func zone_scale() -> float:
	var step := clampi(floori(maxf(0.0, beats())), 0, SHRINK_BEATS)
	return lerpf(1.0, MIN_SCALE, float(step) / SHRINK_BEATS)

func _process(_delta):
	if not is_active or has_cut:
		return
	cursor = sweep_cursor()
	var step := floori(beats())
	if step > _last_step and step >= 1 and step <= SHRINK_BEATS:
		AudioManager.play_sfx("zone_tick", 0.0, 1.0 + 0.05 * step)
	_last_step = maxi(_last_step, step)
	if beats() > TIMEOUT_BEATS:
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if has_cut:
		return
	has_cut = true
	cursor = sweep_cursor()
	var s = zone_scale()
	var q = judge(abs(cursor - 0.5), BASE_PERFECT_W * s, BASE_GREAT_W * s, BASE_GOOD_W * s)
	cut_result.quality = q
	cut_result.score_multiplier = multiplier_for(q)
	cut_result.animation_trigger = "speed_cut_" + q.to_lower()
	end_minigame()

func _draw():
	if not is_active:
		return
	var s = zone_scale()
	draw_timing_track(cursor, BASE_PERFECT_W * s, BASE_GREAT_W * s, BASE_GOOD_W * s, has_cut)
	draw_hint("[SPACE] The zone shrinks every beat — cut fast!")
