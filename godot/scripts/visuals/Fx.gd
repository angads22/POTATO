extends RefCounted
class_name Fx

# One-shot particle bursts. Each call spawns a CPUParticles2D that frees
# itself when finished. Callers should check the particle_effects setting.

static func burst(parent: Node, pos: Vector2, color: Color, count: int = 16, velocity: float = 240.0):
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = velocity * 0.5
	p.initial_velocity_max = velocity
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = color
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# Gold sparkle shower for golden potatoes
static func sparkle(parent: Node, pos: Vector2):
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = 28
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(1.0, 0.85, 0.25)
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# Sickly green puff for rotten outcomes
static func splat(parent: Node, pos: Vector2):
	burst(parent, pos, Color(0.45, 0.6, 0.25), 22, 200.0)

# Expanding shock ring for PERFECT cuts
static func ring(parent: Node, pos: Vector2, color: Color = Color.GOLD):
	var r := RingFx.new()
	r.position = pos
	r.color = color
	parent.add_child(r)
