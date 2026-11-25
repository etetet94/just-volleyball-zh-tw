extends Node
## Original Traditional Chinese UI localization. No gameplay or networking hooks.

var _messages: Dictionary = {}
var _normalized: Dictionary = {}
var _cache: Dictionary = {}
var _templates: Array = []
var _fonts: Dictionary = {}
var _font_nodes: Dictionary = {}
var _seen: Dictionary = {}
var _nodes: Array[WeakRef] = []
var _chinese: Font
var _translation: Translation
var _format = RegEx.new()
var _elapsed := 0.0
var _base: String

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
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_refresh")
	print("[JV zh-TW] loaded ", _messages.size(), " entries; UI/text/font only")

func _ready() -> void:
	TranslationServer.set_locale("zh_TW")
	_refresh()

func _load_chinese_font() -> Font:
	var windows = OS.get_environment("WINDIR")
	if windows.is_empty():
		windows = "C:/Windows"
	for file in ["msjh.ttc", "msjhbd.ttc", "mingliu.ttc"]:
		var path = windows.path_join("Fonts").path_join(file)
		if FileAccess.file_exists(path):
			var font = FontFile.new()
			font.data = FileAccess.get_file_as_bytes(path)
			return font
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Microsoft YaHei"])
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
	# Never rewrite user text boxes, player-name labels, or the chat display.
	if node is LineEdit or node is TextEdit:
		return true
	# ControlHints names its static action captions "Name" and has a "Chat"
	# action row. These are game labels, not player names or chat messages.
	if node is Label and str(node.name).to_lower() == "name":
		var owner = node
		for depth in 10:
			if owner == null:
				break
			var script = owner.get_script()
			if script != null and script.resource_path in ["res://game/ui/control_hints.gd", "res://game/ui/control_hints.gdc"]:
				return false
			owner = owner.get_parent()
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
	return false

func _on_node_added(node: Node) -> void:
	if _is_identity(node):
		node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_track(node)
	call_deferred("_localize_node", node)

func _track(node: Node) -> void:
	var id = node.get_instance_id()
	if _seen.has(id):
		return
	if not (node is Label or node is Button or node is RichTextLabel or node is LineEdit or node is TextEdit or node is Label3D or node is PopupMenu or node is TabBar or node is Window or (node is Control and not node.tooltip_text.is_empty())):
		return
	_seen[id] = true
	_nodes.append(weakref(node))
	if node is Control:
		node.theme_changed.connect(func(): _font_nodes.erase(id))

func _context_text(node: Node, text: String) -> String:
	var key = text.strip_edges().to_lower()
	if key in ["block", "blocks", "sets", "error", "play", "setting", "gym"]:
		var current = node
		for depth in 9:
			if current == null:
				break
			var script = current.get_script()
			var path: String = script.resource_path.to_lower() if script != null else ""
			if key == "block" and "/player_menu.gd" in path:
				return "封鎖"
			if "/hud.gd" in path or "/stats_drawer.gd" in path:
				if key == "sets":
					return "舉球"
				if key == "error":
					return "失誤"
			if key == "play" and "/replay/" in path:
				return "播放"
			if key == "gym" and ("/locker.gd" in path or "/shop.gd" in path):
				return "運動服"
			if key == "setting" and (str(node.name).to_lower().contains("header") or str(node.name).to_lower().contains("column")):
				return "設定"
			current = current.get_parent()
	return _translate(text)

func _localize_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Control and not _font_nodes.has(node.get_instance_id()):
		_font_nodes[node.get_instance_id()] = true
		for name in ["font", "normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			_patch_font(node.get_theme_font(name))
	if node is Control:
		if not node.tooltip_text.is_empty():
			node.tooltip_text = _translate(node.tooltip_text)
	if node is Label3D:
		_patch_font(node.font)
	var identity = _is_identity(node)
	if identity and node is Node:
		node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if node is LineEdit or node is TextEdit:
		node.placeholder_text = _translate(node.placeholder_text)
	elif not identity and (node is Label or node is Button or node is RichTextLabel or node is Label3D):
		var text: String = node.text
		var translated = _context_text(node, text)
		if text != translated:
			node.text = translated
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
		node.title = _translate(node.title)

func _scan(node: Node) -> void:
	_track(node)
	_localize_node(node)
	for child in node.get_children():
		_scan(child)

func _refresh() -> void:
	if _messages.is_empty() or _chinese == null:
		return
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

func _process(delta: float) -> void:
	# The game may reset its locale while booting or changing settings.
	if TranslationServer.get_locale() != "zh_TW":
		TranslationServer.set_locale("zh_TW")
	_refresh()
