extends CanvasLayer
## Isolated presentation preview. Has no connection to the match or its ball.

var options: Dictionary = {}
var panel_theme: Theme
var _world: SubViewport
var _glyph_script: Script
var _next_spawn: int = 0
var _card: PanelContainer
var _surface: TextureRect
var _previous_focus: WeakRef
const NAMES = {"ring": "光環衝擊", "star": "星芒爆發", "comic": "漫畫撞擊", "fire": "火焰爆發", "ice": "冰雪碎晶", "electric": "雷電衝擊"}

func _ready() -> void:
	set_meta("jv_mod_ui", true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_glyph_script = load(get_script().resource_path.get_base_dir().path_join("impact_glyph.gd"))
	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if panel_theme != null: overlay.theme = panel_theme
	add_child(overlay)
	var shade = ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	_card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("17232f")
	style.border_color = Color("596a7e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 18.0)
	_card.add_theme_stylebox_override("panel", style)
	overlay.add_child(_card)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_card.add_child(box)
	var title = Label.new()
	title.text = "特效預覽：" + str(NAMES.get(options.get("hit_effect", "ring"), "光環衝擊"))
	title.add_theme_color_override("font_color", Color("ffe06a"))
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	# Ignore the render texture's dimensions when measuring UI minimum sizes.
	# A SubViewportContainer can otherwise feed its stretched height back into
	# this card's minimum height and push the title/buttons out of the window.
	_surface = TextureRect.new()
	_surface.custom_minimum_size = Vector2(260, 180)
	_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_surface.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_surface)
	_world = SubViewport.new()
	_world.size = Vector2i(480, 220)
	_world.own_world_3d = true
	_world.transparent_bg = true
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_world)
	_surface.texture = _world.get_texture()
	_surface.resized.connect(_resize_world)
	var camera = Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0, 0, 3.5)
	camera.fov = 45
	camera.current = true
	var caption = Label.new()
	caption.text = "依目前風格與強度顯示，對局中會在擊球位置出現。"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color("afbdcd"))
	box.add_child(caption)
	var close = Button.new()
	close.text = "返回設定  Esc"
	close.custom_minimum_size.y = 40
	close.pressed.connect(_dismiss)
	box.add_child(close)
	get_viewport().size_changed.connect(_fit)
	_fit()
	var focused = get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if is_instance_valid(focused) else null
	close.grab_focus()
	call_deferred("_resize_world")

func _resize_world() -> void:
	if is_instance_valid(_world) and is_instance_valid(_surface):
		_world.size = Vector2i(maxi(64, roundi(_surface.size.x)), maxi(64, roundi(_surface.size.y)))

func _fit() -> void:
	if not is_instance_valid(_card): return
	var size = get_viewport().get_visible_rect().size
	_surface.custom_minimum_size.y = minf(180.0, maxf(64.0, size.y - 230.0))
	_card.size = Vector2(minf(520.0, size.x - 24.0), minf(380.0, size.y - 24.0))
	_card.position = (size - _card.size) * 0.5

func _process(_delta: float) -> void:
	# Font and wrapped-caption minimum sizes settle after the first container
	# layout. Reapply the bounded card size so an early large minimum cannot
	# leave it stretched beyond the window after that minimum becomes smaller.
	_fit()
	if _glyph_script == null or _world == null: return
	var now = Time.get_ticks_msec()
	if now < _next_spawn: return
	_next_spawn = now + 850
	var glyph = _glyph_script.new()
	glyph.style = str(options.get("hit_effect", "ring"))
	glyph.strength = float(options.get("effect_intensity", 0.65))
	glyph.tint = Color("79baff")
	_world.add_child(glyph)
	glyph.position = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_ESCAPE, KEY_F8] or event.physical_keycode in [KEY_ESCAPE, KEY_F8]):
		get_viewport().set_input_as_handled()
		_dismiss()

func _dismiss() -> void:
	visible = false
	queue_free()

func _exit_tree() -> void:
	if _previous_focus != null:
		var previous = _previous_focus.get_ref()
		if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree():
			previous.grab_focus()
