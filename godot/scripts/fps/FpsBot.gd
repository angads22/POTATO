extends CharacterBody3D
class_name FpsBot

# Target-dummy "sack of potatoes" for solo PRACTICE (and the headless smoke
# test). Bots only ever exist on an authority that owns the whole world
# (offline practice), so their state never needs replicating. They wander
# lazily, take hits, and on being sliced they award the shooter a frag and
# respawn elsewhere after a short beat.

const SPEED := 2.0
const GRAVITY := 20.0
const MAX_HEALTH := 100

var health := MAX_HEALTH
var alive := true
var wander_enabled := true
var arena = null  # FpsArena

var _target := Vector3.ZERO
var _retarget := 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	collision_layer = 2   # detectable by aim rays
	collision_mask = 1    # collide with world
	_build()
	_pick_target()

func _build() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.7
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.45
	body.height = 1.7
	_mesh.mesh = body
	_mesh.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.45, 0.28)
	mat.roughness = 0.9
	_mesh.material_override = mat
	add_child(_mesh)

	# a painted bullseye so it reads as a target
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.18
	rm.outer_radius = 0.30
	ring.mesh = rm
	ring.position = Vector3(0, 1.2, -0.42)
	ring.rotation = Vector3(PI / 2.0, 0, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.85, 0.2, 0.15)
	ring.material_override = rmat
	add_child(ring)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if wander_enabled:
		_retarget -= delta
		if _retarget <= 0.0 or global_position.distance_to(_target) < 1.0:
			_pick_target()
		var dir := (_target - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

func _pick_target() -> void:
	var r := FpsArena.HALF_FLOOR - 3.0
	_target = Vector3(randf_range(-r, r), global_position.y, randf_range(-r, r))
	_retarget = randf_range(2.0, 5.0)

func take_hit(amount: int, shooter) -> void:
	if not alive:
		return
	health -= amount
	if _mesh:
		_flash_white()
	if health <= 0:
		_die(shooter)

func _flash_white() -> void:
	var m := _mesh.material_override as StandardMaterial3D
	if m == null:
		return
	var base := m.albedo_color
	m.albedo_color = Color(1, 1, 1)
	get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(_mesh):
			var mm := _mesh.material_override as StandardMaterial3D
			if mm:
				mm.albedo_color = base)

func _die(shooter) -> void:
	alive = false
	visible = false
	if arena and shooter is FpsPlayer:
		arena.award_frag(shooter.peer_id)
	get_tree().create_timer(1.5).timeout.connect(_respawn)

func _respawn() -> void:
	if not is_inside_tree():
		return
	health = MAX_HEALTH
	alive = true
	visible = true
	var r := FpsArena.HALF_FLOOR - 4.0
	global_position = Vector3(randf_range(-r, r), 0.2, randf_range(-r, r))
	_pick_target()
