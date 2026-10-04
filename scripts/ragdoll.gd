extends RefCounted
class_name Ragdoll
## Turns one of the procedural "visitor" rigs (the clerk, the officers) into a physics ragdoll:
## each body part becomes a RigidBody3D with a capsule collider, joined by cone-twist joints,
## and the part's meshes are moved onto it. Replaces the web build's scripted fall.

const LAYER := 2          # ragdoll parts live on layer 2 and collide with the world (layer 1) only

# body -> [anchor joint, joints whose direct meshes ride on it, segment end joint (or "" + fixed vector), radius, mass]
const PARTS := {
	torso = ["spine", ["hips", "spine", "chest"], "neck", 0.2, 30.0],
	head = ["neck", ["neck", "head"], "", 0.12, 5.0],
	thighL = ["thighL", ["thighL"], "kneeL", 0.085, 8.0],
	thighR = ["thighR", ["thighR"], "kneeR", 0.085, 8.0],
	shinL = ["kneeL", ["kneeL", "ankleL"], "ankleL", 0.07, 5.0],
	shinR = ["kneeR", ["kneeR", "ankleR"], "ankleR", 0.07, 5.0],
	armL = ["shL", ["shL"], "elL", 0.065, 3.0],
	armR = ["shR", ["shR"], "elR", 0.065, 3.0],
	foreL = ["elL", ["elL", "wrL"], "wrL", 0.055, 2.0],
	foreR = ["elR", ["elR", "wrR"], "wrR", 0.055, 2.0],
}
# child body -> [parent body, joint at, swing limit (deg), twist limit (deg)]
const LINKS := {
	head = ["torso", "neck", 40.0, 30.0],
	thighL = ["torso", "thighL", 70.0, 20.0], thighR = ["torso", "thighR", 70.0, 20.0],
	shinL = ["thighL", "kneeL", 75.0, 5.0], shinR = ["thighR", "kneeR", 75.0, 5.0],
	armL = ["torso", "shL", 95.0, 40.0], armR = ["torso", "shR", 95.0, 40.0],
	foreL = ["armL", "elL", 80.0, 10.0], foreR = ["armR", "elR", 80.0, 10.0],
}

## J: joint name -> Node3D (from visitor.gd). Returns the bodies by name.
static func build(parent: Node, J: Dictionary, hit_part: String, impulse: Vector3) -> Dictionary:
	var bodies := {}
	var jpos := {}
	for k in J: jpos[k] = (J[k] as Node3D).global_position
	for part in PARTS:
		var d: Array = PARTS[part]
		var anchor: Node3D = J.get(d[0])
		if anchor == null: continue
		var body := RigidBody3D.new(); body.name = "Rag_" + part
		body.collision_layer = 1 << (LAYER - 1); body.collision_mask = 1
		body.mass = d[4]; body.linear_damp = 0.15; body.angular_damp = 1.2
		body.continuous_cd = true
		parent.add_child(body)
		body.global_transform = Transform3D(anchor.global_transform.basis.orthonormalized(), anchor.global_position)
		# move the part's meshes onto the body (whole subtree for the hands)
		for jn in d[1]:
			var j: Node3D = J.get(jn)
			if j == null: continue
			var movers := []
			for c in j.get_children():
				if c is MeshInstance3D: movers.append(c)
				elif jn.begins_with("wr") and c is Node3D: movers.append(c)   # fingers + thumb groups
			for m in movers:
				var gt: Transform3D = m.global_transform
				m.get_parent().remove_child(m); body.add_child(m); m.global_transform = gt
		# capsule along the segment
		var a: Vector3 = jpos[d[0]]
		var b: Vector3
		if d[2] != "" and jpos.has(d[2]): b = jpos[d[2]]
		elif part == "head": b = a + anchor.global_transform.basis.y.normalized() * 0.3
		else: b = a + Vector3(0, -0.3, 0)
		if part == "torso": a = jpos.get("hips", a) - anchor.global_transform.basis.y.normalized() * 0.12
		if part.begins_with("fore"): b = b + (b - a).normalized() * 0.12
		var r: float = d[3]
		var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
		var seg := b - a; var length: float = max(seg.length(), 0.05)
		cap.radius = r; cap.height = length + 2 * r
		cs.shape = cap; body.add_child(cs)
		var y := seg.normalized(); var x := y.cross(Vector3.FORWARD if abs(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		cs.global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
		bodies[part] = body
	for child in LINKS:
		if not bodies.has(child) or not bodies.has(LINKS[child][0]): continue
		var l: Array = LINKS[child]
		var jt := ConeTwistJoint3D.new()
		parent.add_child(jt)
		var at: Vector3 = jpos.get(l[1], bodies[child].global_position)
		var dir: Vector3 = (bodies[child].global_position - at)
		var seg_dir := Vector3.DOWN
		for cs in bodies[child].get_children():
			if cs is CollisionShape3D: seg_dir = (cs.global_position - at).normalized()
		if seg_dir.length_squared() < 0.5: seg_dir = Vector3.DOWN
		var xax := seg_dir; var yax := xax.cross(Vector3.UP if abs(xax.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).normalized()
		jt.global_transform = Transform3D(Basis(xax, yax, xax.cross(yax)), at)
		jt.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(l[2]))
		jt.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(l[3]))
		jt.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
		jt.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.6)
		jt.node_a = jt.get_path_to(bodies[l[0]]); jt.node_b = jt.get_path_to(bodies[child])
	# the shot: everything lurches with it, the part that was hit takes the impulse
	for p in bodies: (bodies[p] as RigidBody3D).linear_velocity = impulse.normalized() * 0.6
	var hb: RigidBody3D = bodies.get(hit_part, bodies.get("torso"))
	if hb: hb.apply_central_impulse(impulse)
	return bodies
