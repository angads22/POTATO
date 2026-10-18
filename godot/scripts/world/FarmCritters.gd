extends Node2D
class_name FarmCritters

# Little living things above the fields (design §5.5, §7.3):
# - the butterfly: it appears whenever FarmEconomy.butterfly_due() (a timed
#   spawn, or the welcome butterfly Collect schedules), flutters over
#   buffs.butterfly_field with a gold trail and a 12 s countdown ring, and is
#   caught by a click, by G from anywhere, or by walking within 60 px; the
#   HUD draws its edge arrow while it is off screen;
# - Spudling figures at their hut doors, waving while you're here, hopping
#   about their field while they work, out of sight while they nap;
# - the coin pops: "+3" / "+4 *" floating up from each plot after a tend, in a
#   quick ripple (stars are drawn, the font has none).

var ctrl                      # FarmController
var t := 0.0

# butterfly state (derived from the farm each tick; nothing here is saved)
var bf_active := false
var bf_pos := Vector2.ZERO
var bf_field := 0
var bf_spawn_ms := 0
var bf_life01 := 0.0          # 1 = just appeared, 0 = about to leave
var bf_welcome := false
var _trail: Array = []        # recent positions

var _pops: Array = []         # {pos, text, stars, age, delay}

func _ready():
	z_index = 3

# Called by the controller every frame with the live farm dict.
func tick(delta: float, farm: Dictionary, now: int):
	t += delta
	var due := FarmEconomy.butterfly_due(farm, now)
	if due:
		var spawn := int(farm["buffs"]["next_butterfly_ms"])
		var life_ms := int(FarmEconomy.cfg()["butterflies"].get("life_s", 12)) * 1000
		if not bf_active or spawn != bf_spawn_ms:
			bf_active = true
			bf_spawn_ms = spawn
			bf_field = int(farm["buffs"].get("butterfly_field", 0))
			bf_welcome = bool(farm["buffs"].get("welcome", false))
			_trail.clear()
			AudioManager.play_sfx("butterfly")
		bf_life01 = clampf(1.0 - float(now - spawn) / float(life_ms), 0.0, 1.0)
		var r := FarmView.field_rect(bf_field)
		var u := float(now - spawn) / 1000.0
		bf_pos = r.get_center() + Vector2(sin(u * 0.9) * r.size.x * 0.38, sin(u * 1.7 + 0.6) * r.size.y * 0.36) \
				+ Vector2(0, -20 + sin(u * 7.0) * 6.0)
		_trail.push_front(bf_pos)
		if _trail.size() > 14:
			_trail.pop_back()
	else:
		bf_active = false
	for p in _pops:
		p.age += delta
	_pops = _pops.filter(func(p): return p.age < p.delay + 1.1)
	queue_redraw()

# Coin pops for a tend: one per plot, rippling across the field.
func pop_field(i: int, coins: int, stars: Array):
	if stars.is_empty():
		return
	var r := FarmView.field_rect(i)
	var g := FarmView.plot_grid()
	var mults: Array = []
	var sum := 0.0
	var sm: Dictionary = FarmEconomy.cfg().get("stars", {})
	for s in stars:
		var m := 1.0 if s == 0 else (float(sm.get("gold_mult", 2.0)) if s == 2 else float(sm.get("silver_mult", 1.5)))
		mults.append(m)
		sum += m
	for k in stars.size():
		var c := k % g.x
		var row := k / g.x
		var pc := r.position + Vector2((c + 0.5) * r.size.x / g.x, (row + 0.5) * r.size.y / g.y)
		var v := int(round(coins * float(mults[k]) / maxf(0.01, sum)))
		_pops.append({"pos": pc, "text": "+%s" % NumFmt.coins(v), "stars": int(stars[k]), "age": 0.0, "delay": k * 0.04})

func pop_text(world_pos: Vector2, text: String):
	_pops.append({"pos": world_pos, "text": text, "stars": 0, "age": 0.0, "delay": 0.0})

func butterfly_world() -> Vector2:
	return bf_pos

func _draw():
	var farm: Dictionary = SaveDataManager.farm
	if farm.has("fields") and ctrl != null:
		_draw_spudlings(farm)
	if bf_active:
		_draw_butterfly()
	_draw_pops()

func _draw_butterfly():
	for k in range(_trail.size()):
		var a := 0.5 * (1.0 - float(k) / _trail.size())
		draw_circle(_trail[k] + Vector2(0, 8), 4.0 - k * 0.2, Color(1.0, 0.85, 0.3, a))
	var flap := sin(t * 18.0)
	var col := Color(0.6, 0.85, 1.0) if bf_welcome else Color(1.0, 0.78, 0.25)
	draw_circle(bf_pos, 34.0, Color(1.0, 0.95, 0.6, 0.12))
	WorldHUD.icon_butterfly(self, bf_pos, 22.0, flap, col)
	# countdown ring: the arc shrinks as its 12 s run out
	draw_arc(bf_pos, 36.0, -PI / 2.0, -PI / 2.0 + TAU * bf_life01, 32, Color(1.0, 0.95, 0.6, 0.85), 3.0)

func _draw_spudlings(farm: Dictionary):
	var now := FarmClock.now_ms()
	var present := FarmEconomy.is_present(farm, now)
	for i in FarmEconomy.FIELDS:
		var f: Dictionary = farm["fields"][i]
		if not (f["owned"] and f["hut"]):
			continue
		var hat := FarmView.hut_hat(int(f.get("hut_k", 0)))
		var door := FarmView.hut_pos(i) + Vector2(30, 30)
		if present:
			# waving hello by the door
			_spudling(door, hat, sin(t * 6.0 + i) * 0.6, 0.0)
			continue
		var v := FarmEconomy.field_view(farm, i, now)
		if v["working"]:
			var r := FarmView.field_rect(i)
			var u := t * 0.35 + i * 1.3
			var p := r.position + Vector2((0.5 + 0.42 * sin(u)) * r.size.x, (0.5 + 0.38 * sin(u * 1.7)) * r.size.y)
			_spudling(p, hat, 0.0, absf(sin(t * 8.0 + i)) * 6.0)

func _spudling(p: Vector2, hat: Color, wave: float, hop: float):
	var c := p - Vector2(0, hop)
	draw_set_transform(p + Vector2(0, 14), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := Color(0.82, 0.62, 0.36)
	draw_set_transform(c, 0.0, Vector2(1.0, 1.15))
	draw_circle(Vector2.ZERO, 13.0, body)
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 18, body.darkened(0.45), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(c + Vector2(-4, -3), 2.0, Color(0.15, 0.1, 0.05))
	draw_circle(c + Vector2(4, -3), 2.0, Color(0.15, 0.1, 0.05))
	draw_arc(c + Vector2(0, 2), 4.0, 0.3, PI - 0.3, 8, Color(0.3, 0.18, 0.08), 1.5)
	draw_rect(Rect2(c.x - 11, c.y - 16, 22, 5), hat)
	draw_circle(c + Vector2(0, -17), 7.0, hat)
	if wave != 0.0:
		var arm := c + Vector2(12, -2)
		draw_line(arm, arm + Vector2(8, -12).rotated(wave), body.darkened(0.15), 4.0)
		draw_circle(arm + Vector2(8, -12).rotated(wave), 3.5, body)

func _draw_pops():
	var font := ThemeDB.fallback_font
	for p in _pops:
		var a: float = p.age - p.delay
		if a < 0.0:
			continue
		var fr := clampf(a / 1.1, 0.0, 1.0)
		var pos: Vector2 = p.pos + Vector2(0, -20 - fr * 50.0)
		var alpha := 1.0 - fr * fr
		var zoom := 1.0 if ctrl == null else maxf(0.3, float(ctrl.zoom_now))
		var size := int(clampf(15.0 / zoom, 22.0, 44.0))
		var txt: String = p.text
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var ns: int = p.stars
		var sk := size / 26.0
		var total := w + ns * 18.0 * sk
		var x0 := pos.x - total / 2.0
		draw_string(font, Vector2(x0 + 2, pos.y + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.5 * alpha))
		draw_string(font, Vector2(x0, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(1.0, 0.86, 0.3, alpha) if ns == 0 else Color(1.0, 0.95, 0.6, alpha))
		for s in ns:
			var sc := Color(0.92, 0.92, 0.98, alpha) if ns == 1 else Color(1.0, 0.8, 0.2, alpha)
			WorldHUD.icon_star(self, Vector2(x0 + w + (10 + s * 18.0) * sk, pos.y - 9 * sk), 8.0 * sk, sc, false)
