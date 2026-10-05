extends Node
## Ben, John's neighbour across the cul-de-sac (v2.16).
##
## John knocks on Ben's front door with E. Ben opens it and steps out onto the step. With E
## again John talks to him, and Ben gives him a job: rob the Fuel Stop and bring him the money.
## Once John has the till's cash, he can hand it over at Ben's door for a cut.
##
## Model: assets/chars/Ben.glb (rigged and animated in Blender: Idle, Walk, Talk, LookAround,
## Laugh, Nod, ShakeHead, Shrug).

const DOOR_HINGE := Vector3(0.4, -0.35, -44.47)   # Ben's front door (in the neighbourhood model)
const STEP := Vector3(0.9, -0.29, -43.95)         # where Ben stands when he answers
const HALL := Vector3(0.9, -0.29, -45.3)          # just inside
const KNOCK_SPOT := Vector2(0.9, -43.1)           # John at the door
const LOOPS := ["Idle", "Walk", "Talk", "LookAround"]

var g: Node
var ben: Node3D
var anim: AnimationPlayer
var door: Node3D                 # pivot the door panel hangs on
var door_open := 0.0
var door_target := 0.0
var st := "inside"               # inside | coming | door | talking | going
var t := 0.0
var away_t := 0.0
var mission := "none"            # none | rob | done
var owed := 0.0                  # the haul John should bring back
var visits := 0
var lines: Array = []
var line_t := 0.0
var line_i := 0

func setup(game: Node) -> void:
	g = game
	var ps: PackedScene = load("res://assets/chars/Ben.glb")
	ben = ps.instantiate(); ben.name = "Ben"; g.add_child(ben)
	ben.global_position = HALL; ben.visible = false
	anim = ben.find_child("*", true, false) as AnimationPlayer
	for a in ben.find_children("*", "AnimationPlayer", true, false): anim = a
	if anim:
		for n in LOOPS:
			if anim.has_animation(n): anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for mi: MeshInstance3D in ben.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_hang_door()

## the door panel is part of the neighbourhood model: hang it on a pivot at its hinge and put a
## dim hallway behind it so the open doorway shows a room, not the sky
func _hang_door() -> void:
	var nb: Node = g.world.get_node_or_null("JBR_Neighborhood")
	if nb == null: return
	var panel: MeshInstance3D = null
	for mi: MeshInstance3D in nb.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.position.distance_to(Vector3(0.4, -0.35, -44.51)) < 0.06 and abs(b.size.x - 1.0) < 0.05 and abs(b.size.y - 2.1) < 0.05:
			panel = mi; break
	if panel == null: push_warning("[ben] front door not found"); return
	door = Node3D.new(); door.name = "BenDoorPivot"; nb.add_child(door); door.global_position = DOOR_HINGE
	panel.reparent(door, true)
	var hall := MeshInstance3D.new(); hall.name = "BenHall"
	var bm := BoxMesh.new(); bm.size = Vector3(1.05, 2.15, 1.6); bm.flip_faces = true; hall.mesh = bm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.32, 0.26, 0.2); m.roughness = 0.9; hall.material_override = m
	nb.add_child(hall); hall.global_position = Vector3(0.9, 0.72, -45.33)
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.78, 0.5); l.light_energy = 0.9; l.omni_range = 2.6
	nb.add_child(l); l.global_position = Vector3(0.9, 1.6, -45.6)

func reset() -> void:
	st = "inside"; t = 0.0; mission = "none"; owed = 0.0; visits = 0; lines = []
	door_target = 0.0; door_open = 0.0
	if ben: ben.visible = false; ben.global_position = HALL
	_apply_door()

# ------------------------------------------------------------------ helpers
func _play(n: String, blend := 0.25) -> void:
	if anim and anim.has_animation(n) and anim.current_animation != n: anim.play(n, blend)
func b_say(text: String, secs := 3.0) -> void: g.hud.say("Ben", text, secs)
func jpos() -> Vector2: return Vector2(g.john.global_position.x, g.john.global_position.z)
func at_door() -> bool: return jpos().distance_to(KNOCK_SPOT) < 1.5 and g.state == "walking"
func can_pay() -> bool: return mission == "rob" and owed > 0.0

## what Ben is waiting for, shown when nothing else is in reach
func hint() -> String:
	if mission == "rob" and owed <= 0.0: return "Ben's job: rob the Fuel Stop on Main Street"
	if mission == "rob": return "Bring the money to Ben, across the street"
	return ""

func prompt() -> Array:
	if not at_door(): return []
	match st:
		"inside": return ["Knock on Ben's door", true]
		"door":
			if can_pay(): return ["Give Ben the money (%s)" % g.store.money(min(owed, g.store.cash)), true]
			return ["Talk to Ben", true]
	return []

func interact() -> bool:
	if not at_door(): return false
	if st == "inside":
		Sfx.play("knock"); g.say("Ben! You home?" if visits == 0 else "Ben, it's me.", 1.8)
		if g.police and g.police.hostile:
			st = "going"; t = 0.0
			get_tree().create_timer(1.6).timeout.connect(func(): b_say("Go away, John! The cops are all over you!", 2.6); st = "inside")
			return true
		st = "coming"; t = 0.0
		return true
	if st == "door":
		if can_pay(): _pay()
		else: _talk()
		return true
	if st == "talking": line_t = min(line_t, 0.05); return true      # E skips to the next line
	return st == "coming"

# ------------------------------------------------------------------ the conversations
func _talk() -> void:
	var slur: bool = g.beers >= 3
	match mission:
		"none":
			lines = [["B", "Actually, glad you came by. I've got a job for you.", "Talk"],
				["J", "A job? Whash kind of job?" if slur else "A job? What kind of job?"],
				["B", "The Fuel Stop on Main Street. That register's full this time of night.", "Talk"],
				["J", "You want me to rob the gash station?" if slur else "You want me to rob the gas station?"],
				["B", "Just bring me the money. All of it. I'll make it worth your while.", "Nod"],
				["J", "...Fine. I'll be back."],
				["B", "Don't keep me waiting.", "Idle", "rob"]]
			if g.store.rob.till == false and g.store.haul > 0.0:
				lines[5] = ["J", "Funny you should say that. Already did it."]
				lines[6] = ["B", "Ha! Then hand it over.", "Laugh", "rob_done"]
		"rob":
			lines = [["B", ["The register isn't going to empty itself, John.", "Fuel Stop. Register. Money. Go.", "Why are you still standing here?"].pick_random(), "Shrug"]]
		"done":
			lines = [["B", ["Lay low for a while, John.", "We're square. Go home.", "Nice doing business with you."].pick_random(), "Nod"]]
	_start_lines()

func _pay() -> void:
	var give: float = min(owed, g.store.cash)
	var cut: float = round(give * 0.25)
	g.store.add_cash(-give)
	lines = [["J", "Here. All of it."],
		["B", "Ha! Look at that!", "Laugh"],
		["B", "Here's your cut. Now get lost before the cops come knocking.", "Talk", "paid", cut]]
	if give < owed * 0.6: lines[1] = ["B", "That's it? Where's the rest of it?", "ShakeHead"]
	mission = "done"; owed = 0.0
	_start_lines()

func _start_lines() -> void:
	st = "talking"; line_i = 0; line_t = 0.0
	g.set_state("busy")
	g.hud.prompt("")
	_next_line()

func _next_line() -> void:
	if line_i >= lines.size():
		st = "door"; t = 0.0; away_t = 0.0; _play("Idle")
		g.set_state("walking"); return
	var ln: Array = lines[line_i]
	if ln[0] == "B":
		b_say(ln[1], 3.0); _play(ln[2] if ln.size() > 2 else "Talk")
		if ln.size() > 3:
			match ln[3]:
				"rob": mission = "rob"
				"rob_done": mission = "rob"; owed = g.store.haul
				"paid":
					var cut: float = ln[4]
					if cut > 0: g.store.add_cash(cut)
	else:
		g.say(ln[1], 2.6); _play("Idle")
	line_t = 3.1 if ln[0] == "B" else 2.6
	line_i += 1

# ------------------------------------------------------------------ update
func update(dt: float) -> void:
	if ben == null: return
	t += dt
	# the till's been emptied while Ben's job is on: that's what he's owed
	if mission == "rob" and owed <= 0.0 and g.store.haul > 0.0 and g.store.rob.till == false: owed = g.store.haul
	match st:
		"coming":
			if t > 1.4: door_target = 1.0
			if t > 1.9:
				ben.visible = true
				var k: float = clamp((t - 1.9) / 1.2, 0.0, 1.0)
				ben.global_position = HALL.lerp(STEP, k); ben.rotation.y = 0.0; _play("Walk", 0.15)
				if k >= 1.0:
					st = "door"; t = 0.0; away_t = 0.0; _play("Idle")
					visits += 1
					var greet := "John! Little late for a visit, isn't it?" if visits == 1 else "Back again?"
					if mission == "rob" and owed > 0.0: greet = "Well? You got it?"
					elif mission == "rob": greet = "Did you do it yet?"
					b_say(greet, 2.6)
		"door":
			_face_john(dt)
			if t > 6.0 and anim and anim.current_animation == "Idle" and randf() < dt * 0.15: _play("LookAround")
			if anim and anim.current_animation == "LookAround" and not anim.is_playing(): _play("Idle")
			if jpos().distance_to(KNOCK_SPOT) > 6.0: away_t += dt
			else: away_t = 0.0
			if away_t > 2.5: st = "going"; t = 0.0
		"talking":
			_face_john(dt)
			line_t -= dt
			if line_t <= 0.0: _next_line()
		"going":
			if ben.visible:
				var k: float = clamp(t / 1.2, 0.0, 1.0)
				ben.rotation.y = lerp_angle(ben.rotation.y, PI, 1.0 - exp(-dt * 10)); _play("Walk", 0.15)
				ben.global_position = STEP.lerp(HALL, k)
				if k >= 1.0: ben.visible = false; door_target = 0.0; Sfx.play("thunk"); st = "inside"; t = 0.0
			else:
				st = "inside"
	if anim and not anim.is_playing() and ben.visible and st != "coming" and st != "going": _play("Idle")
	var was := door_open
	door_open = move_toward(door_open, door_target, dt * 1.6)
	if door_open != was:
		if was == 0.0: Sfx.play("creak")
		_apply_door()

func _face_john(dt: float) -> void:
	var d: Vector3 = g.john.global_position - ben.global_position
	var want := atan2(d.x, d.z)
	ben.rotation.y = lerp_angle(ben.rotation.y, want, 1.0 - exp(-dt * 4))

func _apply_door() -> void:
	if door: door.rotation.y = door_open * 1.45
