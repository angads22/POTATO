extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  Security — shared input-validation, sanitisation and rate-limiting helpers.
#  Autoloaded as `Security` (see project.godot).
#
#  SLICE IT! is a desktop game, not a web service, but it still exposes three
#  "public endpoints" that accept data from outside the local process:
#    • the Supabase leaderboard REST client  (OnlineLeaderboard.gd)
#    • the SPUD BLASTER arena host on UDP 7370 (FpsNetwork / FpsArena RPCs)
#    • the rhythm-duel host on TCP/UDP 7369   (MultiplayerManager RPCs)
#
#  Any byte arriving on those surfaces is attacker-controlled and must be
#  validated before use. This module centralises that work following OWASP
#  guidance (ASVS V5 — Validation, Sanitisation & Encoding; and the API
#  Security "lack of resources / rate limiting" risk):
#
#    • validate by type, range and an explicit allow-list — never a deny-list;
#    • cap every string length and strip control characters;
#    • reject unexpected fields rather than silently passing them through;
#    • percent-encode anything interpolated into a URL/query (output encoding);
#    • rate-limit every endpoint per identity, dropping floods gracefully.
#
#  The helpers are deliberately dependency-free so the FpsNetwork autoload can
#  preload this script during a clean import without a class_name cache.
# ─────────────────────────────────────────────────────────────────────────────

# ── sane, conservative limits (one place to tune) ────────────────────────────
const MAX_NAME_LEN := 24          # leaderboard/display name hard cap
const MAX_SCORE := 100_000_000    # any single run that beats this is bogus
const MAX_STARCH := 100_000_000   # lifetime premium currency sanity ceiling
const MAX_FRAGS := 100_000        # frags in one arena match sanity ceiling
const MAX_DAMAGE := 1_000         # a single hit can never exceed this
const MAX_HEALTH := 1_000         # health value a peer may claim
const ARENA_HALF_EXTENT := 60.0   # reject transforms well outside the arena box

# Allow-listed enum values. Anything not present is rejected outright.
const ALLOWED_MODES := [
	"championship", "endless", "timeattack", "daily", "spud_blaster",
]

# ─────────────────────────────────────────────────────────────────────────────
#  String sanitisation
# ─────────────────────────────────────────────────────────────────────────────

# Sanitise a human-supplied display name. Strips control characters and any
# code point outside the printable BMP range, collapses runs of whitespace,
# trims the ends, then hard-caps the length. Returns `fallback` when nothing
# usable remains so downstream code never has to handle an empty name.
static func sanitize_name(raw: String, fallback: String = "Chef",
		max_len: int = MAX_NAME_LEN) -> String:
	if typeof(raw) != TYPE_STRING:
		return fallback
	var out := ""
	var prev_space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		# Drop C0/C1 control chars (incl. NUL, newlines, DEL) and stray surrogates.
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or (c >= 0xD800 and c <= 0xDFFF):
			continue
		if c == 0x20 or c == 0x09:  # space / tab → single space
			if not out.is_empty() and not prev_space:
				out += " "
				prev_space = true
			continue
		out += char(c)
		prev_space = false
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len).strip_edges()
	return out if out != "" else fallback

# Percent-encode a value for safe interpolation into a URL query string.
# Prevents query-parameter injection into the PostgREST filter (e.g. a `mode`
# of "x&select=*" smuggling extra parameters). Godot's String.uri_encode
# escapes the reserved set we care about (& = ? # space, etc.).
static func encode_query_value(value: String) -> String:
	return value.uri_encode()

# ─────────────────────────────────────────────────────────────────────────────
#  Scalar validation
# ─────────────────────────────────────────────────────────────────────────────

# Coerce to int and clamp into [lo, hi]. Non-numeric input becomes `lo`.
static func clamp_int(value, lo: int, hi: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return lo
	return clampi(int(value), lo, hi)

# True when `value` is an exact member of `allowed` (case-sensitive allow-list).
static func is_allowed(value: String, allowed: Array) -> bool:
	return allowed.has(value)

# Validate a replicated position: finite components inside the arena box.
# A garbage/NaN/inf or wildly out-of-bounds transform from a peer is rejected
# so it can't be used to teleport, hide, or crash physics on other clients.
static func valid_position(pos: Vector3, half_extent: float = ARENA_HALF_EXTENT) -> bool:
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return false
	return (absf(pos.x) <= half_extent and absf(pos.z) <= half_extent
			and pos.y >= -half_extent and pos.y <= half_extent)

# ─────────────────────────────────────────────────────────────────────────────
#  Schema validation — reject unexpected fields
# ─────────────────────────────────────────────────────────────────────────────

# Returns true only when `dict` is a Dictionary whose keys are exactly a subset
# of `allowed_keys` and which contains every key in `required_keys`. Used to
# reject roster/score payloads carrying unexpected fields (mass-assignment).
static func keys_within(dict, allowed_keys: Array, required_keys: Array = []) -> bool:
	if typeof(dict) != TYPE_DICTIONARY:
		return false
	for k in dict.keys():
		if not allowed_keys.has(k):
			return false
	for k in required_keys:
		if not dict.has(k):
			return false
	return true

# ─────────────────────────────────────────────────────────────────────────────
#  RateLimiter — token-bucket, keyed by identity (peer id, IP, or "self").
#
#  Each key gets a bucket that refills at `refill_per_sec` up to `capacity`
#  tokens. `allow(key)` spends one token and returns true, or returns false
#  (the in-process equivalent of an HTTP 429) when the bucket is empty so the
#  caller can drop the request gracefully without tearing down the session.
#  Idle buckets are pruned so a flood of distinct keys can't grow memory.
# ─────────────────────────────────────────────────────────────────────────────
# Factory for a RateLimiter. Call through the autoload (`Security.new_rate_limiter`)
# rather than `Security.RateLimiter.new()` — accessing an inner class through an
# autoload *instance* isn't reliable, but an instance method always is.
func new_rate_limiter(capacity: float, refill_per_sec: float) -> RateLimiter:
	return RateLimiter.new(capacity, refill_per_sec)

class RateLimiter:
	var _capacity: float
	var _refill: float          # tokens per second
	var _buckets := {}          # key -> { "tokens": float, "ts": int(msec) }
	var _last_prune := 0

	func _init(capacity: float, refill_per_sec: float) -> void:
		_capacity = maxf(1.0, capacity)
		_refill = maxf(0.001, refill_per_sec)

	# Spend one token for `key`. Returns true if allowed, false if rate-limited.
	func allow(key) -> bool:
		var now := Time.get_ticks_msec()
		var b = _buckets.get(key)
		if b == null:
			b = {"tokens": _capacity, "ts": now}
			_buckets[key] = b
		else:
			var elapsed := float(now - b["ts"]) / 1000.0
			b["tokens"] = minf(_capacity, b["tokens"] + elapsed * _refill)
			b["ts"] = now
		_maybe_prune(now)
		if b["tokens"] >= 1.0:
			b["tokens"] -= 1.0
			return true
		return false

	# Forget a key (e.g. when a peer disconnects).
	func forget(key) -> void:
		_buckets.erase(key)

	func reset() -> void:
		_buckets.clear()

	# Drop buckets that have sat full and untouched for a while, so churn of
	# unique keys (peer ids, spoofed IPs) can't leak memory.
	func _maybe_prune(now: int) -> void:
		if now - _last_prune < 30_000:
			return
		_last_prune = now
		for key in _buckets.keys():
			var b = _buckets[key]
			if now - int(b["ts"]) > 60_000 and b["tokens"] >= _capacity:
				_buckets.erase(key)
