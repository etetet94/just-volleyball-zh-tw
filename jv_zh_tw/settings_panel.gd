extends CanvasLayer
## Local presentation preferences. Does not change the game's configuration.

signal settings_changed(options: Dictionary)
signal panel_visibility_changed(open: bool)
signal effect_preview_requested()
signal trail_preview_requested()

const CONFIG_PATH = "user://jv_zh_tw/preferences.cfg"
const EFFECT_KEYS = ["off", "ring", "star", "comic", "fire", "ice", "electric", "portal", "enchant"]
const EFFECT_LABELS = ["關閉", "光環衝擊", "星芒爆發", "漫畫撞擊", "火焰爆發", "冰雪碎晶", "雷電衝擊", "終界珍珠風格", "附魔符文"]
const DEFAULTS = {
	"font_weight": "bold",
	"font_scale": 1.0,
	"high_contrast": true,
	"hit_effect": "ring",
	"effect_intensity": 0.65,
	"trail_enabled": true,
	"trail_intensity": 0.65,
	"trail_lifetime": 0.45,
	"fun_stats": true,
}
const INPUT_ACTIONS = ["move_forward", "move_back", "move_left", "move_right", "aim_left", "aim_right", "aim_up", "aim_down", "jump", "contact", "set", "dive", "block", "serve", "strafe", "aim_recenter", "sprint"]

var _options: Dictionary = DEFAULTS.duplicate()
var _overlay: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _weight: OptionButton
var _scale: HSlider
var _scale_value: Label
var _contrast: CheckButton
var _effect: OptionButton
var _intensity: HSlider
var _intensity_value: Label
var _preview: Button
var _trail_style: Label
var _trail_enabled: CheckButton
var _trail_intensity: HSlider
var _trail_intensity_value: Label
var _trail_lifetime: HSlider
var _trail_lifetime_value: Label
var _fun: CheckButton
var _status: Label
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _font: Font
var _panel_theme: Theme
var _last_focus: WeakRef
var _game_pause: WeakRef
var _owns_game_pause := false
var _game_pause_tree_flag := false
var _gated_collectors: Array[Dictionary] = []

func _ready() -> void:
	name = "JVModSettings"
	set_meta("jv_mod_ui", true)
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10001
	_load_options()
	_build_ui()
	_refresh_controls()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()

func get_options() -> Dictionary:
	var options = _options.duplicate(true)
	options["trail_effect"] = str(_options.hit_effect) if bool(_options.trail_enabled) else "off"
	return options

func is_open() -> bool:
	return is_instance_valid(_overlay) and _overlay.visible

func set_option(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	var normalized = _normalize(key, value)
	if _options.get(key) == normalized:
		return
	_options[key] = normalized
	_save_options()
	_refresh_controls()
	settings_changed.emit(get_options())

func _normalize(key: String, value: Variant) -> Variant:
	match key:
		"font_weight":
			return str(value) if str(value) in ["normal", "bold"] else DEFAULTS[key]
		"font_scale":
			if value is float or value is int:
				var number = float(value)
				return roundf(clampf(number, 1.0, 1.2) * 20.0) / 20.0 if is_finite(number) else DEFAULTS[key]
			return DEFAULTS[key]
		"effect_intensity", "trail_intensity":
			if value is float or value is int:
				var number = float(value)
				return roundf(clampf(number, 0.2, 1.0) * 20.0) / 20.0 if is_finite(number) else DEFAULTS[key]
			return DEFAULTS[key]
		"hit_effect":
			return str(value) if str(value) in EFFECT_KEYS else DEFAULTS[key]
		"trail_lifetime":
			if value is float or value is int:
				var number = float(value)
				return roundf(clampf(number, 0.15, 0.9) * 20.0) / 20.0 if is_finite(number) else DEFAULTS[key]
			return DEFAULTS[key]
		"high_contrast", "fun_stats", "trail_enabled":
			return value if value is bool else DEFAULTS[key]
	return DEFAULTS[key]

func _load_options() -> void:
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for key in DEFAULTS:
		_options[key] = _normalize(key, config.get_value("presentation", key, DEFAULTS[key]))
	if not config.has_section_key("presentation", "trail_enabled") and config.get_value("presentation", "trail_effect", "") == "off":
		_options.trail_enabled = false

func _save_options() -> void:
	var directory = ProjectSettings.globalize_path("user://jv_zh_tw")
	var result = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK and result != ERR_ALREADY_EXISTS:
		_set_status("設定已套用；無法建立儲存資料夾。", true)
		return
	var config = ConfigFile.new()
	for key in DEFAULTS:
		config.set_value("presentation", key, _options[key])
	var temporary = CONFIG_PATH + ".tmp"
	if config.save(temporary) != OK:
		_set_status("設定已套用；無法寫入設定檔。", true)
		return
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(CONFIG_PATH))
	if error != OK:
		_set_status("設定已套用；儲存失敗，重開遊戲後可能還原。", true)
		return
	_set_status("已儲存・下次啟動會沿用", false)

func _set_status(value: String, failed: bool) -> void:
	if is_instance_valid(_status):
		_status.text = value
		_status.modulate = Color("ffad9b") if failed else Color("9fb0bf")

func _style(background: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _load_font() -> Font:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Microsoft YaHei", "sans-serif"])
	font.font_weight = 600
	return font

func _button(text: String) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	return button

func _label(text: String, size: int = 18, color: Color = Color("e8eff5")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _build_ui() -> void:
	_font = _load_font()
	_panel_theme = Theme.new()
	_panel_theme.default_font = _font
	_panel_theme.default_font_size = 18
	for kind in ["Button", "OptionButton"]:
		_panel_theme.set_stylebox("normal", kind, _style(Color("263544"), Color("405060"), 10))
		_panel_theme.set_stylebox("hover", kind, _style(Color("35485b"), Color("ffe06a"), 10))
		_panel_theme.set_stylebox("pressed", kind, _style(Color("495337"), Color("ffe06a"), 10))
		_panel_theme.set_stylebox("focus", kind, _style(Color(0, 0, 0, 0), Color("ffe06a"), 10))
		_panel_theme.set_color("font_color", kind, Color("edf3f8"))
		_panel_theme.set_color("font_hover_color", kind, Color.WHITE)
		_panel_theme.set_color("font_pressed_color", kind, Color("ffe06a"))
	_panel_theme.set_color("font_color", "CheckButton", Color("edf3f8"))
	_panel_theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	_panel_theme.set_stylebox("slider", "HSlider", _style(Color("324455"), Color("324455"), 4))
	_panel_theme.set_stylebox("grabber_area", "HSlider", _style(Color("f4cf48"), Color("f4cf48"), 4))
	_panel_theme.set_stylebox("grabber_area_highlight", "HSlider", _style(Color("ffe992"), Color("ffe992"), 4))

	_overlay = Control.new()
	_overlay.name = "ModSettingsOverlay"
	_overlay.set_meta("jv_mod_ui", true)
	_overlay.theme = _panel_theme
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay.hide()
	var shade = ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	_panel = PanelContainer.new()
	_panel.name = "SettingsCard"
	_panel.add_theme_stylebox_override("panel", _style(Color("17232f"), Color("556273"), 20))
	_overlay.add_child(_panel)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var header = HBoxContainer.new()
	content.add_child(header)
	var title = _label("繁中模組設定", 28, Color("ffe06a"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close = _button("關閉  Esc")
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func(): set_open(false))
	header.add_child(close)
	content.add_child(_label("介面更清楚，擊球更有感。", 16, Color("acbbc9")))
	var separator = HSeparator.new()
	content.add_child(separator)

	var scroll = ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 200
	content.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	rows.add_child(_label("文字與閱讀", 19, Color("ffe06a")))
	_weight = OptionButton.new()
	_weight.add_item("清晰粗體", 0)
	_weight.add_item("標準字重", 1)
	_weight.item_selected.connect(func(index): set_option("font_weight", "bold" if index == 0 else "normal"))
	_add_row(rows, "中文字重", _weight)
	var scale_box = HBoxContainer.new()
	_scale = HSlider.new()
	_scale.min_value = 1.0
	_scale.max_value = 1.2
	_scale.step = 0.05
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.custom_minimum_size.x = 140
	_scale.value_changed.connect(func(value): set_option("font_scale", value))
	scale_box.add_child(_scale)
	_scale_value = _label("100%", 17)
	_scale_value.custom_minimum_size.x = 54
	_scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_box.add_child(_scale_value)
	_add_row(rows, "中文介面大小", scale_box)
	_contrast = CheckButton.new()
	_contrast.text = "提高次要文字對比"
	_contrast.toggled.connect(func(value): set_option("high_contrast", value))
	rows.add_child(_contrast)
	rows.add_child(HSeparator.new())
	rows.add_child(_label("擊打與球跡", 19, Color("ffe06a")))
	_effect = OptionButton.new()
	for text in EFFECT_LABELS:
		_effect.add_item(text)
	_effect.item_selected.connect(func(index): set_option("hit_effect", EFFECT_KEYS[index]))
	_add_row(rows, "特效主題（擊打＋球跡）", _effect)
	var intensity_box = HBoxContainer.new()
	_intensity = HSlider.new()
	_intensity.min_value = 0.2
	_intensity.max_value = 1.0
	_intensity.step = 0.05
	_intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intensity.custom_minimum_size.x = 140
	_intensity.value_changed.connect(func(value): set_option("effect_intensity", value))
	intensity_box.add_child(_intensity)
	_intensity_value = _label("65%", 17)
	_intensity_value.custom_minimum_size.x = 54
	_intensity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intensity_box.add_child(_intensity_value)
	_add_row(rows, "特效強度", intensity_box)
	_preview = _button("預覽整組效果")
	_preview.tooltip_text = "以移動示範球預覽同一主題的擊打特效與球跡。"
	_preview.pressed.connect(func(): effect_preview_requested.emit())
	_add_row(rows, "效果預覽", _preview)
	rows.add_child(HSeparator.new())
	rows.add_child(_label("球的軌跡", 19, Color("ffe06a")))
	_trail_enabled = CheckButton.new()
	_trail_enabled.text = "開啟搭配的球跡"
	_trail_enabled.toggled.connect(func(value): set_option("trail_enabled", value))
	rows.add_child(_trail_enabled)
	_trail_style = _label("光環衝擊", 17, Color("afbdcd"))
	_add_row(rows, "目前搭配", _trail_style)
	var trail_intensity_box = HBoxContainer.new()
	_trail_intensity = HSlider.new()
	_trail_intensity.min_value = 0.2
	_trail_intensity.max_value = 1.0
	_trail_intensity.step = 0.05
	_trail_intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trail_intensity.custom_minimum_size.x = 140
	_trail_intensity.value_changed.connect(func(value): set_option("trail_intensity", value))
	trail_intensity_box.add_child(_trail_intensity)
	_trail_intensity_value = _label("65%", 17)
	_trail_intensity_value.custom_minimum_size.x = 54
	_trail_intensity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trail_intensity_box.add_child(_trail_intensity_value)
	_add_row(rows, "球跡強度", trail_intensity_box)
	var trail_lifetime_box = HBoxContainer.new()
	_trail_lifetime = HSlider.new()
	_trail_lifetime.min_value = 0.15
	_trail_lifetime.max_value = 0.9
	_trail_lifetime.step = 0.05
	_trail_lifetime.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trail_lifetime.custom_minimum_size.x = 140
	_trail_lifetime.value_changed.connect(func(value): set_option("trail_lifetime", value))
	trail_lifetime_box.add_child(_trail_lifetime)
	_trail_lifetime_value = _label("0.45 秒", 17)
	_trail_lifetime_value.custom_minimum_size.x = 76
	_trail_lifetime_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trail_lifetime_box.add_child(_trail_lifetime_value)
	_add_row(rows, "殘留時間", trail_lifetime_box)
	rows.add_child(HSeparator.new())
	rows.add_child(_label("趣味統計", 19, Color("ffe06a")))
	_fun = CheckButton.new()
	_fun.text = "結算顯示所有玩家的撲倒次數"
	_fun.toggled.connect(func(value): set_option("fun_stats", value))
	rows.add_child(_fun)
	var hint = _label("擊打特效與球跡只影響本機畫面；連線趣味統計由房主同步。", 14, Color("a2b4c6"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(hint)

	content.add_child(HSeparator.new())
	_status = _label("設定會自動儲存", 14, Color("9fb0bf"))
	content.add_child(_status)
	var footer = HBoxContainer.new()
	content.add_child(footer)
	var version = _label("模組 v1.2.1  ·  遊戲 v1.0.4.3", 14, Color("9fb0bf"))
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(version)
	var reset = _button("恢復預設")
	reset.add_theme_font_size_override("font_size", 16)
	reset.pressed.connect(_reset_options)
	footer.add_child(reset)

func _add_row(parent: VBoxContainer, caption: String, control: Control) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label = _label(caption, 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 230)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)

func _refresh_controls() -> void:
	if not is_instance_valid(_weight):
		return
	_weight.select(0 if _options.font_weight == "bold" else 1)
	_scale.set_value_no_signal(_options.font_scale)
	_scale_value.text = "%d%%" % roundi(_options.font_scale * 100)
	_contrast.set_pressed_no_signal(_options.high_contrast)
	_effect.select(EFFECT_KEYS.find(_options.hit_effect))
	_intensity.set_value_no_signal(_options.effect_intensity)
	_intensity_value.text = "%d%%" % roundi(_options.effect_intensity * 100)
	_fun.set_pressed_no_signal(_options.fun_stats)
	_intensity.editable = _options.hit_effect != "off"
	_intensity.modulate.a = 1.0 if _intensity.editable else 0.45
	_preview.disabled = _options.hit_effect == "off"
	_trail_enabled.set_pressed_no_signal(_options.trail_enabled)
	_trail_style.text = EFFECT_LABELS[EFFECT_KEYS.find(_options.hit_effect)] if _options.trail_enabled else "球跡已關閉"
	_trail_intensity.set_value_no_signal(_options.trail_intensity)
	_trail_intensity_value.text = "%d%%" % roundi(_options.trail_intensity * 100)
	_trail_lifetime.set_value_no_signal(_options.trail_lifetime)
	_trail_lifetime_value.text = "%.2f 秒" % _options.trail_lifetime
	var trails_enabled = bool(_options.trail_enabled) and _options.hit_effect != "off"
	_trail_intensity.editable = trails_enabled
	_trail_lifetime.editable = trails_enabled
	_trail_intensity.modulate.a = 1.0 if trails_enabled else 0.45
	_trail_lifetime.modulate.a = 1.0 if trails_enabled else 0.45

func _reset_options() -> void:
	_options = DEFAULTS.duplicate()
	_save_options()
	_refresh_controls()
	settings_changed.emit(get_options())

func _fit_panel() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport_size = get_viewport().get_visible_rect().size
	_scroll.custom_minimum_size.y = minf(200.0, maxf(24.0, viewport_size.y - 320.0))
	var width = minf(660.0, maxf(360.0, viewport_size.x - 32.0))
	var height = minf(690.0, maxf(280.0, viewport_size.y - 32.0))
	_panel.size = Vector2(width, height)
	_panel.position = (viewport_size - _panel.size) * 0.5

func toggle() -> void:
	set_open(not is_open())

func set_open(open: bool) -> void:
	if not is_instance_valid(_overlay) or open == _overlay.visible:
		return
	if open:
		_previous_mouse_mode = Input.mouse_mode
		var focused = get_viewport().gui_get_focus_owner()
		_last_focus = weakref(focused) if is_instance_valid(focused) else null
		if not _open_game_pause():
			_gate_local_collectors(get_tree().root)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_overlay.show()
		_fit_panel()
		_weight.grab_focus()
	else:
		_overlay.hide()
		_close_game_pause()
		_restore_local_collectors()
		Input.mouse_mode = _previous_mouse_mode
		if _last_focus != null:
			var previous = _last_focus.get_ref()
			if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree():
				previous.grab_focus()
	panel_visibility_changed.emit(open)

func _find_game_pause(node: Node) -> Node:
	# Use the game's existing local input gate rather than alter input bindings.
	var script = node.get_script()
	if script != null and script.resource_path in ["res://game/ui/pause_menu.gd", "res://game/ui/pause_menu.gdc"]:
		if node.has_method("set_open") and node.has_method("is_open"):
			var owner = node.get_parent()
			while owner != null:
				var owner_script = owner.get_script()
				if owner_script != null and owner_script.resource_path in ["res://game/ui/hud.gd", "res://game/ui/hud.gdc"]:
					return node if bool(owner.get("pause_enabled")) else null
				owner = owner.get_parent()
	for child in node.get_children():
		var found = _find_game_pause(child)
		if found != null:
			return found
	return null

func _open_game_pause() -> bool:
	_game_pause = null
	_owns_game_pause = false
	var pause = _find_game_pause(get_tree().root)
	if pause == null:
		return false
	if bool(pause.call("is_open")):
		return true
	_game_pause_tree_flag = bool(pause.get("pauses_tree"))
	pause.set("pauses_tree", false)
	pause.call("set_open", true)
	if bool(pause.call("is_open")):
		_game_pause = weakref(pause)
		_owns_game_pause = true
	else:
		pause.set("pauses_tree", _game_pause_tree_flag)
	return _owns_game_pause

func _close_game_pause() -> void:
	if _owns_game_pause and _game_pause != null:
		var pause = _game_pause.get_ref()
		if is_instance_valid(pause):
			pause.call("set_open", false)
			pause.set("pauses_tree", _game_pause_tree_flag)
	_game_pause = null
	_owns_game_pause = false

func _gate_local_collectors(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path in ["res://game/ui/menu.gd", "res://game/ui/menu.gdc", "res://game/main/main.gd", "res://game/main/main.gdc"]:
		var collector = node.get("_input_collector")
		if is_instance_valid(collector):
			var device = collector.get("_dev")
			if is_instance_valid(device):
				var already_saved := false
				for saved in _gated_collectors:
					if saved.device.get_ref() == device:
						already_saved = true
						break
				if not already_saved:
					_gated_collectors.append({"collector": weakref(collector), "device": weakref(device), "mode": device.get("device"), "kbm": device.get("exclude_kbm"), "pads": device.get("exclude_pads")})
					_quarantine_device(device)
					collector.call("clear_buffers")
					device.call("poll", PackedStringArray(INPUT_ACTIONS))
	for child in node.get_children():
		_gate_local_collectors(child)

func _quarantine_device(device: Object) -> void:
	# Fixed KBM/pad modes bypass exclusions. MERGED honors both exclusions.
	# This is only this collector's local device object; bindings stay intact.
	device.set("device", -2)
	device.set("exclude_kbm", true)
	device.set("exclude_pads", Input.get_connected_joypads())

func _restore_local_collectors() -> void:
	for saved in _gated_collectors:
		var device = saved.device.get_ref()
		var collector = saved.collector.get_ref()
		if is_instance_valid(device):
			device.set("device", saved.mode)
			device.set("exclude_kbm", saved.kbm)
			device.set("exclude_pads", saved.pads)
			device.call("poll", PackedStringArray(INPUT_ACTIONS))
		if is_instance_valid(collector):
			collector.call("clear_buffers")
			collector.call("swallow_held", INPUT_ACTIONS)
	_gated_collectors.clear()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F8 or event.keycode == KEY_F8:
			toggle()
			get_viewport().set_input_as_handled()
		elif is_open() and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
			set_open(false)
			get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# Some game screens update cursor capture every frame.
	if is_open() and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_open():
		for saved in _gated_collectors:
			var device = saved.device.get_ref()
			if is_instance_valid(device):
				_quarantine_device(device)

func _exit_tree() -> void:
	if is_open():
		_close_game_pause()
		_restore_local_collectors()
		Input.mouse_mode = _previous_mouse_mode
