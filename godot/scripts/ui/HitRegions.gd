extends RefCounted
class_name HitRegions

# Immediate-mode click targets for procedurally drawn UI (design §7.1). A
# drawing pass calls begin(), then add(rect, id) for every button it draws;
# the input code asks hit(pos) for the topmost region under the pointer. The
# last region added wins, so draw order is click order. Rects are in the
# coordinate space they were drawn in (screen space for the HUD layers).
#
# Every target is padded to at least MIN_TARGET x MIN_TARGET (the trackpad
# rule: nothing smaller than 44 px), so a small icon can be drawn small and
# still be easy to hit.

const MIN_TARGET := 44.0

var _regions: Array = []   # [{rect: Rect2, id: String, data}]

func begin() -> void:
	_regions.clear()

# Register a target. Returns the (possibly padded) rect actually used.
func add(rect: Rect2, id: String, data = null) -> Rect2:
	var r := pad(rect)
	_regions.append({"rect": r, "id": id, "data": data})
	return r

# Topmost region containing pos: {rect, id, data}, or {} when none.
func hit(pos: Vector2) -> Dictionary:
	for k in range(_regions.size() - 1, -1, -1):
		if (_regions[k]["rect"] as Rect2).has_point(pos):
			return _regions[k]
	return {}

func hit_id(pos: Vector2) -> String:
	var h := hit(pos)
	return str(h.get("id", ""))

# The rect last registered under id (Rect2() when absent). Test hook: click
# at rect_of(id).get_center().
func rect_of(id: String) -> Rect2:
	for k in range(_regions.size() - 1, -1, -1):
		if _regions[k]["id"] == id:
			return _regions[k]["rect"]
	return Rect2()

func has(id: String) -> bool:
	return rect_of(id).size != Vector2.ZERO

func ids() -> Array:
	var out: Array = []
	for r in _regions:
		out.append(r["id"])
	return out

func size() -> int:
	return _regions.size()

# Grow a rect around its centre to at least MIN_TARGET in both directions.
static func pad(rect: Rect2, min_size := MIN_TARGET) -> Rect2:
	var r := rect.abs()
	if r.size.x < min_size:
		r = r.grow_individual((min_size - r.size.x) * 0.5, 0, (min_size - r.size.x) * 0.5, 0)
	if r.size.y < min_size:
		r = r.grow_individual(0, (min_size - r.size.y) * 0.5, 0, (min_size - r.size.y) * 0.5)
	return r
