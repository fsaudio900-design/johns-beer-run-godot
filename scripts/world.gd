extends Node3D
## Loads the exported world (cabin, cul-de-sac, town, fuel stop, terrain), gives every
## solid mesh a collision body, tunes the imported lights and spawns John in his cabin.

const WORLD := ["JBR_Terrain", "JBR_Cabin", "JBR_Neighborhood", "JBR_Town", "JBR_FuelStop"]
const SPAWN := Vector3(-2.0, 0.05, 1.85)
const LIGHT_SCALE := 0.9           # three.js intensities -> Godot energy (Godot omni falloff is steeper)
const MIN_COLLIDE := 0.18          # skip collision on tiny props (cans, bottles, products)

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var shapes := 0
	for n in WORLD:
		var ps: PackedScene = load("res://assets/world/%s.glb" % n)
		if ps == null:
			push_warning("missing world chunk " + n); continue
		var inst := ps.instantiate()
		inst.name = n
		add_child(inst)
		shapes += _prepare(inst)
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
		if l is DirectionalLight3D: l.light_energy = 0.45; l.directional_shadow_max_distance = 80.0
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
