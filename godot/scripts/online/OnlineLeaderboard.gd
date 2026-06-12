extends Node

# Global online leaderboard via Supabase REST API.
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
#          created_at timestamptz default now()
#        );
#        alter table sliceit_scores enable row level security;
#        create policy "anyone can insert"
#          on sliceit_scores for insert to anon with check (true);
#        create policy "anyone can read"
#          on sliceit_scores for select to anon using (true);
#
#   3. Replace SUPABASE_URL and SUPABASE_KEY below with your project's
#      values (Settings → API in the Supabase dashboard).
#
# The game works fully offline when these are left as placeholders —
# is_available() returns false and all calls are no-ops.

const SUPABASE_URL := "YOUR_SUPABASE_URL"
const SUPABASE_KEY := "YOUR_SUPABASE_ANON_KEY"
const TABLE := "sliceit_scores"
const FETCH_LIMIT := 10

func _ready():
	pass

func is_available() -> bool:
	return (SUPABASE_URL != "YOUR_SUPABASE_URL" and
			SUPABASE_KEY != "YOUR_SUPABASE_ANON_KEY")

# Fire-and-forget: submit a score. Errors are silently swallowed so a
# network hiccup never interrupts gameplay.
func submit_score(player_name: String, score: int, mode: String, knife: String):
	if not is_available():
		return
	var body := JSON.stringify({
		"name": player_name.left(24),
		"score": score,
		"mode": mode,
		"knife": knife,
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	req.request(
		SUPABASE_URL + "/rest/v1/" + TABLE,
		_headers("application/json"),
		HTTPClient.METHOD_POST,
		body
	)

# Fetch top FETCH_LIMIT scores, optionally filtered by mode.
# Calls callback(Array) — empty array on error or when offline.
func fetch_scores(mode: String, callback: Callable):
	if not is_available():
		callback.call([])
		return
	var filter := ("?mode=eq.%s&" % mode) if mode != "" else "?"
	filter += "order=score.desc&limit=%d" % FETCH_LIMIT
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
	req.request(
		SUPABASE_URL + "/rest/v1/" + TABLE + filter,
		_headers("")
	)

func _headers(content_type: String) -> PackedStringArray:
	var h := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Authorization: Bearer " + SUPABASE_KEY,
	])
	if content_type != "":
		h.append("Content-Type: " + content_type)
		h.append("Prefer: return=minimal")
	return h
