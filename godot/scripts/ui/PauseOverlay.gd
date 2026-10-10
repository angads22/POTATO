extends CanvasLayer
class_name PauseOverlay

# A modal pause menu that works while the tree is paused (PROCESS_MODE_ALWAYS).
# The owner passes the option list and connects `chosen(id)`. Keyboard
# (Up/Down + Enter, ESC = first option, letter hotkeys) and mouse (hover +
# click) both work. Pausing also pauses the music + beat clock so a cut
# resumes exactly where it left off.
#
#   var pause := PauseOverlay.new()
#   pause.options = [{"id": "resume", "label": "Resume", "key": KEY_ESCAPE}, ...]
#   pause.chosen.connect(_on_pause_choice)
#   add_child(pause)

signal chosen(id: String)

var title := "PAUSED"
var subtitle := ""
var body := ""                 # optional multi-line text under the subtitle
var options: Array = []        # [{id, label, key}]
var freeze_tree := true        # false in LAN multiplayer: the match keeps going
var selected := 0
var _rects: Array[Rect2] = []
var _canvas: Node2D

func _ready():
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)
	if freeze_tree:
		get_tree().paused = true
		AudioManager.pause_music()
	AudioManager.play_sfx("pause")

func close():
	if freeze_tree:
		get_tree().paused = false
		AudioManager.resume_music()
	queue_free()

func _process(_d):
	_canvas.queue_redraw()

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		for i in _rects.size():
			if _rects[i].has_point(event.position) and selected != i:
				selected = i
				AudioManager.play_sfx("menu_move")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _rects.size():
			if _rects[i].has_point(event.position):
				_pick(i)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_UP, KEY_W:
			selected = posmod(selected - 1, options.size())
			AudioManager.play_sfx("menu_move")
		KEY_DOWN, KEY_S:
			selected = posmod(selected + 1, options.size())
			AudioManager.play_sfx("menu_move")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_pick(selected)
		_:
			for i in options.size():
				if options[i].get("key", -1) == event.keycode:
					_pick(i)
					return

func _pick(i: int):
	var id: String = options[i].get("id", "")
	AudioManager.play_sfx("unpause" if id == "resume" else "menu_select")
	chosen.emit(id)

func _draw_menu():
	var font := ThemeDB.fallback_font
	var vp := _canvas.get_viewport_rect().size
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.02, 0.01, 0.62))
	var w: float = 420.0
	var body_lines := body.split("\n") if body != "" else PackedStringArray()
	var h := 120.0 + options.size() * 48.0 + (24.0 if subtitle != "" else 0.0) + body_lines.size() * 26.0
	if body != "":
		w = 640.0
	var panel := Rect2(vp.x / 2 - w / 2, vp.y / 2 - h / 2, w, h)
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.96)).draw(_canvas.get_canvas_item(), panel)
	var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 38)
	_canvas.draw_string(font, Vector2(vp.x / 2 - ts.x / 2, panel.position.y + 56), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color.GOLD)
	var y := panel.position.y + 80.0
	if subtitle != "":
		var ss := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		_canvas.draw_string(font, Vector2(vp.x / 2 - ss.x / 2, y + 4), subtitle,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.68, 0.55))
		y += 24.0
	for line in body_lines:
		var bs := font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		_canvas.draw_string(font, Vector2(vp.x / 2 - bs.x / 2, y + 26), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.9, 0.8))
		y += 26.0
	if body != "":
		y += 8.0
	_rects.clear()
	for i in options.size():
		var r := Rect2(panel.position.x + 30, y + 6, w - 60, 40)
		_rects.append(r)
		var active := i == selected
		if active:
			_canvas.draw_rect(r, Color(0.85, 0.68, 0.3, 0.22))
			_canvas.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(1.0, 0.8, 0.3))
		var label: String = options[i].get("label", "?")
		var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 21)
		_canvas.draw_string(font, Vector2(vp.x / 2 - ls.x / 2, r.position.y + 28), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.GOLD if active else Color(0.95, 0.9, 0.8))
		y += 48.0
