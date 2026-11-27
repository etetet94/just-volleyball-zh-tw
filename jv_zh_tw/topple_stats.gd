extends Node
## Extra match statistics, kept separate from the game's official statistics.
## Hosts publish only numeric player IDs and counts through the existing event channel.

const EVENT_KIND = "jv_zh_tw:topples:v1"
const MAX_ROWS = 64
const MAX_ID = 65535
const MAX_COUNT = 1000000
const MAX_SEQUENCE = 2147483647
const COLUMN_NAME = "JVToppleColumn"
const GAME_PATHS = ["res://game/main/main.gd", "res://game/main/main.gdc"]
const TABLE_PATHS = ["res://game/ui/score_table.gd", "res://game/ui/score_table.gdc"]

var _games: Dictionary = {}
var _columns: Array[WeakRef] = []
var _transport: Node
var _explicit_transport := false
var _show := true
var _next_poll_msec := 0
var _accepted_events := 0
var _rejected_events := 0
var _sent_events := 0
var _column_font: Font

func _ready() -> void:
	name = "JVToppleStats"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10002
	get_tree().node_added.connect(_on_node_added)
	_scan_games(get_tree().root)
	_ensure_transport()

func setup(extras: Node) -> void:
	if not is_instance_valid(extras):
		return
	if extras.has_method("set_external_stats"):
		extras.call("set_external_stats", true)
	var callback = Callable(self, "record_topple")
	if extras.has_signal("topple_observed") and not extras.is_connected("topple_observed", callback):
		extras.connect("topple_observed", callback)

func configure(options: Dictionary) -> void:
	_show = bool(options.get("fun_stats", true))
	for reference in _columns:
		var column = reference.get_ref()
		if is_instance_valid(column):
			column.visible = _show

func set_transport(transport: Node) -> void:
	# Explicit injection supports offline verification without sending a real RPC.
	_explicit_transport = true
	_attach_transport(transport)

func _attach_transport(transport: Node) -> void:
	var callback = Callable(self, "_on_net_event")
	if is_instance_valid(_transport) and _transport.has_signal("event_received") and _transport.is_connected("event_received", callback):
		_transport.disconnect("event_received", callback)
	_transport = transport
	if is_instance_valid(_transport) and _transport.has_signal("event_received") and not _transport.is_connected("event_received", callback):
		_transport.connect("event_received", callback)

func _ensure_transport() -> void:
	if _explicit_transport:
		return
	var net = get_tree().root.get_node_or_null("Net")
	if net != _transport:
		_attach_transport(net)

func _on_node_added(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path in GAME_PATHS:
		call_deferred("_register_game", weakref(node))

func _scan_games(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path in GAME_PATHS:
		_state_for(node)
	for child in node.get_children():
		_scan_games(child)

func _register_game(reference: WeakRef) -> void:
	var game = reference.get_ref()
	if is_instance_valid(game):
		_state_for(game)

func _state_for(game: Node) -> Dictionary:
	var id = game.get_instance_id()
	var generation = int(game.get("_match_gen"))
	var role = int(game.get("_net_role"))
	var over = bool(game.get("_match_over"))
	if not _games.has(id) or _games[id].generation != generation or _games[id].role != role:
		_games[id] = {"reference": weakref(game), "generation": generation, "role": role, "over": over, "counts": {}, "sequence": 0, "received": false, "dirty": true, "last_send": -100000, "last_receive": -100000}
	elif bool(_games[id].over) and not over:
		# Native "play again" reuses Main and its generation. Keep the sequence
		# monotonic so clients accept the next zeroed snapshot for this rematch.
		_games[id].counts = {}
		_games[id].received = false
		_games[id].dirty = true
		_games[id].last_receive = -100000
	_games[id].over = over
	return _games[id]

func _id_for(game: Node, body: Node) -> int:
	var ids = game.get("_net_ids")
	if ids is Dictionary and ids.has(body):
		var value = ids[body]
		return value if value is int and value > 0 and value <= MAX_ID else 0
	if int(game.get("_net_role")) == 0:
		var players = game.get("_all_players")
		if players is Array:
			var index = players.find(body)
			return index + 1 if index >= 0 and index < MAX_ROWS else 0
	return 0

func record_topple(game: Node, attacker: Node, victim: Node) -> void:
	if not is_instance_valid(game) or not is_instance_valid(attacker) or not is_instance_valid(victim) or attacker == victim:
		return
	var state = _state_for(game)
	# Only the host (or an offline game) observes authoritative collisions.
	if state.role == 2:
		return
	var attacker_id = _id_for(game, attacker)
	if attacker_id == 0 or _id_for(game, victim) == 0:
		return
	state.counts[attacker_id] = mini(MAX_COUNT, int(state.counts.get(attacker_id, 0)) + 1)
	state.dirty = true

func get_count(game: Node, player_id: int) -> Variant:
	var state = _state_for(game)
	if state.role == 2 and not state.received:
		return null
	return int(state.counts.get(player_id, 0))

func _network_ready(host: bool) -> bool:
	return is_instance_valid(_transport) and bool(_transport.get("active")) and bool(_transport.get("in_match")) and bool(_transport.get("is_host")) == host

func _roster_ids(game: Node, state: Dictionary) -> Array:
	var result: Array = []
	var ids = game.get("_net_ids")
	if ids is Dictionary:
		for value in ids.values():
			if value is int and value > 0 and value <= MAX_ID and not value in result:
				result.append(value)
	for value in state.counts:
		if not value in result:
			result.append(value)
	result.sort()
	return result.slice(0, MAX_ROWS)

func _send_snapshot(game: Node, state: Dictionary, now: int) -> void:
	if state.role != 1 or not _network_ready(true) or not _transport.has_method("send_event"):
		return
	var since = now - int(state.last_send)
	if since < 500 or (not state.dirty and since < 2000):
		return
	if state.sequence >= MAX_SEQUENCE:
		return
	var rows: Array = []
	for id in _roster_ids(game, state):
		rows.append([id, int(state.counts.get(id, 0))])
	state.sequence += 1
	var payload = {"v": 1, "g": state.generation, "s": state.sequence, "r": rows}
	_transport.call("send_event", EVENT_KIND, payload)
	state.last_send = now
	state.dirty = false
	_sent_events += 1

func _on_net_event(kind: String, payload: Dictionary) -> void:
	receive_event(kind, payload)

func _validated_snapshot(payload: Variant) -> Dictionary:
	if not payload is Dictionary or payload.size() != 4:
		return {}
	for key in ["v", "g", "s", "r"]:
		if not payload.has(key):
			return {}
	if not payload.v is int or payload.v != 1 or not payload.g is int or not payload.s is int:
		return {}
	if payload.s < 1 or payload.s > MAX_SEQUENCE or not payload.r is Array or payload.r.size() > MAX_ROWS:
		return {}
	var counts: Dictionary = {}
	for row in payload.r:
		if not row is Array or row.size() != 2 or not row[0] is int or not row[1] is int:
			return {}
		var id: int = row[0]
		var count: int = row[1]
		if id < 1 or id > MAX_ID or count < 0 or count > MAX_COUNT or counts.has(id):
			return {}
		counts[id] = count
	return {"generation": payload.g, "sequence": payload.s, "counts": counts}

func receive_event(kind: String, payload: Variant) -> void:
	if kind != EVENT_KIND:
		return
	if not _network_ready(false):
		_rejected_events += 1
		return
	var snapshot = _validated_snapshot(payload)
	if snapshot.is_empty():
		_rejected_events += 1
		return
	var accepted := false
	for id in _games.keys():
		var game = _games[id].reference.get_ref()
		if not is_instance_valid(game):
			continue
		var state = _state_for(game)
		if state.role != 2 or state.generation != snapshot.generation or snapshot.sequence <= state.sequence:
			continue
		state.counts = snapshot.counts.duplicate()
		state.sequence = snapshot.sequence
		state.received = true
		state.last_receive = Time.get_ticks_msec()
		accepted = true
	if accepted:
		_accepted_events += 1
	else:
		_rejected_events += 1

func _make_column(parent: HBoxContainer, width: float, header: bool) -> Label:
	var column = parent.get_node_or_null(COLUMN_NAME) as Label
	if column == null:
		column = Label.new()
		column.name = COLUMN_NAME
		column.set_meta("jv_mod_ui", true)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if _column_font == null:
			var font = SystemFont.new()
			font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Microsoft YaHei"])
			font.font_weight = 600
			_column_font = font
		column.add_theme_font_override("font", _column_font)
		column.add_theme_font_size_override("font_size", 14 if header else 17)
		column.add_theme_color_override("font_color", Color("ffe06a") if header else Color("fff0b0"))
		column.tooltip_text = "額外趣味統計：撲倒其他玩家的次數。連線時由房主同步；— 表示尚無房主資料。"
		parent.add_child(column)
		_columns.append(weakref(column))
	column.custom_minimum_size.x = width
	column.visible = _show
	return column

func _row_box(row: Node) -> HBoxContainer:
	var labels = row.get("_stat_labels")
	if labels is Array and not labels.is_empty() and is_instance_valid(labels[0]):
		return labels[0].get_parent() as HBoxContainer
	for child in row.get_children():
		if child is HBoxContainer:
			return child
	return null

func _row_id_for(game: Node, data: Dictionary) -> int:
	var id = data.get("id", 0)
	if id is int and id > 0 and id <= MAX_ID:
		return id
	if int(game.get("_net_role")) != 0:
		return 0
	# Offline StatRows use id=0. Match the untouched ready_name and team identity
	# to exactly one body; ambiguous duplicate names deliberately stay unknown.
	var names = game.get("_names")
	var players = game.get("_all_players")
	if not names is Dictionary or not players is Array or not data.get("ready_name") is String:
		return 0
	var candidates: Array = []
	for body in players:
		if not is_instance_valid(body) or not names.has(body) or str(names[body]) != data.ready_name:
			continue
		var side = body.get("team_side")
		if game.has_method("_team_identity"):
			side = game.call("_team_identity", side)
		if side is int and side == data.get("side"):
			candidates.append(_id_for(game, body))
	return int(candidates[0]) if candidates.size() == 1 else 0

func _update_table(game: Node, table: Node) -> void:
	var heads = table.get("_heads")
	var rows = table.get("row_by_key")
	if not heads is Array or not rows is Dictionary:
		return
	var width = maxf(40.0, minf(56.0, float(table.get("_stat_w"))))
	for head in heads:
		if is_instance_valid(head) and head is HBoxContainer:
			_make_column(head, width, true).text = "撲倒"
	for row in rows.values():
		if not is_instance_valid(row):
			continue
		var box = _row_box(row)
		var data = row.get("_row_data")
		if box == null or not data is Dictionary:
			continue
		var player_id = _row_id_for(game, data)
		var value = get_count(game, player_id) if player_id > 0 else null
		_make_column(box, width, false).text = "—" if value == null else str(value)

func _update_results(game: Node) -> void:
	var hud = game.get("hud")
	if not is_instance_valid(hud):
		return
	var panel = hud.get_node_or_null("PostStats")
	if not panel is Control or not panel.is_visible_in_tree():
		return
	var table = hud.get("_post_stats_board")
	if is_instance_valid(table):
		var script = table.get_script()
		if script != null and script.resource_path in TABLE_PATHS:
			_update_table(game, table)

func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec()
	if now < _next_poll_msec:
		return
	_next_poll_msec = now + 200
	_ensure_transport()
	for id in _games.keys():
		var game = _games[id].reference.get_ref()
		if not is_instance_valid(game):
			_games.erase(id)
			continue
		var state = _state_for(game)
		_send_snapshot(game, state, now)
		_update_results(game)
	var alive: Array[WeakRef] = []
	for reference in _columns:
		if is_instance_valid(reference.get_ref()):
			alive.append(reference)
	_columns = alive

func debug_snapshot() -> Dictionary:
	var states: Array = []
	for state in _games.values():
		states.append({"generation": state.generation, "role": state.role, "counts": state.counts.duplicate(), "sequence": state.sequence, "received": state.received})
	return {"states": states, "accepted_events": _accepted_events, "rejected_events": _rejected_events, "sent_events": _sent_events, "columns": _columns.size()}
