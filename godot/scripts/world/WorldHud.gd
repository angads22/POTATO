extends Node2D
class_name WorldHUD

# Overworld overlay UI shared by the farm and the town, hosted on a
# CanvasLayer so it ignores the scrolling camera and the night tint. Reads
# everything from the owning WorldController (ctrl) and SaveDataManager.

var ctrl  # WorldController

func _draw():
	if ctrl == null:
		return
	var font = ThemeDB.fallback_font

	_draw_wallet_panel(font)
	_draw_inventory_panel(font)
	_draw_day_dial()

	# interaction prompt above the hotbar area
	if ctrl.open_shop == "" and ctrl.prompt != "":
		var ps = font.get_string_size(ctrl.prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		GameHUD.panel_style().draw(get_canvas_item(), Rect2(640 - ps.x / 2 - 18, 622, ps.x + 36, 44))
		draw_string(font, Vector2(640 - ps.x / 2, 652), ctrl.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.98, 0.95, 0.85))

	# rising popups
	for p in ctrl.popups:
		var frac = p.age / ctrl.POPUP_LIFE
		var col: Color = p.color
		col.a = 1.0 - frac
		var ts = font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
		var py = 250 - frac * 60.0
		draw_string(font, Vector2(642 - ts.x / 2, py + 2), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0, 0, 0, (1.0 - frac) * 0.6))
		draw_string(font, Vector2(640 - ts.x / 2, py), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)

	# entry banner
	if ctrl.banner_age < 2.0:
		var alpha = 1.0 if ctrl.banner_age < 1.4 else (2.0 - ctrl.banner_age) / 0.6
		var bs = font.get_string_size(ctrl.banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 56)
		draw_rect(Rect2(0, 300, 1280, 110), Color(0.07, 0.12, 0.04, 0.7 * alpha))
		draw_rect(Rect2(0, 300, 1280, 4), Color(0.85, 0.68, 0.3, alpha))
		draw_rect(Rect2(0, 406, 1280, 4), Color(0.85, 0.68, 0.3, alpha))
		draw_string(font, Vector2(643 - bs.x / 2, 375), ctrl.banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0, 0, 0, 0.5 * alpha))
		draw_string(font, Vector2(640 - bs.x / 2, 372), ctrl.banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.85, 0.3, alpha))

	# controls hint
	var hint = "[ESC] Close" if ctrl.open_shop != "" else "[WASD] Move · [E] Interact · [ESC] Menu"
	draw_string(font, Vector2(20, 706), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.92, 0.85, 0.65))

	if ctrl.open_shop != "":
		_draw_shop(font)

func _draw_wallet_panel(font: Font):
	GameHUD.panel_style().draw(get_canvas_item(), Rect2(10, 8, 350, 52))
	# coin icon
	draw_circle(Vector2(38, 34), 14.0, Color(0.95, 0.78, 0.25))
	draw_arc(Vector2(38, 34), 14.0, 0, TAU, 20, Color(0.7, 0.52, 0.1), 2.5)
	draw_arc(Vector2(38, 34), 8.0, 0, TAU, 16, Color(0.8, 0.62, 0.15), 2.0)
	draw_string(font, Vector2(60, 43), "%d" % SaveDataManager.wallet(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.GOLD)
	# watering can charges as droplets
	var water: int = int(SaveDataManager.farm.get("water", 0))
	for i in range(4):
		var cx = 152.0 + i * 18.0
		var col = Color(0.4, 0.7, 0.95) if i < water else Color(0.35, 0.32, 0.3)
		draw_circle(Vector2(cx, 38), 5.5, col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 4.5, 35), Vector2(cx + 4.5, 35), Vector2(cx, 25)
		]), col)
	# plow durability
	var uses: int = int(SaveDataManager.farm.get("plow_uses", 0))
	var pcol = Color(0.85, 0.66, 0.4) if uses > 0 else Color(0.45, 0.4, 0.36)
	draw_line(Vector2(238, 24), Vector2(250, 36), pcol, 3.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(247, 33), Vector2(257, 33), Vector2(250, 45)
	]), pcol.lightened(0.15))
	draw_string(font, Vector2(262, 43), "%d" % uses, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(0.95, 0.92, 0.85) if uses > 0 else Color(0.6, 0.55, 0.5))
	# sprinklers waiting in the pack
	var stock: int = int(SaveDataManager.farm.get("sprinkler_stock", 0))
	var scol = Color(0.45, 0.75, 0.95) if stock > 0 else Color(0.42, 0.4, 0.38)
	draw_line(Vector2(308, 44), Vector2(308, 32), scol, 3.0)
	draw_circle(Vector2(308, 30), 4.5, scol)
	draw_arc(Vector2(308, 30), 9.0, -2.4, -0.7, 8, scol, 2.0)
	draw_string(font, Vector2(320, 43), "%d" % stock, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(0.95, 0.92, 0.85) if stock > 0 else Color(0.6, 0.55, 0.5))

func _draw_inventory_panel(font: Font):
	GameHUD.panel_style().draw(get_canvas_item(), Rect2(920, 8, 350, 112))
	draw_string(font, Vector2(936, 32), "SEEDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.68, 0.3))
	draw_string(font, Vector2(936, 68), "SPUDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.68, 0.3))
	draw_string(font, Vector2(936, 104), "FERT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.68, 0.3))
	for row in range(3):
		var things: Array
		var inv_name: String
		match row:
			0:
				inv_name = "seeds"
				things = GameData.farmable_potatoes()
			1:
				inv_name = "spuds"
				things = GameData.farmable_potatoes()
			_:
				# fertilizer counts are charges remaining
				inv_name = "items"
				things = GameData.enhancers()
		var y = 26.0 + row * 36.0
		var x = 1000.0
		var any = false
		for p in things:
			var n = SaveDataManager.item_count(inv_name, p["id"])
			if n <= 0:
				continue
			any = true
			draw_circle(Vector2(x, y), 8.0, Color(p.get("color", "#b87333")))
			draw_arc(Vector2(x, y), 8.0, 0, TAU, 14, Color(0, 0, 0, 0.4), 1.5)
			draw_string(font, Vector2(x + 11, y + 6), "%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.92, 0.85))
			x += 44.0
			if x > 1240.0:
				break
		if not any:
			draw_string(font, Vector2(1000, y + 6), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.55, 0.5))

func _draw_day_dial():
	# sun/moon arc dial: marker travels the day circle
	var c = Vector2(640, 38)
	GameHUD.panel_style().draw(get_canvas_item(), Rect2(c.x - 56, 8, 112, 56))
	draw_arc(c + Vector2(0, 14), 30.0, PI, TAU, 24, Color(0.85, 0.68, 0.3, 0.6), 2.5)
	# day_t < 0.5 is daytime: the sun sweeps the arc; then the moon repeats it
	var sun_up = fposmod(ctrl.day_t, 1.0) < 0.5
	var frac = fposmod(ctrl.day_t, 0.5) / 0.5
	var day_angle = PI + frac * PI
	var marker = c + Vector2(0, 14) + Vector2(cos(day_angle), sin(day_angle)) * 30.0
	if sun_up:
		draw_circle(marker, 8.0, Color(1.0, 0.85, 0.3))
		for i in range(8):
			var a = i * TAU / 8.0
			draw_line(marker + Vector2(cos(a), sin(a)) * 10.0, marker + Vector2(cos(a), sin(a)) * 14.0, Color(1.0, 0.85, 0.3), 2.0)
	else:
		draw_circle(marker, 8.0, Color(0.85, 0.88, 0.95))
		draw_circle(marker + Vector2(3, -2), 6.5, GameHUD.panel_style().bg_color)

# ── shop overlays ──

func _draw_shop(font: Font):
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.55))
	var panel = Rect2(320, 110, 640, 500)
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.97)).draw(get_canvas_item(), panel)

	var title = ""
	match ctrl.open_shop:
		"seeds": title = "SEED SHOP"
		"market": title = "MARKET — SELL YOUR SPUDS"
		"knives": title = "KNIFE STAND"
		"plant": title = "PLANT A SEED"
		"tools": title = "TOOL SHED"
		"enhance": title = "FERTILIZE THIS CROP"
	var ts = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
	draw_string(font, Vector2(640 - ts.x / 2, 160), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.GOLD)

	# wallet, top-right of the panel
	var wt = "%d coins" % SaveDataManager.wallet()
	var ws = font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(panel.end.x - ws.x - 24, 146), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GOLD)

	match ctrl.open_shop:
		"seeds":
			_draw_seed_rows(font, panel, true)
			_draw_footer(font, panel, "[1-%d] Buy seed   ·   [ESC] Close" % GameData.farmable_potatoes().size())
		"plant":
			_draw_seed_rows(font, panel, false)
			_draw_footer(font, panel, "[1-%d] Plant   ·   [ESC] Cancel" % GameData.farmable_potatoes().size())
		"market":
			_draw_market_rows(font, panel)
			_draw_footer(font, panel, "[1-7] Sell stack   ·   [A] Sell everything   ·   [ESC] Close")
		"knives":
			_draw_knife_rows(font, panel)
			_draw_footer(font, panel, "[1-%d] Buy / Equip   ·   [ESC] Close" % GameData.knives().size())
		"tools":
			_draw_tool_rows(font, panel)
			_draw_footer(font, panel, "[1-%d] Buy   ·   [ESC] Close" % (GameData.tools().size() + GameData.enhancers().size()))
		"enhance":
			_draw_enhance_rows(font, panel)
			_draw_footer(font, panel, "[1-%d] Apply   ·   [ESC] Cancel" % maxi(ctrl.owned_enhancers().size(), 1))

func _draw_seed_rows(font: Font, panel: Rect2, shop_mode: bool):
	var y = 210.0
	var i = 0
	for p in GameData.farmable_potatoes():
		i += 1
		var owned = SaveDataManager.item_count("seeds", p["id"])
		var cost = int(p["seed_cost"])
		var ok = SaveDataManager.wallet() >= cost if shop_mode else owned > 0
		var col = Color(0.95, 0.92, 0.85) if ok else Color(0.55, 0.5, 0.45)
		draw_circle(Vector2(panel.position.x + 48, y - 7), 10.0, Color(p.get("color", "#b87333")))
		var line = "[%d] %s" % [i, p["name"]]
		draw_string(font, Vector2(panel.position.x + 70, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		var detail = ""
		if shop_mode:
			detail = "%d c · grows %ds · sells %d c" % [cost, int(p["grow_time"]), int(p["sell_value"])]
		else:
			detail = "x%d in pocket · grows %ds" % [owned, int(p["grow_time"])]
		var ds = font.get_string_size(detail, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, Vector2(panel.end.x - ds.x - 30, y), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.darkened(0.15))
		if shop_mode and owned > 0:
			draw_string(font, Vector2(panel.position.x + 70, y + 18), "owned: %d" % owned, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.65, 0.55))
		y += 48.0

func _draw_market_rows(font: Font, panel: Rect2):
	var y = 210.0
	var i = 0
	var any = false
	for p in GameData.farmable_potatoes():
		i += 1
		var n = SaveDataManager.item_count("spuds", p["id"])
		if n <= 0:
			continue
		any = true
		var value = n * int(p["sell_value"])
		draw_circle(Vector2(panel.position.x + 48, y - 7), 10.0, Color(p.get("color", "#b87333")))
		draw_string(font, Vector2(panel.position.x + 70, y), "[%d] %s × %d" % [i, p["name"], n], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.92, 0.85))
		var detail = "sell for %d c" % value
		var ds = font.get_string_size(detail, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(panel.end.x - ds.x - 30, y), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GOLD)
		y += 48.0
	if not any:
		var msg = "Nothing to sell — go grow some potatoes!"
		var ms = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(640 - ms.x / 2, 300), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))

func _draw_knife_rows(font: Font, panel: Rect2):
	var y = 200.0
	var i = 0
	var owned_list: Array = SaveDataManager.farm.get("owned_knives", [])
	var equipped: String = SaveDataManager.farm.get("equipped_knife", "butter")
	for k in GameData.knives():
		i += 1
		var owned = k["id"] in owned_list
		var cost = int(k["cost"])
		var col = Color(0.95, 0.92, 0.85)
		if not owned and SaveDataManager.wallet() < cost:
			col = Color(0.55, 0.5, 0.45)
		# little blade icon
		draw_colored_polygon(PackedVector2Array([
			Vector2(panel.position.x + 40, y - 14), Vector2(panel.position.x + 58, y - 14),
			Vector2(panel.position.x + 49, y + 4)
		]), Color(k.get("color", "#d0d0d0")))
		draw_string(font, Vector2(panel.position.x + 70, y), "[%d] %s" % [i, k["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		draw_string(font, Vector2(panel.position.x + 70, y + 18), "score ×%.2f" % float(k["damage"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.65, 0.55))
		var status = ""
		var scol = Color.GOLD
		if k["id"] == equipped:
			status = "EQUIPPED"
			scol = Color.LIGHT_GREEN
		elif owned:
			status = "owned — equip"
		else:
			status = "%d c" % cost
			scol = col
		var ss = font.get_string_size(status, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, Vector2(panel.end.x - ss.x - 30, y), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, scol)
		y += 54.0

func _draw_tool_rows(font: Font, panel: Rect2):
	var y = 196.0
	var i = 0
	for tl in GameData.tools():
		i += 1
		var id: String = tl["id"]
		var cost = ctrl.plow_cost() if id == "plow" else int(tl.get("cost", 0))
		var desc: String = tl.get("desc", "")
		var status = "%d c" % cost
		var scol = Color(0.95, 0.92, 0.85) if SaveDataManager.wallet() >= cost else Color(0.55, 0.5, 0.45)
		var col = scol
		match id:
			"plow":
				if ctrl.plow_uses() > 0:
					status = "uses left: %d" % ctrl.plow_uses()
					scol = Color.LIGHT_GREEN
					col = Color(0.95, 0.92, 0.85)
			"sprinkler":
				desc += "  ·  placed: %d · stock: %d" % [ctrl.sprinklers_placed(), ctrl.sprinkler_stock()]
				col = Color(0.95, 0.92, 0.85)
			_:
				if ctrl.owns_tool(id):
					status = "INSTALLED"
					scol = Color.LIGHT_GREEN
					col = Color(0.95, 0.92, 0.85)
		draw_circle(Vector2(panel.position.x + 48, y - 7), 10.0, Color(tl.get("color", "#888")))
		draw_string(font, Vector2(panel.position.x + 70, y), "[%d] %s" % [i, tl["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		draw_string(font, Vector2(panel.position.x + 70, y + 18), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.65, 0.55))
		var ss = font.get_string_size(status, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, Vector2(panel.end.x - ss.x - 30, y), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, scol)
		y += 48.0
	# divider, then the fertilizers (multi-charge consumables)
	draw_rect(Rect2(panel.position.x + 30, y - 24, panel.size.x - 60, 2), Color(0.85, 0.68, 0.3, 0.4))
	for e in GameData.enhancers():
		i += 1
		var cost2 = int(e["cost"])
		var have = SaveDataManager.item_count("items", e["id"])
		var col2 = Color(0.95, 0.92, 0.85) if SaveDataManager.wallet() >= cost2 else Color(0.55, 0.5, 0.45)
		draw_circle(Vector2(panel.position.x + 48, y - 7), 10.0, Color(e.get("color", "#888")))
		draw_string(font, Vector2(panel.position.x + 70, y), "[%d] %s" % [i, e["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col2)
		var desc2 = e.get("desc", "")
		if have > 0:
			desc2 += "  ·  charges left: %d" % have
		draw_string(font, Vector2(panel.position.x + 70, y + 18), desc2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.65, 0.55))
		var ss2 = font.get_string_size("%d c" % cost2, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, Vector2(panel.end.x - ss2.x - 30, y), "%d c" % cost2, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col2)
		y += 48.0

func _draw_enhance_rows(font: Font, panel: Rect2):
	var owned = ctrl.owned_enhancers()
	if owned.is_empty():
		var msg = "No fertilizer in your pockets — buy some at the tool shed"
		var ms = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, Vector2(640 - ms.x / 2, 300), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.65, 0.55))
		return
	var y = 220.0
	var i = 0
	for e in owned:
		i += 1
		var n = SaveDataManager.item_count("items", e["id"])
		draw_circle(Vector2(panel.position.x + 48, y - 7), 10.0, Color(e.get("color", "#888")))
		draw_string(font, Vector2(panel.position.x + 70, y), "[%d] %s — %d charges" % [i, e["name"], n], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.92, 0.85))
		draw_string(font, Vector2(panel.position.x + 70, y + 18), e.get("desc", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.65, 0.55))
		y += 54.0

func _draw_footer(font: Font, panel: Rect2, text: String):
	var fs = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(640 - fs.x / 2, panel.end.y - 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.7, 0.62))
