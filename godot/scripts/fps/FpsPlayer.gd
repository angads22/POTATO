extends CharacterBody3D
class_name FpsPlayer

# First-person avatar for the SPUD BLASTER arena, built entirely in code (no
# scene file or art assets — a procedural "potato chef" capsule). One instance
# per human peer. The instance whose peer_id matches the local peer owns its
# own movement/aim/weapons and broadcasts its transform; the others are remote
# dolls that lerp toward the last state the arena handed them.
#
# Weapons: each player spawns with a two-gun loadout (FpsWeapons.default_loadout)
# and can pick up more in the arena. Per-weapon magazine + reserve ammo, reload
# (R or auto-on-empty), weapon swap (1-5 / scroll / Q), aim-down-sights (RMB,
# scoped on the sniper). Health regenerates out of combat (driven by the arena's
# authority). The viewmodel is rebuilt per weapon.

const SPEED := 7.0
const ADS_SPEED := 4.4
const JUMP_VELOCITY := 6.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0026
const EYE_HEIGHT := 1.6
const MAX_HEALTH := 100
const BASE_FOV := 78.0

var peer_id := 1
var player_name := "Chef"
var is_local := false
var health := MAX_HEALTH
var alive := true
var arena = null  # FpsArena — set on spawn

var head: Node3D
var camera: Camera3D
var aim_ray: RayCast3D
var muzzle: Node3D
var _avatar: Node3D
var _flash: MeshInstance3D
var _viewmodel: Node3D

# ── weapons / ammo ───────────────────────────────────────────────────────────
var loadout: Array = []                 # ordered weapon ids (slots)
var current_slot := 0
var last_slot := 0
var _ammo := {}                          # weapon_id -> {"mag": int, "reserve": int}
var reloading := false
var _reload_end_msec := 0
var _last_fire_msec := 0
var ads := false
var _fire_held := false

# remote interpolation targets
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0

func setup(p_peer_id: int, p_name: String, p_arena) -> void:
	peer_id = p_peer_id
	player_name = p_name
	arena = p_arena
	is_local = peer_id == FpsNetwork.local_id()

func _ready() -> void:
	collision_layer = 2          # characters
	collision_mask = 1           # collide with world geometry only
	_init_loadout()
	_build()
	_target_pos = global_position
	_target_yaw = rotation.y
	camera.current = is_local

func _init_loadout() -> void:
	loadout = FpsWeapons.default_loadout()
	for id in loadout:
		_grant_ammo(id, true)
	current_slot = 0
	last_slot = 0

func _grant_ammo(id: String, full: bool) -> void:
	var def := FpsWeapons.get_def(id)
	if not _ammo.has(id):
		_ammo[id] = {"mag": int(def["mag"]), "reserve": int(def["reserve"])}
	elif full:
		_ammo[id]["reserve"] = int(def["reserve"])

func _build() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# ── the potato-chef avatar (hidden from the owner's first-person camera) ──
	_avatar = Node3D.new()
	add_child(_avatar)

	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.42
	bm.height = 0.84
	body.mesh = bm
	body.scale = Vector3(0.95, 1.3, 0.85)  # upright potato, not a ball
	body.position = Vector3(0, 0.85, 0)
	body.material_override = _skin(_potato_brown())
	_avatar.add_child(body)

	# googly potato eyes on the front (-Z)
	for sx in [-0.16, 0.16]:
		var white := MeshInstance3D.new()
		var wm := SphereMesh.new()
		wm.radius = 0.08
		wm.height = 0.16
		white.mesh = wm
		white.position = Vector3(sx, 1.08, -0.32)
		white.material_override = _skin(Color(0.96, 0.96, 0.92))
		_avatar.add_child(white)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.04
		pm.height = 0.08
		pupil.mesh = pm
		pupil.position = Vector3(sx, 1.08, -0.39)
		pupil.material_override = _skin(Color(0.1, 0.07, 0.05))
		_avatar.add_child(pupil)

	# chef toque: a coloured band (the player's colour, so peers are
	# distinguishable) topped with a white puff
	var band := MeshInstance3D.new()
	var bandm := CylinderMesh.new()
	bandm.top_radius = 0.30
	bandm.bottom_radius = 0.30
	bandm.height = 0.14
	band.mesh = bandm
	band.position = Vector3(0, 1.45, 0)
	band.material_override = _skin(_colour_for(peer_id))
	_avatar.add_child(band)
	var puff := MeshInstance3D.new()
	var puffm := SphereMesh.new()
	puffm.radius = 0.30
	puffm.height = 0.60
	puff.mesh = puffm
	puff.scale = Vector3(1.0, 1.15, 1.0)
	puff.position = Vector3(0, 1.66, 0)
	puff.material_override = _skin(Color(0.97, 0.97, 0.95))
	_avatar.add_child(puff)

	_avatar.visible = not is_local

	head = Node3D.new()
	head.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.fov = BASE_FOV
	head.add_child(camera)

	muzzle = Node3D.new()
	muzzle.position = Vector3(0.18, -0.12, -0.4)
	head.add_child(muzzle)

	# first-person viewmodel (per-weapon, local only)
	if is_local:
		_viewmodel = Node3D.new()
		camera.add_child(_viewmodel)
		_rebuild_viewmodel()

	aim_ray = RayCast3D.new()
	aim_ray.target_position = Vector3(0, 0, -FpsArena.RAY_LEN)
	aim_ray.collision_mask = 1 | 2  # world + characters
	aim_ray.collide_with_bodies = true
	aim_ray.enabled = true
	aim_ray.add_exception(self)
	head.add_child(aim_ray)

# ── weapon queries ───────────────────────────────────────────────────────────

func current_weapon_id() -> String:
	if loadout.is_empty():
		return "spud_rifle"
	return str(loadout[clampi(current_slot, 0, loadout.size() - 1)])

func current_weapon_def() -> Dictionary:
	return FpsWeapons.get_def(current_weapon_id())

func mag_ammo() -> int:
	return int(_ammo.get(current_weapon_id(), {}).get("mag", 0))

func reserve_ammo() -> int:
	return int(_ammo.get(current_weapon_id(), {}).get("reserve", 0))

func current_spread() -> float:
	var d := current_weapon_def()
	return float(d["ads_spread"]) if ads else float(d["spread"])

func fire_cooldown() -> float:
	return 60.0 / maxf(1.0, float(current_weapon_def()["rpm"]))

func can_fire() -> bool:
	return alive and not reloading and mag_ammo() > 0

func reload_progress() -> float:
	if not reloading:
		return 0.0
	var total := float(current_weapon_def()["reload_time"]) * 1000.0
	var left := float(_reload_end_msec - Time.get_ticks_msec())
	return clampf(1.0 - left / maxf(1.0, total), 0.0, 1.0)

# ── input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or arena == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if alive and not arena.input_locked:
			rotation.y -= event.relative.x * MOUSE_SENS
			head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.4, 1.4)
		return
	if arena.input_locked or not alive:
		_fire_held = false
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_fire_held = event.pressed
				if event.pressed:
					_try_fire()
			MOUSE_BUTTON_RIGHT:
				_set_ads(event.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					cycle_weapon(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					cycle_weapon(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_try_fire()  # keyboard fire fallback
			KEY_R:
				start_reload()
			KEY_Q:
				select_slot(last_slot)
			KEY_1: select_slot(0)
			KEY_2: select_slot(1)
			KEY_3: select_slot(2)
			KEY_4: select_slot(3)
			KEY_5: select_slot(4)

func _try_fire() -> void:
	if Time.get_ticks_msec() - _last_fire_msec < int(fire_cooldown() * 1000.0):
		return
	if reloading:
		return
	if mag_ammo() <= 0:
		start_reload()
		return
	_last_fire_msec = Time.get_ticks_msec()
	arena.fire_from(self)

# ── per-frame ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_local:
		if alive:
			_local_move(delta)
			_update_reload()
			_update_auto_fire()
			_update_view(delta)
			if FpsNetwork.is_networked():
				_broadcast_state()
	else:
		# remote doll: smooth toward the last broadcast transform
		global_position = global_position.lerp(_target_pos, clampf(delta * 14.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 14.0, 0.0, 1.0))

func _local_move(delta: float) -> void:
	var locked: bool = arena != null and arena.input_locked
	var input := Vector3.ZERO
	if not locked:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input.z -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input.z += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input.x += 1.0
	var dir := (transform.basis * input).normalized()
	var spd := ADS_SPEED if ads else SPEED
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_floor():
		if not locked and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

func _update_auto_fire() -> void:
	var def := current_weapon_def()
	if _fire_held and bool(def.get("automatic", false)):
		_try_fire()

func _update_reload() -> void:
	if reloading and Time.get_ticks_msec() >= _reload_end_msec:
		_finish_reload()

func _update_view(delta: float) -> void:
	# smooth FOV between hip and aim-down-sights (scoped guns zoom further)
	var target_fov := BASE_FOV
	if ads:
		target_fov = float(current_weapon_def().get("ads_fov", 58.0))
	if camera != null:
		camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 12.0, 0.0, 1.0))
	if _viewmodel != null:
		var rest := Vector3.ZERO
		var aim := Vector3(-0.22, 0.04, 0.06)  # pull toward centre when aiming
		var want: Vector3 = aim if ads else rest
		_viewmodel.position = _viewmodel.position.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
		_viewmodel.visible = not (ads and bool(current_weapon_def().get("scoped", false)))

# ── weapon actions ───────────────────────────────────────────────────────────

func select_slot(slot: int) -> void:
	if slot < 0 or slot >= loadout.size() or slot == current_slot:
		return
	last_slot = current_slot
	current_slot = slot
	reloading = false
	_set_ads(false)
	_rebuild_viewmodel()

func cycle_weapon(dir: int) -> void:
	if loadout.size() <= 1:
		return
	select_slot((current_slot + dir + loadout.size()) % loadout.size())

func give_weapon(id: String, switch_to: bool = false) -> void:
	if not FpsWeapons.has(id):
		return
	_grant_ammo(id, true)
	if not loadout.has(id):
		loadout.append(id)
	if switch_to:
		select_slot(loadout.find(id))

func start_reload() -> void:
	if reloading:
		return
	var id := current_weapon_id()
	var def := FpsWeapons.get_def(id)
	var st: Dictionary = _ammo.get(id, {})
	if int(st.get("mag", 0)) >= int(def["mag"]) or int(st.get("reserve", 0)) <= 0:
		return
	reloading = true
	_reload_end_msec = Time.get_ticks_msec() + int(float(def["reload_time"]) * 1000.0)
	AudioManager.play_sfx("menu_move")

func _finish_reload() -> void:
	reloading = false
	var id := current_weapon_id()
	var def := FpsWeapons.get_def(id)
	var st: Dictionary = _ammo.get(id, {"mag": 0, "reserve": 0})
	var need := int(def["mag"]) - int(st["mag"])
	var take := mini(need, int(st["reserve"]))
	st["mag"] = int(st["mag"]) + take
	st["reserve"] = int(st["reserve"]) - take
	_ammo[id] = st

# Spend one round from the current magazine. Called by the arena when a shot
# actually fires. Auto-reloads when the magazine runs dry.
func consume_ammo() -> void:
	var id := current_weapon_id()
	var st: Dictionary = _ammo.get(id, {"mag": 0, "reserve": 0})
	st["mag"] = maxi(0, int(st["mag"]) - 1)
	_ammo[id] = st
	if int(st["mag"]) <= 0:
		start_reload()

func refill_reserve_all() -> bool:
	var changed := false
	for id in loadout:
		var def := FpsWeapons.get_def(id)
		var st: Dictionary = _ammo.get(id, {"mag": int(def["mag"]), "reserve": 0})
		var cap := int(def["reserve"])
		if int(st["reserve"]) < cap:
			st["reserve"] = cap
			_ammo[id] = st
			changed = true
	return changed

func _set_ads(on: bool) -> void:
	# launchers and shotguns can still "aim" (tighter spread) but only scoped
	# guns zoom hard; nothing stops ADS, it just trims spread / FOV.
	ads = on

func heal(amount: int) -> void:
	health = clampi(health + amount, 0, MAX_HEALTH)

# ── viewmodel ────────────────────────────────────────────────────────────────

func _rebuild_viewmodel() -> void:
	if not is_local or _viewmodel == null:
		return
	for c in _viewmodel.get_children():
		c.queue_free()
	_flash = null
	if DisplayServer.get_name() == "headless":
		return
	var def := current_weapon_def()
	var tint: Color = FpsWeapons.tint_for(def.get("color", Color(0.5, 0.4, 0.3)))
	var shape := str(def.get("shape", "rifle"))
	var base := Vector3(0.26, -0.22, -0.5)

	# every gun: a body + a barrel, sized by shape
	var body_len := 0.42
	var barrel_len := 0.34
	var barrel_r := 0.05
	match shape:
		"smg": body_len = 0.32; barrel_len = 0.22
		"shotgun": body_len = 0.4; barrel_len = 0.4; barrel_r = 0.07
		"sniper": body_len = 0.5; barrel_len = 0.7; barrel_r = 0.045
		"launcher": body_len = 0.34; barrel_len = 0.3; barrel_r = 0.1
		"plasma": body_len = 0.36; barrel_len = 0.34; barrel_r = 0.07

	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.1, 0.22, body_len)
	grip.mesh = gm
	grip.material_override = _skin(tint.darkened(0.2))
	grip.position = base
	_viewmodel.add_child(grip)

	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = barrel_r
	bm.bottom_radius = barrel_r
	bm.height = barrel_len
	barrel.mesh = bm
	barrel.rotation = Vector3(PI / 2.0, 0, 0)
	barrel.material_override = _skin(tint)
	barrel.position = base + Vector3(0, 0.06, -body_len * 0.5 - barrel_len * 0.4)
	_viewmodel.add_child(barrel)

	if shape == "sniper":
		var scope := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.05
		sm.bottom_radius = 0.05
		sm.height = 0.22
		scope.mesh = sm
		scope.rotation = Vector3(PI / 2.0, 0, 0)
		scope.material_override = _skin(Color(0.1, 0.1, 0.12))
		scope.position = base + Vector3(0, 0.16, -0.1)
		_viewmodel.add_child(scope)
	elif shape == "launcher":
		var drum := MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = 0.13
		dm.height = 0.26
		drum.mesh = dm
		drum.material_override = _skin(tint.darkened(0.15))
		drum.position = base + Vector3(0, 0.02, -0.18)
		_viewmodel.add_child(drum)
	elif shape == "plasma":
		var coil := MeshInstance3D.new()
		var cm := TorusMesh.new()
		cm.inner_radius = barrel_r + 0.02
		cm.outer_radius = barrel_r + 0.09
		coil.mesh = cm
		coil.material_override = _emissive(def.get("color", Color(0.45, 0.95, 0.85)))
		coil.position = base + Vector3(0, 0.06, -body_len * 0.5 - barrel_len * 0.3)
		_viewmodel.add_child(coil)

	_flash = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	_flash.mesh = fm
	_flash.material_override = _emissive(Color(1.0, 0.85, 0.35))
	_flash.position = base + Vector3(0, 0.06, -body_len * 0.5 - barrel_len * 0.9)
	_flash.visible = false
	_viewmodel.add_child(_flash)

# ── networking / state ───────────────────────────────────────────────────────

func _broadcast_state() -> void:
	arena._recv_state.rpc(global_position, rotation.y)

func set_remote_state(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw

func muzzle_world_pos() -> Vector3:
	return muzzle.global_position if muzzle else global_position

func show_muzzle_flash() -> void:
	if _flash == null:
		return
	_flash.visible = true
	get_tree().create_timer(0.05).timeout.connect(func():
		if is_instance_valid(_flash):
			_flash.visible = false)

# aim the avatar at a world point (used by the headless smoke test, which has
# no mouse to look with)
func face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.05:
		look_at(flat, Vector3.UP)
	var to := point - head.global_position
	var flat_dist := Vector2(to.x, to.z).length()
	head.rotation.x = clampf(atan2(to.y, flat_dist), -1.4, 1.4)

func set_health(hp: int) -> void:
	health = hp

func set_dead(dead: bool) -> void:
	alive = not dead
	visible = not dead
	if dead:
		velocity = Vector3.ZERO
		_fire_held = false
		reloading = false
		_set_ads(false)

func teleport(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	velocity = Vector3.ZERO

func _potato_brown() -> Color:
	return Color(0.78, 0.6, 0.36)

func _colour_for(id: int) -> Color:
	var palette := [
		Color(0.85, 0.72, 0.35), Color(0.78, 0.42, 0.30),
		Color(0.45, 0.65, 0.85), Color(0.55, 0.78, 0.45),
	]
	return palette[abs(id) % palette.size()]

func _skin(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

func _emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
