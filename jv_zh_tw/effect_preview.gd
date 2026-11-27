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
var _trail_mode := true
var _preview_style := "ring"
var _preview_ball: Node3D
var _trail_manager: Node
var _started_msec := 0
const NAMES = {"off": "關閉", "ring": "光環衝擊", "star": "星芒爆發", "comic": "漫畫撞擊", "fire": "火焰爆發", "ice": "冰雪碎晶", "electric": "雷電衝擊", "portal": "終界珍珠風格", "enchant": "附魔符文"}

func _ready() -> void:
	set_meta("jv_mod_ui", true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	# Earlier hit/trail callers now preview the same paired presentation.
	options = options.duplicate(true)
	_preview_style = str(options.get("hit_effect", "ring"))
	options.trail_effect = _preview_style if bool(options.get("trail_enabled", true)) else "off"
	_started_msec = Time.get_ticks_msec()
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
	title.text = "整組效果預覽：" + str(NAMES.get(_preview_style, "光環衝擊"))
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
	camera.position = Vector3(0, 0, 3.0)
	camera.fov = 45
	camera.current = true
	_build_trail_preview()
	var caption = Label.new()
	caption.text = "同一主題的擊打與球跡，會隨著示範球一起顯示。" if bool(options.get("trail_enabled", true)) else "球跡已關閉；示範球會呈現目前的擊打特效。"
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

func _build_trail_preview() -> void:
	_preview_ball = Node3D.new()
	_preview_ball.name = "PreviewBall"
	_world.add_child(_preview_ball)
	var sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.115
	mesh.height = 0.23
	mesh.radial_segments = 24
	mesh.rings = 12
	sphere.mesh = mesh
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("d9edff")
	sphere.material_override = material
	_preview_ball.add_child(sphere)
	for rotation in [Vector3.ZERO, Vector3(PI * 0.5, 0, 0)]:
		var band = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = 0.109
		ring.outer_radius = 0.12
		ring.rings = 24
		ring.ring_segments = 8
		band.mesh = ring
		var band_material = StandardMaterial3D.new()
		band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		band_material.albedo_color = Color("ffe06a")
		band.material_override = band_material
		band.rotation = rotation
		_preview_ball.add_child(band)
	var path = get_script().resource_path.get_base_dir().path_join("ball_trails.gd")
	if FileAccess.file_exists(path):
		var script = load(path)
		if script != null:
			_trail_manager = script.new()
			_trail_manager.preview_only = true
			_world.add_child(_trail_manager)
			_trail_manager.configure(options)
			_trail_manager.attach_preview_ball(_preview_ball)

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
	if _trail_mode:
		if is_instance_valid(_preview_ball):
			var time = float(Time.get_ticks_msec() - _started_msec) / 1000.0
			_preview_ball.position = Vector3(sin(time * 2.1) * 1.55, sin(time * 4.2) * 0.46, 0)
			_preview_ball.rotation = Vector3(time * 1.4, time * 2.2, time * 0.6)
	if _glyph_script == null or _world == null: return
	if _preview_style == "off": return
	var now = Time.get_ticks_msec()
	if now < _next_spawn: return
	_next_spawn = now + 850
	var glyph = _glyph_script.new()
	glyph.style = _preview_style
	glyph.strength = float(options.get("effect_intensity", 0.65))
	glyph.tint = Color("79baff")
	_world.add_child(glyph)
	glyph.position = _preview_ball.position if is_instance_valid(_preview_ball) else Vector3.ZERO

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
