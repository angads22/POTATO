extends Node2D
class_name MinigameBase

# Base class for all minigame mechanics
# Extend this for each cut type (Slice, Peel, Speed, Julienne, Dodge)
#
# Everything runs on the music: each cut has a `beat_origin` (the downbeat the
# potato lands on) and cursors are pure functions of the beat clock
# (AudioManager.music_beat()) rather than accumulated frame deltas. The
# classic sweep crosses the centre on beat 3 of the bar — the snare in every
# kitchen groove — so a PERFECT is a cut on the beat you can hear. With the
# sound off (or on the headless CI server) the clock runs on the wall clock
# at the same tempo, so the game plays identically.

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
# presses this many beats before the landing still count (early-bird grace)
const EARLY_GRACE = 0.25

var potato_data: Dictionary
var cut_result: CutResult = CutResult.new()
var timer_started: float = 0.0
var is_active: bool = false
var beat_origin: float = 0.0

# phase-continuous sweep state (see sweep_cursor / change_sweep)
var _sweep_beats: float = 4.0
var _sweep_ref_beat: float = 0.0
var _sweep_ref_phase: float = 0.0

# origin_beat: the beat the potato lands on; defaults to "now"
func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	potato_data = potato
	cut_result = CutResult.new()
	timer_started = Time.get_ticks_msec()
	beat_origin = origin_beat if origin_beat > -1.0e8 else AudioManager.music_beat()
	_sweep_ref_beat = 0.0
	_sweep_ref_phase = 0.0
	is_active = true
	minigame_started.emit()
	queue_redraw()

# Beats since the potato landed (negative while it is still falling).
func beats() -> float:
	return AudioManager.music_beat() - beat_origin

# Seconds since the potato landed, at the current tempo.
func elapsed() -> float:
	return beats() * AudioManager.beat_sec()

func landed() -> bool:
	return beats() >= 0.0

func end_minigame():
	is_active = false
	cut_result.time_taken = elapsed()
	minigame_completed.emit({
		"quality": cut_result.quality,
		"multiplier": cut_result.score_multiplier,
		"animation": cut_result.animation_trigger,
		"beat": beats(),
	})
	queue_redraw()

# Quick-cut bonus window: GOOD+ cuts under 1.5s earn +25% in GameManager
func check_quick_cut() -> bool:
	return cut_result.time_taken < 1.5

func _input(event: InputEvent):
	if not is_active or beats() < -EARLY_GRACE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_primary_input()
		elif event.keycode == KEY_X:
			_on_secondary_input()
	elif event is InputEventMouseButton and event.pressed:
		# mouse / touchpad: left click cuts, right click bins
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_primary_input()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_secondary_input()

# Override in subclasses
func _on_primary_input():
	pass

# Override in subclasses (rotten-potato bin)
func _on_secondary_input():
	pass

# ────────────────────────────────────────────────────────
#  Beat-locked sweeping cursor
# ────────────────────────────────────────────────────────
#
# The cursor is a triangle wave over the beat clock: `sweep_beats` is the
# time for one end-to-end pass. With the default 4 it leaves the left end on
# the landing downbeat and crosses the centre on beat 3 of every bar.

func set_sweep(sweep_beats: float, phase: float = 0.0):
	_sweep_beats = sweep_beats
	_sweep_ref_beat = 0.0
	_sweep_ref_phase = phase

# Change speed mid-sweep without the cursor jumping (Julienne's speed-up).
func change_sweep(new_sweep_beats: float):
	_sweep_ref_phase = sweep_phase()
	_sweep_ref_beat = maxf(0.0, beats())
	_sweep_beats = new_sweep_beats

func sweep_phase() -> float:
	var b := maxf(0.0, beats())
	return _sweep_ref_phase + (b - _sweep_ref_beat) / _sweep_beats

func sweep_cursor() -> float:
	var ph := fposmod(sweep_phase(), 2.0)
	return ph if ph <= 1.0 else 2.0 - ph

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

# 0..1 flash that peaks on every beat and decays through it
static func beat_pulse(sharp: float = 5.0) -> float:
	var b := AudioManager.music_beat()
	if b < 0.0:
		return 0.0
	return exp(-fposmod(b, 1.0) * sharp)

# Horizontal timing track with perfect/great/good zones centred at 0.5
func draw_timing_track(cursor01: float, perfect_w: float, great_w: float, good_w: float, locked: bool = false,
		lamp_targets: Array = [2]):
	var cx = TRACK_X + TRACK_W * 0.5
	var pulse := beat_pulse()

	# frame (breathes with the beat) + background
	var frame_col := Color(0.35, 0.28, 0.18).lerp(Color(0.95, 0.78, 0.35), pulse * 0.6)
	draw_rect(Rect2(TRACK_X - 4, TRACK_Y - 4, TRACK_W + 8, TRACK_H + 8), frame_col, false, 2.0 + pulse * 1.5)
	draw_rect(Rect2(TRACK_X, TRACK_Y, TRACK_W, TRACK_H), Color(0.09, 0.08, 0.1))

	# zones, widest first so they layer correctly
	draw_rect(Rect2(cx - TRACK_W * good_w, TRACK_Y, TRACK_W * good_w * 2.0, TRACK_H), Color(0.8, 0.65, 0.15, 0.45))
	draw_rect(Rect2(cx - TRACK_W * great_w, TRACK_Y, TRACK_W * great_w * 2.0, TRACK_H), Color(0.25, 0.75, 0.3, 0.65))
	draw_rect(Rect2(cx - TRACK_W * perfect_w, TRACK_Y, TRACK_W * perfect_w * 2.0, TRACK_H), Color(1, 1, 1, 0.9))

	# centre marker — grows as the cursor closes in on it
	var near := clampf(1.0 - absf(cursor01 - 0.5) * 6.0, 0.0, 1.0)
	var mk := 7.0 + near * 5.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - mk, TRACK_Y - 16 - near * 4), Vector2(cx + mk, TRACK_Y - 16 - near * 4), Vector2(cx, TRACK_Y - 5)
	]), Color.WHITE.lerp(Color.GOLD, near))

	# cursor
	var px = TRACK_X + clamp(cursor01, 0.0, 1.0) * TRACK_W
	var col = Color.CYAN if locked else Color.WHITE
	draw_rect(Rect2(px - 3, TRACK_Y - 8, 6, TRACK_H + 16), col)

	_draw_beat_lamps(TRACK_Y + TRACK_H + 14, lamp_targets)

# Four lamps under the track, one per beat of the bar; the one the cut is
# due on (beat 3) is gold. A metronome you can see.
func _draw_beat_lamps(y: float, target_beats: Array = [2]):
	var b := AudioManager.music_beat()
	var in_bar := posmod(floori(b), 4) if b >= 0.0 else -1
	var pulse := beat_pulse(4.0)
	draw_rect(Rect2(640.0 - 62.0, y - 11.0, 124.0, 22.0), Color(0.1, 0.07, 0.04, 0.55))
	for i in 4:
		var x := 640.0 + (i - 1.5) * 28.0
		var is_target: bool = i in target_beats
		var base := Color(0.85, 0.68, 0.3, 0.45) if is_target else Color(0.7, 0.65, 0.6, 0.3)
		var r := 5.0
		if i == in_bar:
			base = Color(1.0, 0.85, 0.3) if is_target else Color(0.97, 0.94, 0.88)
			r = 5.0 + pulse * 3.0
		if is_target:
			draw_arc(Vector2(x, y), 8.5, 0.0, TAU, 20, Color(1.0, 0.82, 0.3, 0.7), 1.5)
		draw_circle(Vector2(x, y), r, base)

# Centred instruction line under the track
func draw_hint(text: String):
	var font = ThemeDB.fallback_font
	var size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(640 - size.x / 2, TRACK_Y + 72), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.85, 0.85))
