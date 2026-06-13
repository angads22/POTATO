extends Node3D
class_name FpsArena

# The SPUD BLASTER deathmatch arena — a procedurally built 3D box-canyon with
# cover crates. This node has a stable scene path ("/root/FpsArena" once loaded
# via change_scene), so all the gameplay RPCs (movement / shots / damage /
# scores) live here and route reliably across peers. ENet's server relay
# forwards client→client packets through the host.
#
# Authority model: the host (peer 1) — or, offline, the single local peer —
# owns health, frags, deaths and respawns. Each peer simulates its own avatar
# and broadcasts its transform; everyone else interpolates. Hit detection is
# done on the shooter and confirmed by the authority (casual, responsive).

const RAY_LEN := 200.0
const FLOOR_SIZE := 44.0
const HALF_FLOOR := FLOOR_SIZE / 2.0
const WALL_H := 7.0
const BULLET_DMG := 34
const RESPAWN_DELAY := 2.0
const PRACTICE_BOTS := 3

var players := {}        # peer_id -> FpsPlayer
var bots: Array = []     # FpsBot (offline practice only)
var scores := {}         # peer_id -> frags
var spawn_points: Array[Vector3] = []

var frag_limit := FpsNetwork.DEFAULT_FRAG_LIMIT
var time_left := FpsNetwork.DEFAULT_TIME_LIMIT
var match_over := false
var paused := false
var input_locked := false
var winner_id := -1

var _spud_mat: StandardMaterial3D
var _splat_mat: StandardMaterial3D
var _return_timer := 0.0
var _leaving := false
var hud

func _ready() -> void:
	name = "FpsArena"
	seed(FpsNetwork.match_seed)
	frag_limit = FpsNetwork.frag_limit
	time_left = FpsNetwork.time_limit
	_spud_mat = _make_spud_mat()
	_splat_mat = _make_splat_mat()

	_build_environment()
	_build_geometry()
	_make_spawn_points()

	# spawn an avatar for every known peer (roster was synced in the lobby)
	for pid in _sorted_ids():
		_spawn_player(pid)

	if FpsNetwork.mode == "offline":
		for i in range(PRACTICE_BOTS):
			spawn_bot(_random_ground_point())

	# late join / leave during a networked match
	if FpsNetwork.is_networked():
		FpsNetwork.roster_changed.connect(_reconcile_players)

	_build_hud()

	# capture the mouse for first-person look (skip on the headless CI server)
	if get_local_player() != null and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if FpsNetwork.is_networked() and FpsNetwork.roster_changed.is_connected(_reconcile_players):
		FpsNetwork.roster_changed.disconnect(_reconcile_players)

func _process(delta: float) -> void:
	if match_over:
		_return_timer -= delta
		if _return_timer <= 0.0:
			_go_to_menu()
		return
	time_left = maxf(0.0, time_left - delta)
	if _auth() and time_left <= 0.0:
		end_match(leader())

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if match_over:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE]:
			_go_to_menu()
		return
	match event.keycode:
		KEY_ESCAPE:
			_toggle_pause()
		KEY_Q:
			if paused:
				_go_to_menu()

# ── helpers ──────────────────────────────────────────────────────────────────

func _auth() -> bool:
	return FpsNetwork.is_authority()

func _net() -> bool:
	return FpsNetwork.is_networked()

func get_local_player():
	return players.get(FpsNetwork.local_id())

func _sorted_ids() -> Array:
	var ids := FpsNetwork.players.keys()
	ids.sort()
	return ids

func leader() -> int:
	var best := -1
	var best_score := -1
	for pid in _sorted_ids():
		var s: int = scores.get(pid, 0)
		if s > best_score:
			best_score = s
			best = pid
	return best

# ── spawning ─────────────────────────────────────────────────────────────────

func _spawn_player(pid: int) -> void:
	if players.has(pid):
		return
	var p := FpsPlayer.new()
	p.name = "P_%d" % pid
	var pname := str(FpsNetwork.players.get(pid, {}).get("name", "Chef"))
	p.setup(pid, pname, self)
	add_child(p)
	var idx := _sorted_ids().find(pid)
	if idx < 0:
		idx = players.size()
	p.teleport(spawn_points[idx % spawn_points.size()])
	players[pid] = p
	if not scores.has(pid):
		scores[pid] = 0

func spawn_bot(pos: Vector3) -> FpsBot:
	var b := FpsBot.new()
	b.arena = self
	add_child(b)
	b.global_position = pos
	bots.append(b)
	return b

func _reconcile_players() -> void:
	for pid in FpsNetwork.players.keys():
		if not players.has(pid):
			_spawn_player(pid)
	for pid in players.keys().duplicate():
		if not FpsNetwork.players.has(pid):
			var p = players[pid]
			players.erase(pid)
			scores.erase(pid)
			if is_instance_valid(p):
				p.queue_free()
	if _auth() and _net():
		_mirror_scores.rpc(scores)

# ── firing ───────────────────────────────────────────────────────────────────

# Always called on the shooter's own machine (local input only).
func fire_from(shooter: FpsPlayer) -> void:
	if match_over or shooter == null or not shooter.alive:
		return
	var ray := shooter.aim_ray
	ray.force_raycast_update()
	var muzzle := shooter.muzzle_world_pos()
	var endpoint: Vector3
	var hit_player: FpsPlayer = null
	var hit_bot: FpsBot = null
	if ray.is_colliding():
		endpoint = ray.get_collision_point()
		var col = ray.get_collider()
		if col is FpsPlayer and col != shooter:
			hit_player = col as FpsPlayer
		elif col is FpsBot:
			hit_bot = col as FpsBot
	else:
		endpoint = muzzle - shooter.global_transform.basis.z * RAY_LEN

	_spawn_spud(muzzle, endpoint)
	shooter.show_muzzle_flash()
	AudioManager.play_sfx("cut_great")
	if _net():
		_recv_shot.rpc(muzzle, endpoint, shooter.peer_id)

	if hit_player != null:
		resolve_hit(hit_player.peer_id, BULLET_DMG)
	elif hit_bot != null:
		hit_bot.take_hit(BULLET_DMG, shooter)

@rpc("any_peer", "call_remote", "unreliable")
func _recv_shot(from: Vector3, to: Vector3, shooter_pid: int) -> void:
	_spawn_spud(from, to)
	var p = players.get(shooter_pid)
	if p and is_instance_valid(p):
		p.show_muzzle_flash()

# ── movement replication ─────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _recv_state(pos: Vector3, yaw: float) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var p = players.get(pid)
	if p and is_instance_valid(p):
		p.set_remote_state(pos, yaw)

# ── damage / scoring (authority owned) ──────────────────────────────────────

func resolve_hit(target_pid: int, dmg: int) -> void:
	if _auth():
		_apply_damage(target_pid, dmg, FpsNetwork.local_id())
	else:
		_req_damage.rpc_id(1, target_pid, dmg)

@rpc("any_peer", "call_remote", "reliable")
func _req_damage(target_pid: int, dmg: int) -> void:
	if not _auth():
		return
	_apply_damage(target_pid, dmg, multiplayer.get_remote_sender_id())

func _apply_damage(target_pid: int, dmg: int, shooter_pid: int) -> void:
	if match_over:
		return
	var p = players.get(target_pid)
	if p == null or not is_instance_valid(p) or not p.alive:
		return
	var hp: int = maxi(0, p.health - dmg)
	p.set_health(hp)
	if _net():
		_mirror_health.rpc(target_pid, hp)
	if hp <= 0:
		p.set_dead(true)
		if _net():
			_mirror_death.rpc(target_pid)
		award_frag(shooter_pid)
		_schedule_respawn(target_pid)

func award_frag(pid: int) -> void:
	if not _auth() or match_over:
		return
	scores[pid] = scores.get(pid, 0) + 1
	if _net():
		_mirror_scores.rpc(scores)
	if scores[pid] >= frag_limit:
		end_match(pid)

func _schedule_respawn(pid: int) -> void:
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_do_respawn.bind(pid))

func _do_respawn(pid: int) -> void:
	if match_over:
		return
	var p = players.get(pid)
	if p == null or not is_instance_valid(p):
		return
	var pos := _random_ground_point()
	p.teleport(pos)
	p.set_health(FpsPlayer.MAX_HEALTH)
	p.set_dead(false)
	if _net():
		_mirror_respawn.rpc(pid, pos)

@rpc("authority", "call_remote", "reliable")
func _mirror_health(pid: int, hp: int) -> void:
	var p = players.get(pid)
	if p and is_instance_valid(p):
		p.set_health(hp)

@rpc("authority", "call_remote", "reliable")
func _mirror_death(pid: int) -> void:
	var p = players.get(pid)
	if p and is_instance_valid(p):
		p.set_dead(true)

@rpc("authority", "call_remote", "reliable")
func _mirror_respawn(pid: int, pos: Vector3) -> void:
	var p = players.get(pid)
	if p and is_instance_valid(p):
		p.teleport(pos)
		p.set_health(FpsPlayer.MAX_HEALTH)
		p.set_dead(false)

@rpc("authority", "call_remote", "reliable")
func _mirror_scores(s: Dictionary) -> void:
	scores = s

@rpc("authority", "call_remote", "reliable")
func _mirror_end(winner: int) -> void:
	_finish(winner)

# ── match end ────────────────────────────────────────────────────────────────

func end_match(winner: int) -> void:
	if match_over:
		return
	if _net():
		_mirror_end.rpc(winner)
	_finish(winner)

func _finish(winner: int) -> void:
	if match_over:
		return
	match_over = true
	winner_id = winner
	input_locked = true
	paused = false
	_return_timer = 12.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.play_sfx("level_complete")

func _toggle_pause() -> void:
	paused = not paused
	input_locked = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED

func _go_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FpsNetwork.leave()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ── world construction ───────────────────────────────────────────────────────

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 1.15
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.47, 0.62, 0.80)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.68)
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.55, 0.65, 0.78)
	we.environment = env
	add_child(we)

func _build_geometry() -> void:
	# floor + perimeter walls
	_add_block(Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE), Vector3(0, -0.5, 0), Color(0.42, 0.5, 0.32))
	var wall := Color(0.55, 0.45, 0.34)
	_add_block(Vector3(FLOOR_SIZE, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, -HALF_FLOOR), wall)
	_add_block(Vector3(FLOOR_SIZE, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, HALF_FLOOR), wall)
	_add_block(Vector3(1.0, WALL_H, FLOOR_SIZE), Vector3(-HALF_FLOOR, WALL_H / 2.0, 0), wall)
	_add_block(Vector3(1.0, WALL_H, FLOOR_SIZE), Vector3(HALF_FLOOR, WALL_H / 2.0, 0), wall)

	# cover crates ("sacks & barrels")
	var crate := Color(0.5, 0.36, 0.22)
	var spots := [
		Vector3(-8, 1.0, -6), Vector3(9, 1.0, 7), Vector3(-10, 1.0, 9),
		Vector3(7, 1.0, -9), Vector3(0, 1.0, 0), Vector3(13, 1.5, -2),
		Vector3(-13, 1.5, 3),
	]
	for s in spots:
		var sz := 2.0 + (int(s.x) % 2)
		_add_block(Vector3(sz, s.y * 2.0, sz), Vector3(s.x, s.y, s.z), crate)

func _add_block(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)
	body.position = pos
	add_child(body)

func _make_spawn_points() -> void:
	var s := HALF_FLOOR - 4.0
	spawn_points = [
		Vector3(-s, 0.3, -s), Vector3(s, 0.3, s),
		Vector3(s, 0.3, -s), Vector3(-s, 0.3, s),
	]

func _random_ground_point() -> Vector3:
	var r := HALF_FLOOR - 4.0
	return Vector3(randf_range(-r, r), 0.3, randf_range(-r, r))

# ── tracer FX ────────────────────────────────────────────────────────────────

func _make_spud_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.6, 0.36)
	m.roughness = 0.8
	return m

func _make_splat_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.86, 0.7)
	m.roughness = 0.95
	return m

# Cosmetic only — the actual hit is the instant raycast in fire_from(). Skipped
# on the headless CI server (no renderer).
func _spawn_spud(a: Vector3, b: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if a.distance_to(b) < 0.05:
		return
	var spud := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	spud.mesh = sm
	spud.scale = Vector3(1.0, 1.0, 1.35)  # a little potato, not a pea
	spud.material_override = _spud_mat
	add_child(spud)
	spud.global_position = a
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		spud.look_at(b, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(spud, "global_position", b, 0.07)
	tw.tween_callback(func():
		_spawn_splat(b)
		if is_instance_valid(spud):
			spud.queue_free())

func _spawn_splat(p: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var splat := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.16
	m.height = 0.32
	splat.mesh = m
	splat.material_override = _splat_mat
	add_child(splat)
	splat.global_position = p
	var tw := create_tween()
	tw.tween_property(splat, "scale", Vector3(2.0, 2.0, 0.5), 0.12)
	tw.tween_callback(func():
		if is_instance_valid(splat):
			splat.queue_free())

# ── HUD ──────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = FpsHud.new()
	hud.arena = self
	layer.add_child(hud)
