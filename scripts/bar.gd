extends Node
## The dive bar down the street (v2.14).
##
## The building is assets/bar/Bar.glb (the supplied facade, finished on all sides by
## tools/build_bar.py); the room inside is assets/bar/BarInterior.glb, modelled in Blender by
## tools/blender_bar_interior.py in the same frame, so it sits in the shell with no offset.
## This module swings the front door open and shut with E, lights the room (pendants, the pool
## table lamp, neon) and gives the lamps that sit by the walls shadows so no light bleeds through
## the brick in either direction.
## Positions are in the bar's own frame: x across the front, y up, z from the street front (0)
## to the back wall (9.6); the street side is -z.

const DOOR_OPEN := 1.42            # radians the door swings in
const SPEED := 3.5

var g: Node
var bar: Node3D
var door: Node3D
var door_rest := 0.0
var open := 0.0
var target := 0.0
var door_shapes: Array[CollisionShape3D] = []
var lights: Array[Light3D] = []
var lit := true

# [kind, bar-local position, colour, energy, range, shadow]
const LIGHTS := [
	["omni", Vector3(-3.5, 1.84, 0.6), Color(1.0, 0.7, 0.4), 2.2, 4.5, true],     # pendants over the bar
	["omni", Vector3(-3.5, 1.84, 2.7), Color(1.0, 0.7, 0.4), 2.2, 4.5, false],
	["omni", Vector3(-3.5, 1.84, 4.8), Color(1.0, 0.7, 0.4), 2.2, 4.5, false],
	["spot", Vector3(0.55, 1.68, 5.0), Color(1.0, 0.86, 0.62), 5.0, 3.2, false],   # pool table lamp
	["omni", Vector3(0.55, 1.95, 5.0), Color(0.6, 0.9, 0.6), 0.35, 3.0, false],   # its green shade glow
	["omni", Vector3(-1.9, 1.6, 8.75), Color(1.0, 0.68, 0.38), 1.8, 3.4, false],  # booth pendants
	["omni", Vector3(-0.25, 1.6, 8.75), Color(1.0, 0.68, 0.38), 1.8, 3.4, false],
	["omni", Vector3(1.4, 1.6, 8.75), Color(1.0, 0.68, 0.38), 1.8, 3.4, false],
	["omni", Vector3(-4.9, 2.7, 2.7), Color(1.0, 0.55, 0.15), 1.4, 3.6, false],   # Lumberjack neon
	["omni", Vector3(4.9, 2.4, 5.3), Color(0.3, 0.6, 1.0), 1.2, 3.2, false],      # COLD BEER neon
	["omni", Vector3(-0.25, 2.35, 9.0), Color(1.0, 0.3, 0.85), 1.0, 3.0, false],  # Cocktails neon
	["omni", Vector3(-0.13, 2.7, 0.55), Color(1.0, 0.15, 0.3), 0.8, 2.6, true],   # OPEN neon by the door
	["omni", Vector3(3.0, 1.0, 4.95), Color(1.0, 0.55, 0.3), 0.6, 2.2, false],    # jukebox
	["omni", Vector3(1.3, 2.9, 2.0), Color(1.0, 0.75, 0.5), 0.7, 5.0, true],      # room fill by the door
	["omni", Vector3(-1.0, 3.1, 5.6), Color(1.0, 0.72, 0.45), 0.8, 5.5, false],   # room fill, middle
	["omni", Vector3(-3.6, 3.1, 2.4), Color(1.0, 0.72, 0.45), 0.6, 4.0, false],   # over the bar
	["omni", Vector3(2.8, 2.8, 6.6), Color(1.0, 0.72, 0.45), 0.5, 3.5, false],    # by the back door
]
# materials that glow, and how much
const GLOW := {"Neon_": 1.1, "Bar_Bulb": 1.5, "Bar_LampDiffuser": 1.0, "Bar_TVScreen": 1.2, "Bar_JukeboxFront": 1.6, "Bar_ExitSign": 2.0, "Bar_CoolerGlass": 0.35}

func setup(game: Node) -> void:
	g = game
	bar = g.world.get_node_or_null("JBR_Bar")
	if bar == null: return
	door = bar.find_child("BarDoor", true, false)
	if door:
		door_rest = door.rotation.y
		for s in door.find_children("*", "CollisionShape3D", true, false): door_shapes.append(s)
	for l in LIGHTS:
		var L: Light3D
		if l[0] == "spot":
			var sp := SpotLight3D.new(); sp.spot_range = l[4]; sp.spot_angle = 52.0; sp.spot_attenuation = 0.6
			sp.rotation = Vector3(-PI / 2, 0, 0); L = sp
		else:
			var om := OmniLight3D.new(); om.omni_range = l[4]; om.omni_attenuation = 1.1; L = om
		L.position = l[1]; L.light_color = l[2]; L.light_energy = l[3]; L.shadow_enabled = l[5]
		L.name = "BarLight%d" % lights.size()
		bar.add_child(L); lights.append(L)
	# the street lamps on the bar's own walls light through the brick without shadows
	for k in ["Neon", "FrontLamp", "BackLamp"]:
		var l: Light3D = bar.get_node_or_null(k)
		if l: l.shadow_enabled = true
	var inter := bar.find_child("BarInterior", true, false)
	if inter:
		for mi: MeshInstance3D in inter.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if not (m is BaseMaterial3D): continue
				for key in GLOW:
					if String(m.resource_name).begins_with(key):
						m.emission_enabled = true; m.emission_energy_multiplier = GLOW[key]

func reset() -> void:
	open = 0.0; target = 0.0
	_apply_door()

## John in the bar's frame
func local(p: Vector3) -> Vector3: return bar.to_local(p) if bar else Vector3(1e9, 0, 1e9)
func jl() -> Vector3: return local(g.john.global_position)

func inside() -> bool:
	var p := jl()
	if p.y < -1.0 or p.y > 3.0 or abs(p.x) > 5.4 or p.z > 9.45: return false
	return p.z > 0.02 or (p.x < -2.57 and p.z > -1.25)

func near_door() -> bool:
	if door == null: return false
	var p := jl()
	return p.x > -1.25 and p.x < 0.95 and p.z > -1.5 and p.z < 1.25 and abs(p.y) < 1.5

## the space the door sweeps through as it swings in
func in_swing() -> bool:
	var p := jl()
	return p.x > -0.75 and p.x < 0.45 and p.z > -0.1 and p.z < 1.0

## keep the camera in the room while John is inside (the open door would let it out to the street)
func clamp_cam(p: Vector3) -> Vector3:
	var l := local(p)
	l.x = clamp(l.x, -5.15, 5.15); l.y = clamp(l.y, 0.35, 3.3)
	l.z = clamp(l.z, -1.0 if l.x < -2.8 else 0.45, 9.2)
	return bar.to_global(l)

func interact() -> bool:
	if not near_door(): return false
	if target > 0 and in_swing():
		g.say("Gotta get out of the doorway first.", 1.8); return true
	target = 0.0 if target > 0 else 1.0
	Sfx.play("creak")
	if target == 0: Sfx.play("thunk")
	return true

func prompt() -> Array:
	if not near_door(): return []
	if target > 0: return ["Close the door", true]
	return ["Go into the bar" if not inside() else "Open the door", true]

func update(dt: float) -> void:
	if bar == null: return
	var was := open
	open = lerp(open, target, 1.0 - exp(-dt * SPEED))
	if abs(open - target) < 0.002: open = target
	if open != was: _apply_door()
	# lights only near the bar (the room has no windows)
	var want: bool = g.john.global_position.distance_to(bar.global_position + bar.global_basis * Vector3(0, 0, 4.8)) < 22.0
	if want != lit:
		lit = want
		for l in lights: l.visible = lit

func _apply_door() -> void:
	if door == null: return
	door.rotation.y = door_rest + open * DOOR_OPEN
	# a moving door would shove John about: it only blocks while it is shut (or all the way open)
	var solid := open < 0.03 or open > 0.97
	for s in door_shapes: s.set_deferred("disabled", not solid)
