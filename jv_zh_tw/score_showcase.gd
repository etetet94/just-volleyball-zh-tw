extends Node
## A finite cosmetic broadcast cut-in. Reads completed native points only; it
## never changes a score, a body, a native effect, or a network packet.

const GAME_PATHS = ["res://game/main/main.gd", "res://game/main/main.gdc"]
const DURATION = 1.65
const THEMES = {
	"ring": ["75dcff", "1878c9"], "star": ["ffe36a", "be771b"],
	"comic": ["ff83cf", "c42776"], "fire": ["ffbd59", "df4825"],
	"ice": ["a5f9ff", "249ec1"], "electric": ["c0b2ff", "6443dd"],
	"portal": ["be8dff", "6a37bb"], "enchant": ["f0c5ff", "813fae"]
}
const TITLES = {
	"spike": ["強攻得分", "SPIKE KILL"], "block": ["鐵壁攔網", "MONSTER BLOCK"],
	"block out": ["打手出界", "BLOCK OUT"], "ace": ["發球得分", "SERVICE ACE"],
	"dump": ["巧妙吊球", "DUMP SHOT"], "kill": ["精彩得分", "POINT"],
	"out": ["出界得分", "OUT OF BOUNDS"], "foot fault": ["踩線犯規", "FOOT FAULT"],
	"fault": ["犯規得分", "FAULT"], "error": ["拿下一分", "POINT"]
}
const REASONS = {
	"serve foul": ["發球違規", "SERVICE FAULT", "發球超時、未合法過網，或發球程序違規"],
	"line fault": ["越中線犯規", "CENTER LINE FAULT", "球員跨越中線進入對方場區"],
	"outside the antenna": ["標竿外過網", "ANTENNA FAULT", "排球從標竿外側越過球網"],
	"foot fault": ["發球踩線", "SERVICE FOOT FAULT", "發球時踩到或越過端線"],
	"illegal attack on serve": ["非法攻擊發球", "ILLEGAL SERVE ATTACK", "接發球時違規攻擊、攔網或跳躍舉球"],
	"four touches": ["四次觸球", "FOUR TOUCHES", "同隊觸球超過三次；攔網不計入三次觸球"],
	"ball out": ["出界得分", "OUT OF BOUNDS", "排球出界，最後觸球的一方失分"]
}

var _enabled = true
var _intensity = 0.85
var _theme = "ring"
var _games: Dictionary = {}
var _transport: Node
var _font: Font
var _layer: CanvasLayer
var _art: BroadcastArt
var _owner_game: WeakRef
var _shown = 0
var _rejected = 0
var _duplicates = 0
var _draw_frames = 0
var _born_usec = 0
var _last_payload: Dictionary = {}
var _suppressed = false
var _preview = false
var _preview_index = 0
var _quality = "auto"

class BroadcastArt extends Control:
	var font: Font
	var title = ""
	var subtitle = ""
	var scorer = ""
	var team = ""
	var home_score = "0"
	var away_score = "0"
	var winner_home = true
	var accent = Color("75dcff")
	var secondary = Color("1878c9")
	var intensity = 0.85
	var age = 0.0
	var event_tag = "spike"
	var reason_detail = ""
	var quality = "auto"
	var _lines: Array = []
	var _shards: Array = []
	var _polys: Array = []
	var _hex = PackedVector2Array()
	var _burst: Array = []
	var _title_width = 0.0
	var _name_width = 0.0
	var _reason_width = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_meta("jv_mod_ui", true)
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		# Deterministic geometry; no global RNG, textures, particle systems, or
		# per-frame nodes. Cache once for the lifetime of the module.
		for i in 32:
			var angle = TAU * float(i) / 32.0 + 0.06 * sin(i * 2.4)
			_lines.append([Vector2(cos(angle), sin(angle)), 0.62 + 0.16 * sin(i * 1.7), 0.08 + 0.11 * absf(cos(i * 3.1))])
		for i in 14:
			_shards.append([float(i) / 14.0, 0.12 + fmod(i * 0.137, 0.68), 7.0 + fmod(i * 11.0, 24.0)])
		for i in 7:
			_polys.append(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
		for i in 7:
			var angle = float(i % 6) * TAU / 6.0
			_hex.append(Vector2(cos(angle), sin(angle)) * 69.0)
		for i in 9:
			var angle = float(i) * TAU / 9.0
			var dir = Vector2(cos(angle), sin(angle))
			var side = dir.orthogonal()
			_burst.append(PackedVector2Array([dir * 43 - side * 11, dir * (125 if i % 2 == 0 else 103), dir * 43 + side * 11]))

	func set_payload(payload: Dictionary, colors: Array, shared_font: Font, strength: float) -> void:
		font = shared_font
		event_tag = str(payload.tag)
		reason_detail = str(payload.get("reason_detail", ""))
		title = str(payload.title)
		subtitle = str(payload.subtitle)
		scorer = str(payload.get("scorer", ""))
		team = "演出預覽" if bool(payload.get("preview", false)) else ("主場得分" if bool(payload.winner_home) else "客場得分")
		home_score = str(payload.home_score)
		away_score = str(payload.away_score)
		winner_home = bool(payload.winner_home)
		accent = Color(colors[0])
		secondary = Color(colors[1])
		intensity = strength
		_title_width = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
		_name_width = font.get_string_size(scorer, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
		_reason_width = font.get_string_size(reason_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		age = 0.0
		visible = true
		queue_redraw()

	func _quad(index: int, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
		var points: PackedVector2Array = _polys[index]
		points[0] = a
		points[1] = b
		points[2] = c
		points[3] = d
		draw_colored_polygon(points, color)

	func _ink(text: String, at: Vector2, font_size: int, color: Color, outline: int = 0) -> void:
		if outline > 0:
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0.018, 0.025, 0.052, color.a * 0.9))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _draw() -> void:
		if font == null or not visible:
			return
		var viewport_size = get_viewport_rect().size
		var fit = minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
		var origin = (viewport_size - Vector2(1920, 1080) * fit) * 0.5
		draw_set_transform(origin, 0, Vector2.ONE * fit)
		var enter = 1.0 - pow(1.0 - clampf(age / 0.20, 0, 1), 3)
		var exit = clampf((age - 1.32) / 0.33, 0, 1)
		var alpha = (1.0 - exit) * enter
		var center = Vector2(960, 478)
		var tint = accent
		tint.a = alpha
		# Wide, transparent edge treatment keeps the original top score and the
		# central players readable. This is only shown after a rally has ended.
		var edge = Color(0.018, 0.024, 0.052, alpha * 0.60)
		_quad(0, Vector2(-160, 200), Vector2(450, 200), Vector2(140, 830), Vector2(-160, 830), edge)
		_quad(1, Vector2(1780, 170), Vector2(2080, 170), Vector2(2080, 820), Vector2(1470, 820), edge)
		for i in _lines.size():
			if quality == "low" and i % 2 == 1: continue
			var line: Array = _lines[i]
			var dir: Vector2 = line[0]
			var inner = Vector2(dir.x * 1170, dir.y * 670)
			var outer = Vector2(dir.x * 1460, dir.y * 910)
			var sweep = 0.92 + 0.08 * enter
			var a = center + inner * float(line[1]) * sweep
			# Do not paint speed-lines through the title, score, or native HUD.
			if a.y > 170 and (a.x < 420 or a.x > 1500 or a.y > 780):
				var c = accent
				c.a = alpha * float(line[2]) * intensity
				draw_line(a, center + outer, c, 3.0 if int(a.x) % 3 == 0 else 1.3, true)
		# One event-specific emblem carries the visual idea. Its silhouette is
		# deliberate (shield / attack burst / cut ball), not extra random noise.
		var emblem_alpha = alpha * (0.65 + 0.25 * intensity)
		var emblem_scale = 0.82 + 0.18 * enter + 0.06 * clampf(age, 0, 1)
		draw_set_transform(origin + Vector2(1670, 436) * fit, -0.13, Vector2.ONE * fit * emblem_scale)
		var hot = Color(accent, emblem_alpha)
		var glow = Color(secondary, emblem_alpha * 0.27)
		if event_tag == "block":
			for offset in [Vector2(-38, -54), Vector2(38, 54), Vector2(0, 0)]:
				draw_set_transform(origin + (Vector2(1670, 436) + offset) * fit, -0.13, Vector2.ONE * fit * emblem_scale)
				draw_polyline(_hex, glow, 14.0, true)
				draw_polyline(_hex, hot, 3.5, true)
			draw_set_transform(origin + Vector2(1670, 436) * fit, -0.13, Vector2.ONE * fit * emblem_scale)
			draw_line(Vector2(-23, -23), Vector2(-23, 23), Color(0.97, 0.99, 1, emblem_alpha), 5, true)
			draw_line(Vector2(0, -32), Vector2(0, 32), Color(0.97, 0.99, 1, emblem_alpha), 5, true)
			draw_line(Vector2(23, -23), Vector2(23, 23), Color(0.97, 0.99, 1, emblem_alpha), 5, true)
		elif event_tag == "block out":
			draw_arc(Vector2(-11, -8), 70, 0.77, 3.87, 30, hot, 6, true)
			draw_arc(Vector2(11, 8), 70, 3.91, 7.02, 30, hot, 6, true)
			draw_line(Vector2(-93, 71), Vector2(93, -71), glow, 22, true)
			draw_line(Vector2(-105, 80), Vector2(105, -80), Color(0.98, 0.99, 1, emblem_alpha), 5, true)
			draw_line(Vector2(-75, 91), Vector2(112, -52), hot, 2, true)
		else:
			for triangle in _burst:
				draw_colored_polygon(triangle, hot)
			draw_circle(Vector2.ZERO, 24, glow)
			draw_arc(Vector2.ZERO, 29, 0, TAU, 28, Color(0.97, 0.99, 1, emblem_alpha), 3, true)
		draw_set_transform(origin, 0, Vector2.ONE * fit)
		var slide = (1.0 - enter) * 350.0 + exit * 280.0
		var y = 350.0 - (1.0 - enter) * 25.0
		var x = 280.0 - slide
		# Layered slashes: black enamel base, saturated trailing edge, a fine
		# metallic keyline, and a short accent blade instead of a flat dialog.
		var under = secondary
		under.a = alpha * 0.76
		_quad(2, Vector2(x + 28, y + 16), Vector2(x + 1395, y - 24), Vector2(x + 1305, y + 206), Vector2(x - 60, y + 238), under)
		_quad(3, Vector2(x, y), Vector2(x + 1370, y - 38), Vector2(x + 1290, y + 184), Vector2(x - 80, y + 222), Color(0.025, 0.032, 0.065, alpha * 0.95))
		_quad(4, Vector2(x + 28, y + 5), Vector2(x + 1372, y - 33), Vector2(x + 1366, y - 18), Vector2(x + 22, y + 20), tint)
		_quad(5, Vector2(x - 76, y + 220), Vector2(x + 1288, y + 182), Vector2(x + 1285, y + 187), Vector2(x - 79, y + 225), Color(accent, alpha * 0.64))
		var blade = Color(accent, alpha * 0.9)
		_quad(6, Vector2(x + 1278, y + 39), Vector2(x + 1330, y + 37), Vector2(x + 1300, y + 122), Vector2(x + 1248, y + 124), blade)
		# An overshoot from 1.08 to 1.00 supplies a single strong impact beat,
		# not repeated flashes. Diagonal ghost lettering provides the wake.
		var pop = 1.0 + 0.075 * pow(1.0 - clampf((age - 0.12) / 0.32, 0, 1), 2)
		var title_fit = minf(1.0, 630.0 / maxf(_title_width, 1.0))
		var tx = x + 120.0
		var title_at = Vector2(tx, y + 122)
		var wake_alpha = alpha * clampf(1.0 - age / 0.55, 0, 1) * 0.27 if quality != "low" else 0.0
		var wake_scale = 1.12 + age * 0.25
		if wake_alpha > 0.001:
			draw_set_transform(origin + (title_at + Vector2(-11, 6)) * fit, -0.028, Vector2.ONE * fit * wake_scale * title_fit)
			draw_string_outline(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 100, 2, Color(accent, wake_alpha))
		draw_set_transform(origin + title_at * fit, -0.028, Vector2.ONE * fit * pop * title_fit)
		_ink(title, Vector2(14, 9), 100, Color(secondary, alpha * 0.65), 5)
		_ink(title, Vector2.ZERO, 100, Color(0.98, 0.985, 1.0, alpha), 3)
		draw_set_transform(origin, 0, Vector2.ONE * fit)
		_ink(subtitle, Vector2(tx + 3, y + 164), 23, Color(accent, alpha))
		# A single foreground slash resolves into the card's keyline. It never
		# changes the entire screen brightness and does not loop or strobe.
		var slash = clampf(1.0 - absf(age - 0.18) / 0.20, 0, 1)
		if slash > 0:
			draw_line(Vector2(x - 125, y + 240), Vector2(x + 1410, y - 48), Color(secondary, slash * 0.38 * intensity), 16, true)
			draw_line(Vector2(x - 125, y + 240), Vector2(x + 1410, y - 48), Color(1, 0.99, 0.94, slash * 0.82), 3, true)
		var name_at = Vector2(x + 825, y + 74)
		_ink(team, name_at, 20, Color(accent, alpha))
		if not scorer.is_empty():
			var available = 390.0
			var name_fit = minf(1.0, available / maxf(_name_width, 1.0))
			draw_set_transform(origin + Vector2(name_at.x, name_at.y + 43) * fit, 0, Vector2.ONE * fit * name_fit)
			_ink(scorer, Vector2.ZERO, 25, Color(0.95, 0.96, 1.0, alpha))
			draw_set_transform(origin, 0, Vector2.ONE * fit)
		# One separate CJK explanation line is measured once at event time and
		# remains readable at 720p. Never abbreviate the actual violation.
		if not reason_detail.is_empty():
			var detail_fit = minf(1.0, 1240.0 / maxf(_reason_width, 1.0))
			draw_set_transform(origin + Vector2(342, 611) * fit, 0, Vector2.ONE * fit * detail_fit)
			_ink(reason_detail, Vector2.ZERO, 24, Color(0.98, 0.985, 1.0, alpha), 4)
			draw_set_transform(origin, 0, Vector2.ONE * fit)
		# Independent scores augment, rather than suppress, the native scoreboard.
		var score_y = 705.0 + exit * 24.0
		var score_alpha = alpha * clampf((age - 0.13) / 0.17, 0, 1)
		var panel = Rect2(716, score_y - 43, 488, 141)
		draw_style_box(_score_box(Color(0.025, 0.032, 0.065, score_alpha * 0.9)), panel)
		var home_color = Color("45ff88") if winner_home else Color("7d9b99")
		var away_color = Color("ff42b9") if not winner_home else Color("9b7d91")
		home_color.a = score_alpha
		away_color.a = score_alpha
		_ink("主場", Vector2(765, score_y - 6), 20, home_color)
		_ink("客場", Vector2(1072, score_y - 6), 20, away_color)
		_ink(home_score, Vector2(770, score_y + 65), 68, Color(0.98, 0.99, 1, score_alpha))
		_ink("—", Vector2(929, score_y + 54), 36, Color(0.56, 0.62, 0.75, score_alpha))
		_ink(away_score, Vector2(1077, score_y + 65), 68, Color(0.98, 0.99, 1, score_alpha))
		# Thin, finite debris outside the focal card; themes retain their palette.
		for shard in _shards:
			if quality == "low": break
			var side = -1.0 if int(shard[0] * 14) % 2 == 0 else 1.0
			var at = Vector2(960 + side * (565 + float(shard[0]) * 310 + age * 100), 290 + float(shard[1]) * 540 - age * 25)
			draw_line(at, at + Vector2(1, -0.35) * float(shard[2]), Color(accent, alpha * 0.7), 2.0, true)
		draw_set_transform(Vector2.ZERO)

	var _box: StyleBoxFlat
	func _score_box(color: Color) -> StyleBoxFlat:
		if _box == null:
			_box = StyleBoxFlat.new()
			_box.corner_radius_top_left = 10
			_box.corner_radius_top_right = 10
			_box.corner_radius_bottom_left = 10
			_box.corner_radius_bottom_right = 10
			_box.border_width_top = 1
			_box.border_color = Color(1, 1, 1, 0.15)
		_box.bg_color = color
		return _box

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10004
	set_process(false)
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)
	_attach_transport(get_tree().root.get_node_or_null("Net"))

func configure(options: Dictionary) -> void:
	_enabled = bool(options.get("score_showcase", true))
	_intensity = clampf(float(options.get("score_intensity", 0.85)), 0.2, 1.0)
	_theme = str(options.get("hit_effect", "ring"))
	_quality = str(options.get("effect_quality", "auto"))
	if _quality not in ["auto", "high", "low"]: _quality = "auto"
	if not THEMES.has(_theme): _theme = "ring"
	if not _enabled: _finish()

func set_font(font: Font) -> void:
	_font = font

func set_suppressed(value: bool) -> void:
	_suppressed = value
	# Closing F8 must also remove a preview before live controls resume.
	if value or _preview: _finish()

func preview() -> void:
	# A deliberate F8 preview is independent of suppression and carries no
	# real-player attribution or invented match score.
	_ensure_art()
	var tags = ["spike", "block", "block out", "ace"]
	var tag = tags[_preview_index % tags.size()]
	_preview_index += 1
	var words: Array = TITLES[tag]
	_last_payload = {"preview": true, "tag": tag, "title": words[0], "subtitle": words[1], "scorer": "非實際對局判定", "winner_home": true, "home_score": "—", "away_score": "—"}
	_preview = true
	_owner_game = null
	_born_usec = Time.get_ticks_usec()
	_layer.layer = 115
	_art.quality = _quality
	_art.set_payload(_last_payload, THEMES[_theme], _font, _intensity)
	_layer.show()
	set_process(true)

func _script_is_game(node: Node) -> bool:
	var script = node.get_script()
	return script != null and script.resource_path in GAME_PATHS

func _scan(node: Node) -> void:
	if _script_is_game(node): _bind_game(weakref(node))
	for child in node.get_children(): _scan(child)

func _on_node_added(node: Node) -> void:
	# Filter before deferring: no recursive rescans and no work for each glyph.
	if _script_is_game(node):
		call_deferred("_bind_game", weakref(node))
	elif node.name == "Net":
		_attach_transport(node)

func _bind_game(reference: WeakRef) -> void:
	var game = reference.get_ref()
	if not is_instance_valid(game) or _games.has(game.get_instance_id()): return
	if not game.is_node_ready():
		game.ready.connect(_bind_game.bind(reference), CONNECT_ONE_SHOT)
		return
	var rally = game.get("_rally")
	if not is_instance_valid(rally) or not rally.has_signal("point"): return
	var id = game.get_instance_id()
	_games[id] = {"reference": reference, "rally": weakref(rally), "last_key": "", "touches": {}, "contacts": {}, "touch_generation": int(game.get("_match_gen"))}
	var callback = _on_native_point.bind(reference)
	if not rally.is_connected("point", callback): rally.connect("point", callback)
	if rally.has_signal("serve_prepared"):
		rally.connect("serve_prepared", _on_serve_prepared.bind(reference))
	var ball = game.get("ball")
	if is_instance_valid(ball):
		if ball.has_signal("net_hit"): ball.connect("net_hit", _on_ball_net.bind(reference))
		if ball.has_signal("antenna_hit"): ball.connect("antenna_hit", _on_ball_antenna.bind(reference))
	game.tree_exited.connect(_drop_game.bind(id), CONNECT_ONE_SHOT)

func _on_serve_prepared(_server: Node, reference: WeakRef) -> void:
	var game = reference.get_ref()
	if is_instance_valid(game) and _games.has(game.get_instance_id()):
		# A rematch can reuse Main, its generation and its first-point score.
		# Preparing the next native serve starts a new completed-point window.
		_games[game.get_instance_id()].last_key = ""
		_games[game.get_instance_id()].touches.clear()
		_games[game.get_instance_id()].contacts.clear()

func _contact_marker(reference: WeakRef) -> Dictionary:
	var game = reference.get_ref()
	if not is_instance_valid(game) or not _games.has(game.get_instance_id()): return {}
	var ball = game.get("ball")
	if not is_instance_valid(ball): return {}
	return {"generation": int(game.get("_match_gen")), "seq": int(ball.get("strike_seq")), "cross": int(ball.get("cross_seq")), "tape": bool(ball.get("last_net_over"))}

func _on_ball_net(reference: WeakRef) -> void:
	var marker = _contact_marker(reference)
	var game = reference.get_ref()
	if not marker.is_empty(): _games[game.get_instance_id()].contacts.net = marker

func _on_ball_antenna(_side: int, reference: WeakRef) -> void:
	var marker = _contact_marker(reference)
	var game = reference.get_ref()
	if not marker.is_empty(): _games[game.get_instance_id()].contacts.antenna = marker

func _native_evidence(game: Node, winner: int, winners_ball: bool) -> Dictionary:
	var result = {}
	var ball = game.get("ball")
	var rally = game.get("_rally")
	var state: Dictionary = _games[game.get_instance_id()]
	if not is_instance_valid(ball): return result
	for kind in ["antenna", "net"]:
		var marker: Dictionary = state.contacts.get(kind, {})
		if marker.is_empty() or int(marker.generation) != int(game.get("_match_gen")) or int(marker.seq) != int(ball.get("strike_seq")): continue
		if kind == "antenna": result.antenna = true
		elif not winners_ball and is_instance_valid(rally) and int(rally.get("last_touch_side")) == -winner and int(marker.cross) == int(ball.get("cross_seq")) and int(signf((ball as Node3D).global_position.z)) == -winner:
			# A net contact alone is legal. This refinement additionally requires
			# the same untouched flight, no subsequent crossing, and own-half loss.
			result.net_failed = true
			result.tape = bool(marker.tape)
	return result

func describe_reason(raw_reason: String, tag: String, evidence: Dictionary = {}) -> Dictionary:
	var words: Array = TITLES.get(tag, TITLES.error)
	var result = {"title": words[0], "subtitle": words[1], "detail": "", "raw_reason": raw_reason}
	if REASONS.has(raw_reason):
		var mapped: Array = REASONS[raw_reason]
		result.title = mapped[0]
		result.subtitle = mapped[1]
		result.detail = mapped[2]
		if raw_reason == "ball out" and tag == "block out":
			result.title = TITLES["block out"][0]
			result.subtitle = TITLES["block out"][1]
			result.detail = "扣球碰到對方攔網球員後出界，攻擊方得分"
		elif raw_reason == "outside the antenna" and bool(evidence.get("antenna", false)):
			result.title = "觸碰標竿"
			result.detail = "排球觸碰標竿，最後觸球的一方失分"
	elif raw_reason.is_empty() and bool(evidence.get("net_failed", false)):
		result.title = "未過網"
		result.subtitle = "NET FAULT"
		result.detail = "觸白帶後未過網，球落回己方場內" if bool(evidence.get("tape", false)) else "觸網後未過網，球落回己方場內"
	elif not raw_reason.is_empty():
		# Preserve unknown future native reasons verbatim, without reclassifying.
		result.detail = "遊戲判定：" + raw_reason.replace("\n", " ").replace("\r", " ").left(100)
	return result

func _drop_game(id: int) -> void:
	_games.erase(id)
	if _owner_game != null:
		var current = _owner_game.get_ref()
		if not is_instance_valid(current) or current.get_instance_id() == id: _finish()

func _attach_transport(net: Node) -> void:
	if is_instance_valid(_transport) and _transport.has_signal("event_received") and _transport.is_connected("event_received", _on_net_event):
		_transport.disconnect("event_received", _on_net_event)
	_transport = net
	if is_instance_valid(net) and net.has_signal("event_received"):
		net.connect("event_received", _on_net_event)

func _active_game(game: Node) -> bool:
	if not _enabled or _suppressed or not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion(): return false
	if game is Node3D and not game.is_visible_in_tree(): return false
	if bool(game.get("embedded")) and not bool(game.get("embedded_active")): return false
	# A practice sandbox never produces a scored native point. Replays and
	# result screens must not re-trigger an announcement while being replayed.
	return int(game.get("_phase")) not in [6, 7]

func _native_tag(game: Node, winner: int, reason: String, scorer: Node, winners_ball: bool) -> String:
	var rally = game.get("_rally")
	var loser_last = rally.get("team_last_toucher").get(-winner) if is_instance_valid(rally) else null
	if reason == "ball out" and is_instance_valid(loser_last) and int(loser_last.get("last_touch")) == 5:
		return "block out"
	if winners_ball and is_instance_valid(scorer):
		var server = rally.get("server") if is_instance_valid(rally) else null
		if reason.is_empty() and is_instance_valid(server) and int(server.get("team_side")) == winner and not bool(rally.get("serve_received")):
			return "ace"
		match int(scorer.get("last_touch")):
			3: return "spike"
			4: return "dump"
			5: return "block"
		return "kill"
	if reason in ["foot fault", "line fault"]: return "foot fault"
	if reason in ["serve foul", "outside the antenna", "illegal attack on serve", "four touches"]: return "fault"
	return "out" if reason == "ball out" else "error"

func _name_for(game: Node, body: Node) -> String:
	if not is_instance_valid(body): return ""
	var names = game.get("_names")
	var value = str(names.get(body, "")) if names is Dictionary else ""
	return value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(64)

func _home_side(game: Node) -> int:
	if not game.has_method("_team_identity"): return 1
	return 1 if int(game.call("_team_identity", 1)) == 1 else -1

func _on_native_point(winner: int, reason: String, scorer: Node, _power: float, winners_ball: bool, reference: WeakRef) -> void:
	var game = reference.get_ref()
	if not _active_game(game) or int(game.get("_net_role")) == 2:
		_rejected += 1
		return
	var rally = game.get("_rally")
	var scores = rally.get("scores")
	var tag = _native_tag(game, winner, reason, scorer, winners_ball)
	# On a fault, the native scorer can be the previous winning toucher. Only
	# show an individual's name when the actual point was earned by that side.
	var earned = tag in ["spike", "block", "block out", "ace", "dump", "kill"]
	_accept(game, winner, int(scores.get(1, 0)), int(scores.get(-1, 0)), tag, _name_for(game, scorer) if earned else "", reason, _native_evidence(game, winner, winners_ball))

func _on_net_event(event: String, args: Dictionary) -> void:
	if event not in ["strike", "antenna", "rally_end"]: return
	for state in _games.values():
		var game = state.reference.get_ref()
		if not _active_game(game) or int(game.get("_net_role")) != 2: continue
		var generation = int(game.get("_match_gen"))
		if args.has("g") and int(args.g) != generation: continue
		if int(state.touch_generation) != generation:
			state.touches.clear()
			state.contacts.clear()
			state.touch_generation = generation
		if event == "antenna":
			state.contacts.antenna = {"generation": generation}
			continue
		if event == "strike":
			state.contacts.clear()
			# Used only to refine the host's generic 'kill' into a block. The
			# authoritative rally_end still decides whether any point is shown.
			if args.get("id") is int and args.get("k") is int:
				var id = int(args.id)
				if id > 0 and id <= 65535 and int(args.k) in [1,2,3,4,5,6]:
					if state.touches.size() >= 64 and not state.touches.has(id): state.touches.clear()
					state.touches[id] = int(args.k)
			continue
		if not (args.get("w") is int and args.get("s1") is int and args.get("s2") is int):
			_rejected += 1
			continue
		var winner = int(args.w)
		if winner not in [-1, 1] or int(args.s1) < 0 or int(args.s2) < 0 or int(args.s1) > 999 or int(args.s2) > 999:
			_rejected += 1
			continue
		var tag = str(args.get("kind", "error"))
		if not TITLES.has(tag): tag = "error"
		var scorer_id = int(args.get("sc", 0))
		if tag == "kill" and int(state.touches.get(scorer_id, 0)) == 5: tag = "block"
		var bodies = game.get("_by_net_id")
		var scorer = bodies.get(scorer_id) if bodies is Dictionary else null
		var earned = tag in ["spike", "block", "block out", "ace", "dump", "kill"]
		var reason = str(args.get("r", "")) if args.get("r", "") is String else ""
		var evidence = {"antenna": state.contacts.has("antenna")}
		_accept(game, winner, int(args.s1), int(args.s2), tag, _name_for(game, scorer) if earned else "", reason, evidence)
		state.touches.clear()
		state.contacts.clear()

func _accept(game: Node, winner: int, positive: int, negative: int, tag: String, scorer: String, raw_reason: String = "", evidence: Dictionary = {}) -> void:
	var state: Dictionary = _games.get(game.get_instance_id(), {})
	if state.is_empty(): return
	var key = "%d:%d:%d:%d:%d" % [int(game.get("_match_gen")), int(game.get("_set_number")), positive, negative, winner]
	if state.last_key == key:
		_duplicates += 1
		return
	state.last_key = key
	var home = _home_side(game)
	var verdict = describe_reason(raw_reason, tag, evidence)
	_last_payload = {"tag": tag, "title": verdict.title, "subtitle": verdict.subtitle, "reason_detail": verdict.detail, "raw_reason": raw_reason, "evidence": evidence.duplicate(), "scorer": scorer, "winner_home": winner == home, "home_score": positive if home == 1 else negative, "away_score": negative if home == 1 else positive}
	_ensure_art()
	_preview = false
	_layer.layer = 50
	_art.quality = _quality
	_owner_game = weakref(game)
	_born_usec = Time.get_ticks_usec()
	_art.set_payload(_last_payload, THEMES[_theme], _font, _intensity)
	_layer.show()
	_shown += 1
	set_process(true)

func _ensure_art() -> void:
	if _font == null:
		var fallback = SystemFont.new()
		fallback.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "sans-serif"])
		fallback.font_weight = 900
		_font = fallback
	if is_instance_valid(_art): return
	_layer = CanvasLayer.new()
	_layer.name = "JVScoreShowcase"
	_layer.layer = 50
	add_child(_layer)
	_art = BroadcastArt.new()
	_art.name = "BroadcastArt"
	_layer.add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	var game = _owner_game.get_ref() if _owner_game != null else null
	var age = float(Time.get_ticks_usec() - _born_usec) / 1000000.0
	if (not _preview and not _active_game(game)) or age >= DURATION:
		_finish()
		return
	_art.age = age
	_art.queue_redraw()
	_draw_frames += 1

func _finish() -> void:
	set_process(false)
	if is_instance_valid(_layer): _layer.hide()
	_owner_game = null
	_preview = false

func get_diagnostics() -> Dictionary:
	return {"enabled": _enabled, "intensity": _intensity, "quality": _quality, "active": is_processing(), "preview": _preview, "shown": _shown, "rejected": _rejected, "duplicates": _duplicates, "draw_frames": _draw_frames, "tracked_games": _games.size(), "last": _last_payload.duplicate(true)}
