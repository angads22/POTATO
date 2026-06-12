extends Node2D
class_name MinigameBase

# Base class for all minigame mechanics
# Extend this for each cut type (Slice, Peel, Speed, Julienne, Dodge)

signal minigame_started
signal minigame_completed(result: Dictionary)  # {quality, multiplier, animation}

class CutResult:
	var quality: String = "MISS"  # "PERFECT", "GREAT", "GOOD", "MISS", "FAIL"
	var score_multiplier: float = 0.0
	var time_taken: float = 0.0
	var animation_trigger: String = ""

# Shared layout for the bar-based mechanics (screen is 1280x720)
const TRACK_X = 240.0
const TRACK_W = 800.0
const TRACK_H = 26.0
const TRACK_Y = 560.0

var potato_data: Dictionary
var cut_result: CutResult = CutResult.new()
var timer_started: float = 0.0
var is_active: bool = false

func start_minigame(potato: Dictionary):
	potato_data = potato
	cut_result = CutResult.new()
	timer_started = Time.get_ticks_msec()
	is_active = true
	minigame_started.emit()
	queue_redraw()

func elapsed() -> float:
	return (Time.get_ticks_msec() - timer_started) / 1000.0

func end_minigame():
	is_active = false
	cut_result.time_taken = elapsed()
	minigame_completed.emit({
		"quality": cut_result.quality,
		"multiplier": cut_result.score_multiplier,
		"animation": cut_result.animation_trigger
	})
	queue_redraw()

# Quick-cut bonus window: GOOD+ cuts under 1.5s earn +25% in GameManager
func check_quick_cut() -> bool:
	return cut_result.time_taken < 1.5

func _input(event: InputEvent):
	if not is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_primary_input()
		elif event.keycode == KEY_X:
			_on_secondary_input()

# Override in subclasses
func _on_primary_input():
	pass

# Override in subclasses (rotten-potato bin)
func _on_secondary_input():
	pass

# ────────────────────────────────────────────────────────
#  Shared judging helpers
#  Distances/widths are in track-fractions (0..1, centre = 0.5)
# ────────────────────────────────────────────────────────

func judge(dist01: float, perfect_w: float, great_w: float, good_w: float) -> String:
	if dist01 <= perfect_w:
		return "PERFECT"
	if dist01 <= great_w:
		return "GREAT"
	if dist01 <= good_w:
		return "GOOD"
	return "MISS"

func multiplier_for(quality: String) -> float:
	match quality:
		"PERFECT":
			return 1.5
		"GREAT":
			return 1.25
		"GOOD":
			return 1.0
		_:
			return 0.0

# ────────────────────────────────────────────────────────
#  Shared drawing helpers
# ────────────────────────────────────────────────────────

# Horizontal timing track with perfect/great/good zones centred at 0.5
func draw_timing_track(cursor01: float, perfect_w: float, great_w: float, good_w: float, locked: bool = false):
	var font = ThemeDB.fallback_font
	var cx = TRACK_X + TRACK_W * 0.5

	# frame + background
	draw_rect(Rect2(TRACK_X - 4, TRACK_Y - 4, TRACK_W + 8, TRACK_H + 8), Color(0.35, 0.28, 0.18), false, 2.0)
	draw_rect(Rect2(TRACK_X, TRACK_Y, TRACK_W, TRACK_H), Color(0.09, 0.08, 0.1))

	# zones, widest first so they layer correctly
	draw_rect(Rect2(cx - TRACK_W * good_w, TRACK_Y, TRACK_W * good_w * 2.0, TRACK_H), Color(0.8, 0.65, 0.15, 0.45))
	draw_rect(Rect2(cx - TRACK_W * great_w, TRACK_Y, TRACK_W * great_w * 2.0, TRACK_H), Color(0.25, 0.75, 0.3, 0.65))
	draw_rect(Rect2(cx - TRACK_W * perfect_w, TRACK_Y, TRACK_W * perfect_w * 2.0, TRACK_H), Color(1, 1, 1, 0.9))

	# centre marker
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 7, TRACK_Y - 16), Vector2(cx + 7, TRACK_Y - 16), Vector2(cx, TRACK_Y - 5)
	]), Color.WHITE)

	# cursor
	var px = TRACK_X + clamp(cursor01, 0.0, 1.0) * TRACK_W
	var col = Color.CYAN if locked else Color.WHITE
	draw_rect(Rect2(px - 3, TRACK_Y - 8, 6, TRACK_H + 16), col)

# Centred instruction line under the track
func draw_hint(text: String):
	var font = ThemeDB.fallback_font
	var size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(640 - size.x / 2, TRACK_Y + 64), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.85, 0.85))
