extends CharacterBody3D
## John's red BMW M1. Arcade "bicycle model" handling ported from the web build:
## throttle / brake / reverse, speed-sensitive steering, handbrake slides, drunk steering
## wobble, crash bumps, headlights and brake lights. Collision uses Godot physics (a box body
## sliding against the world), and the ride height follows the ground under the car.

const WHEELBASE := 2.56
const VMAX := 33.0
const VMAX_BOOST := 40.0
const HOME_PHI := PI / 3
const OUT_C := Vector2(0.9, -26.0)
const OUTG := -0.45

var v := 0.0          # forward speed (m/s)
var h := 0.0          # heading (radians, 0 = +Z)
var steer := 0.0
var ride_y := OUTG + 0.04
var hit_t := 0.0
var shake_t := 0.0
var yaw_rate := 0.0
var braking := false
var wheels := []      # {steer: Node3D, spin: Node3D, front: bool}
var head_lights: Array[SpotLight3D] = []
var tail_mats: Array[StandardMaterial3D] = []
var head_mats: Array[StandardMaterial3D] = []
var model: Node3D
var lid: Node3D
var home := Transform3D()
signal crashed(strength: float)

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(1.94, 0.95, 4.4)
	col.shape = box; col.position = Vector3(0, 0.78, 0); add_child(col)
	_build_model()
	var hx := OUT_C.x + cos(HOME_PHI) * 8.9; var hz := OUT_C.y + sin(HOME_PHI) * 8.9
	home = Transform3D(Basis(Vector3.UP, atan2(-sin(HOME_PHI), cos(HOME_PHI))), Vector3(hx, OUTG + 0.04, hz))
	park()

func _build_model() -> void:
	model = (load("res://assets/cars/m1.glb") as PackedScene).instantiate()
	add_child(model)
	var red := StandardMaterial3D.new()
	red.albedo_texture = load("res://assets/cars/m1_ext_red.jpg"); red.metallic = 0.3; red.roughness = 0.3
	red.clearcoat_enabled = true; red.clearcoat = 1.0; red.clearcoat_roughness = 0.05
	var glass := StandardMaterial3D.new(); glass.albedo_color = Color(0.043, 0.059, 0.082, 0.62); glass.metallic = 0.2; glass.roughness = 0.03
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var nm := String(mi.name)
		for s in mi.mesh.get_surface_count():
			var mt: Material = mi.mesh.surface_get_material(s)
			var mn: String = mt.resource_name if mt else ""
			if mn.ends_with("mm_ext"): mi.set_surface_override_material(s, red)
			elif mn.ends_with("mm_windows") and not nm.contains("HEADLIGHT"): mi.set_surface_override_material(s, glass)
			elif mn.ends_with("mm_lights") and mt is StandardMaterial3D:
				var tail := nm.contains("TAILLIGHT") or nm.contains("BRAKES") or nm.contains("BODY_mm_lights") or nm.contains("BOOT_mm_lights")
				var head := nm.contains("HEADLIGHT") or nm.contains("FRONTBUMPER")
				if tail or head:
					var c: StandardMaterial3D = mt.duplicate()
					c.emission_enabled = true; c.emission_texture = (mt as StandardMaterial3D).albedo_texture
					c.emission = Color(1, 0.08, 0.03) if tail else Color(1, 0.95, 0.86)
					c.emission_energy_multiplier = 0.25 if tail else 0.0
					mi.set_surface_override_material(s, c)
					(tail_mats if tail else head_mats).append(c)
	# wheels: each ROTOR mesh gets a steer pivot and a spin pivot
	for n in model.get_children():
		if not String(n.name).begins_with("LOD_A_ROTOR"): continue
		var p: Vector3 = n.position
		var sp := Node3D.new(); sp.position = p; model.add_child(sp)
		var spin := Node3D.new(); sp.add_child(spin)
		n.get_parent().remove_child(n); spin.add_child(n); n.position = Vector3.ZERO
		wheels.append({steer = sp, spin = spin, front = p.z > 0})
	# boot lid pivot (for the trunk in stage 6)
	lid = Node3D.new(); lid.position = Vector3(0, 1.12, -0.6); model.add_child(lid)
	for n in model.get_children():
		if String(n.name).begins_with("LOD_A_BOOT"):
			var gt: Transform3D = n.transform
			model.remove_child(n); lid.add_child(n); n.transform = lid.transform.affine_inverse() * gt
	# headlight beams
	for s in [-1.0, 1.0]:
		var l := SpotLight3D.new(); l.light_color = Color(1, 0.94, 0.85); l.light_energy = 0.0
		l.spot_range = 34.0; l.spot_angle = 24.0; l.spot_attenuation = 1.1; l.shadow_enabled = true
		l.position = Vector3(s * 0.62, 0.6, 2.15)
		add_child(l); l.look_at_from_position(l.position, Vector3(s * 0.9, 0, 12), Vector3.UP)
		head_lights.append(l)

func park() -> void:
	global_transform = home; h = home.basis.get_euler().y; v = 0; steer = 0; ride_y = home.origin.y
	set_lights(false); brake_lights(0.0)

func set_lights(on: bool) -> void:
	for l in head_lights: l.light_energy = 7.0 if on else 0.0
	for m in head_mats: m.emission_energy_multiplier = 1.6 if on else 0.0

func brake_lights(k: float) -> void:
	for m in tail_mats: m.emission_energy_multiplier = 0.25 + 1.6 * k

## one physics step. inputs: throttle (1 fwd, -1 reverse), brake, steer (-1..1, +1 = left), handbrake
func drive(dt: float, driving: bool, thr_in: float, back_in: float, steer_in: float, handbrake: bool, drunk: float, boost: bool, clock: float) -> void:
	var thr := 0.0; var brk := 0.0
	if driving:
		thr = thr_in
		if back_in > 0:
			if v > 0.5: brk = 1.0
			else: thr = -1.0
	var wobble := (sin(clock * 1.3) * 0.5 + sin(clock * 3.1) * 0.3) * 0.11 * drunk if driving else 0.0
	var max_steer := 0.6 / (1.0 + v * v / 260.0)
	steer = lerp(steer, steer_in * max_steer + wobble, 1.0 - exp(-dt * (7.0 - 4.0 * drunk)))
	var vmax := VMAX_BOOST if boost else VMAX
	if thr > 0: v += (16.0 if v < 0 else 9.5 * (1.0 - max(0.0, v) / vmax)) * dt
	elif thr < 0: v -= (14.0 if v > 0 else 5.0) * dt; v = max(v, -8.0)
	if brk > 0: v -= sign(v) * min(abs(v), 15.0 * dt)
	if thr == 0 and brk == 0: v -= sign(v) * min(abs(v), (1.4 + 0.04 * v * v) * dt)
	if driving and handbrake: v -= sign(v) * min(abs(v), 7.0 * dt)
	yaw_rate = v * tan(steer) / WHEELBASE * (1.7 if (driving and handbrake) else 1.0)
	h += yaw_rate * dt
	# move with physics; any contact is a crash
	var fwd := Vector3(sin(h), 0, cos(h))
	var before := global_position
	velocity = fwd * v
	rotation = Vector3(0, h, 0)
	if abs(v) > 0.01 or driving:
		move_and_slide()
		if get_slide_collision_count() > 0:
			var sp: float = abs(v)
			if sp > 3 and hit_t <= 0:
				crashed.emit(min(1.0, sp / 25.0)); shake_t = min(0.5, sp / 40.0); hit_t = 0.4
			# lose speed according to how much the body was stopped
			var moved := (global_position - before).dot(fwd)
			var expected := v * dt
			if abs(expected) > 1e-4 and moved / expected < 0.6:
				v *= -0.25 if sp > 2 else 0.5
	hit_t = max(0.0, hit_t - dt); shake_t = max(0.0, shake_t - dt)
	# ride height follows the ground
	var gy := _ground()
	ride_y = lerp(ride_y, gy - 0.01, 1.0 - exp(-dt * 12))
	global_position.y = ride_y
	model.rotation = Vector3((0.022 if brk > 0 else 0.0) * sign(v) - (0.012 if thr > 0 else 0.0), 0, -yaw_rate * 0.02 * min(1.0, abs(v) / 10.0))
	for w in wheels:
		w.spin.rotation.x += v * dt / 0.3
		w.steer.rotation.y = steer if w.front else 0.0
	braking = brk > 0 or (driving and handbrake)
	brake_lights(1.0 if braking else 0.0)

func _ground() -> float:
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 1.5, p.z), Vector3(p.x, p.y - 4.0, p.z))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else ride_y + 0.01

## local point (car space) -> world
func to_world(local: Vector3) -> Vector3: return global_transform * local
