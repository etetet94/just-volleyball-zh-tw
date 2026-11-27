extends Node3D
## Procedural, local-only hit artwork. No bodies, lights, or gameplay changes.

var style := "ring"
var tint := Color("79baff")
var strength := 0.65
var age := 0.0
var _born_usec: int = 0
static var _comic_font_shared: Font
const LIFETIME := 0.68
const ARCANE_LIFETIME := 0.76
var _material: StandardMaterial3D
var _art: MeshInstance3D
var _caption: Label3D
var _origin: Vector3
var _origin_set := false
var _screen_scale := 1.0
var _parts: Array = []
var _lifetime := LIFETIME
var _particle_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _glow: MeshInstance3D

func _ready() -> void:
	set_meta("jv_mod_ui", true)
	strength = clampf(strength, 0.2, 1.0)
	if not style in ["ring", "star", "comic", "fire", "ice", "electric", "portal", "enchant"]:
		style = "ring"
	if style in ["portal", "enchant"]:
		_lifetime = ARCANE_LIFETIME
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_material.albedo_color = Color(1, 1, 1, lerpf(0.78, 1.0, strength))
	_particle_material = _material.duplicate()
	_glow_material = _material.duplicate()
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.albedo_color.a = 0.0
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	match style:
		"ring": _ring(mesh)
		"star": _star(mesh)
		"comic": _comic(mesh)
		"fire": _fire(mesh)
		"ice": _ice(mesh)
		"electric": _electric(mesh)
		"portal": _portal(mesh)
		"enchant": _enchant(mesh)
	mesh.surface_end()
	_art = MeshInstance3D.new()
	_art.mesh = mesh
	_art.material_override = _material
	_art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.layers = 1
	_art.extra_cull_margin = 0.5
	add_child(_art)
	_build_glow()
	if style == "comic":
		_caption = Label3D.new()
		_caption.text = "啪！"
		if _comic_font_shared == null:
			var font = SystemFont.new()
			font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC"])
			font.font_weight = 700
			_comic_font_shared = font
		_caption.font = _comic_font_shared
		_caption.font_size = 72
		_caption.pixel_size = 0.0048
		_caption.modulate = Color("fff4bc")
		_caption.outline_modulate = Color("462143")
		_caption.outline_size = 12
		_caption.position.z = 0.025
		_caption.no_depth_test = false
		add_child(_caption)
	if not _parts.is_empty():
		_animate_parts(0.0)
	_born_usec = Time.get_ticks_usec()

func _triangle(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(vertex)

func _gradient_triangle(mesh: ImmediateMesh, points: Array, colors: Array) -> void:
	for i in 3:
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(points[i])

func _build_glow() -> void:
	var color = tint
	if style in ["star", "comic"]: color = Color("ffd76d")
	elif style == "fire": color = Color("ff8f34")
	elif style == "ice": color = Color("70dfff")
	elif style == "electric": color = Color("979bff")
	elif style in ["portal", "enchant"]: color = Color("b16af3")
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var transparent = Color(color, 0)
	for i in 40:
		var a = TAU * float(i) / 40.0
		var b = TAU * float(i + 1) / 40.0
		var da = Vector3(cos(a), sin(a), -0.012)
		var db = Vector3(cos(b), sin(b), -0.012)
		if style in ["ring", "portal", "enchant"]:
			# Vertex alpha creates a soft band without a texture or scene bloom.
			for radii in [Vector2(0.30, 0.52), Vector2(0.52, 0.78)]:
				var c1 = transparent if radii.x < 0.5 else Color(color, 0.20)
				var c2 = transparent if radii.y > 0.6 else Color(color, 0.20)
				_gradient_triangle(mesh, [da * radii.x, db * radii.x, db * radii.y], [c1, c1, c2])
				_gradient_triangle(mesh, [da * radii.x, db * radii.y, da * radii.y], [c1, c2, c2])
		else:
			_gradient_triangle(mesh, [Vector3(0, 0, -0.012), da * 0.85, db * 0.85], [Color(color, 0.26), transparent, transparent])
	mesh.surface_end()
	_glow = MeshInstance3D.new()
	_glow.mesh = mesh
	_glow.material_override = _glow_material
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.layers = 1
	_glow.extra_cull_margin = 0.5
	add_child(_glow)

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
	_circle(mesh, 0.49, 0.050, Color(tint, 0.95))
	_circle(mesh, 0.39, 0.022, Color("f2fcff"), 0.005)
	for i in 8:
		_motion_part(i, TAU * i / 8.0, "spark", tint.lightened(0.12))

func _star(mesh: ImmediateMesh) -> void:
	_burst(mesh, 8, 0.78, 0.30, tint.darkened(0.3))
	_burst(mesh, 8, 0.66, 0.24, Color("ffe66d"), 0.006)
	_burst(mesh, 4, 0.40, 0.09, Color("fffce3"), 0.012)
	for i in 6:
		_motion_part(i, TAU * i / 6.0 + 0.4, "star", Color("fff6be"))

func _comic(mesh: ImmediateMesh) -> void:
	_burst(mesh, 11, 0.80, 0.39, Color("a72975"))
	_burst(mesh, 11, 0.70, 0.35, Color("ffda4f"), 0.006)
	for i in 5:
		_motion_part(i, TAU * i / 5.0 + 0.2, "fragment", Color("ff71af") if i % 2 == 0 else Color("ffe887"))

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
	for i in 3:
		_motion_part(i, -0.42 + i * 0.42, "plume", Color("ff9b36"))
	for i in 6:
		_motion_part(i, -0.65 + i * 0.26, "ember", Color("ffd470"))

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
	for i in 6:
		_motion_part(i, TAU * i / 6.0 + 0.4, "crystal", Color("a1ecff"))

func _electric(mesh: ImmediateMesh) -> void:
	_burst(mesh, 5, 0.32, 0.12, Color("fff9bb"), 0.012)
	_burst(mesh, 4, 0.16, 0.035, Color("f0f8ff"), 0.018)
	for i in 6:
		_motion_part(i, TAU * i / 6.0 + 0.28, "bolt", Color("b6bfff"))

func _motion_part(index: int, angle: float, kind: String, color: Color) -> void:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"spark":
			_line(mesh, Vector3(-0.08, 0, 0), Vector3(0.12, 0, 0), 0.047, color)
			_line(mesh, Vector3(-0.03, 0, 0.004), Vector3(0.09, 0, 0.004), 0.018, Color("f7fcff"))
		"star":
			_burst(mesh, 4, 0.13, 0.035, color)
		"fragment":
			_polygon(mesh, [Vector3(-0.10, -0.055, 0), Vector3(0.13, -0.015, 0), Vector3(0.075, 0.07, 0), Vector3(-0.045, 0.045, 0)], color)
		"plume":
			_flame(mesh, Vector3.ZERO, 0.24, 0.54, 0.035, Color("e74d28"))
			_flame(mesh, Vector3(0, -0.025, 0.005), 0.14, 0.40, -0.02, color)
		"ember":
			_flame(mesh, Vector3.ZERO, 0.07, 0.19, 0.025, color)
		"crystal":
			_triangle(mesh, Vector3(-0.09, 0, 0), Vector3(0, 0.19, 0), Vector3(0, -0.13, 0), Color("3ba8e1"))
			_triangle(mesh, Vector3(0.09, 0, 0), Vector3(0, 0.19, 0), Vector3(0, -0.13, 0), color)
		"bolt":
			var points = [Vector3(0.15, 0, 0), Vector3(0.38, 0.14, 0), Vector3(0.46, -0.10, 0), Vector3(0.72, 0.11, 0), Vector3(0.98, 0, 0)]
			for j in points.size() - 1:
				_line(mesh, points[j], points[j + 1], 0.082, Color("6476e7"))
				_line(mesh, points[j] + Vector3(0, 0, 0.004), points[j + 1] + Vector3(0, 0, 0.004), 0.030, Color("f5f7ff"))
	mesh.surface_end()
	_part(mesh, angle, 0.42 + float(index % 3) * 0.07, index, kind)

func _square(mesh: ImmediateMesh, center: Vector3, side: float, color: Color) -> void:
	var x = Vector3(side * 0.5, 0, 0)
	var y = Vector3(0, side * 0.5, 0)
	_triangle(mesh, center - x - y, center + x - y, center + x + y, color)
	_triangle(mesh, center - x - y, center + x + y, center - x + y, color)

func _part(mesh: ImmediateMesh, angle: float, radius: float, index: int, kind: String = "") -> void:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _particle_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 1
	node.extra_cull_margin = 0.5
	add_child(node)
	_parts.append({"node": node, "angle": angle, "radius": radius, "index": index, "kind": kind})

func _portal(mesh: ImmediateMesh) -> void:
	# Original eight-by-eight pearl artwork; no external game textures/fonts.
	var pearl = ["..2222..", ".233332.", "23444332", "23455532", "23345532", "22333322", ".222222.", "..2222.."]
	var palette = {"2": Color("14594f"), "3": Color("2b9f87"), "4": Color("67dec0"), "5": Color("c0ffe6")}
	for y in pearl.size():
		for x in pearl[y].length():
			var key: String = pearl[y][x]
			if palette.has(key):
				_square(mesh, Vector3((x - 3.5) * 0.078, (3.5 - y) * 0.078, 0.020), 0.080, palette[key])
	# A broken, elliptical portal rim surrounds the pixel pearl.
	for i in 24:
		var angle = TAU * float(i) / 24.0
		var next = angle + TAU / 24.0 * 0.69
		var color = Color("d87bff") if i % 3 == 0 else Color("8652d6")
		_line(mesh, Vector3(cos(angle) * 0.66, sin(angle) * 0.43, 0), Vector3(cos(next) * 0.66, sin(next) * 0.43, 0), 0.045, color)
	for i in 10:
		var particle = ImmediateMesh.new()
		particle.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var side = 0.10 + float(i % 3) * 0.025
		_square(particle, Vector3.ZERO, side, Color("a751ea") if i % 2 == 0 else Color("d78bff"))
		_square(particle, Vector3(-side * 0.19, side * 0.19, 0.004), side * 0.39, Color("f2c7ff"))
		particle.surface_end()
		_part(particle, TAU * float(i) / 10.0 + 0.14, 0.59 + float(i % 3) * 0.11, i)

func _enchant(mesh: ImmediateMesh) -> void:
	# Hand-designed pixel marks, not an alphabet or a copied game font.
	var patterns = [
		["01110", "01000", "11100", "00100", "00110", "00010", "00110"],
		["00100", "11100", "00101", "00111", "10001", "11000", "01000"],
		["10010", "10010", "11110", "00100", "01110", "01010", "01000"],
		["01100", "00100", "10110", "11100", "00100", "00111", "00001"],
		["10100", "11100", "00100", "00110", "00010", "01110", "01000"],
		["00010", "01110", "01000", "11010", "10010", "11110", "00010"],
		["01010", "01010", "01110", "00010", "11110", "10000", "11000"],
		["11000", "01000", "01110", "00010", "10110", "11100", "00100"]]
	_circle(mesh, 0.42, 0.025, Color(0.65, 0.42, 0.96, 0.68))
	_burst(mesh, 4, 0.27, 0.065, Color("f1c8ff"), 0.010)
	_square(mesh, Vector3(0, 0, 0.015), 0.10, Color("fff1b8"))
	for i in patterns.size():
		var rune = ImmediateMesh.new()
		rune.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for y in patterns[i].size():
			for x in patterns[i][y].length():
				if patterns[i][y][x] != "1":
					continue
				var center = Vector3((x - 2.0) * 0.045, (3.0 - y) * 0.045, 0)
				_square(rune, center, 0.047, Color("7142b0"))
				_square(rune, center + Vector3(0, 0, 0.004), 0.033, Color("ffe5a8") if i % 2 == 0 else Color("e4c5ff"))
		rune.surface_end()
		_part(rune, TAU * float(i) / patterns.size() + 0.12, 0.66 + float(i % 2) * 0.13, i)

func _animate_parts(progress: float) -> void:
	var travel = smoothstep(0.03, 0.96, progress)
	var launch = smoothstep(0.0, 0.18, progress)
	for part in _parts:
		var node: MeshInstance3D = part.node
		var index: int = part.index
		if style == "portal":
			var angle: float = part.angle + progress * (1.4 if index % 2 == 0 else -1.0)
			var radius: float = part.radius + progress * 0.44
			node.position = Vector3(cos(angle) * radius, sin(angle) * radius * 0.72 + progress * 0.12, 0.030)
			node.rotation.z = part.angle + progress * (1.7 + index * 0.15)
			node.scale = Vector3.ONE * (1.0 - progress * 0.30)
		elif style == "enchant":
			var angle: float = part.angle + progress * 0.85
			var radius: float = part.radius + progress * 0.32
			node.position = Vector3(cos(angle) * radius, sin(angle) * radius * 0.86 + sin(progress * TAU + part.angle) * 0.085, 0.026)
			node.rotation.z = sin(progress * TAU + part.angle) * 0.16
			node.scale = Vector3.ONE * (0.88 + sin(progress * PI) * 0.16)
		elif style == "fire":
			if part.kind == "plume":
				node.position = Vector3(part.angle + sin(progress * TAU * 2.0 + index) * 0.07, 0.16 + travel * 0.42, 0.022)
				node.rotation.z = sin(progress * TAU * 1.7 + index) * 0.15
				node.scale = Vector3(0.8 + sin(progress * TAU * 2.0 + index) * 0.12, 0.80 + launch * 0.40, 1) * (1.0 - travel * 0.45)
			else:
				node.position = Vector3(part.angle + sin(progress * 4.0 + index) * 0.13, 0.30 + travel * (0.70 + index * 0.045), 0.026)
				node.rotation.z = sin(progress * TAU + index) * 0.35
				node.scale = Vector3.ONE * launch * (1.0 - travel * 0.50)
		elif style == "electric":
			node.position = Vector3(0, 0, 0.025)
			node.rotation.z = part.angle + sin(progress * TAU * 3.0 + index * 1.8) * 0.10
			var pulse = 0.90 + sin(progress * TAU * 4.0 + index) * 0.09
			node.scale = Vector3(lerpf(0.45, 1.08, launch) * pulse * (1.0 - travel * 0.22), pulse, 1)
		else:
			var angular_speed = 0.22 if style == "ring" else 0.40
			var angle: float = part.angle + progress * angular_speed * (1 if index % 2 == 0 else -1)
			var radius: float = part.radius + travel * (0.80 if style == "ring" else 0.67)
			node.position = Vector3(cos(angle) * radius, sin(angle) * radius - (progress * progress * 0.12 if style == "comic" else 0.0), 0.020)
			node.rotation.z = angle if style == "ring" else part.angle + progress * (1.4 + index * 0.25)
			node.scale = Vector3.ONE * lerpf(0.35, 1.0, launch) * (1.0 - travel * 0.46)

func _process(_delta: float) -> void:
	# Presentation previews continue during a stopped gameplay clock. Expire
	# effects against real time too, so those previews cannot accumulate glyphs.
	age = float(Time.get_ticks_usec() - _born_usec) / 1000000.0
	if age >= _lifetime:
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
	var progress = age / _lifetime
	var launch = smoothstep(0.0, 0.17, progress)
	var expand = smoothstep(0.02, 0.88, progress)
	scale = Vector3.ONE * _screen_scale * lerpf(0.86, 1.08, expand)
	var fade = 1.0 - smoothstep(0.43, 1.0, progress)
	_material.albedo_color.a = lerpf(0.78, 1.0, strength) * fade
	_particle_material.albedo_color.a = lerpf(0.85, 1.0, strength) * fade
	_glow_material.albedo_color.a = lerpf(0.48, 0.72, strength) * fade * launch
	_glow.scale = Vector3.ONE * lerpf(0.75, 1.30, expand)
	if style == "ring":
		_art.scale = Vector3.ONE * lerpf(0.65, 1.44, expand)
		_glow.scale = Vector3.ONE * lerpf(0.76, 1.82, expand)
	elif style == "star":
		_art.scale = Vector3.ONE * (0.64 + launch * 0.44 - smoothstep(0.62, 1.0, progress) * 0.13)
		_art.rotation.z = progress * 0.20
	elif style == "comic":
		_art.scale = Vector3.ONE * (0.70 + launch * 0.32)
		_art.rotation.z = -0.08 + progress * 0.15
	elif style == "fire":
		_art.position.y = progress * 0.24
		_art.rotation.z = sin(progress * TAU * 2.0) * 0.035
		_art.scale = Vector3(0.88 + sin(progress * TAU * 2.4) * 0.055, 0.72 + launch * 0.28 + sin(progress * TAU * 2.0) * 0.065, 1)
		_glow.scale = Vector3(0.85, 1.05 + expand * 0.20, 1)
	elif style == "electric":
		_art.rotation.z = progress * 1.40
		_art.scale = Vector3.ONE * (0.60 + launch * 0.40)
	elif style == "ice":
		_art.rotation.z = progress * 0.22
		_art.scale = Vector3.ONE * (0.70 + launch * 0.32)
	elif style == "portal":
		_art.rotation.z = sin(progress * TAU) * 0.045
		# The pearl rises out of the contact cloud; its core remains readable
		# when a third-person hit happens in front of the local avatar's head.
		_art.position.y = 0.35 + progress * 0.20 + sin(progress * PI) * 0.05
		_art.scale = Vector3.ONE * (0.78 + launch * 0.24)
		_glow.scale = Vector3(1.0 + expand * 0.30, 0.65 + expand * 0.20, 1)
	elif style == "enchant":
		_art.rotation.z = -progress * 0.55
		_art.scale = Vector3.ONE * (0.72 + launch * 0.30)
	if not _parts.is_empty():
		_animate_parts(progress)
	if is_instance_valid(_caption):
		_caption.scale = Vector3.ONE * (0.62 + launch * 0.52 - smoothstep(0.60, 1.0, progress) * 0.12)
		_caption.position.y = sin(progress * PI) * 0.075
		_caption.rotation.z = -0.08 + sin(progress * PI) * 0.14
		_caption.modulate.a = fade
		_caption.outline_modulate.a = fade
