extends Node
## Traditional Chinese presentation and optional room-synchronized fun stats.

var _messages: Dictionary = {}
var _normalized: Dictionary = {}
var _cache: Dictionary = {}
var _templates: Array = []
var _fonts: Dictionary = {}
var _font_nodes: Dictionary = {}
var _seen: Dictionary = {}
var _nodes: Array[WeakRef] = []
var _hot_nodes: Array[WeakRef] = []
var _states: Dictionary = {}
var _chinese: Font
var _chinese_bold: Font
var _translation: Translation
var _format = RegEx.new()
var _elapsed := 0.0
var _base: String
var _options: Dictionary = {"font_weight": "bold", "font_scale": 1.0, "high_contrast": true, "hit_effect": "ring", "effect_intensity": 0.65, "fun_stats": true}
var _settings_panel: Node
var _extras: Node
var _topple_stats: Node
var _effect_preview: Node
var _style_revision := 0
var _applying_style := false
var _visits := 0
var _translations := 0
var _process_calls := 0
var _refresh_calls := 0
var _process_usec := 0
var _last_process_usec := 0
const STATIC_INTERVAL := 0.2
const SCORE_HEADERS = {"player": "玩家", "pts": "得分", "spk": "扣球", "blk": "攔網", "rec": "接球", "set": "舉球", "ast": "助攻", "ace": "發球", "dig": "救球", "net": "連線"}

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10000
	_base = get_script().resource_path.get_base_dir()
	var guide = _base.path_join("guide_zhTW.pck")
	if FileAccess.file_exists(guide):
		if not ProjectSettings.load_resource_pack(guide):
			push_warning("[JV zh-TW] Could not load translated guide data")
	var data = JSON.parse_string(FileAccess.get_file_as_string(_base.path_join("translations.json")))
	if not data is Dictionary:
		push_error("[JV zh-TW] Cannot read translations.json")
		set_process(false)
		return
	_messages = data
	_format.compile("%[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdf]")
	_translation = Translation.new()
	_translation.locale = "zh_TW"
	for source: String in _messages:
		var target: String = _messages[source]
		_translation.add_message(source, target)
		_normalized[source.strip_edges().to_lower()] = target
		var matches = _format.search_all(source)
		if not matches.is_empty() and source.replace("%s", "").strip_edges().length() > 3:
			var pattern := "^"
			var cursor := 0
			for item in matches:
				pattern += _escape_regex(source.substr(cursor, item.get_start() - cursor))
				var kind = item.get_string().right(1)
				pattern += "(-?[0-9]+)" if kind == "d" else ("(-?[0-9]+(?:\\.[0-9]+)?)" if kind == "f" else "(.+?)")
				cursor = item.get_end()
			pattern += _escape_regex(source.substr(cursor)) + "$"
			var regex = RegEx.new()
			if regex.compile("(?i)" + pattern) == OK and _format.search_all(target).size() == matches.size():
				_templates.append({"regex": regex, "target": target, "length": source.length(), "source": source})
	_templates.sort_custom(func(a, b): return a.length > b.length)
	TranslationServer.add_translation(_translation)
	TranslationServer.set_locale("zh_TW")
	_chinese = _load_chinese_font()
	_chinese_bold = _load_chinese_font(true)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_refresh")
	print("[JV zh-TW] v1.1.1 loaded ", _messages.size(), " entries")

func _ready() -> void:
	TranslationServer.set_locale("zh_TW")
	_start_modules()
	_refresh()

func _start_modules() -> void:
	var extras_path = _base.path_join("match_extras.gd")
	if FileAccess.file_exists(extras_path):
		var script = load(extras_path)
		if script != null and script.can_instantiate():
			_extras = script.new()
			_extras.name = "MatchExtras"
			add_child(_extras)
	var stats_path = _base.path_join("topple_stats.gd")
	if FileAccess.file_exists(stats_path) and is_instance_valid(_extras):
		var script = load(stats_path)
		if script != null and script.can_instantiate():
			_topple_stats = script.new()
			_topple_stats.name = "ToppleStats"
			add_child(_topple_stats)
			_topple_stats.setup(_extras)
	var panel_path = _base.path_join("settings_panel.gd")
	if FileAccess.file_exists(panel_path):
		var script = load(panel_path)
		if script != null and script.can_instantiate():
			_settings_panel = script.new()
			_settings_panel.name = "ModSettings"
			_settings_panel.settings_changed.connect(_on_mod_settings_changed)
			_settings_panel.effect_preview_requested.connect(_on_effect_preview_requested)
			add_child(_settings_panel)
			_on_mod_settings_changed(_settings_panel.get_options())
	if is_instance_valid(_extras) and _extras.has_method("configure"):
		_configure_extras()
	if is_instance_valid(_topple_stats): _topple_stats.configure(_options)

func _configure_extras() -> void:
	var options = _options.duplicate()
	# Visibility is personal; a host continues collecting counts for the room.
	if is_instance_valid(_topple_stats): options.fun_stats = true
	_extras.configure(options)

func _on_effect_preview_requested() -> void:
	if str(_options.hit_effect) == "off": return
	if is_instance_valid(_effect_preview): _effect_preview.queue_free()
	var script = load(_base.path_join("effect_preview.gd"))
	if script == null or not script.can_instantiate(): return
	_effect_preview = script.new()
	_effect_preview.options = _options.duplicate()
	if is_instance_valid(_settings_panel): _effect_preview.panel_theme = _settings_panel._panel_theme
	add_child(_effect_preview)

func _on_mod_settings_changed(options: Dictionary) -> void:
	_options.merge(options, true)
	_options.font_scale = clampf(float(_options.font_scale), 1.0, 1.2)
	_style_revision += 1
	_font_nodes.clear()
	if is_instance_valid(_extras) and _extras.has_method("configure"):
		_configure_extras()
	if is_instance_valid(_topple_stats): _topple_stats.configure(_options)
	call_deferred("_refresh")

func _load_chinese_font(bold: bool = false) -> Font:
	var windows = OS.get_environment("WINDIR")
	if windows.is_empty():
		windows = "C:/Windows"
	var files = ["msjhbd.ttc", "msjh.ttc", "mingliu.ttc"] if bold else ["msjh.ttc", "msjhbd.ttc", "mingliu.ttc"]
	for file in files:
		var path = windows.path_join("Fonts").path_join(file)
		if FileAccess.file_exists(path):
			var font = FontFile.new()
			font.data = FileAccess.get_file_as_bytes(path)
			return font
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Microsoft YaHei"])
	font.font_weight = 700 if bold else 400
	return font

func _escape_regex(value: String) -> String:
	var result := ""
	for c in value:
		if c in ["\\", ".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]:
			result += "\\"
		result += c
	return result

func _translate(value: String) -> String:
	if value.is_empty():
		return value
	if _messages.has(value):
		return _messages[value]
	if _cache.has(value):
		return _cache[value]
	var key = value.strip_edges().to_lower()
	if _normalized.has(key):
		return _normalized[key]
	for item in _templates:
		var found = item.regex.search(value)
		if found == null:
			continue
		var target: String = item.target
		var pieces := ""
		var cursor := 0
		var index := 1
		for placeholder in _format.search_all(target):
			var argument = found.get_string(index)
			if item.source in ["outfit: %s", "ball: %s", "stage: %s"]:
				if item.source == "outfit: %s" and argument.to_lower() == "gym":
					argument = "運動服"
				elif _normalized.has(argument.to_lower()):
					argument = _normalized[argument.to_lower()]
			pieces += target.substr(cursor, placeholder.get_start() - cursor) + argument
			cursor = placeholder.get_end()
			index += 1
		pieces += target.substr(cursor)
		if _cache.size() > 2048:
			_cache.clear()
		_cache[value] = pieces
		return pieces
	if _cache.size() > 2048:
		_cache.clear()
	_cache[value] = value
	return value

func _patch_font(font: Font) -> void:
	if font == null or font == _chinese or _fonts.has(font.get_instance_id()):
		return
	_fonts[font.get_instance_id()] = true
	var fallbacks = font.fallbacks
	if not _chinese in fallbacks:
		fallbacks.append(_chinese)
		font.fallbacks = fallbacks

func _is_identity(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	return _get_state(node).identity

func _detect_identity(node: Node, paths: String) -> bool:
	# Never rewrite user text boxes, player-name labels, or the chat display.
	if node is LineEdit or node is TextEdit:
		return true
	# Nameplates build anonymous Labels below CachedPlate at runtime.
	if "/nameplate.gd" in paths:
		return true
	# ControlHints names its static action captions "Name" and has a "Chat"
	# action row. These are game labels, not player names or chat messages.
	if node is Label and str(node.name).to_lower() == "name" and "/control_hints.gd" in paths:
		return false
	var current = node
	for depth in 5:
		if current == null:
			break
		var id = str(current.name).to_lower().replace("_", "")
		if id in ["chat", "chatlog", "chatmessages", "chatinput", "playername", "profilename", "friendname", "servername", "nickname", "wornname"]:
			return true
		if depth == 0 and node is Label and (id.ends_with("namelabel") or id == "name"):
			return true
		current = current.get_parent()
	if "/stat_row.gd" in paths:
		current = node.get_parent()
		for depth in 12:
			if current == null:
				break
			var script = current.get_script()
			if script != null and script.resource_path in ["res://game/ui/stat_row.gd", "res://game/ui/stat_row.gdc"]:
				return current.get("name_label") == node
			current = current.get_parent()
	return false

func _score_header_info(node: Node, paths: String) -> Dictionary:
	var info = {"score_header": false, "results_header": false}
	if not node is Label or not "/score_table.gd" in paths:
		return info
	var current = node.get_parent()
	for depth in 12:
		if current == null:
			break
		var script = current.get_script()
		if script != null and script.resource_path in ["res://game/ui/score_table.gd", "res://game/ui/score_table.gdc"]:
			var heads = current.get("_heads")
			info.score_header = node.get_parent() is HBoxContainer and heads is Array and heads.has(node.get_parent())
			info.results_header = info.score_header and node.is_inside_tree() and "/PostStats/" in str(node.get_path())
			break
		current = current.get_parent()
	return info

func _module_ui(node: Node) -> bool:
	var current = node
	for depth in 16:
		if current == null:
			break
		if current.has_meta("jv_mod_ui"):
			return true
		current = current.get_parent()
	return false

func _get_state(node: Node) -> Dictionary:
	var id = node.get_instance_id()
	var parent = node.get_parent()
	var parent_id = parent.get_instance_id() if parent != null else 0
	if _states.has(id):
		var cached: Dictionary = _states[id]
		if cached.parent == parent_id and cached.node_name == str(node.name):
			return cached
	var paths := ""
	var current = node
	for depth in 12:
		if current == null:
			break
		var script = current.get_script()
		if script != null:
			paths += script.resource_path.to_lower() + "\n"
		current = current.get_parent()
	var state: Dictionary = {"parent": parent_id, "node_name": str(node.name), "paths": paths,
		"identity": _detect_identity(node, paths), "module_ui": _module_ui(node),
		"last_text": null, "last_tooltip": null, "style_revision": -1, "style": {}}
	state.merge(_score_header_info(node, paths))
	if _states.has(id):
		# Renaming/reparenting changes context, not the original size/color.
		state.style = _states[id].style
	_states[id] = state
	return state

func _invalidate_node(id: int) -> void:
	if _states.has(id):
		_states[id].parent = -1
	_font_nodes.erase(id)

func _on_theme_changed(id: int) -> void:
	if not _applying_style:
		_font_nodes.erase(id)

func _on_node_added(node: Node) -> void:
	_track(node)
	# Added nodes may receive their name, text, and parents later in the frame.
	if _seen.has(node.get_instance_id()):
		call_deferred("_localize_node", node)

func _track(node: Node) -> void:
	var id = node.get_instance_id()
	if _seen.has(id):
		return
	if not (node is Label or node is Button or node is RichTextLabel or node is LineEdit or node is TextEdit or node is Label3D or node is PopupMenu or node is TabBar or node is Window or (node is Control and not node.tooltip_text.is_empty())):
		return
	if _module_ui(node):
		return
	_seen[id] = true
	_nodes.append(weakref(node))
	var state = _get_state(node)
	# These captions are regenerated in the game's frame loop. Keep them late
	# and immediate; ordinary menus only need the slower maintenance pass.
	if not state.identity and (node is Label3D or "/control_hints.gd" in state.paths or "/hud.gd" in state.paths or "/stats_drawer.gd" in state.paths or "/score_table.gd" in state.paths or "/lobby/rules_strip.gd" in state.paths):
		_hot_nodes.append(weakref(node))
	node.tree_entered.connect(_invalidate_node.bind(id))
	node.renamed.connect(_invalidate_node.bind(id))
	if node is Control:
		node.theme_changed.connect(_on_theme_changed.bind(id))

func _context_text(node: Node, text: String) -> String:
	var key = text.strip_edges().to_lower()
	if SCORE_HEADERS.has(key) and _get_state(node).get("score_header", false):
		return SCORE_HEADERS[key]
	if key in ["block", "blocks", "sets", "error", "play", "setting", "gym"]:
		var paths: String = _get_state(node).paths
		if key == "block" and "/player_menu.gd" in paths:
			return "封鎖"
		if "/hud.gd" in paths or "/stats_drawer.gd" in paths:
			if key == "sets":
				return "舉球"
			if key == "error":
				return "失誤"
		if key == "play" and "/replay/" in paths:
			return "播放"
		if key == "gym" and ("/locker.gd" in paths or "/shop.gd" in paths):
			return "運動服"
		if key == "setting" and (str(node.name).to_lower().contains("header") or str(node.name).to_lower().contains("column")):
			return "設定"
	return _translate(text)

func _localize_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not (node is Control or node is Label3D or node is Window):
		return
	_visits += 1
	var state = _get_state(node)
	if state.module_ui:
		return
	var identity: bool = state.identity
	if identity:
		node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var text_value: Variant = null
	if node is Label or node is Button or node is RichTextLabel or node is Label3D:
		text_value = node.text
	elif node is LineEdit or node is TextEdit:
		text_value = node.placeholder_text
	elif node is Window:
		text_value = node.title
	var tooltip: String = node.tooltip_text if node is Control else ""
	var changed: bool = state.last_text != text_value or state.last_tooltip != tooltip
	if node is Control and not tooltip.is_empty() and state.last_tooltip != tooltip:
		node.tooltip_text = _translate(tooltip)
		state.last_tooltip = node.tooltip_text
	else:
		state.last_tooltip = tooltip
	if node is LineEdit or node is TextEdit:
		if changed:
			node.placeholder_text = _translate(node.placeholder_text)
		state.last_text = node.placeholder_text
	elif not identity and (node is Label or node is Button or node is RichTextLabel or node is Label3D):
		if changed:
			var text: String = node.text
			var translated = _context_text(node, text)
			_translations += 1
			if text != translated:
				node.text = translated
		state.last_text = node.text
	else:
		state.last_text = text_value
	if not identity and (node is Control or node is Label3D):
		var chinese_changed = false
		if changed and (node is Label or node is Button or node is RichTextLabel or node is Label3D):
			chinese_changed = state.get("style_chinese", null) != _has_chinese(node.text)
		if state.style_revision != _style_revision or not _font_nodes.has(node.get_instance_id()) or chinese_changed:
			_style_node(node, state)
	if not identity and node is OptionButton:
		for i in node.item_count:
			var text = node.get_item_text(i)
			var translated = _translate(text)
			if text != translated:
				node.set_item_text(i, translated)
	elif not identity and node is PopupMenu:
		for i in node.item_count:
			var text = node.get_item_text(i)
			var translated = _translate(text)
			if text != translated:
				node.set_item_text(i, translated)
	elif not identity and node is TabBar:
		for i in node.tab_count:
			var text = node.get_tab_title(i)
			var translated = _translate(text)
			if text != translated:
				node.set_tab_title(i, translated)
	if node is Window:
		if changed:
			node.title = _translate(node.title)
		state.last_text = node.title

func _has_chinese(value: String) -> bool:
	for character in value:
		var code = character.unicode_at(0)
		if code >= 0x3400 and code <= 0x9fff:
			return true
	return false

func _style_node(node: Node, state: Dictionary) -> void:
	_applying_style = true
	var baseline: Dictionary = state.style
	if node is Control:
		if baseline.is_empty():
			baseline["size"] = node.get_theme_font_size("normal_font_size" if node is RichTextLabel else "font_size")
			baseline["color"] = node.get_theme_color("default_color" if node is RichTextLabel else "font_color")
			baseline["size_override"] = node.has_theme_font_size_override("normal_font_size" if node is RichTextLabel else "font_size")
			baseline["color_override"] = node.has_theme_color_override("default_color" if node is RichTextLabel else "font_color")
			baseline["fonts"] = {}
			for name in ["font", "normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
				baseline.fonts[name] = {"font": node.get_theme_font(name), "override": node.has_theme_font_override(name)}
		for name in baseline.fonts:
			_patch_font(baseline.fonts[name].font)
		if node is Label or node is Button or node is RichTextLabel:
			var chinese = _has_chinese(node.text)
			var title = node is Button or int(baseline.size) >= 24 or "title" in str(node.name).to_lower() or "header" in str(node.name).to_lower()
			for name in baseline.fonts:
				if chinese:
					var use_bold = str(_options.font_weight) == "bold" and (title or name in ["bold_font", "bold_italics_font"])
					node.add_theme_font_override(name, _chinese_bold if use_bold else _chinese)
				elif baseline.fonts[name].override:
					node.add_theme_font_override(name, baseline.fonts[name].font)
				else:
					node.remove_theme_font_override(name)
			var size_name = "normal_font_size" if node is RichTextLabel else "font_size"
			var scale = float(_options.font_scale)
			if is_equal_approx(scale, 1.0) and not baseline.size_override:
				node.remove_theme_font_size_override(size_name)
			else:
				node.add_theme_font_size_override(size_name, maxi(1, roundi(float(baseline.size) * scale)))
			var color_name = "default_color" if node is RichTextLabel else "font_color"
			var original: Color = baseline.color
			var color = original
			var gray = maxf(original.r, maxf(original.g, original.b)) - minf(original.r, minf(original.g, original.b)) < 0.14
			var light = (original.r + original.g + original.b) / 3.0
			# Preserve colorful and white HUD labels. Darken only pale gray captions.
			if bool(_options.high_contrast) and chinese and gray and light > 0.4 and light < 0.88 and original.a >= 0.5:
				color = Color(original.r * 0.72, original.g * 0.72, original.b * 0.72, original.a)
			if color != original or baseline.color_override:
				node.add_theme_color_override(color_name, color)
			else:
				node.remove_theme_color_override(color_name)
			if state.get("score_header", false):
				# Keep two-character stat headings inside the game's narrow columns.
				node.add_theme_font_size_override("font_size", 14)
				if state.get("results_header", false):
					node.add_theme_color_override("font_color", Color("f5f8ff"))
					node.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.12, 0.85))
					node.add_theme_constant_override("outline_size", 2)
	elif node is Label3D:
		if baseline.is_empty():
			baseline["font"] = node.font
			baseline["size"] = node.font_size
		_patch_font(baseline.font)
		if _has_chinese(node.text):
			node.font = _chinese_bold if str(_options.font_weight) == "bold" else _chinese
		else:
			node.font = baseline.font
		node.font_size = maxi(1, roundi(float(baseline.size) * float(_options.font_scale)))
	state.style_revision = _style_revision
	if node is Label or node is Button or node is RichTextLabel or node is Label3D:
		state.style_chinese = _has_chinese(node.text)
	_font_nodes[node.get_instance_id()] = true
	_applying_style = false

func _scan(node: Node) -> void:
	if _module_ui(node):
		return
	_track(node)
	if _seen.has(node.get_instance_id()):
		_localize_node(node)
	for child in node.get_children():
		_scan(child)

func _refresh() -> void:
	if _messages.is_empty() or _chinese == null:
		return
	_refresh_calls += 1
	_patch_font(ThemeDB.fallback_font)
	if _nodes.is_empty():
		_scan(get_tree().root)
	else:
		var alive: Array[WeakRef] = []
		for reference in _nodes:
			var node = reference.get_ref()
			if is_instance_valid(node):
				alive.append(reference)
				_localize_node(node)
		_nodes = alive
		var live: Dictionary = {}
		for reference in _nodes:
			var node = reference.get_ref()
			if is_instance_valid(node):
				live[node.get_instance_id()] = true
		for id in _seen.keys():
			if not live.has(id):
				_seen.erase(id)
				_states.erase(id)
				_font_nodes.erase(id)
		var hot_alive: Array[WeakRef] = []
		for reference in _hot_nodes:
			if is_instance_valid(reference.get_ref()):
				hot_alive.append(reference)
		_hot_nodes = hot_alive

func _process(delta: float) -> void:
	var started = Time.get_ticks_usec()
	_process_calls += 1
	# The game may reset its locale while booting or changing settings.
	if TranslationServer.get_locale() != "zh_TW":
		TranslationServer.set_locale("zh_TW")
	_elapsed += delta
	if _elapsed >= STATIC_INTERVAL:
		_elapsed = fmod(_elapsed, STATIC_INTERVAL)
		_refresh()
	else:
		for reference in _hot_nodes:
			var node = reference.get_ref()
			if is_instance_valid(node):
				_localize_node(node)
	_last_process_usec = Time.get_ticks_usec() - started
	_process_usec += _last_process_usec

func get_diagnostics() -> Dictionary:
	return {"tracked_nodes": _nodes.size(), "hot_nodes": _hot_nodes.size(),
		"cached_node_states": _states.size(), "visits": _visits, "translations": _translations,
		"process_calls": _process_calls, "static_refreshes": _refresh_calls,
		"static_interval_seconds": STATIC_INTERVAL, "process_usec_total": _process_usec,
		"last_process_usec": _last_process_usec,
		"mean_process_usec": float(_process_usec) / maxi(1, _process_calls)}
