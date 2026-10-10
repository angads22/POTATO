extends MinigameBase
class_name DodgeMinigame

# Dodge — a rotten potato is on the board. Press X to bin it.
# Pressing SPACE slices it (FAIL); hesitating past the bar's end also costs you.

const DODGE_BEATS = 6.0

var resolved: bool = false

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	resolved = false

func _process(_delta):
	if not is_active or resolved:
		return
	if beats() > DODGE_BEATS:
		resolved = true
		cut_result.quality = "MISS"
		cut_result.animation_trigger = "dodge_timeout"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	# SPACE on a rotten potato — sliced it, FAIL
	if resolved:
		return
	resolved = true
	cut_result.quality = "FAIL"
	cut_result.animation_trigger = "dodge_fail"
	end_minigame()

func _on_secondary_input():
	# X — binned it correctly
	if resolved:
		return
	resolved = true
	cut_result.quality = "PERFECT"
	cut_result.score_multiplier = 1.0
	cut_result.animation_trigger = "dodge_success"
	end_minigame()

func _draw():
	if not is_active:
		return
	var font = ThemeDB.fallback_font
	var pulse = beat_pulse(3.0)

	# red alarm tint + a border that throbs with the beat
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.8, 0.1, 0.1, 0.05 + pulse * 0.07))
	draw_rect(Rect2(8, 8, 1264, 704), Color(0.9, 0.15, 0.1, 0.35 + pulse * 0.5), false, 6.0)

	var warning = "ROTTEN POTATO!"
	var ws = font.get_string_size(warning, HORIZONTAL_ALIGNMENT_CENTER, -1, 42)
	draw_string(font, Vector2(640 - ws.x / 2, 130), warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color.ORANGE_RED)

	# countdown in beats: one segment per beat, draining
	var left := clampf(DODGE_BEATS - maxf(0.0, beats()), 0.0, DODGE_BEATS)
	var seg_w := 400.0 / DODGE_BEATS
	draw_rect(Rect2(438, 556, 404, 24), Color(1, 1, 1, 0.4), false, 2.0)
	for i in int(DODGE_BEATS):
		var f := clampf(left - i, 0.0, 1.0)
		if f > 0.0:
			draw_rect(Rect2(440 + i * seg_w + 1, 558, (seg_w - 2) * f, 20), Color.ORANGE_RED)

	draw_hint("[X] Bin it — do NOT press SPACE!   (right-click works too)")
