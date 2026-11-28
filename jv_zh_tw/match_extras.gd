extends Node
## Local visual effects and deliberately conservative, non-authoritative fun stats.
## Observes existing signals. Never invokes gameplay actions or sends network data.

const GAME_SCRIPT = "res://game/main/main"
const PLAYER_SCRIPT = "res://game/player/player"
const BALL_SCRIPT = "res://game/ball/ball"
signal topple_observed(game: Node, attacker: Node, victim: Node)

const MAX_EFFECTS = 12
const DIVE_CONTACT_REACH = 1.05

var _options: Dictionary = {"hit_effect": "ring", "effect_intensity": 0.65, "fun_stats": true}
var _games: Dictionary = {}
var _players: Dictionary = {}
var _balls: Dictionary = {}
var _effects: Array[WeakRef] = []
var _next_poll_msec = 0
var _accepted = 0
var _rejected = 0
var _spawned = 0
var _external_stats = false
var _impact_script: Script
var _last_ball_hits: Dictionary = {}
var _network_seen: Dictionary = {}
var _network_latest: Dictionary = {}
var _freeplay_seen: Dictionary = {}
var _event_counts: Dictionary = {"ball_struck": 0, "network_strike": 0, "freeplay_fx": 0, "duplicates": 0, "ignored": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10001
	var glyph_path = get_script().resource_path.get_base_dir().path_join("impact_glyph.gd")
	if FileAccess.file_exists(glyph_path):
		_impact_script = load(glyph_path)
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)

func configure(options: Dictionary) -> void:
	for key in ["hit_effect", "effect_intensity", "fun_stats", "spike_showcase"]:
		if options.has(key):
			_options[key] = options[key]
	if not str(_options.hit_effect) in ["off", "ring", "star", "comic", "fire", "ice", "electric", "portal", "enchant"]:
		_options.hit_effect = "ring"
	_options.effect_intensity = clampf(float(_options.effect_intensity), 0.2, 1.0)
	if _options.hit_effect == "off":
		for reference in _effects:
			var effect = reference.get_ref()
			if is_instance_valid(effect):
				effect.queue_free()
	for id in _games:
		_update_results(_games[id])

func set_external_stats(enabled: bool) -> void:
	_external_stats = enabled
	for state in _games.values():
		var row = state.row.get_ref() if state.row is WeakRef else null
		if is_instance_valid(row):
			row.visible = not enabled and bool(_options.fun_stats)

func _script_is(node: Node, path: String) -> bool:
	var script = node.get_script()
	return script != null and script.resource_path in [path + ".gd", path + ".gdc"]

func _find_game(node: Node) -> Node:
	var current = node
	for i in 16:
		if current == null:
			return null
		if _script_is(current, GAME_SCRIPT):
			return current
		current = current.get_parent()
	return null

func _scan(node: Node) -> void:
	_bind(node)
	for child in node.get_children():
		_scan(child)

func _on_node_added(node: Node) -> void:
	call_deferred("_bind_reference", weakref(node))

func _bind_reference(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node): _bind(node)

func _bind(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var id = node.get_instance_id()
	if _script_is(node, "res://game/net/net"):
		_bind_network(node)
	elif _script_is(node, GAME_SCRIPT):
		if not _games.has(id):
			_games[id] = {"reference": weakref(node), "count": 0, "generation": int(node.get("_match_gen")), "over": bool(node.get("_match_over")), "cooldowns": {}, "row": null, "label": null}
	elif _script_is(node, BALL_SCRIPT) and node.has_signal("struck"):
		if not _balls.has(id):
			_balls[id] = weakref(node)
			node.connect("struck", _on_struck.bind(weakref(node)))
	elif _script_is(node, PLAYER_SCRIPT) and node.has_signal("knock_started"):
		if not _players.has(id):
			_players[id] = weakref(node)
			node.connect("knock_started", _on_knock_started.bind(weakref(node)))

func _bind_network(net: Node) -> void:
	if net.has_signal("event_received") and not net.is_connected("event_received", _on_network_event):
		net.connect("event_received", _on_network_event)
	if net.has_signal("freeplay_fx") and not net.is_connected("freeplay_fx", _on_freeplay_fx):
		net.connect("freeplay_fx", _on_freeplay_fx)
	if net.has_signal("session_ended") and not net.is_connected("session_ended", _on_session_ended):
		net.connect("session_ended", _on_session_ended)

func _on_session_ended(_reason: String) -> void:
	_last_ball_hits.clear()
	_network_seen.clear()
	_network_latest.clear()
	_freeplay_seen.clear()

func _effect_game_active(game: Node) -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not game.is_inside_tree():
		return false
	if game is Node3D and not game.is_visible_in_tree():
		return false
	if bool(game.get("embedded")) and not bool(game.get("embedded_active")):
		return false
	return int(game.get("_phase")) != 7

func _sync_hit_generation(game: Node) -> void:
	if not _games.has(game.get_instance_id()):
		return
	var state: Dictionary = _games[game.get_instance_id()]
	var generation = int(game.get("_match_gen"))
	if generation == int(state.generation):
		return
	state.generation = generation
	state.count = 0
	state.cooldowns.clear()
	_last_ball_hits.clear()
	_network_seen.clear()
	_network_latest.clear()
	_freeplay_seen.clear()

func _on_struck(pos: Vector3, power: float, kind: int, reference: WeakRef) -> void:
	_event_counts.ball_struck += 1
	var ball = reference.get_ref()
	if not is_instance_valid(ball) or not ball.is_inside_tree():
		return
	var game = _find_game(ball)
	if game != null and not _effect_game_active(game):
		_event_counts.ignored += 1
		return
	if game != null:
		_sync_hit_generation(game)
	var played = _spawn_impact(ball.get_parent(), pos, power, kind)
	_last_ball_hits[ball.get_instance_id()] = {"when": Time.get_ticks_msec(), "kind": kind, "seq": int(ball.get("strike_seq")), "pos": pos, "played": played, "source": ball.get("strike_source")}

func _read_network_position(value: Variant) -> Vector3:
	if value is Vector3:
		return value if value.is_finite() else Vector3.INF
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array:
		if value.size() == 3:
			for component in value:
				if not (component is int or component is float) or not is_finite(float(component)):
					return Vector3.INF
			var pos = Vector3(float(value[0]), float(value[1]), float(value[2]))
			return pos if pos.length_squared() < 100000000.0 else Vector3.INF
	return Vector3.INF

func _on_network_event(event: String, args: Dictionary) -> void:
	if event != "strike":
		return
	_event_counts.network_strike += 1
	var pos = _read_network_position(args.get("p"))
	var kind = int(args.get("k", 0))
	var power = float(args.get("w", 0.0))
	var seq_value = args.get("n", -1)
	if not pos.is_finite() or kind < 1 or kind > 6 or not is_finite(power) or not (seq_value is int or seq_value is float) or not is_finite(float(seq_value)) or float(seq_value) < 0.0:
		_event_counts.ignored += 1
		return
	for state in _games.values():
		var game = state.reference.get_ref()
		if not _effect_game_active(game) or int(game.get("_net_role")) != 2 or bool(game.get("_match_over")):
			continue
		_sync_hit_generation(game)
		var generation = int(game.get("_match_gen"))
		if args.has("g") and int(args.g) != generation:
			_event_counts.ignored += 1
			continue
		var key = "%d:%d:%d" % [game.get_instance_id(), generation, int(seq_value)]
		var match_key = "%d:%d" % [game.get_instance_id(), generation]
		if _network_seen.has(key) or int(seq_value) <= int(_network_latest.get(match_key, -1)):
			_event_counts.duplicates += 1
			continue
		_network_seen[key] = Time.get_ticks_msec()
		_network_latest[match_key] = int(seq_value)
		var ball = game.get("ball")
		if not is_instance_valid(ball):
			continue
		var recent: Dictionary = _last_ball_hits.get(ball.get_instance_id(), {})
		var local = game.get("player")
		var ids: Dictionary = game.get("_net_ids")
		var own = is_instance_valid(local) and int(args.get("id", -1)) == int(ids.get(local, -2))
		# The game predicts local strikes, then suppresses their server echo using
		# _pred_strike_mutes. Observe that decision without consuming its counter.
		var recent_played = not recent.is_empty() and bool(recent.get("played", false)) and Time.get_ticks_msec() - int(recent.get("when", 0)) < 1500
		var recent_source = recent.get("source")
		if recent_played and is_instance_valid(recent_source) and not bool(recent_source.get("net_puppet")):
			# Couch players have separate network IDs; their own prediction echoes
			# need the same treatment as the primary player's echo.
			own = own or int(args.get("id", -1)) == int(ids.get(recent_source, -2))
		var same_contact = recent_played and int(recent.kind) == kind and (recent.pos as Vector3).distance_to(pos) < 0.75 and Time.get_ticks_msec() - int(recent.when) < 350
		if own and recent_played and (int(game.get("_pred_strike_mutes")) > 0 or same_contact):
			_event_counts.duplicates += 1
			continue
		_spawn_impact(ball.get_parent(), pos, power, kind)
	_trim_event_history()

func _on_freeplay_fx(peer_id: int, kind: int, pos: Vector3, power: float, _velocity: Vector3) -> void:
	_event_counts.freeplay_fx += 1
	if not pos.is_finite() or not is_finite(power) or kind < 1 or kind > 6:
		_event_counts.ignored += 1
		return
	for state in _games.values():
		var game = state.reference.get_ref()
		if not _effect_game_active(game) or not bool(game.get("embedded")):
			continue
		var key = "%d:%d:%d" % [game.get_instance_id(), peer_id, kind]
		var recent: Dictionary = _freeplay_seen.get(key, {})
		var now = Time.get_ticks_msec()
		if not recent.is_empty() and now - int(recent.when) < 80 and (recent.pos as Vector3).distance_to(pos) < 0.05:
			_event_counts.duplicates += 1
			continue
		_freeplay_seen[key] = {"when": now, "pos": pos}
		_spawn_impact(game, pos, power, kind)
	_trim_event_history()

func _trim_event_history() -> void:
	# Bounded history: enough to cover retransmits, without a growing match log.
	if _network_seen.size() > 256:
		var cutoff = Time.get_ticks_msec() - 10000
		for key in _network_seen.keys():
			if int(_network_seen[key]) < cutoff:
				_network_seen.erase(key)
		if _network_seen.size() > 512:
			_network_seen.clear()
			_network_latest.clear()
	if _freeplay_seen.size() > 128:
		_freeplay_seen.clear()

func _spawn_impact(parent: Node, pos: Vector3, power: float, kind: int) -> bool:
	if _options.hit_effect == "off" or DisplayServer.get_name() == "headless" or _impact_script == null:
		return false
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return false
	_prune_effects()
	if _effects.size() >= MAX_EFFECTS:
		return false
	var effect = _impact_script.new()
	effect.style = str(_options.hit_effect)
	effect.spike = kind == 3 and bool(_options.get("spike_showcase", true))
	effect.strength = float(_options.effect_intensity) * clampf(0.7 + power * 0.3, 0.7, 1.0)
	# Keep the selected theme's palette consistent with its paired ball trail.
	effect.tint = Color("79baff")
	parent.add_child(effect)
	effect.global_position = pos
	_effects.append(weakref(effect))
	_spawned += 1
	return true

func _on_knock_started(_pos: Vector3, strength: float, reference: WeakRef) -> void:
	if not bool(_options.fun_stats):
		return
	var victim = reference.get_ref()
	if not is_instance_valid(victim):
		return
	var game = _find_game(victim)
	if game == null or not _games.has(game.get_instance_id()):
		return
	# Remote clients do not receive the originating collision event/impulse.
	# Never turn an absence of that data into a misleading zero or guessed count.
	if int(game.get("_net_role")) == 2 or bool(game.get("_match_over")) or int(game.get("_phase")) == 7:
		return
	if victim.call("diving") or victim.call("knocked"):
		return
	var candidates: Array = []
	for body in game.get("_all_players"):
		if not is_instance_valid(body) or body == victim:
			continue
		if int(body.get("team_side")) != int(victim.get("team_side")):
			continue
		if signf(body.global_position.z) * signf(victim.global_position.z) < 0.0:
			continue
		if body.global_position.distance_to(victim.global_position) > DIVE_CONTACT_REACH:
			continue
		if body.has_method("dive_strikes") and body.call("dive_strikes") and not body.call("knocked"):
			candidates.append(body)
	if candidates.size() != 1:
		_rejected += 1
		return
	var local = candidates[0]
	var delta_pos: Vector3 = victim.global_position - local.global_position
	delta_pos.y = 0.0
	if delta_pos.length() < 0.01:
		_rejected += 1
		return
	var momentum: Vector3 = local.velocity
	momentum.y = 0.0
	# Check the impulse produced by the game's actual single-diver collision,
	# after knock_started has returned and the game assigned that velocity.
	var expected = momentum * 0.8 + delta_pos.normalized() * 2.0 + Vector3.UP * 2.0
	if absf(strength - clampf(expected.length() / 6.0, 0.35, 1.0)) > 0.01:
		_rejected += 1
		return
	call_deferred("_confirm_topple", reference, weakref(local), weakref(game), expected, int(game.get("_match_gen")))

func _confirm_topple(victim_ref: WeakRef, local_ref: WeakRef, game_ref: WeakRef, expected: Vector3, generation: int) -> void:
	var victim = victim_ref.get_ref()
	var local = local_ref.get_ref()
	var game = game_ref.get_ref()
	if not bool(_options.fun_stats) or not is_instance_valid(victim) or not is_instance_valid(local) or not is_instance_valid(game):
		return
	if not _games.has(game.get_instance_id()) or generation != int(game.get("_match_gen")):
		return
	if not victim.call("knocked") or bool(game.get("_match_over")):
		_rejected += 1
		return
	var actual: Vector3 = victim.velocity
	if Vector2(actual.x, actual.z).distance_to(Vector2(expected.x, expected.z)) > 0.05 or absf(actual.y - expected.y) > 0.4:
		_rejected += 1
		return
	var state: Dictionary = _games[game.get_instance_id()]
	var now = Time.get_ticks_msec()
	var victim_id = victim.get_instance_id()
	if now - int(state.cooldowns.get(victim_id, -1000)) < 500:
		return
	state.cooldowns[victim_id] = now
	if local == game.get("player"):
		state.count += 1
	_accepted += 1
	topple_observed.emit(game, local, victim)
	_update_results(state)

func _update_results(state: Dictionary) -> void:
	if _external_stats:
		return
	var game = state.reference.get_ref()
	if not is_instance_valid(game):
		return
	var hud = game.get("hud")
	if not is_instance_valid(hud):
		return
	# StatsPanel is the legacy in-play board; PostStats is the real results UI.
	var panel = hud.get_node_or_null("PostStats")
	if not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var row = state.row.get_ref() if state.row is WeakRef else null
	if not is_instance_valid(row):
		var inner = panel.get_node_or_null("Box/Margin/Inner")
		if not inner is VBoxContainer:
			inner = panel.find_child("Inner", true, false)
		if not inner is VBoxContainer:
			return
		row = PanelContainer.new()
		row.name = "JVFunStats"
		row.set_meta("jv_mod_ui", true)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var style = StyleBoxFlat.new()
		style.bg_color = Color("fff2bd")
		style.set_corner_radius_all(12)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		row.add_theme_stylebox_override("panel", style)
		var label = Label.new()
		label.name = "ToppleCount"
		label.add_theme_color_override("font_color", Color("293346"))
		label.add_theme_font_size_override("font_size", 18)
		var font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC"])
		font.font_weight = 700
		label.add_theme_font_override("font", font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = "趣味統計，僅計本機主要玩家。依同隊魚躍、實際倒地事件與碰撞推力比對；來源不明不計。不是右鍵按下次數，也不是官方戰績。"
		row.add_child(label)
		inner.add_child(row)
		var buttons = inner.get_node_or_null("Buttons")
		if buttons != null:
			inner.move_child(row, buttons.get_index())
		state.row = weakref(row)
		state.label = weakref(label)
	row.visible = bool(_options.fun_stats)
	var label = state.label.get_ref() if state.label is WeakRef else null
	if is_instance_valid(label):
		label.text = "右鍵撲倒隊友：—（加入方缺少碰撞來源資料）" if int(game.get("_net_role")) == 2 else "右鍵撲倒隊友：%d 次　｜　本機判定" % int(state.count)

func _prune_effects() -> void:
	var alive: Array[WeakRef] = []
	for reference in _effects:
		var node = reference.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive.append(reference)
	_effects = alive

func _process(_delta: float) -> void:
	# Results/pause screens may stop gameplay time; this is UI housekeeping.
	var now = Time.get_ticks_msec()
	if now < _next_poll_msec:
		return
	_next_poll_msec = now + 100
	for id in _games.keys():
		var state: Dictionary = _games[id]
		var game = state.reference.get_ref()
		if not is_instance_valid(game):
			_games.erase(id)
			continue
		var generation = int(game.get("_match_gen"))
		var over = bool(game.get("_match_over"))
		if generation != state.generation or (state.over and not over):
			state.count = 0
			state.cooldowns.clear()
			state.generation = generation
			_last_ball_hits.clear()
			_network_seen.clear()
		state.over = over
		_update_results(state)
	for collection in [_players, _balls]:
		for id in collection.keys():
			if not is_instance_valid(collection[id].get_ref()):
				collection.erase(id)
	for id in _last_ball_hits.keys():
		if not _balls.has(id):
			_last_ball_hits.erase(id)
	_prune_effects()

func get_diagnostics() -> Dictionary:
	var counts: Array = []
	for state in _games.values():
		counts.append({"count": state.count, "generation": state.generation, "results_row": state.row is WeakRef and is_instance_valid(state.row.get_ref())})
	return {"games": _games.size(), "bound_players": _players.size(), "bound_balls": _balls.size(), "accepted_topples": _accepted, "rejected_candidates": _rejected, "active_effects": _effects.size(), "spawned_effects": _spawned, "event_sources": _event_counts.duplicate(), "external_stats": _external_stats, "states": counts}
