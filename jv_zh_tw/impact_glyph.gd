extends Node3D
## Procedural, local-only hit artwork. No bodies, lights, or gameplay changes.

var style := "ring"
var tint := Color("79baff")
var strength := 0.65
var age := 0.0
const LIFETIME := 0.58
var _material: StandardMaterial3D
var _art: MeshInstance3D
var _caption: Label3D
var _origin: Vector3
var _origin_set := false
var _screen_scale := 1.0

func _ready() -> void:
	set_meta("jv_mod_ui", true)
	strength = clampf(strength, 0.2, 1.0)
	if not style in ["ring", "star", "comic", "fire", "ice", "electric"]:
		style = "ring"
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_material.albedo_color = Color(1, 1, 1, lerpf(0.78, 1.0, strength))
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	match style:
		"ring": _ring(mesh)
		"star": _star(mesh)
		"comic": _comic(mesh)
		"fire": _fire(mesh)
		"ice": _ice(mesh)
		"electric": _electric(mesh)
	mesh.surface_end()
	_art = MeshInstance3D.new()
	_art.mesh = mesh
	_art.material_override = _material
	_art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.layers = 1
	_art.extra_cull_margin = 0.5
	add_child(_art)
	if style == "comic":
		_caption = Label3D.new()
		_caption.text = "啪！"
		var font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC"])
		font.font_weight = 700
		_caption.font = font
		_caption.font_size = 72
		_caption.pixel_size = 0.0048
		_caption.modulate = Color("fff4bc")
		_caption.outline_modulate = Color("462143")
		_caption.outline_size = 12
		_caption.position.z = 0.025
		_caption.no_depth_test = false
		add_child(_caption)

func _triangle(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(vertex)

func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var direction = (b - a).normalized()
	var perpendicular = Vector3(-direction.y, direction.x, 0) * width * 0.5
	_triangle(mesh, a + perpendicular, b + perpendicular, b - perpendicular, color)
	_triangle(mesh, a + perpendicular, b - perpendicular, a - perpendicular, color)

func _polygon(mesh: ImmediateMesh, points: Array, color: Color) -> void:
	var center := Vector3.ZERO
	for point in points: center += point
	center /= points.size()
	for i in points.size():
		_triangle(mesh, center, points[i], points[(i + 1) % points.size()], color)

func _circle(mesh: ImmediateMesh, radius: float, width: float, color: Color, depth: float = 0.0) -> void:
	for i in 40:
		var a = TAU * float(i) / 40.0
		var b = TAU * float(i + 1) / 40.0
		_line(mesh, Vector3(cos(a) * radius, sin(a) * radius, depth), Vector3(cos(b) * radius, sin(b) * radius, depth), width, color)

func _burst(mesh: ImmediateMesh, rays: int, outer: float, inner: float, color: Color, depth: float = 0.0) -> void:
	var points: Array = []
	for i in rays * 2:
		var angle = TAU * float(i) / (rays * 2) + PI * 0.5
		var radius = outer if i % 2 == 0 else inner
		points.append(Vector3(cos(angle) * radius, sin(angle) * radius, depth))
	_polygon(mesh, points, color)

func _ring(mesh: ImmediateMesh) -> void:
	_circle(mesh, 0.50, 0.065, Color(tint.darkened(0.3), 0.95))
	_circle(mesh, 0.50, 0.032, Color("f2fcff"), 0.005)
	for i in 8:
		var direction = Vector3(cos(TAU * i / 8.0), sin(TAU * i / 8.0), 0)
		_line(mesh, direction * 0.64, direction * 0.85, 0.055, tint.lightened(0.12))

func _star(mesh: ImmediateMesh) -> void:
	_burst(mesh, 8, 0.78, 0.30, tint.darkened(0.3))
	_burst(mesh, 8, 0.66, 0.24, Color("ffe66d"), 0.006)
	_burst(mesh, 4, 0.40, 0.09, Color("fffce3"), 0.012)
	for i in 4:
		var direction = Vector3(cos(TAU * i / 4.0 + 0.4), sin(TAU * i / 4.0 + 0.4), 0)
		_line(mesh, direction * 0.88, direction * 1.02, 0.045, Color("fff6be"))

func _comic(mesh: ImmediateMesh) -> void:
	_burst(mesh, 11, 0.80, 0.39, Color("a72975"))
	_burst(mesh, 11, 0.70, 0.35, Color("ffda4f"), 0.006)
	for i in 6:
		var direction = Vector3(cos(TAU * i / 6.0), sin(TAU * i / 6.0), 0)
		_line(mesh, direction * 0.90, direction * 1.05, 0.045, Color("ff71af"))

func _flame(mesh: ImmediateMesh, center: Vector3, width: float, height: float, lean: float, color: Color) -> void:
	_polygon(mesh, [center + Vector3(-width * 0.5, -height * 0.26, 0),
		center + Vector3(-width * 0.62, height * 0.08, 0),
		center + Vector3(-width * 0.25 + lean, height * 0.48, 0),
		center + Vector3(lean, height * 0.78, 0),
		center + Vector3(width * 0.26 + lean, height * 0.32, 0),
		center + Vector3(width * 0.58, 0, 0),
		center + Vector3(width * 0.35, -height * 0.26, 0)], color)

func _fire(mesh: ImmediateMesh) -> void:
	_flame(mesh, Vector3(-0.32, 0.04, 0), 0.50, 0.94, -0.13, Color("e33a28"))
	_flame(mesh, Vector3(0.29, 0.04, 0), 0.52, 1.08, 0.16, Color("e33a28"))
	_flame(mesh, Vector3(0, -0.10, 0.004), 0.94, 1.38, 0.10, Color("ff751f"))
	_flame(mesh, Vector3(0, -0.13, 0.010), 0.62, 1.05, -0.06, Color("ffd143"))
	_flame(mesh, Vector3(0.02, -0.18, 0.016), 0.30, 0.58, 0.04, Color("fff4b0"))
	for i in 7:
		var x = -0.72 + float(i) * 0.23
		var y = 0.65 + float(i % 3) * 0.17
		_line(mesh, Vector3(x, y, 0), Vector3(x + 0.04, y + 0.14, 0), 0.052, Color("ffcc55"))

func _ice(mesh: ImmediateMesh) -> void:
	_polygon(mesh, [Vector3(0, 0.61, 0), Vector3(0.35, 0.25, 0), Vector3(0.28, -0.30, 0), Vector3(0, -0.50, 0), Vector3(-0.28, -0.30, 0), Vector3(-0.35, 0.25, 0)], Color("168fd2"))
	_polygon(mesh, [Vector3(0, 0.49, 0.006), Vector3(0.23, 0.19, 0.006), Vector3(0.18, -0.24, 0.006), Vector3(0, -0.37, 0.006), Vector3(-0.18, -0.24, 0.006), Vector3(-0.23, 0.19, 0.006)], Color("a3f0ff"))
	for i in 6:
		var angle = TAU * i / 6.0 + PI * 0.5
		var direction = Vector3(cos(angle), sin(angle), 0)
		var side = Vector3(-direction.y, direction.x, 0)
		_line(mesh, Vector3(0, 0, 0.014), direction * 0.86 + Vector3(0, 0, 0.014), 0.052, Color("edffff"))
		for sign_value in [-1, 1]:
			_line(mesh, direction * 0.54 + Vector3(0, 0, 0.014), direction * 0.71 + side * float(sign_value) * 0.18 + Vector3(0, 0, 0.014), 0.043, Color("b0f5ff"))
	_circle(mesh, 0.96, 0.025, Color(0.55, 0.88, 1.0, 0.70), -0.006)

func _electric(mesh: ImmediateMesh) -> void:
	for i in 5:
		var angle = TAU * i / 5.0 + 0.28
		var direction = Vector3(cos(angle), sin(angle), 0)
		var side = Vector3(-direction.y, direction.x, 0)
		var points = [direction * 0.16, direction * 0.40 + side * 0.17,
			direction * 0.47 - side * 0.10, direction * 0.72 + side * 0.13, direction * 1.02]
		for j in points.size() - 1:
			_line(mesh, points[j], points[j + 1], 0.095, Color("5367e8"))
			_line(mesh, points[j] + Vector3(0, 0, 0.006), points[j + 1] + Vector3(0, 0, 0.006), 0.038, Color("f3f5ff"))
	_burst(mesh, 5, 0.32, 0.12, Color("fff9bb"), 0.012)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	if not _origin_set:
		_origin = global_position
		_origin_set = true
	var camera = get_viewport().get_camera_3d()
	if camera != null:
		global_basis = camera.global_basis.orthonormalized()
		# Keep depth testing; a small contact offset avoids burying every stroke
		# inside the ball/body without rendering through other scenery.
		global_position = _origin + camera.global_basis.z.normalized() * 0.22
		if not camera.is_position_behind(global_position):
			var center = camera.unproject_position(global_position)
			var pixels_per_metre = center.distance_to(camera.unproject_position(global_position + camera.global_basis.x.normalized()))
			if pixels_per_metre > 0.01:
				_screen_scale = clampf(lerpf(28.0, 40.0, strength) / (pixels_per_metre * 0.50), 0.65, 3.2)
	var progress = age / LIFETIME
	scale = Vector3.ONE * _screen_scale * lerpf(0.95, 1.32, progress)
	var fade = 1.0 - smoothstep(0.20, 1.0, progress)
	_material.albedo_color.a = lerpf(0.78, 1.0, strength) * fade
	if style == "fire":
		_art.position.y = progress * 0.24
		_art.rotation.z = sin(progress * TAU * 2.0) * 0.035
	elif style == "electric":
		_art.rotation.z = sin(progress * TAU * 3.0) * 0.055
	elif style == "ice":
		_art.rotation.z = progress * 0.12
	if is_instance_valid(_caption):
		_caption.modulate.a = fade
		_caption.outline_modulate.a = fade
