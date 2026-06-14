extends Area3D
class_name FpsPickup

# A floating, bobbing, spinning pickup in the SPUD BLASTER arena — health,
# ammo, or a weapon. Built procedurally (no art). Only FpsPlayers collect them
# (bots are ignored), and only the local owner's collection has any effect, so
# pickups never need authority replication — each peer collects for itself.
# After collection the node hides and respawns after a cooldown.
#
# Detection: the Area sits on no collision layer and masks layer 2 (characters),
# with collide_with_areas off, so aim rays (which hit bodies on layers 1|2)
# pass straight through it.

const RESPAWN_TIME := 12.0
const BOB_HEIGHT := 0.25
const SPIN_SPEED := 1.6

var kind := "health"            # "health" | "ammo" | "weapon"
var weapon_id := ""             # for weapon pickups
var arena = null                # FpsArena

var _base_y := 0.0
var _t := 0.0
var _cooldown := 0.0
var _active := true
var _visual: Node3D

func setup(p_kind: String, p_weapon: String, p_arena) -> void:
	kind = p_kind
	weapon_id = p_weapon
	arena = p_arena

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2              # detect characters
	monitoring = true
	monitorable = false
	monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	col.shape = sphere
	add_child(col)
	_base_y = global_position.y
	_build_visual()
	body_entered.connect(_on_body_entered)

func _build_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_visual = Node3D.new()
	add_child(_visual)
	var c := _accent()
	# glowing base orb
	var orb := MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.34
	om.height = 0.68
	orb.mesh = om
	orb.material_override = _glow(c, 0.5)
	_visual.add_child(orb)
	# spinning ring
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.45
	rm.outer_radius = 0.6
	ring.mesh = rm
	ring.rotation = Vector3(PI / 2.0, 0, 0)
	ring.material_override = _glow(c, 1.4)
	_visual.add_child(ring)
	# a little symbol icon (cross / clip / gun) on top
	_build_icon(c)

func _build_icon(c: Color) -> void:
	var mat := _glow(Color(1, 1, 1), 1.0)
	match kind:
		"health":
			for r in [Vector3(0.32, 0.1, 0.1), Vector3(0.1, 0.32, 0.1)]:
				var bar := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = r
				bar.mesh = bm
				bar.material_override = mat
				bar.position = Vector3(0, 0.0, -0.45)
				_visual.add_child(bar)
		"ammo":
			for i in range(3):
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.08, 0.3, 0.08)
				b.mesh = bm
				b.material_override = mat
				b.position = Vector3(-0.12 + i * 0.12, 0.0, -0.45)
				_visual.add_child(b)
		"weapon":
			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(0.4, 0.12, 0.12)
			g.mesh = gm
			g.material_override = _glow(_accent(), 1.2)
			g.position = Vector3(0, 0.0, -0.45)
			_visual.add_child(g)

func _process(delta: float) -> void:
	_t += delta
	if _visual != null:
		_visual.rotation.y += SPIN_SPEED * delta
		_visual.position.y = sin(_t * 2.0) * 0.06
	global_position.y = _base_y + (BOB_HEIGHT * 0.5) * (1.0 + sin(_t * 2.0))
	if not _active:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_respawn()

func _on_body_entered(body: Node) -> void:
	if not _active or not (body is FpsPlayer):
		return
	var player := body as FpsPlayer
	if not player.is_local or not player.alive:
		return
	if not _apply(player):
		return
	AudioManager.play_sfx("coin")
	if arena != null and arena.hud != null:
		arena.hud.notify(_pickup_label())
	_active = false
	visible = false
	monitoring = false
	_cooldown = RESPAWN_TIME

# Returns false (no consume) when the pickup would be wasted (full health, etc.)
func _apply(player: FpsPlayer) -> bool:
	match kind:
		"health":
			if player.health >= FpsPlayer.MAX_HEALTH:
				return false
			player.heal(35)
			if arena != null:
				arena.notify_health(player.peer_id, player.health)
			return true
		"ammo":
			return player.refill_reserve_all()
		"weapon":
			player.give_weapon(weapon_id, true)
			return true
	return false

func _respawn() -> void:
	_active = true
	visible = true
	monitoring = true

func _pickup_label() -> String:
	match kind:
		"health": return "+35 HP"
		"ammo": return "AMMO"
		"weapon": return "Picked up %s" % FpsWeapons.display_name(weapon_id)
	return ""

func _accent() -> Color:
	match kind:
		"health": return Color(0.3, 0.9, 0.4)
		"ammo": return Color(0.95, 0.8, 0.3)
		"weapon": return Color(0.5, 0.7, 1.0)
	return Color(1, 1, 1)

func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
