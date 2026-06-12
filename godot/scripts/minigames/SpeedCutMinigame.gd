extends MinigameBase
class_name SpeedCutMinigame

# Speed Cut — the sweet spot shrinks while the cursor sweeps; commit fast.

const BASE_PERFECT_W = 0.025
const BASE_GREAT_W = 0.06
const BASE_GOOD_W = 0.12
const SHRINK_TIME = 3.0   # seconds until zones reach minimum size
const MIN_SCALE = 0.2
const TIMEOUT = 4.0

var cursor: float = 0.0
var dir: float = 1.0
var speed: float = 0.9
var has_cut: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	has_cut = false
	cursor = 0.0
	dir = 1.0

func zone_scale() -> float:
	return lerpf(1.0, MIN_SCALE, clampf(elapsed() / SHRINK_TIME, 0.0, 1.0))

func _process(delta):
	if not is_active or has_cut:
		return
	cursor += dir * speed * delta
	if cursor >= 1.0:
		cursor = 1.0
		dir = -1.0
	elif cursor <= 0.0:
		cursor = 0.0
		dir = 1.0
	if elapsed() > TIMEOUT:
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if has_cut:
		return
	has_cut = true
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
	draw_hint("[SPACE] The zone is shrinking — cut fast!")
