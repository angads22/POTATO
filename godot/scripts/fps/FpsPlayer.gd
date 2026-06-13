extends CharacterBody3D
class_name FpsPlayer

# First-person avatar for the SPUD BLASTER arena, built entirely in code (no
# scene file or art assets — a procedural "potato chef" capsule). One instance
# per human peer. The instance whose peer_id matches the local peer owns its
# own movement/aim and broadcasts its transform; the others are remote dolls
# that lerp toward the last state the arena handed them.

const SPEED := 7.0
const JUMP_VELOCITY := 6.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0026
const EYE_HEIGHT := 1.6
const MAX_HEALTH := 100

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
	_build()
	_target_pos = global_position
	_target_yaw = rotation.y
	if is_local:
		camera.current = true
	else:
		camera.current = false

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
	camera.fov = 78.0
	head.add_child(camera)

	muzzle = Node3D.new()
	muzzle.position = Vector3(0.18, -0.12, -0.4)
	head.add_child(muzzle)

	# first-person spud-launcher viewmodel (a tube with a potato loaded)
	if is_local:
		var tube := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.06
		tm.bottom_radius = 0.07
		tm.height = 0.5
		tube.mesh = tm
		tube.rotation = Vector3(PI / 2.0, 0, 0)  # lay the cylinder along -Z
		tube.position = Vector3(0.22, -0.2, -0.45)
		tube.material_override = _skin(Color(0.30, 0.22, 0.13))
		camera.add_child(tube)
		var loaded := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.06
		lm.height = 0.12
		loaded.mesh = lm
		loaded.scale = Vector3(1, 1, 1.3)
		loaded.position = Vector3(0.22, -0.2, -0.72)
		loaded.material_override = _skin(_potato_brown())
		camera.add_child(loaded)
		_flash = MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.08
		fm.height = 0.16
		_flash.mesh = fm
		_flash.material_override = _emissive(Color(1.0, 0.85, 0.35))
		_flash.position = Vector3(0.22, -0.2, -0.8)
		_flash.visible = false
		camera.add_child(_flash)

	aim_ray = RayCast3D.new()
	aim_ray.target_position = Vector3(0, 0, -FpsArena.RAY_LEN)
	aim_ray.collision_mask = 1 | 2  # world + characters
	aim_ray.collide_with_bodies = true
	aim_ray.enabled = true
	aim_ray.add_exception(self)
	head.add_child(aim_ray)

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not alive or arena == null or arena.input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		arena.fire_from(self)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		arena.fire_from(self)  # keyboard fallback

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if is_local:
		_local_move(delta)
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
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if is_on_floor():
		if not locked and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

func _broadcast_state() -> void:
	arena._recv_state.rpc(global_position, rotation.y)

# called on remote peers by the arena when a transform packet arrives
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
