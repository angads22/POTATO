extends Node3D
class_name FpsArena

# The SPUD BLASTER deathmatch arena — a procedurally built 3D arena (palette,
# fog, cover, spawns and pickups all come from the chosen FpsMaps entry). This
# node has a stable scene path ("/root/FpsArena" once loaded via change_scene),
# so all the gameplay RPCs (movement / shots / damage / scores) live here and
# route reliably across peers. ENet's server relay forwards client→client
# packets through the host.
#
# Authority model: the host (peer 1) — or, offline, the single local peer —
# owns health, frags, deaths, respawns and out-of-combat health regen. Each
# peer simulates its own avatar and broadcasts its transform; everyone else
# interpolates. Hit detection runs on the shooter (per the shooter's current
# weapon) and is confirmed by the authority (casual, responsive). Weapon pickups
# and ammo are purely local; health pickups route through the authority.

const RAY_LEN := 200.0
const FLOOR_SIZE := 44.0
const HALF_FLOOR := FLOOR_SIZE / 2.0
const WALL_H := 7.0
const RESPAWN_DELAY := 2.0
const PRACTICE_BOTS := 3

# health regen (authority owned)
const REGEN_DELAY_MS := 5000
const REGEN_RATE := 14.0   # hp per second once out of combat

# match payout (each peer pays its own local player)
const COIN_PER_FRAG := 12
const WIN_BONUS := 60
const STARCH_PER_WIN := 3

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

var map_name := ""
var payout := {}         # filled at match end for the HUD payout screen

var _map := {}
var _spud_mat: StandardMaterial3D
var _splat_mat: StandardMaterial3D
var _last_dmg := {}      # pid -> last-damage msec (regen gate)
var _regen_accum := {}   # pid -> fractional hp accumulator
var _return_timer := 0.0
var _leaving := false
var hud

func _ready() -> void:
	name = "FpsArena"
	seed(FpsNetwork.match_seed)
	frag_limit = FpsNetwork.frag_limit
	time_left = FpsNetwork.time_limit
	_map = FpsMaps.get_map(FpsNetwork.map_id)
	map_name = str(_map.get("name", "Arena"))
	_spud_mat = _make_spud_mat()
	_splat_mat = _make_splat_mat()

	_build_environment()
	_build_geometry()
	_make_spawn_points()
	_spawn_pickups()

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
	if _auth():
		_regen_tick(delta)
		if time_left <= 0.0:
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
	var idx := _sorted_ids().find(pid)
	if idx < 0:
		idx = players.size()
	# Place the avatar at its spawn BEFORE adding it to the tree — otherwise it
	# registers with the physics server at the origin for a frame and trips any
	# pickup Area3D sitting at the map centre.
	var spawn: Vector3 = spawn_points[idx % spawn_points.size()]
	p.position = spawn
	add_child(p)
	p.teleport(spawn)
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

func _spawn_pickups() -> void:
	for pk in _map.get("pickups", []):
		var pickup := FpsPickup.new()
		pickup.setup(str(pk.get("type", "health")), str(pk.get("weapon", "")), self)
		pickup.position = pk.get("pos", Vector3.ZERO)
		add_child(pickup)

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

# Always called on the shooter's own machine (local input only, or the smoke
# test). Reads the shooter's current weapon to resolve the shot.
func fire_from(shooter: FpsPlayer) -> void:
	if match_over or shooter == null or not shooter.alive or not shooter.can_fire():
		return
	var w := shooter.current_weapon_def()
	shooter.consume_ammo()
	shooter.show_muzzle_flash()
	AudioManager.play_sfx("cut_great")
	var muzzle := shooter.muzzle_world_pos()
	if bool(w.get("projectile", false)):
		_fire_projectile(shooter, w, muzzle)
	else:
		_fire_hitscan(shooter, w, muzzle)

func _fire_hitscan(shooter: FpsPlayer, w: Dictionary, muzzle: Vector3) -> void:
	var pellets := maxi(1, int(w.get("pellets", 1)))
	var spread_rad := deg_to_rad(shooter.current_spread())
	var dmg := int(w.get("damage", 20))
	var hs_mult := float(w.get("headshot_mult", 1.0))
	var origin: Vector3 = shooter.head.global_position
	var basis := shooter.head.global_transform.basis
	var center_end := origin - basis.z * RAY_LEN
	var any_hit := false
	var any_head := false
	for i in range(pellets):
		var dir := _cone_dir(basis, spread_rad)
		var to := origin + dir * RAY_LEN
		var hit := _raycast(origin, to, shooter)
		var endpoint := to
		if not hit.is_empty():
			endpoint = hit["position"]
			var col = hit["collider"]
			var is_head := _is_headshot(col, endpoint)
			var d := int(round(dmg * hs_mult)) if is_head else dmg
			if col is FpsPlayer and col != shooter:
				resolve_hit(col.peer_id, d)
				any_hit = true
				any_head = any_head or is_head
			elif col is FpsBot:
				col.take_hit(d, shooter)
				any_hit = true
				any_head = any_head or is_head
		_spawn_spud(muzzle, endpoint)
		if i == 0:
			center_end = endpoint
	if any_hit and shooter.is_local and hud != null:
		hud.hitmarker(any_head)
	if _net():
		_recv_shot.rpc(muzzle, center_end, shooter.peer_id)

func _fire_projectile(shooter: FpsPlayer, w: Dictionary, muzzle: Vector3) -> void:
	var origin: Vector3 = shooter.head.global_position
	var basis := shooter.head.global_transform.basis
	var to := origin - basis.z * RAY_LEN
	var hit := _raycast(origin, to, shooter)
	var endpoint := to
	if not hit.is_empty():
		endpoint = hit["position"]
	var radius := float(w.get("splash_radius", 4.0))
	var sdmg := int(w.get("splash_damage", 50))
	_spawn_projectile(muzzle, endpoint, radius, sdmg, shooter.peer_id, shooter.is_local)
	if _net():
		_recv_shot.rpc(muzzle, endpoint, shooter.peer_id)

func _cone_dir(basis: Basis, spread: float) -> Vector3:
	var fwd := -basis.z
	if spread <= 0.0:
		return fwd
	var ang := randf() * TAU
	var rad := sqrt(randf()) * spread
	var offset := (basis.x * cos(ang) + basis.y * sin(ang)) * tan(rad)
	return (fwd + offset).normalized()

func _raycast(from: Vector3, to: Vector3, exclude) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 2
	q.collide_with_bodies = true
	if exclude != null and exclude is CollisionObject3D:
		q.exclude = [exclude.get_rid()]
	return space.intersect_ray(q)

func _is_headshot(col, point: Vector3) -> bool:
	if col is FpsPlayer:
		return point.y >= col.global_position.y + 1.3
	elif col is FpsBot:
		return point.y >= col.global_position.y + 1.45
	return false

@rpc("any_peer", "call_remote", "unreliable")
func _recv_shot(from: Vector3, to: Vector3, shooter_pid: int) -> void:
	_spawn_spud(from, to)
	var p = players.get(shooter_pid)
	if p and is_instance_valid(p):
		p.show_muzzle_flash()

# ── explosive splash (Fry Launcher) ──────────────────────────────────────────

func _spawn_projectile(from: Vector3, to: Vector3, radius: float, dmg: int,
		shooter_pid: int, shooter_local: bool) -> void:
	var travel := clampf(from.distance_to(to) / 36.0, 0.05, 1.4)
	if DisplayServer.get_name() == "headless":
		get_tree().create_timer(travel).timeout.connect(
			_explode.bind(to, radius, dmg, shooter_pid, shooter_local))
		return
	var nade := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.16
	nm.height = 0.32
	nade.mesh = nm
	nade.material_override = _make_splat_mat()
	add_child(nade)
	nade.global_position = from
	var tw := create_tween()
	tw.tween_property(nade, "global_position", to, travel)
	tw.tween_callback(func():
		_explode(to, radius, dmg, shooter_pid, shooter_local)
		if is_instance_valid(nade):
			nade.queue_free())

func _explode(point: Vector3, radius: float, dmg: int, shooter_pid: int,
		shooter_local: bool) -> void:
	if match_over:
		return
	var any := false
	for pid in players.keys():
		if pid == shooter_pid:
			continue
		var p = players.get(pid)
		if p == null or not is_instance_valid(p) or not p.alive:
			continue
		var dist: float = p.global_position.distance_to(point)
		if dist <= radius:
			var d := int(round(dmg * (1.0 - dist / radius)))
			if d > 0:
				resolve_hit(pid, d)
				any = true
	var bshooter = players.get(shooter_pid)
	for b in bots:
		if is_instance_valid(b) and b.alive:
			var dist: float = b.global_position.distance_to(point)
			if dist <= radius:
				var d := int(round(dmg * (1.0 - dist / radius)))
				if d > 0:
					b.take_hit(d, bshooter)
					any = true
	if any and shooter_local and hud != null:
		hud.hitmarker(false)
	_spawn_explosion(point, radius)

func _spawn_explosion(point: Vector3, radius: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fx := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	fx.mesh = sm
	fx.material_override = _emissive(Color(1.0, 0.6, 0.2))
	add_child(fx)
	fx.global_position = point
	var tw := create_tween()
	tw.parallel().tween_property(fx, "scale", Vector3.ONE * (radius * 1.6), 0.22)
	tw.parallel().tween_property(fx.material_override, "albedo_color",
			Color(1.0, 0.3, 0.1, 0.0), 0.22)
	tw.tween_callback(func():
		if is_instance_valid(fx):
			fx.queue_free())

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
	_last_dmg[target_pid] = Time.get_ticks_msec()
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
	_last_dmg[pid] = Time.get_ticks_msec()
	if _net():
		_mirror_respawn.rpc(pid, pos)

# out-of-combat health regen, ticked by the authority
func _regen_tick(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for pid in players.keys():
		var p = players.get(pid)
		if p == null or not is_instance_valid(p) or not p.alive:
			continue
		if p.health >= FpsPlayer.MAX_HEALTH:
			continue
		if now - int(_last_dmg.get(pid, -REGEN_DELAY_MS)) < REGEN_DELAY_MS:
			continue
		var acc := float(_regen_accum.get(pid, 0.0)) + REGEN_RATE * delta
		var whole := int(acc)
		_regen_accum[pid] = acc - whole
		if whole >= 1:
			var hp := mini(FpsPlayer.MAX_HEALTH, p.health + whole)
			p.set_health(hp)
			if _net():
				_mirror_health.rpc(pid, hp)

# health pickups: client asks the authority to bump its health (never reduces)
func notify_health(pid: int, hp: int) -> void:
	if _auth():
		var p = players.get(pid)
		if p and is_instance_valid(p):
			p.set_health(hp)
		if _net():
			_mirror_health.rpc(pid, hp)
	else:
		_req_heal.rpc_id(1, pid, hp)

@rpc("any_peer", "call_remote", "reliable")
func _req_heal(pid: int, hp: int) -> void:
	if not _auth():
		return
	var p = players.get(pid)
	if p and is_instance_valid(p):
		p.set_health(maxi(p.health, hp))
		_mirror_health.rpc(pid, hp)

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
	_return_timer = 14.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.play_sfx("level_complete")
	_award_payout(winner)

# Each peer pays its own local player: coins per frag (+ a win bonus), and the
# premium "starch" currency only on a win. Lifetime starch feeds the global
# leaderboard.
func _award_payout(winner: int) -> void:
	var local := FpsNetwork.local_id()
	var frags := int(scores.get(local, 0))
	var won := winner == local
	var coins := frags * COIN_PER_FRAG + (WIN_BONUS if won else 0)
	var starch := STARCH_PER_WIN if won else 0
	payout = {"frags": frags, "coins": coins, "starch": starch, "won": won}
	if coins > 0:
		SaveDataManager.add_coins(coins)
	if starch > 0:
		SaveDataManager.add_starch(starch)
	OnlineLeaderboard.submit_fps_result(
			FpsNetwork.my_name(), SaveDataManager.lifetime_starch(), frags)

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
	var sr: Vector3 = _map.get("sun_rot", Vector3(-52.0, 38.0, 0.0))
	sun.rotation = Vector3(deg_to_rad(sr.x), deg_to_rad(sr.y), deg_to_rad(sr.z))
	sun.light_energy = float(_map.get("sun_energy", 1.15))
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _map.get("sky", Color(0.47, 0.62, 0.80))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _map.get("ambient", Color(0.62, 0.62, 0.68))
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_density = float(_map.get("fog_density", 0.006))
	env.fog_light_color = _map.get("fog", Color(0.55, 0.65, 0.78))
	we.environment = env
	add_child(we)

func _build_geometry() -> void:
	# floor + perimeter walls
	_add_block(Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE), Vector3(0, -0.5, 0),
			_map.get("floor", Color(0.42, 0.5, 0.32)))
	var wall: Color = _map.get("wall", Color(0.55, 0.45, 0.34))
	_add_block(Vector3(FLOOR_SIZE, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, -HALF_FLOOR), wall)
	_add_block(Vector3(FLOOR_SIZE, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, HALF_FLOOR), wall)
	_add_block(Vector3(1.0, WALL_H, FLOOR_SIZE), Vector3(-HALF_FLOOR, WALL_H / 2.0, 0), wall)
	_add_block(Vector3(1.0, WALL_H, FLOOR_SIZE), Vector3(HALF_FLOOR, WALL_H / 2.0, 0), wall)

	# cover from the map
	var crate: Color = _map.get("crate", Color(0.5, 0.36, 0.22))
	for c in _map.get("cover", []):
		_add_block(c.get("size", Vector3(2, 2, 2)), c.get("pos", Vector3.ZERO), crate)

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
	spawn_points.clear()
	for s in _map.get("spawns", []):
		spawn_points.append(s)
	if spawn_points.is_empty():
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

func _emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
