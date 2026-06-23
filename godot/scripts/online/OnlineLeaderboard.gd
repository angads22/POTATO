extends Node

# Global online leaderboard via Supabase REST API.
#
# ── SECURE CREDENTIAL HANDLING (OWASP A05/A07) ───────────────────────────────
# The Supabase URL and anon key are NEVER hard-coded in source or committed to
# the repo. They are read at startup from, in priority order:
#   1. Environment variables  SLICEIT_SUPABASE_URL / SLICEIT_SUPABASE_KEY
#   2. A local, git-ignored config file  user://supabase.cfg  (see below)
# If neither is present the game runs fully offline: is_available() returns
# false and every call is a no-op.
#
# Note on the "anon" key: Supabase anon keys are *designed* to ship in clients
# and are safe to expose ONLY when Row Level Security (RLS) is enabled and the
# policies are least-privilege — that is the real authorization boundary, not
# secrecy of the key. We still keep it out of source control so it can be
# rotated without a code change and so a leaked repo doesn't hand out a working
# key. NEVER place a service_role key here — that key bypasses RLS and must
# stay strictly server-side.
#
# SETUP (one-time, free):
#   1. Create a project at https://supabase.com (free tier is fine).
#   2. Run this SQL in the Supabase SQL editor:
#
#        create table sliceit_scores (
#          id         bigserial primary key,
#          name       text not null,
#          score      integer not null,
#          mode       text not null,
#          knife      text,
#          starch     integer default 0,
#          created_at timestamptz default now()
#        );
#        alter table sliceit_scores enable row level security;
#        -- Least-privilege: anon may insert and read, nothing else.
#        create policy "anyone can insert"
#          on sliceit_scores for insert to anon with check (true);
#        create policy "anyone can read"
#          on sliceit_scores for select to anon using (true);
#
#      Server-side hardening is recommended on top of the client checks here:
#      a CHECK constraint (score >= 0 and score < 100000000, char_length(name)
#      <= 24) and a per-IP insert rate limit / edge function, since a client
#      can always be bypassed. Defence in depth.
#
#   3. Provide the credentials WITHOUT editing this file, either:
#        • export SLICEIT_SUPABASE_URL="https://xxxx.supabase.co"
#          export SLICEIT_SUPABASE_KEY="<anon key>"
#        • or create  user://supabase.cfg  (next to your save data) with:
#              [supabase]
#              url="https://xxxx.supabase.co"
#              key="<anon key>"
#
# ── KEY ROTATION ─────────────────────────────────────────────────────────────
# To rotate: generate a new anon key in the Supabase dashboard (Settings → API),
# update the env var / supabase.cfg, and revoke the old one. Because the key
# lives outside source control, rotation needs no rebuild or release.

const TABLE := "sliceit_scores"
const FETCH_LIMIT := 10

# Loaded once at _ready() from the environment / local config — never literals.
var _url := ""
var _key := ""

# Rate limiting (OWASP API4 — unrestricted resource consumption). Even though
# this is the client side, we throttle outbound writes so a stuck game loop or
# a modified build can't flood the shared leaderboard: ~1 submit/3s sustained
# (burst of 3), and a gentler cap on reads.
var _submit_limiter   # ~1 submit / 3s sustained, burst of 3
var _fetch_limiter    # ~1 read / s sustained, burst of 5

func _ready():
	_submit_limiter = Security.new_rate_limiter(3, 1.0 / 3.0)
	_fetch_limiter = Security.new_rate_limiter(5, 1.0)
	_load_credentials()

# Resolve credentials from env first, then a git-ignored local config file.
func _load_credentials() -> void:
	var env_url := OS.get_environment("SLICEIT_SUPABASE_URL").strip_edges()
	var env_key := OS.get_environment("SLICEIT_SUPABASE_KEY").strip_edges()
	if env_url != "" and env_key != "":
		_url = _normalize_url(env_url)
		_key = env_key
		return
	var cfg := ConfigFile.new()
	if cfg.load("user://supabase.cfg") == OK:
		_url = _normalize_url(str(cfg.get_value("supabase", "url", "")).strip_edges())
		_key = str(cfg.get_value("supabase", "key", "")).strip_edges()

# Require HTTPS so the API key is never transmitted over plaintext HTTP
# (OWASP A02 — cryptographic failures / transport security). A non-https or
# blank URL leaves the leaderboard disabled rather than leaking credentials.
func _normalize_url(url: String) -> String:
	url = url.rstrip("/")
	if not url.begins_with("https://"):
		return ""
	return url

func is_available() -> bool:
	return _url != "" and _key != ""

# Fire-and-forget: submit a score. Every field is validated/sanitised against an
# explicit schema before it leaves the machine, and the call is rate-limited.
# Errors are silently swallowed so a network hiccup never interrupts gameplay.
func submit_score(player_name: String, score: int, mode: String, knife: String, starch: int = 0):
	if not is_available():
		return
	# ── input validation & sanitisation (reject, don't coerce blindly) ──
	var clean_mode := mode.strip_edges().to_lower()
	if not Security.is_allowed(clean_mode, Security.ALLOWED_MODES):
		return  # unknown mode → drop rather than store garbage
	var clean_name := Security.sanitize_name(player_name, "Chef")
	var clean_knife := Security.sanitize_name(knife, "", 24)  # may be empty
	var clean_score := Security.clamp_int(score, 0, Security.MAX_SCORE)
	var clean_starch := Security.clamp_int(starch, 0, Security.MAX_STARCH)
	# ── rate limit (graceful drop, the local analogue of a 429) ──
	if not _submit_limiter.allow("self"):
		return
	# Body carries exactly the known columns — no caller-supplied extra fields.
	var body := JSON.stringify({
		"name": clean_name,
		"score": clean_score,
		"mode": clean_mode,
		"knife": clean_knife,
		"starch": clean_starch,
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	req.request(
		_url + "/rest/v1/" + TABLE,
		_headers("application/json"),
		HTTPClient.METHOD_POST,
		body
	)

# SPUD BLASTER result: the global leaderboard ranks by lifetime starch, so we
# submit the player's all-time starch as the score under the "spud_blaster"
# mode (frags ride along in the "score" column too via the starch field).
func submit_fps_result(player_name: String, lifetime_starch: int, frags: int):
	submit_score(player_name, frags, "spud_blaster", "", lifetime_starch)

# Fetch the top chefs ranked by lifetime starch. Calls callback(Array).
func fetch_starch_leaders(callback: Callable):
	if not is_available() or not _fetch_limiter.allow("self"):
		callback.call([])
		return
	var filter := "?mode=eq.spud_blaster&order=starch.desc&limit=%d" % FETCH_LIMIT
	_get_scores(filter, callback)

# Fetch top FETCH_LIMIT scores, optionally filtered by mode.
# Calls callback(Array) — empty array on error or when offline.
func fetch_scores(mode: String, callback: Callable):
	if not is_available() or not _fetch_limiter.allow("self"):
		callback.call([])
		return
	var filter := "?"
	if mode != "":
		var clean_mode := mode.strip_edges().to_lower()
		if not Security.is_allowed(clean_mode, Security.ALLOWED_MODES):
			callback.call([])
			return
		# Percent-encode the value to prevent query-parameter injection into the
		# PostgREST filter (output encoding — OWASP ASVS V5.3).
		filter = "?mode=eq.%s&" % Security.encode_query_value(clean_mode)
	filter += "order=score.desc&limit=%d" % FETCH_LIMIT
	_get_scores(filter, callback)

# Shared GET → JSON-array helper.
func _get_scores(filter: String, callback: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_result, code, _h, body):
		req.queue_free()
		if code != 200:
			callback.call([])
			return
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		callback.call(parsed if parsed is Array else [])
	)
	req.request(_url + "/rest/v1/" + TABLE + filter, _headers(""))

func _headers(content_type: String) -> PackedStringArray:
	var h := PackedStringArray([
		"apikey: " + _key,
		"Authorization: Bearer " + _key,
	])
	if content_type != "":
		h.append("Content-Type: " + content_type)
		h.append("Prefer: return=minimal")
	return h
