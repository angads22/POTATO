extends Node2D
class_name GameHUD

# HUD drawing, hosted on a CanvasLayer so it renders above the playfield
# and stays still during screen shake. Reads run state from GameManager and
# feedback state (popups/banner/clock) from the owning GameplayController.

var ctrl  # GameplayController

static func panel_style(bg := Color(0.18, 0.12, 0.07, 0.85)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.border_color = Color(0.85, 0.68, 0.3, 0.6)
	sb.set_border_width_all(2)
	return sb

func _draw():
	if ctrl == null:
		return
	var font = ThemeDB.fallback_font
	var s = GameManager.current_state

	# ── fever wash, pulsing edge vignette + banner ──
	if s.fever_active:
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 0.2, 1.0, 0.04 + 0.03 * pulse))
		var edge = Color(1.0, 0.25, 0.9, 0.12 + 0.14 * pulse)
		var thick = 16.0 + 10.0 * pulse
		draw_rect(Rect2(0, 0, 1280, thick), edge)
		draw_rect(Rect2(0, 720 - thick, 1280, thick), edge)
		draw_rect(Rect2(0, 0, thick, 720), edge)
		draw_rect(Rect2(1280 - thick, 0, thick, 720), edge)
		var fever = "FEVER x%.0f" % s.fever_multiplier
		var fs = font.get_string_size(fever, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
		panel_style(Color(0.35, 0.05, 0.3, 0.85)).draw(get_canvas_item(), Rect2(640 - fs.x / 2 - 14, 662, fs.x + 28, 40))
		draw_string(font, Vector2(640 - fs.x / 2, 690), fever, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.5, 1.0))

	# ── lives panel (hearts) ──
	panel_style().draw(get_canvas_item(), Rect2(10, 8, 150, 52))
	for i in range(3):
		var cx = 40.0 + i * 42.0
		var col = Color.CRIMSON if i < s.lives else Color(0.35, 0.3, 0.28)
		draw_circle(Vector2(cx - 6, 28), 8.0, col)
		draw_circle(Vector2(cx + 6, 28), 8.0, col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 13, 31), Vector2(cx + 13, 31), Vector2(cx, 48)
		]), col)

	# mode · stage and the equipped knife, under the hearts (dark so they
	# read on the cream wall)
	draw_string(font, Vector2(14, 84), "%s · Stage %d" % [s.mode.capitalize().replace("_", " "), s.stage], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.35, 0.22, 0.1))
	var knife = SaveDataManager.equipped_knife()
	if not knife.is_empty():
		draw_string(font, Vector2(14, 106), "%s ×%.1f" % [knife.get("name", ""), knife.get("damage", 1.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.3, 0.15))

	# ── score panel, top right ──
	panel_style().draw(get_canvas_item(), Rect2(1040, 8, 230, 66))
	var score_text = "%d" % s.score
	var ss = font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	draw_string(font, Vector2(1256 - ss.x, 40), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_string(font, Vector2(1052, 38), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.68, 0.3))
	var coin_text = "%d coins" % s.coins_earned
	var cs = font.get_string_size(coin_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(1256 - cs.x, 64), coin_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GOLD)

	# ── combo, centred, grows with the streak ──
	if s.combo > 1:
		var combo_text = "COMBO x%d" % s.combo
		var size = 20 + mini(s.combo, 20)
		var cbs = font.get_string_size(combo_text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		draw_string(font, Vector2(642 - cbs.x / 2, 52), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.2, 0.12, 0.05))
		draw_string(font, Vector2(640 - cbs.x / 2, 50), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.8, 0.2))

	# ── time-attack clock ──
	if s.mode == "time_attack":
		var t = "%0.1f" % ctrl.time_left
		var ts = font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 34)
		var t_col = Color.ORANGE_RED if ctrl.time_left < 10.0 else Color.WHITE
		panel_style().draw(get_canvas_item(), Rect2(640 - ts.x / 2 - 16, 64, ts.x + 32, 46))
		draw_string(font, Vector2(640 - ts.x / 2, 98), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, t_col)

	# ── rising quality popups above the potato ──
	for p in ctrl.popups:
		var frac = p.age / ctrl.POPUP_LIFE
		var col = p.color
		col.a = 1.0 - frac
		var shadow = Color(0, 0, 0, (1.0 - frac) * 0.6)
		var ps = font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
		var py = 200 - frac * 60.0
		draw_string(font, Vector2(642 - ps.x / 2, py + 2), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, shadow)
		draw_string(font, Vector2(640 - ps.x / 2, py), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)

	# ── stage banner ──
	if ctrl.banner_age < 1.5:
		var alpha = 1.0 if ctrl.banner_age < 1.0 else (1.5 - ctrl.banner_age) * 2.0
		var bs = font.get_string_size(ctrl.banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 56)
		draw_rect(Rect2(0, 300, 1280, 110), Color(0.1, 0.06, 0.03, 0.7 * alpha))
		draw_rect(Rect2(0, 300, 1280, 4), Color(0.85, 0.68, 0.3, alpha))
		draw_rect(Rect2(0, 406, 1280, 4), Color(0.85, 0.68, 0.3, alpha))
		draw_string(font, Vector2(643 - bs.x / 2, 375), ctrl.banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0, 0, 0, 0.5 * alpha))
		draw_string(font, Vector2(640 - bs.x / 2, 372), ctrl.banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.85, 0.3, alpha))

	# ── ESC hint ──
	draw_string(font, Vector2(20, 706), "[ESC] Quit to menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.85, 0.75, 0.5))
