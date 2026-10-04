extends Node
## Sound effects rendered from the web build's WebAudio synth (tools/synth.py).
## Sfx.play("creak"), Sfx.play_var("bubble", 4) for random variants, loops via set_loop().

const POOL := 16
var players: Array[AudioStreamPlayer] = []
var cache := {}
var loops := {}
var next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); players.append(p)

func _stream(name: String) -> AudioStream:
	if not cache.has(name):
		var path := "res://assets/sfx/%s.wav" % name
		cache[name] = load(path) if ResourceLoader.exists(path) else null
	return cache[name]

func play(name: String, db := 0.0, pitch := 1.0, delay := 0.0) -> void:
	var s := _stream(name)
	if s == null: return
	if delay > 0.0:
		get_tree().create_timer(delay, true).timeout.connect(func(): play(name, db, pitch))
		return
	var p := players[next]; next = (next + 1) % POOL
	p.stream = s; p.volume_db = db; p.pitch_scale = pitch; p.play()

func play_var(base: String, count: int, db := 0.0) -> void:
	play("%s%d" % [base, randi() % count], db)

## looping bed: level 0..1 fades in/out smoothly
func set_loop(name: String, level: float, dt := 0.016, speed := 3.0) -> void:
	var p: AudioStreamPlayer = loops.get(name)
	if p == null:
		var s := _stream(name)
		if s == null: return
		s = s.duplicate()
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = int(s.get_length() * s.mix_rate)
		p = AudioStreamPlayer.new(); p.stream = s; p.volume_db = -80; add_child(p); p.play()
		p.set_meta("lv", 0.0)
		loops[name] = p
	var lv: float = p.get_meta("lv")
	lv = lerp(lv, level, 1.0 - exp(-dt * speed))
	p.set_meta("lv", lv)
	p.volume_db = linear_to_db(max(lv, 0.0001))

func stop_all_loops() -> void:
	for p in loops.values(): p.set_meta("lv", 0.0); p.volume_db = -80

## continuous engine note (port of the web build's oscillator engine): pitch follows a 4-gear rev curve
var _eng: AudioStreamPlayer
var _eng_lv := 0.0
func engine(on: bool, speed: float, thr: float, dt: float) -> void:
	if _eng == null:
		var s := _stream("engine_loop")
		if s == null: return
		s = s.duplicate()
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_end = int(s.get_length() * s.mix_rate)
		_eng = AudioStreamPlayer.new(); _eng.stream = s; _eng.volume_db = -80; add_child(_eng); _eng.play()
	var gear: float = min(4.0, floor(speed / 8.5)); var frac := (speed - gear * 8.5) / 8.5
	var hz := 48.0 + frac * 72.0 + gear * 9.0 + thr * 8.0
	_eng.pitch_scale = clamp(hz / 60.0, 0.4, 3.0)
	var target := (0.045 + 0.05 * thr + speed * 0.0012) / 0.1 if on else 0.0
	_eng_lv = lerp(_eng_lv, target, 1.0 - exp(-dt * (12.0 if on else 4.0)))
	_eng.volume_db = linear_to_db(max(_eng_lv, 0.0001))
