extends Node
## Cosmetic history of already-presented ball positions. No trajectory prediction,
## physics setters, network calls, game RNG use, textures, or external font assets.

const BALL_PATHS = ["res://game/ball/ball.gd", "res://game/ball/ball.gdc"]
const GAME_PATHS = ["res://game/main/main.gd", "res://game/main/main.gdc"]
const STYLES = ["off", "ring", "star", "comic", "fire", "ice", "electric", "portal", "enchant", "ribbon"]
const MAX_TRAILS = 12
const MAX_HISTORY = 47 # One additional live head keeps the displayed total <= 48.
const MAX_TRACKED = 64
const SAMPLE_USEC = 33333
const TELEPORT_DISTANCE = 3.5
const STATIONARY_MSEC = 140
const CONTACT_TTL_MSEC = 1400
const LAUNCH_MOVE_DISTANCE = 0.02
const MAX_HISTORY_UPLOADS_PER_FRAME = 2
const HISTORY_BUDGET_USEC = 1200

var preview_only = false # Set before add_child for an isolated settings preview.
var _options: Dictionary = {"trail_effect": "ring", "trail_intensity": 0.65, "trail_lifetime": 0.45, "spike_showcase": true, "effect_quality": "auto"}
var _states: Dictionary = {}
var _games: Array[WeakRef] = []
var _cameras: Array[WeakRef] = []
var _known_scene_nodes: Dictionary = {}
var _next_sample_usec = 0
var _next_cache_prune_msec = 0
var _sample_count = 0
var _rebuild_count = 0
var _clears: Dictionary = {}
var _detail_high = true
var _last_quality_usec = 0
var _frame_avg_msec = 16.0
var _quality_hot_msec = 0.0
var _quality_cool_msec = 0.0
var _quality_transitions = 0
var _process_cursor = 0
var _last_frame_uploads = 0
var _last_frame_geometry_usec = 0

class TrailSurface extends Node3D:
	# These small geometric symbols are original 5x5 pixel designs, not a font
	# or a copy of glyphs/particles from another game.
	const RUNES = [
		["00100", "10101", "01110", "10101", "00100"],
		["11000", "00101", "01110", "10100", "00011"],
		["01010", "10001", "00100", "11011", "01010"],
		["10010", "01100", "00101", "11010", "00100"],
		["00110", "10100", "01011", "00100", "11001"],
		["10001", "01010", "11100", "00011", "10100"]
	]
	var history_mesh: ArrayMesh
	var head_mesh: ArrayMesh
	var _history_art: MeshInstance3D
	var _head_art: MeshInstance3D
	var _material: StandardMaterial3D
	var triangles = 0
	var history_uploads = 0
	var head_mesh_builds = 0
	var head_transforms = 0
	var _drawing_triangles = 0
	var _vertices = PackedVector3Array()
	var _colors = PackedColorArray()
	var _indices = PackedInt32Array()
	var _vertex_count = 0
	var _index_count = 0
	var _camera_position = Vector3.ZERO
	var _camera_right = Vector3.RIGHT
	var _camera_up = Vector3.UP
	var _camera_back = Vector3.BACK
	var _palette_style = ""
	var _body_old = Color.WHITE
	var _body_new = Color.WHITE
	var _core = Color.WHITE
	var _head_style = ""
	var _head_intensity = -1.0
	var _head_spike = false
	var _rune_cells: Array[PackedVector2Array] = []

	func _ready() -> void:
		set_meta("jv_mod_ui", true)
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.no_depth_test = false
		history_mesh = ArrayMesh.new()
		head_mesh = ArrayMesh.new()
		_history_art = _art(history_mesh)
		_head_art = _art(head_mesh)
		for pattern in RUNES:
			var cells = PackedVector2Array()
			for y in 5:
				for x in 5:
					if pattern[y][x] == "1":
						cells.append(Vector2((x - 2) * 0.032, (2 - y) * 0.032))
			_rune_cells.append(cells)

	func _art(mesh: ArrayMesh) -> MeshInstance3D:
		var art = MeshInstance3D.new()
		art.mesh = mesh
		art.material_override = _material
		art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.layers = 1
		art.extra_cull_margin = 0.5
		add_child(art)
		return art

	func _camera(camera: Camera3D) -> void:
		var pose = camera.global_transform
		_camera_position = pose.origin
		_camera_right = pose.basis.x.normalized()
		_camera_up = pose.basis.y.normalized()
		_camera_back = pose.basis.z

	func _begin(vertex_capacity: int) -> void:
		# Three packed buffers per upload replace per-vertex ImmediateMesh calls
		# and the short-lived [position, color] arrays formerly made per segment.
		_vertices.resize(vertex_capacity)
		_colors.resize(vertex_capacity)
		_indices.resize(vertex_capacity * 3 / 2)
		_vertex_count = 0
		_index_count = 0
		_drawing_triangles = 0

	func _finish(mesh: ArrayMesh) -> void:
		_vertices.resize(_vertex_count)
		_colors.resize(_vertex_count)
		_indices.resize(_index_count)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		mesh.clear_surfaces()
		if _vertex_count > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		var v = _vertex_count
		_vertices[v] = a
		_vertices[v + 1] = b
		_vertices[v + 2] = c
		_colors[v] = color
		_colors[v + 1] = color
		_colors[v + 2] = color
		_indices[_index_count] = v
		_indices[_index_count + 1] = v + 1
		_indices[_index_count + 2] = v + 2
		_vertex_count += 3
		_index_count += 3
		_drawing_triangles += 1

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, end_color: Color) -> void:
		var v = _vertex_count
		_vertices[v] = a
		_vertices[v + 1] = b
		_vertices[v + 2] = c
		_vertices[v + 3] = d
		_colors[v] = color
		_colors[v + 1] = color
		_colors[v + 2] = end_color
		_colors[v + 3] = end_color
		_indices[_index_count] = v
		_indices[_index_count + 1] = v + 1
		_indices[_index_count + 2] = v + 2
		_indices[_index_count + 3] = v
		_indices[_index_count + 4] = v + 2
		_indices[_index_count + 5] = v + 3
		_vertex_count += 4
		_index_count += 6
		_drawing_triangles += 2

	func _side(a: Vector3, b: Vector3) -> Vector3:
		var side = (b - a).cross(_camera_position - (a + b) * 0.5)
		if side.length_squared() < 0.00000001:
			return _camera_right
		return side.normalized()

	func _line(a: Vector3, b: Vector3, width: float, color: Color) -> void:
		if a.distance_squared_to(b) < 0.00000001:
			return
		var side = _side(a, b) * width * 0.5
		_quad(a - side, a + side, b + side, b - side, color, color)

	func _taper(a: Vector3, b: Vector3, width_a: float, width_b: float, color_a: Color, color_b: Color, side: Vector3) -> void:
		_quad(a - side * width_a, a + side * width_a, b + side * width_b, b - side * width_b, color_a, color_b)

	func _pixel(at: Vector3, half_size: float, color: Color) -> void:
		var right = _camera_right * half_size
		var up = _camera_up * half_size
		_quad(at - right - up, at + right - up, at + right + up, at - right + up, color, color)

	func _noise(seed: int) -> float:
		var value = sin(float(seed % 1000003) * 12.9898) * 43758.5453
		return value - floorf(value)

	func _palette(style: String) -> void:
		if _palette_style == style:
			return
		_palette_style = style
		match style:
			"star":
				_body_old = Color("e69b42")
				_body_new = Color("fff4ad")
				_core = Color("fff6ae")
			"comic":
				_body_old = Color("e837a5")
				_body_new = Color("ff93c7")
				_core = Color("fff07c")
			"fire":
				_body_old = Color("e94b30")
				_body_new = Color("fff5a9")
				_core = Color("ffe59a")
			"ice":
				_body_old = Color("159fc5")
				_body_new = Color("70f8ff")
				_core = Color("9ff4ff")
			"electric":
				_body_old = Color("6640e5")
				_body_new = Color("b77bff")
				_core = Color("c5a0ff")
			"portal":
				_body_old = Color("7036c9")
				_body_new = Color("b478ff")
				_core = Color("48f4c3")
			"enchant":
				_body_old = Color("a355ed")
				_body_new = Color("eea7ff")
				_core = Color("e8b7ff")
			_:
				_body_old = Color("4684ee")
				_body_new = Color("77fff0")
				_core = Color("c4fff8")

	func _spark(at: Vector3, size: float, color: Color) -> void:
		var right = _camera_right * size
		var up = _camera_up * size
		_triangle(at - right * 0.25, at + right * 0.25, at + up, color)
		_triangle(at - right * 0.25, at + right * 0.25, at - up, color)
		_triangle(at - up * 0.25, at + up * 0.25, at + right, color)
		_triangle(at - up * 0.25, at + up * 0.25, at - right, color)

	func _rune(at: Vector3, index: int, alpha: float) -> void:
		var right = _camera_right
		var up = _camera_up
		var color = Color("f7c5ff") if index % 2 == 0 else Color("c9f8ff")
		color.a = alpha
		for cell in _rune_cells[index % _rune_cells.size()]:
			_pixel(at + right * cell.x + up * cell.y, 0.032 * 0.42, color)

	func _wake_ribbon(a: Vector3, b: Vector3, side: Vector3, offset_a: float, offset_b: float, width_a: float, width_b: float, color_a: Color, color_b: Color) -> void:
		# A clear central channel leaves the native possession trail readable.
		for sign_value in [-1.0, 1.0]:
			var pa = a + side * offset_a * sign_value
			var pb = b + side * offset_b * sign_value
			_taper(pa, pb, width_a, width_b, color_a, color_b, side)

	func _spike_wake(a: Vector3, b: Vector3, side: Vector3, old_fresh: float, fresh: float, old_boost: float, boost: float, intensity: float, seed: int, tick: int, style: String, old_along: float, along: float, high_detail: bool) -> void:
		# Longitudinal taper starts at zero at the *actual* oldest point, even
		# immediately after contact when every history sample is still fresh.
		var old_envelope = pow(old_along, 0.78)
		var envelope = pow(along, 0.78)
		var old_width = old_envelope * (0.12 + old_boost * 0.15)
		var width = envelope * (0.12 + boost * 0.15)
		var old_radius = old_envelope * (0.30 + old_width * 0.50)
		var radius = envelope * (0.30 + width * 0.50)
		var showcase_alpha = clampf(intensity * 1.32, 0.0, 1.0)
		var old_alpha = pow(old_fresh, 0.7) * old_boost * showcase_alpha
		var alpha = pow(fresh, 0.7) * boost * showcase_alpha
		# Keep the theme saturated; interpolating to the pale palette head
		# washed out the entire lance. Near-white is reserved for a hairline.
		var saturated = _body_old.lerp(_body_new, 0.14)
		var old_color = saturated
		var color = saturated
		old_color.a = old_alpha * 0.10
		color.a = alpha * 0.10
		_wake_ribbon(a, b, side, old_radius, radius, old_width * 1.9, width * 1.9, old_color, color)
		var old_ink = Color(saturated * 0.16, old_alpha * 0.8)
		var ink = Color(saturated * 0.16, alpha * 0.8)
		_wake_ribbon(a, b, side, old_radius, radius, old_width * 1.16, width * 1.16, old_ink, ink)
		old_color.a = old_alpha * 0.96
		color.a = alpha * 0.96
		_wake_ribbon(a, b, side, old_radius, radius, old_width * 0.92, width * 0.92, old_color, color)
		var old_edge = _core.lerp(Color.WHITE, 0.12)
		var edge = old_edge
		old_edge.a = old_alpha * 0.88
		edge.a = alpha * 0.88
		_wake_ribbon(a, b, side, old_radius - old_width * 0.48, radius - width * 0.48, old_width * 0.11, width * 0.11, old_edge, edge)
		# Deliberate sparse accents; all are part of this one batched history mesh.
		var direction = (b - a).normalized()
		var normal = direction.cross(side).normalized()
		# Twin corkscrew filaments follow sampled flight, never a forecast path.
		# Deterministic phase avoids allocating particles or touching game RNG.
		for spiral in (2 if high_detail else 0):
			var phase_a = float(tick - 1) * 0.80 + float(spiral) * PI
			var phase_b = float(tick) * 0.80 + float(spiral) * PI
			var spiral_a = a + (side * cos(phase_a) + normal * sin(phase_a)) * old_radius * 1.75
			var spiral_b = b + (side * cos(phase_b) + normal * sin(phase_b)) * radius * 1.75
			_line(spiral_a, spiral_b, 0.075, Color(saturated, alpha * 0.16))
			_line(spiral_a, spiral_b, 0.020, Color(_core.lerp(saturated, 0.32), alpha * 0.85))
		var flank = side * (-1.0 if tick % 2 == 0 else 1.0)
		if tick % 2 == 0:
			var reach = radius + 0.13 + _noise(seed) * 0.22
			var start = b + flank * reach
			var finish = start - direction * (0.22 + boost * 0.35)
			_line(start, finish, 0.017, Color(_body_old.lerp(_core, 0.4), alpha * 0.8))
			if style == "fire":
				_triangle(start - side * 0.055, start + side * 0.055, finish - direction * 0.18 + _camera_up * 0.08, Color(1.0, 0.54, 0.12, alpha * 0.8))
			elif style == "electric":
				var middle = start.lerp(finish, 0.5) + side * 0.13
				_line(start, middle, 0.036, Color(0.83, 0.75, 1.0, alpha))
				_line(middle, finish, 0.022, Color(0.43, 0.54, 1.0, alpha))
			elif style == "ice":
				_quad(start - side * 0.06, start + _camera_up * 0.15, start + side * 0.06, start - _camera_up * 0.15, Color(0.77, 0.97, 1.0, alpha), Color(0.3, 0.74, 1.0, alpha))
			elif style == "portal":
				_pixel(start, 0.045, Color(0.73, 0.35, 1.0, alpha))
			elif style == "star":
				_spark(start, 0.10, Color(1.0, 0.96, 0.58, alpha))
		if tick % 5 == 0 and boost > 0.2:
			# Broken shock collars perpendicular to the measured flight direction.
			# Open arcs avoid a solid hoop hiding the ball or a player's body.
			var wave_radius = radius + 0.12 + (1.0 - fresh) * 0.22
			for collar in (2 if high_detail else 1):
				var collar_radius = wave_radius * (1.0 + float(collar) * 0.27)
				var center = b - direction * float(collar) * 0.09
				for arc in 2:
					var phase = float(arc) * PI + 0.20 + float(collar) * 0.16
					for j in 4:
						var t0 = phase + float(j) * 0.30
						var t1 = t0 + 0.30
						var c0 = center + (side * cos(t0) + normal * sin(t0)) * collar_radius
						var c1 = center + (side * cos(t1) + normal * sin(t1)) * collar_radius
						_line(c0, c1, 0.026 if collar == 0 else 0.016, Color(_core.lerp(saturated, 0.25), alpha * (0.82 if collar == 0 else 0.5)))

	func draw_history(points: Array, now: int, lifetime: float, style: String, intensity: float, camera: Camera3D, high_detail: bool = true) -> void:
		triangles = 0
		if points.size() < 2:
			_history_art.visible = false
			return
		_history_art.visible = true
		_camera(camera)
		_palette(style)
		var boosted_points = 0
		for point in points:
			if float(point.get("spike", 0.0)) > 0.0: boosted_points += 1
		_begin(points.size() * 40 + boosted_points * (176 if high_detail else 112) + 64)
		var lifetime_msec = lifetime * 1000.0
		var width_scale = lerpf(0.65, 1.05, intensity)
		var previous_fresh = clampf(1.0 - float(now - int(points[0].stamp)) / lifetime_msec, 0.0, 1.0)
		var previous_color = _body_old.lerp(_body_new, previous_fresh)
		previous_color.a = pow(previous_fresh, 0.7) * intensity * 0.94
		var previous_core = _core
		previous_core.a = pow(previous_fresh, 0.55) * intensity * 0.94
		for i in range(1, points.size()):
			var a: Vector3 = points[i - 1].position
			var b: Vector3 = points[i].position
			var fresh = clampf(1.0 - float(now - int(points[i].stamp)) / lifetime_msec, 0.0, 1.0)
			var fade = pow(fresh, 0.7) * intensity
			var width = lerpf(0.025, 0.13, fresh) * width_scale
			var old_width = lerpf(0.006, 0.13, previous_fresh) * width_scale
			var segment_side = _side(a, b) * 0.5
			var color = _body_old.lerp(_body_new, fresh)
			color.a = fade * 0.94
			var old_color = previous_color
			var spike = float(points[i].get("spike", 0.0))
			var previous_spike = float(points[i - 1].get("spike", 0.0))
			# The native ownership ribbon occupies the center. Enhanced spike
			# energy is drawn on either side, with only a very soft central tint.
			if spike > 0.0 or previous_spike > 0.0:
				color.a *= 0.12
				old_color.a *= 0.12
			var halo_a = old_color
			var halo_b = color
			halo_a.a *= 0.22
			halo_b.a *= 0.22
			_taper(a, b, old_width * 2.25, width * 2.25, halo_a, halo_b, segment_side)
			if style == "electric":
				var jitter = _camera_up * (_noise(int(points[i].stamp)) - 0.5) * 0.22 * (1.0 - fresh)
				_line(a, (a + b) * 0.5 + jitter, width * 0.6, color)
				_line((a + b) * 0.5 + jitter, b, width * 0.6, color)
			else:
				_taper(a, b, old_width, width, old_color, color, segment_side)
			var core = _core
			core.a = pow(fresh, 0.55) * intensity * 0.94
			var old_core = previous_core
			if spike > 0.0 or previous_spike > 0.0:
				core.a *= 0.12
				old_core.a *= 0.12
			_taper(a, b, old_width * 0.24, width * 0.24, old_core, core, segment_side)
			previous_fresh = fresh
			previous_color = color
			previous_core = core
			var seed = int(points[i].stamp)
			var side = _camera_right
			var up = _camera_up
			var age = 1.0 - fresh
			var tick = int(points[i].get("serial", i))
			if spike > 0.0 or previous_spike > 0.0:
				_spike_wake(a, b, segment_side * 2.0, clampf(1.0 - float(now - int(points[i - 1].stamp)) / lifetime_msec, 0.0, 1.0), fresh, previous_spike, spike, intensity, seed, tick, style, float(i - 1) / float(points.size() - 1), float(i) / float(points.size() - 1), high_detail)
			if style == "star" and tick % 3 == 0:
				var drift = side * (_noise(seed) - 0.5) * age * 0.6 + up * age * 0.25
				_spark(b + drift, 0.04 + fresh * 0.06, Color(1.0, 0.88, 0.32, fade))
			elif style == "comic" and tick % 3 == 0:
				var direction = (b - a).normalized()
				var offset = side * (_noise(seed) - 0.5) * 0.4
				_line(b + offset - direction * 0.2, b + offset + direction * 0.12, 0.025, Color(1.0, 0.91, 0.32, fade))
				if tick % 6 == 0:
					_spark(b + offset, 0.1, Color(1.0, 0.52, 0.73, fade))
			elif style == "portal" and tick % (2 if high_detail else 4) == 0:
				for j in (2 if high_detail else 1):
					var drift = side * (_noise(seed + j * 41) - 0.5) * age * 0.8 + up * age * 0.25 + _camera_back * (_noise(seed + 71 + j) - 0.5) * age * 0.5
					_pixel(b + drift, 0.025 + _noise(seed + j) * 0.025, Color(0.70, 0.26, 1.0, fade))
				if tick % 4 == 0:
					_pixel(b, 0.022, Color(0.3, 1.0, 0.82, fade))
			elif style == "enchant" and tick % (4 if high_detail else 8) == 0:
				var rhythm = sin(float(now - seed) * 0.009 + float(seed % 7))
				var drift = side * ((_noise(seed) - 0.5) * 0.35 + rhythm * 0.06) + up * (0.12 + age * 0.45)
				_rune(b + drift, seed % RUNES.size(), fade)
			elif style == "ice" and tick % 3 == 0:
				var drift = side * (_noise(seed) - 0.5) * age * 0.45 + up * age * 0.15
				var size = 0.035 + _noise(seed + 1) * 0.04
				_quad(b + drift - side * size, b + drift + up * size * 1.6, b + drift + side * size, b + drift - up * size * 1.6, Color(0.65, 0.94, 1.0, fade), Color(0.65, 0.94, 1.0, fade))
			elif style == "fire" and tick % 2 == 0:
				var lift = up * (0.12 + age * 0.35 + _noise(seed) * 0.10)
				_triangle(b - side * width, b + side * width, b + lift, Color(1.0, 0.36 + fresh * 0.4, 0.12, fade * 0.75))
			elif style == "electric" and tick % 5 == 0:
				var fork = side * (0.13 + age * 0.18) * (-1.0 if seed % 2 == 0 else 1.0)
				_line(b, b + fork * 0.5 + up * 0.04, 0.026, Color(0.66, 0.85, 1.0, fade))
				_line(b + fork * 0.5 + up * 0.04, b + fork + up * 0.14, 0.018, Color(0.73, 0.54, 1.0, fade * 0.7))
		_finish(history_mesh)
		history_uploads += 1
		triangles = _drawing_triangles

	func draw_head(last: Vector3, head: Vector3, style: String, intensity: float, camera: Camera3D, spike: float = 0.0) -> void:
		var direction = head - last
		_head_art.visible = direction.length_squared() > 0.000001
		if not _head_art.visible:
			return
		_camera(camera)
		var spike_active = spike > 0.0
		if _head_style != style or _head_intensity != intensity or _head_spike != spike_active:
			_palette(style)
			_begin(24 if spike_active else 12)
			var color = _body_old.lerp(_body_new, 0.14 if spike_active else 1.0)
			color.a = intensity * 0.94
			var halo = Color(color * 0.16, intensity * 0.65) if spike_active else color
			if not spike_active: halo.a *= 0.22
			var core = _core
			core.a = intensity * 0.94
			var width = 0.13 * lerpf(0.65, 1.05, intensity)
			for layer in 3:
				var half_width = width * (2.25 if layer == 0 else 1.0 if layer == 1 else 0.24) * 0.5
				var tint = halo if layer == 0 else color if layer == 1 else core
				if spike_active:
					# Prebuilt split head, transformed each presentation frame.
					half_width *= 1.6
					for sign_value in [-1.0, 1.0]:
						var x = 0.43 * sign_value
						_quad(Vector3(x - half_width, 0, 0), Vector3(x + half_width, 0, 0), Vector3(x + half_width * 0.8, 0, 1), Vector3(x - half_width * 0.8, 0, 1), tint, tint)
				else:
					_quad(Vector3(-half_width, 0, 0), Vector3(half_width, 0, 0), Vector3(half_width, 0, 1), Vector3(-half_width, 0, 1), tint, tint)
			_finish(head_mesh)
			_head_style = style
			_head_intensity = intensity
			_head_spike = spike_active
			head_mesh_builds += 1
		var side = _side(last, head)
		_head_art.transform = Transform3D(Basis(side * (lerpf(0.85, 1.15, spike) if spike_active else 1.0), direction.normalized().cross(side), direction), last)
		head_transforms += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10010 # Observe the ball after the game's visual presentation.
	if not preview_only:
		var net = get_tree().root.get_node_or_null("Net")
		if net != null:
			if net.has_signal("event_received"): net.connect("event_received", _on_network_event)
			if net.has_signal("own_ball_pose"): net.connect("own_ball_pose", _on_own_ball_pose)
		get_tree().node_added.connect(_on_node_added)
		_scan(get_tree().root)

func configure(options: Dictionary) -> void:
	var previous = str(_options.trail_effect)
	var previous_spike = bool(_options.spike_showcase)
	if options.has("effect_quality") and str(options.effect_quality) in ["auto", "high", "low"]:
		_options.effect_quality = str(options.effect_quality)
	if options.has("spike_showcase"):
		_options.spike_showcase = bool(options.spike_showcase)
	if options.has("trail_effect"):
		_options.trail_effect = str(options.trail_effect) if str(options.trail_effect) in STYLES else "ring"
		if _options.trail_effect == "ribbon":
			_options.trail_effect = "ring"
	for pair in [["trail_intensity", 0.2, 1.0], ["trail_lifetime", 0.15, 0.9]]:
		if options.has(pair[0]) and (options[pair[0]] is int or options[pair[0]] is float) and is_finite(float(options[pair[0]])):
			_options[pair[0]] = clampf(float(options[pair[0]]), pair[1], pair[2])
	if previous != _options.trail_effect or previous_spike != bool(_options.spike_showcase) or _options.trail_effect == "off":
		for state in _states.values():
			_clear(state, "setting")
	_next_sample_usec = 0

func register_preview_ball(ball: Node3D) -> void:
	_track(ball, true)

func attach_preview_ball(ball: Node3D) -> void:
	register_preview_ball(ball)

func _scan(node: Node) -> void:
	_try_track(node)
	for child in node.get_children():
		_scan(child)

func _on_node_added(node: Node) -> void:
	# UI trees contain many short-lived Controls; only 3D nodes can be balls,
	# cameras or a game root, so avoid queueing work for every menu control.
	if node is Node3D:
		call_deferred("_track_deferred", weakref(node))

func _track_deferred(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node):
		_try_track(node)

func _try_track(node: Node) -> void:
	if not is_instance_valid(node) or not node is Node3D:
		return
	if node is Camera3D and not _known_scene_nodes.has(node.get_instance_id()):
		_known_scene_nodes[node.get_instance_id()] = true
		_cameras.append(weakref(node))
	var script = node.get_script()
	if script != null and script.resource_path in GAME_PATHS and not _known_scene_nodes.has(node.get_instance_id()):
		_known_scene_nodes[node.get_instance_id()] = true
		_games.append(weakref(node))
	if script != null and script.resource_path in BALL_PATHS and _find_game(node) != null:
		_track(node, false)

func _find_game(node: Node) -> Node:
	var current = node.get_parent()
	for depth in 18:
		if current == null:
			break
		var script = current.get_script()
		if script != null and script.resource_path in GAME_PATHS:
			return current
		current = current.get_parent()
	# Own/client balls can be attached while a packed scene is still entering
	# the tree. Resolve that association from existing game references later.
	for reference in _games:
		var game = reference.get_ref()
		if not is_instance_valid(game) or not game.is_inside_tree() or game.get_world_3d() != node.get_world_3d():
			continue
		if game.get("ball") == node:
			return game
		var players = game.get("_all_players")
		if players is Array:
			for player in players:
				if is_instance_valid(player) and player.get("ball") == node:
					return game
	return null

func _camera_for(ball: Node3D) -> Camera3D:
	var camera = ball.get_viewport().get_camera_3d()
	if is_instance_valid(camera) and camera.get_world_3d() == ball.get_world_3d():
		return camera
	# Split/local views can render this world from a sibling SubViewport while
	# the ball's own viewport no longer owns a current Camera3D.
	for reference in _cameras:
		var candidate = reference.get_ref()
		if is_instance_valid(candidate) and candidate.is_inside_tree() and candidate.is_current() and candidate.get_world_3d() == ball.get_world_3d():
			return candidate
	return null

func _track(ball: Node3D, preview: bool) -> void:
	if not is_instance_valid(ball) or not ball.is_inside_tree() or _states.has(ball.get_instance_id()) or _states.size() >= MAX_TRACKED:
		return
	var game = null if preview else _find_game(ball)
	_states[ball.get_instance_id()] = {"ball": weakref(ball), "game": weakref(game) if game != null else null, "preview": preview, "points": [], "renderer": null, "position": Vector3.INF, "motion_anchor": Vector3.INF, "head": Vector3.INF, "last_frame": 0, "last_move": 0, "generation": int(game.get("_match_gen")) if game != null else 0, "phase": int(game.get("_phase")) if game != null else -1, "hit_by": 0, "center_source": "ball", "world": 0, "reason": "pending", "serial": 0, "contact_kind": 0, "contact_power": 0.0, "contact_seq": int(ball.get("strike_seq")) if not preview else 0, "contact_at": 0, "contact_pending": false, "contact_origin": Vector3.INF, "contact_flight_at": 0, "sample_position": Vector3.INF, "sample_at": 0, "spike": 0.0, "history_dirty": false, "history_head": Vector3.INF}

	if not preview:
		if ball.has_signal("struck"): ball.connect("struck", _on_ball_struck.bind(weakref(ball)))
		for event in ["bounced", "wall_hit", "net_hit"]:
			if ball.has_signal(event): ball.connect(event, _on_ball_stopped.bind(weakref(ball)))

func _set_contact(ball: Node, kind: int, power: float, sequence: int = -1) -> void:
	if not is_instance_valid(ball) or not _states.has(ball.get_instance_id()) or kind < 1 or kind > 6 or not is_finite(power):
		return
	var state: Dictionary = _states[ball.get_instance_id()]
	var game = state.game.get_ref() if state.game is WeakRef else null
	if is_instance_valid(game) and int(game.get("_match_gen")) != int(state.generation):
		_clear(state, "generation")
		state.generation = int(game.get("_match_gen"))
		state.phase = int(game.get("_phase"))
		state.contact_seq = -1
		state.contact_at = 0
	if sequence >= 0 and (sequence < int(state.contact_seq) or (sequence == int(state.contact_seq) and int(state.contact_at) > 0)):
		return
	state.contact_kind = kind
	state.contact_power = clampf(power, 0.0, 2.0)
	state.contact_seq = sequence if sequence >= 0 else int(ball.get("strike_seq"))
	state.contact_at = _clock_usec() / 1000
	state.contact_pending = kind == 3
	state.contact_origin = _display_position(ball, state)
	state.contact_flight_at = 0

func _on_ball_struck(_pos: Vector3, power: float, kind: int, reference: WeakRef) -> void:
	var ball = reference.get_ref()
	if is_instance_valid(ball): _set_contact(ball, kind, power)

func _on_ball_stopped(reference: WeakRef) -> void:
	var ball = reference.get_ref()
	if is_instance_valid(ball) and _states.has(ball.get_instance_id()):
		_states[ball.get_instance_id()].contact_kind = 0
		_states[ball.get_instance_id()].spike = 0.0
		_states[ball.get_instance_id()].contact_pending = false
		_states[ball.get_instance_id()].contact_flight_at = 0

func _on_network_event(event: String, args: Dictionary) -> void:
	if event in ["bounce", "net", "wall"]:
		var generation = -1
		if args.has("g"):
			var value = args.g
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return
			generation = int(value)
		for reference in _games:
			var game = reference.get_ref()
			if is_instance_valid(game) and int(game.get("_net_role")) == 2:
				if generation >= 0 and int(game.get("_match_gen")) != generation: continue
				var ball = game.get("ball")
				if is_instance_valid(ball): _on_ball_stopped(weakref(ball))
		return
	if event != "strike": return
	var kind = args.get("k", 0)
	var power = args.get("w", 0.0)
	var sequence = args.get("n", -1)
	if not (kind is int or kind is float) or not (power is int or power is float) or not (sequence is int or sequence is float): return
	if not is_finite(float(kind)) or not is_finite(float(power)) or not is_finite(float(sequence)) or float(sequence) < 0.0: return
	# Native clients adopt the original event after it is delivered. Read the
	# same accepted generation/sequence without changing or sending anything.
	call_deferred("_accept_network_contact", int(kind), float(power), int(sequence), int(args.get("g", -1)))

func _accept_network_contact(kind: int, power: float, sequence: int, generation: int) -> void:
	for reference in _games:
		var game = reference.get_ref()
		if not is_instance_valid(game) or not game.is_inside_tree() or int(game.get("_net_role")) != 2: continue
		if generation >= 0 and int(game.get("_match_gen")) != generation: continue
		var ball = game.get("ball")
		if is_instance_valid(ball) and int(ball.get("strike_seq")) == sequence:
			_set_contact(ball, kind, power, sequence)

func _on_own_ball_pose(_peer: int, pose: PackedFloat32Array) -> void:
	if pose.size() < 11: return
	for index in [0, 7, 8, 9, 10]:
		if not is_finite(pose[index]): return
	# Resolve by native body id after OwnBalls creates/updates its exact ghost.
	call_deferred("_accept_ghost_contact", int(pose[0]), int(pose[7]), int(pose[8]), int(pose[9]), float(pose[10]))

func _accept_ghost_contact(body_id: int, pose_state: int, sequence: int, kind: int, power: float) -> void:
	for reference in _games:
		var game = reference.get_ref()
		if not is_instance_valid(game) or not game.is_inside_tree() or not bool(game.get("embedded")): continue
		var practice = game.get("_practice")
		var own = practice.get("own") if practice != null else null
		var ghosts = own.get("_ghosts") if own != null else null
		if not ghosts is Dictionary or not ghosts.has(body_id): continue
		var ghost: Dictionary = ghosts[body_id]
		var ball = ghost.get("ball")
		if not is_instance_valid(ball) or not _states.has(ball.get_instance_id()): continue
		var state: Dictionary = _states[ball.get_instance_id()]
		if pose_state != 1:
			state.contact_kind = 0
		elif sequence > int(state.contact_seq):
			_set_contact(ball, kind, power, sequence)

func _clear(state: Dictionary, reason: String, preserve_pending_contact: bool = false) -> void:
	var renderer = state.renderer.get_ref() if state.renderer is WeakRef else null
	if not state.points.is_empty() or is_instance_valid(renderer):
		_clears[reason] = int(_clears.get(reason, 0)) + 1
	state.points.clear()
	if is_instance_valid(renderer) and not renderer.is_queued_for_deletion():
		renderer.queue_free()
	state.renderer = null
	state.position = Vector3.INF
	state.motion_anchor = Vector3.INF
	state.head = Vector3.INF
	if not preserve_pending_contact:
		state.contact_kind = 0
		state.contact_pending = false
		state.contact_origin = Vector3.INF
		state.contact_flight_at = 0
	state.spike = 0.0
	state.sample_position = Vector3.INF
	state.sample_at = 0
	state.history_dirty = false
	state.history_head = Vector3.INF

func _reason_inactive(ball: Node3D, state: Dictionary) -> String:
	if not ball.is_visible_in_tree():
		return "hidden"
	if state.preview:
		return ""
	if get_tree().paused:
		return "paused"
	var game = state.game.get_ref() if state.game is WeakRef else null
	if not is_instance_valid(game):
		game = _find_game(ball)
		if game != null:
			state.game = weakref(game)
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion():
		return "scene"
	if game is Node3D and not game.is_visible_in_tree():
		return "hidden"
	if bool(game.get("embedded")) and not bool(game.get("embedded_active")):
		return "inactive"
	if int(game.get("_phase")) == 7:
		return "replay"
	if bool(game.get("_match_over")) or int(game.get("_phase")) in [0, 5, 6]:
		return "inactive"
	if bool(ball.get("frozen")) or bool(ball.get("serve_held")):
		return "frozen"
	return ""

func _display_position(ball: Node3D, state: Dictionary) -> Vector3:
	var visual = state.get("visual").get_ref() if state.get("visual") is WeakRef else null
	if not is_instance_valid(visual) or not visual.is_inside_tree():
		visual = ball.get_node_or_null("Mesh") if state.preview else ball.get("mesh")
		state.visual = weakref(visual) if is_instance_valid(visual) else null
	if is_instance_valid(visual) and visual is Node3D and visual.is_inside_tree():
		state.center_source = "mesh"
		return visual.global_position
	state.center_source = "ball"
	return ball.global_position

func _renderer_count() -> int:
	var count = 0
	for state in _states.values():
		var renderer = state.renderer.get_ref() if state.renderer is WeakRef else null
		if is_instance_valid(renderer) and not renderer.is_queued_for_deletion():
			count += 1
	return count

func _prune_scene_cache() -> void:
	var games: Array[WeakRef] = []
	var cameras: Array[WeakRef] = []
	_known_scene_nodes.clear()
	for reference in _games:
		var node = reference.get_ref()
		if is_instance_valid(node) and node.is_inside_tree():
			games.append(reference)
			_known_scene_nodes[node.get_instance_id()] = true
	for reference in _cameras:
		var node = reference.get_ref()
		if is_instance_valid(node) and node.is_inside_tree():
			cameras.append(reference)
			_known_scene_nodes[node.get_instance_id()] = true
	_games = games
	_cameras = cameras

func _renderer(ball: Node3D, state: Dictionary) -> Node3D:
	var renderer = state.renderer.get_ref() if state.renderer is WeakRef else null
	if is_instance_valid(renderer) and not renderer.is_queued_for_deletion():
		return renderer
	if _renderer_count() >= MAX_TRAILS:
		return null
	renderer = TrailSurface.new()
	renderer.name = "JVBallTrail"
	ball.get_parent().add_child(renderer)
	renderer.top_level = true
	renderer.global_transform = Transform3D.IDENTITY
	state.renderer = weakref(renderer)
	return renderer

func _update_quality(now_usec: int) -> void:
	if _options.effect_quality != "auto":
		_detail_high = _options.effect_quality == "high"
		_last_quality_usec = now_usec
		_quality_hot_msec = 0.0
		_quality_cool_msec = 0.0
		return
	var elapsed = float(now_usec - _last_quality_usec) / 1000.0
	_last_quality_usec = now_usec
	# Ignore idle scenes, pauses, native hitstop and scheduling/teleport spikes.
	# Only sustained frame pressure changes decorative geometry, never the
	# core lance silhouette, ball position, physics or native ownership cue.
	if get_tree().paused or Engine.time_scale <= 0.001 or _renderer_count() == 0 or elapsed < 1.0 or elapsed > 100.0:
		_quality_hot_msec = 0.0
		_quality_cool_msec = 0.0
		return
	_frame_avg_msec = lerpf(_frame_avg_msec, elapsed, 0.08)
	if _frame_avg_msec > 22.0:
		_quality_hot_msec += elapsed
		_quality_cool_msec = 0.0
	elif _frame_avg_msec < 17.0:
		_quality_cool_msec += elapsed
		_quality_hot_msec = 0.0
	else:
		_quality_hot_msec = 0.0
		_quality_cool_msec = 0.0
	if _detail_high and _quality_hot_msec >= 1000.0:
		_detail_high = false
		_quality_transitions += 1
	elif not _detail_high and _quality_cool_msec >= 2000.0:
		_detail_high = true
		_quality_transitions += 1

func _clock_usec() -> int:
	return Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now_usec = _clock_usec()
	_update_quality(now_usec)
	var now = now_usec / 1000
	if now >= _next_cache_prune_msec:
		_prune_scene_cache()
		_next_cache_prune_msec = now + 1000
	if _options.trail_effect == "off":
		for id in _states.keys():
			var ball = _states[id].ball.get_ref()
			if not is_instance_valid(ball) or not ball.is_inside_tree():
				_clear(_states[id], "scene")
				_states.erase(id)
		return
	var sample = now_usec >= _next_sample_usec
	if sample:
		_next_sample_usec = now_usec + SAMPLE_USEC
	_last_frame_uploads = 0
	_last_frame_geometry_usec = 0
	var ids = _states.keys()
	var next_cursor = _process_cursor
	for slot in ids.size():
		var id = ids[(slot + _process_cursor) % ids.size()]
		var state: Dictionary = _states[id]
		var ball = state.ball.get_ref()
		if not is_instance_valid(ball) or not ball.is_inside_tree() or ball.is_queued_for_deletion():
			_clear(state, "scene")
			_states.erase(id)
			continue
		var reason = _reason_inactive(ball, state)
		if reason != "":
			state.reason = reason
			_clear(state, reason)
			continue
		var camera = _camera_for(ball)
		state.reason = "camera" if camera == null else "active"
		if camera == null:
			_clear(state, "camera")
			continue
		var pos = _display_position(ball, state)
		if not pos.is_finite() or pos.length_squared() > 100000000.0:
			_clear(state, "invalid")
			continue
		var game = state.game.get_ref() if state.game is WeakRef else null
		if game != null:
			var generation = int(game.get("_match_gen"))
			var phase = int(game.get("_phase"))
			if generation != state.generation or phase != state.phase:
				_clear(state, "phase")
				if generation != state.generation:
					state.contact_seq = -1
					state.contact_at = 0
				state.generation = generation
				state.phase = phase
		var world = ball.get_world_3d().get_instance_id()
		if state.world != 0 and state.world != world:
			_clear(state, "world")
		state.world = world
		if not state.preview:
			var by = ball.get("hit_by")
			var hit_id = by.get_instance_id() if is_instance_valid(by) else 0
			if int(state.hit_by) != 0 and hit_id == 0:
				_clear(state, "recall")
			state.hit_by = hit_id
		# Accumulate displacement from the last confirmed motion, rather than
		# testing a per-frame distance (which misclassifies slow balls at 240 Hz).
		var moved = not (state.motion_anchor as Vector3).is_finite() or (state.motion_anchor as Vector3).distance_squared_to(pos) > 0.000009
		if (state.position as Vector3).is_finite() and (state.position as Vector3).distance_to(pos) > TELEPORT_DISTANCE:
			_clear(state, "teleport")
			moved = true
		if moved:
			state.last_move = now
			state.motion_anchor = pos
		state.position = pos
		state.head = pos
		state.last_frame = now
		if int(state.contact_kind) == 3 and bool(state.contact_pending):
			# Native hard hits briefly hold the ball still. Do not consume a
			# genuine strike while its hitstop is waiting to launch the flight.
			# Track actual presented displacement after native hitstop, bounded
			# by a finite timeout; never use last_hit_kind to re-arm a contact.
			if now - int(state.contact_at) >= CONTACT_TTL_MSEC:
				state.contact_kind = 0
				state.contact_pending = false
			elif float(ball.get("hitstop_left")) <= 0.0 and (state.contact_origin as Vector3).distance_squared_to(pos) > LAUNCH_MOVE_DISTANCE * LAUNCH_MOVE_DISTANCE:
				state.contact_pending = false
				state.contact_flight_at = now
		if now - int(state.last_move) > STATIONARY_MSEC:
			var motion_anchor: Vector3 = state.motion_anchor
			var waiting_launch = int(state.contact_kind) == 3 and bool(state.contact_pending) and now - int(state.contact_at) < CONTACT_TTL_MSEC
			_clear(state, "stationary", waiting_launch)
			state.position = pos
			# Keep the last confirmed motion position while stopped, so a slow
			# restart can accumulate displacement across several render frames.
			state.motion_anchor = motion_anchor
			state.head = pos
			continue
		var points: Array = state.points
		if sample:
			var measured_speed = 0.0
			if (state.sample_position as Vector3).is_finite() and now > int(state.sample_at):
				measured_speed = pos.distance_to(state.sample_position) * 1000.0 / float(now - int(state.sample_at))
			state.sample_position = pos
			state.sample_at = now
			var genuine_spike = state.preview or (int(state.contact_kind) == 3 and not bool(state.contact_pending) and now - int(state.contact_flight_at) < CONTACT_TTL_MSEC)
			state.spike = clampf(0.58 + measured_speed / 65.0, 0.58, 1.0) * clampf(0.7 + float(state.contact_power) * 0.3, 0.7, 1.0) if genuine_spike and bool(_options.spike_showcase) else 0.0
			while not points.is_empty() and now - int(points[0].stamp) > float(_options.trail_lifetime) * 1000.0:
				points.pop_front()
			if points.is_empty() or (points.back().position as Vector3).distance_squared_to(pos) > 0.000144:
				state.serial += 1
				points.append({"position": pos, "stamp": now, "serial": state.serial, "spike": state.spike})
				_sample_count += 1
			while points.size() > MAX_HISTORY:
				points.pop_front()
			state.history_dirty = true
		if points.is_empty():
			continue
		var renderer = _renderer(ball, state)
		if renderer == null:
			_clear(state, "capacity")
			continue
		if state.history_dirty and _last_frame_uploads < MAX_HISTORY_UPLOADS_PER_FRAME and _last_frame_geometry_usec < HISTORY_BUDGET_USEC:
			var began = Time.get_ticks_usec()
			renderer.draw_history(points, now, float(_options.trail_lifetime), str(_options.trail_effect), float(_options.trail_intensity), camera, _detail_high)
			_last_frame_geometry_usec += Time.get_ticks_usec() - began
			_last_frame_uploads += 1
			next_cursor = (slot + _process_cursor + 1) % ids.size()
			state.history_dirty = false
			state.history_head = points.back().position
			_rebuild_count += 1
		# A reusable three-layer ribbon follows the displayed ball by transform;
		# history/decorative geometry is still sampled/rebuilt at <= 30 Hz.
		renderer.draw_head(state.history_head if (state.history_head as Vector3).is_finite() else points.back().position, pos, str(_options.trail_effect), float(_options.trail_intensity), camera, float(state.spike))

	# Round-robin fairness spreads a practice court full of balls over frames.
	# Live heads still follow every rendered frame while old history uploads wait.
	if not ids.is_empty(): _process_cursor = next_cursor

func get_diagnostics() -> Dictionary:
	var states: Array = []
	var max_points = 0
	var total_points = 0
	for id in _states:
		var state: Dictionary = _states[id]
		var ball = state.ball.get_ref()
		var renderer = state.renderer.get_ref() if state.renderer is WeakRef else null
		var count = state.points.size() + (1 if not state.points.is_empty() else 0)
		max_points = maxi(max_points, count)
		total_points += count
		states.append({"id": id, "preview": state.preview, "point_count": count, "history_count": state.points.size(), "head_position": state.head, "center_source": state.center_source, "reason": state.reason, "renderer": is_instance_valid(renderer), "top_level": renderer.top_level if is_instance_valid(renderer) else false, "same_world": is_instance_valid(ball) and is_instance_valid(renderer) and ball.get_world_3d() == renderer.get_world_3d(), "spike": state.spike, "contact_pending": state.contact_pending, "history_pending": state.history_dirty, "contact_kind": state.contact_kind, "triangles": renderer.triangles if is_instance_valid(renderer) else 0, "history_uploads": renderer.history_uploads if is_instance_valid(renderer) else 0, "head_mesh_builds": renderer.head_mesh_builds if is_instance_valid(renderer) else 0, "head_transforms": renderer.head_transforms if is_instance_valid(renderer) else 0})
	return {"history_upload_limit": MAX_HISTORY_UPLOADS_PER_FRAME, "last_frame_uploads": _last_frame_uploads, "last_frame_geometry_usec": _last_frame_geometry_usec, "effect": _options.trail_effect, "spike_showcase": _options.spike_showcase, "effect_quality": _options.effect_quality, "detail": "high" if _detail_high else "low", "frame_average_msec": _frame_avg_msec, "quality_transitions": _quality_transitions, "preview_only": preview_only, "tracked_balls": _states.size(), "active_trails": _renderer_count(), "total_points": total_points, "max_points": max_points, "samples": _sample_count, "history_rebuilds": _rebuild_count, "clears": _clears.duplicate(), "states": states}

func debug_snapshot() -> Dictionary:
	return get_diagnostics()

func _exit_tree() -> void:
	for state in _states.values():
		_clear(state, "manager_exit")
