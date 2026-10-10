extends MinigameBase
class_name SliceMinigame

# Slice/Dice — the classic sweeping cursor; press SPACE at the centre.
# The sweep is locked to the music: it leaves the left end on the landing
# downbeat and crosses the centre on beat 3 (the snare). Golden potatoes
# sweep double-time — a cut on every beat — with slightly kinder windows.

const PERFECT_W = 0.02
const GREAT_W = 0.05
const GOOD_W = 0.11
const SWEEP_BEATS = 4.0
const GOLDEN_SWEEP_BEATS = 2.0
const GOLDEN_WIDEN = 1.3
const TIMEOUT_BEATS = 12.0   # three passes over the centre, then it's gone

var cursor: float = 0.0   # 0..1 along the track
var has_cut: bool = false
var widen: float = 1.0

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	has_cut = false
	cursor = 0.0
	var golden: bool = potato.get("rare", false)
	set_sweep(GOLDEN_SWEEP_BEATS if golden else SWEEP_BEATS)
	widen = GOLDEN_WIDEN if golden else 1.0

func _process(_delta):
	if not is_active or has_cut:
		return
	cursor = sweep_cursor()
	if beats() > TIMEOUT_BEATS:
		cut_result.quality = "MISS"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	if has_cut:
		return
	has_cut = true
	cursor = sweep_cursor()
	var q = judge(abs(cursor - 0.5), PERFECT_W * widen, GREAT_W * widen, GOOD_W * widen)
	cut_result.quality = q
	cut_result.score_multiplier = multiplier_for(q)
	cut_result.animation_trigger = "slice_" + q.to_lower()
	end_minigame()

func _draw():
	if not is_active:
		return
	draw_timing_track(cursor, PERFECT_W * widen, GREAT_W * widen, GOOD_W * widen, has_cut)
	if widen > 1.0:
		draw_hint("[SPACE] GOLDEN! Double-time — cut on any beat!")
	else:
		draw_hint("[SPACE] Slice on beat 3 — when the cursor hits the centre!")
