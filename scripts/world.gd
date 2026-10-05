extends Node3D
## Loads the exported world (cabin, cul-de-sac, town, fuel stop, terrain), gives every
## solid mesh a collision body, tunes the imported lights and spawns John in his cabin.

const WORLD := ["JBR_Terrain", "JBR_Cabin", "JBR_Neighborhood", "JBR_Town", "JBR_FuelStop", "JBR_Bar"]
const SPAWN := Vector3(-2.0, 0.05, 1.85)
const LIGHT_SCALE := 0.9           # three.js intensities -> Godot energy (Godot omni falloff is steeper)
const MIN_COLLIDE := 0.18          # skip collision on tiny props (cans, bottles, products)

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var shapes := 0
	for n in WORLD:
		var inst := get_node_or_null(n)          # placed in main.tscn so it shows in the editor
		if inst == null:
			var ps: PackedScene = load("res://assets/world/%s.glb" % n)
			if ps == null:
				push_warning("missing world chunk " + n); continue
			inst = ps.instantiate(); inst.name = n; add_child(inst)
		shapes += _prepare(inst)
	_add_streetlights()
	print("[world] loaded %d chunks, %d collision shapes in %d ms" % [WORLD.size(), shapes, Time.get_ticks_msec() - t0])

func _prepare(root: Node) -> int:
	var count := 0
	for l: Light3D in root.find_children("*", "Light3D", true, false):
		l.light_energy *= LIGHT_SCALE
		l.shadow_enabled = l is DirectionalLight3D or root.name == "JBR_Cabin"
		if l is OmniLight3D:
			if l.omni_range <= 0.01: l.omni_range = 12.0
			l.omni_range *= 1.35          # reach further so rooms fill instead of pooling
			l.omni_attenuation = 0.8
		if l is SpotLight3D: l.spot_range *= 1.3
		if l is DirectionalLight3D: l.light_energy = 0.75; l.light_color = Color(0.62, 0.7, 1.0); l.directional_shadow_max_distance = 90.0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree(): continue
		var nm := String(mi.name).to_lower()
		if nm.contains("baked") or nm.contains("glow") or nm.contains("sprite") or nm.contains("can"): continue
		if _under(mi, "JBR_Bong") or _under(mi, "JBR_PowderLine") or _under(mi, "JBR_TableBill") or _under(mi, "JBR_TVScreen"): continue
		if _unlit(mi):
			_make_additive(mi)   # three.js glow sprites lose additive blending in glTF
			continue
		var sz := mi.get_aabb().size * mi.global_transform.basis.get_scale()
		if max(sz.x, max(sz.y, sz.z)) < MIN_COLLIDE: continue
		mi.create_trimesh_collision()
		count += 1
	return count

func _make_additive(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m is BaseMaterial3D:
			m = m.duplicate()
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.no_depth_test = false
			mi.set_surface_override_material(s, m)

func _unlit(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m is BaseMaterial3D and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false

func _under(node: Node, prefix: String) -> bool:
	var x := node
	while x and x != self:
		if String(x.name).begins_with(prefix): return true
		x = x.get_parent()
	return false

# ------------------------------------------------------------------ street lighting
## The web build lit only 3 of its 8 street lamps (WebGL light budget) and faked the rest with
## glow sprites. Here every lamp gets a real downward sodium spotlight with shadows, a soft
## fill light and a glow halo, replacing the 3 exported point lights.
const OUT_C := Vector2(0.9, -26.0)
const OUT_R := 10.0
const OUT_HALF := 4.0
const OUTG := -0.45
const LAMP_COLOR := Color(1.0, 0.75, 0.47)

func lamp_heads() -> Array[Vector3]:
	var heads: Array[Vector3] = []
	for deg in [-112.0, 165.0, 55.0]:          # cul-de-sac
		var phi := deg_to_rad(deg); var r := OUT_R + 1.95
		var x := OUT_C.x + cos(phi) * r; var z := OUT_C.y + sin(phi) * r
		heads.append(Vector3(x - cos(phi) * 1.3, OUTG + 4.97, z - sin(phi) * 1.3))
	for xs in [[-44.0, 1.0], [-60.0, -1.0], [-78.0, 1.0], [-96.0, -1.0], [-104.0, 1.0]]:   # Main Street
		var z: float = OUT_C.y + xs[1] * (OUT_HALF + 1.95)
		heads.append(Vector3(xs[0], OUTG + 4.97, z - xs[1] * 1.3))
	return heads

func _add_streetlights() -> void:
	var heads := lamp_heads()
	var placed := get_node_or_null("Streetlights")    # lamps placed in the editor: move or duplicate them freely
	if placed:
		heads.clear()
		for lamp in placed.get_children(): heads.append((lamp as Node3D).global_position)
	# retire the exported lamp lights (they sat right under these heads)
	for l: Light3D in find_children("*", "OmniLight3D", true, false):
		for h in heads:
			if l.global_position.distance_to(h) < 1.2: l.visible = false
	var glow_tex: Texture2D = load("res://assets/fx/glow_add.png")
	var glow_mat := StandardMaterial3D.new(); glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glow_mat.albedo_texture = glow_tex; glow_mat.albedo_color = Color(0.75, 0.56, 0.32)
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; glow_mat.no_depth_test = false
	var glow_mesh := QuadMesh.new(); glow_mesh.size = Vector2(2.4, 2.4)
	if placed: return
	for h in heads:
		var spot := SpotLight3D.new(); spot.name = "StreetLamp"
		spot.light_color = LAMP_COLOR; spot.light_energy = 14.0
		spot.spot_range = 18.0; spot.spot_angle = 68.0; spot.spot_attenuation = 0.9; spot.spot_angle_attenuation = 0.6
		spot.shadow_enabled = true; spot.shadow_blur = 1.5
		add_child(spot); spot.global_position = h + Vector3(0, -0.1, 0)
		spot.rotation = Vector3(-PI / 2, 0, 0)     # point straight down
		var fill := OmniLight3D.new(); fill.light_color = LAMP_COLOR; fill.light_energy = 1.3; fill.omni_range = 13.0
		fill.omni_attenuation = 1.2; add_child(fill); fill.global_position = h + Vector3(0, -0.6, 0)
		var g := MeshInstance3D.new(); g.mesh = glow_mesh; g.material_override = glow_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g); g.global_position = h + Vector3(0, -0.07, 0)
