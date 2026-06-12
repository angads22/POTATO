extends MinigameBase
class_name SliceMinigame

# Slice/Dice — the classic sweeping cursor; press SPACE at the centre.

const PERFECT_W = 0.02
const GREAT_W = 0.05
const GOOD_W = 0.11
const TIMEOUT = 6.0

var cursor: float = 0.0   # 0..1 along the track
var dir: float = 1.0
var speed: float = 0.6    # track-widths per second
var has_cut: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	has_cut = false
	cursor = 0.0
	dir = 1.0
	# golden potatoes sweep faster — the reward is earned
	speed = 0.85 if potato.get("rare", false) else 0.6

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
	var q = judge(abs(cursor - 0.5), PERFECT_W, GREAT_W, GOOD_W)
	cut_result.quality = q
	cut_result.score_multiplier = multiplier_for(q)
	cut_result.animation_trigger = "slice_" + q.to_lower()
	end_minigame()

func _draw():
	if not is_active:
		return
	draw_timing_track(cursor, PERFECT_W, GREAT_W, GOOD_W, has_cut)
	draw_hint("[SPACE] Slice at the centre!")
