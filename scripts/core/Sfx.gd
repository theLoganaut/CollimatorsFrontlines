extends Node
## Autoload. Placeholder sound effects, synthesized at startup (no audio
## files yet): hits, misses, parts breaking, cards, protocols, overheat,
## turns, UI clicks, hologram pop-ups, victory and defeat. play(key) picks
## a free voice from a small pool, with a little pitch variation so repeats
## don't drone.
## They play on the SFX bus (GameSettings sets its volume). Call through
## Audio.play() from scripts that shouldn't depend on autoloads.
##
## Also the music and ambience beds (SoundLoops): one looping layer each,
## on the Music and Ambience buses, crossfading when the key changes
## (Audio.music / Audio.ambience; "" fades it out). A loop is rendered on a
## worker thread the first time it's asked for and plays once it's ready.

const RATE := 22050
const VOICES := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

const FADE := 1.2 # seconds to crossfade a music or ambience change
const LAYER_DB := {"music": -8.0, "ambience": -12.0}
## Per layer ("music", "ambience"): {key, players: [a, b], active: 0|1}.
var _layers: Dictionary = {}
var _loops: Dictionary = {} # "kind:key" -> AudioStreamWAV
var _rendering: Dictionary = {} # "kind:key" -> WorkerThreadPool task id
var _results: Dictionary = {} # filled by the worker threads (under _mutex)
var _mutex := Mutex.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_build()
	for kind in ["music", "ambience"]:
		var pair: Array[AudioStreamPlayer] = []
		for i in range(2):
			var p := AudioStreamPlayer.new()
			p.bus = "Music" if kind == "music" else "Ambience"
			p.volume_db = -80.0
			add_child(p)
			pair.append(p)
		_layers[kind] = {"key": "", "players": pair, "active": 0}

## The music bed ("hub", "map", "combat", "boss"; "" = none).
func set_music(key: String) -> void:
	_set_layer("music", key)

## The ambience bed ("hub", "coast", "flank", "backline", "rain"; "" = none).
func set_ambience(key: String) -> void:
	_set_layer("ambience", key)

func _set_layer(kind: String, key: String) -> void:
	var layer: Dictionary = _layers[kind]
	if layer["key"] == key:
		return
	layer["key"] = key
	var id := "%s:%s" % [kind, key]
	if key != "" and not _loops.has(id) and not _rendering.has(id) and DisplayServer.get_name() != "headless":
		_rendering[id] = WorkerThreadPool.add_task(func():
			var stream := SoundLoops.render(kind, key)
			_mutex.lock()
			_results[id] = stream
			_mutex.unlock())
	_switch(kind)

## Crossfades the layer to its key's loop (if it's rendered yet).
func _switch(kind: String) -> void:
	var layer: Dictionary = _layers[kind]
	var id := "%s:%s" % [kind, layer["key"]]
	var players: Array = layer["players"]
	var old: AudioStreamPlayer = players[layer["active"]]
	var stream: AudioStreamWAV = _loops.get(id, null)
	if layer["key"] != "" and stream == null:
		return # still rendering: _process switches when it's ready
	if stream != null and old.playing and old.stream == stream:
		return
	create_tween().tween_property(old, "volume_db", -80.0, FADE).finished.connect(func():
		if old != players[layer["active"]]:
			old.stop())
	if stream == null:
		return
	layer["active"] = 1 - int(layer["active"])
	var nxt: AudioStreamPlayer = players[layer["active"]]
	nxt.stream = stream
	nxt.volume_db = -60.0
	nxt.play()
	create_tween().tween_property(nxt, "volume_db", LAYER_DB[kind], FADE)

## At exit: loops still rendering are waited for and the beds stopped, so
## nothing is leaked.
func _exit_tree() -> void:
	for id in _rendering:
		WorkerThreadPool.wait_for_task_completion(_rendering[id])
	_rendering.clear()
	for kind in _layers: # a loop still playing at exit is held by the audio server
		for p in _layers[kind]["players"]:
			p.stop()
			p.stream = null
	_loops.clear()

func _process(_delta: float) -> void:
	if _rendering.is_empty():
		return
	_mutex.lock()
	var done := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for id in done:
		WorkerThreadPool.wait_for_task_completion(_rendering[id])
		_rendering.erase(id)
		if done[id] != null:
			_loops[id] = done[id]
		var kind: String = id.get_slice(":", 0)
		if "%s:%s" % [kind, _layers[kind]["key"]] == id:
			_switch(kind)

func play(key: String, pitch_jitter: float = 0.06, volume_db: float = 0.0) -> void:
	if GameSettings.sfx_volume <= 0.0 or GameSettings.master_volume <= 0.0 or not _streams.has(key):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()

# ---------- synthesis ----------

func _build() -> void:
	_streams["hit"] = _make(0.09, func(t, n): return _noise(n) * _env(t, 0.09, 30.0) * 0.55 + sin(TAU * 110.0 * t) * _env(t, 0.09, 40.0) * 0.5)
	_streams["hit_heavy"] = _make(0.22, func(t, n): return _noise(n) * _env(t, 0.22, 14.0) * 0.6 + sin(TAU * (70.0 - 30.0 * t) * t) * _env(t, 0.22, 10.0) * 0.8)
	_streams["shield"] = _make(0.16, func(t, n): return (sin(TAU * 1320.0 * t) + sin(TAU * 1760.0 * t)) * 0.2 * _env(t, 0.16, 18.0))
	_streams["miss"] = _make(0.12, func(t, n): return sin(TAU * (900.0 - 2500.0 * t) * t) * 0.25 * _env(t, 0.12, 20.0))
	_streams["destroyed"] = _make(0.5, func(t, n): return _noise(n) * _env(t, 0.5, 7.0) * 0.7 + sin(TAU * (55.0 - 20.0 * t) * t) * _env(t, 0.5, 5.0) * 0.9)
	_streams["card"] = _make(0.05, func(t, n): return (_noise(n) * 0.3 + sin(TAU * 2200.0 * t) * 0.3) * _env(t, 0.05, 70.0))
	_streams["prime"] = _make(0.18, func(t, n): return sin(TAU * (660.0 if t < 0.08 else 990.0) * t) * 0.3 * _env(t, 0.18, 8.0))
	_streams["overheat"] = _make(0.5, func(t, n): return _square(t, 880.0 if int(t * 12.0) % 2 == 0 else 620.0) * 0.22 * _env(t, 0.5, 2.5))
	# a falling hiss: venting heat
	_streams["vent"] = _make(0.45, func(t, n): return _noise(n) * 0.35 * _env(t, 0.45, 4.0) * (0.4 + 0.6 * sin(TAU * (300.0 - 400.0 * t) * t) ** 2))
	# a low two-note horn: a boss changes tactics
	_streams["boss_phase"] = _make(0.9, func(t, n): return (_square(t, 98.0 if t < 0.35 else 73.0) * 0.18 + sin(TAU * (196.0 if t < 0.35 else 146.0) * t) * 0.2) * _env(t, 0.9, 2.2))
	_streams["turn"] = _make(0.3, func(t, n): return (sin(TAU * 660.0 * t) + 0.6 * sin(TAU * 990.0 * t)) * 0.22 * _env(t, 0.3, 9.0))
	_streams["ui"] = _make(0.035, func(t, n): return sin(TAU * 1400.0 * t) * 0.25 * _env(t, 0.035, 80.0))
	_streams["holo"] = _make(0.08, func(t, n): return sin(TAU * (1100.0 + 2200.0 * t) * t) * 0.12 * _env(t, 0.08, 30.0))
	_streams["victory"] = _make(0.7, func(t, n): return _arp(t, [523.0, 659.0, 784.0, 1047.0], 0.14) * 0.3 * _env(t, 0.7, 2.5))
	# two sharp high beeps: this play overheats into a possible defeat
	_streams["overheat_warn"] = _make(0.32, func(t, n): return _square(t, 1320.0) * 0.16 * (1.0 if fmod(t, 0.16) < 0.08 else 0.0) * _env(t, 0.32, 3.0))
	# a short low buzz: that card can't be played now (spent, or its part can't act)
	_streams["denied"] = _make(0.14, func(t, n): return _square(t, 140.0) * 0.18 * _env(t, 0.14, 14.0))
	# a coin-like two-note ding: a part bought at an autonomous bay
	_streams["shop_buy"] = _make(0.35, func(t, n): return (sin(TAU * (1568.0 if t < 0.07 else 2093.0) * t) * 0.22 + sin(TAU * 3136.0 * t) * 0.05) * _env(t, 0.35, 7.0))
	# a metallic clank rising into a tone: a frame square welded on
	_streams["frame_square"] = _make(0.45, func(t, n): return _noise(n) * 0.35 * _env(t, 0.45, 28.0) + sin(TAU * (220.0 + 330.0 * t) * t) * 0.22 * _env(t, 0.45, 4.5))
	# hits by weapon type (Logan, 2026-09-30; CombatScene.hit_sound picks):
	# a blade's bright scrape, a gun's sharp crack, a rocket's boom, an energy weapon's zap
	_streams["hit_blade"] = _make(0.14, func(t, n): return (_noise(n) * 0.35 + sin(TAU * (2400.0 - 6000.0 * t) * t) * 0.3) * _env(t, 0.14, 22.0) + sin(TAU * 140.0 * t) * _env(t, 0.14, 35.0) * 0.35)
	_streams["hit_gun"] = _make(0.08, func(t, n): return _noise(n) * _env(t, 0.08, 45.0) * 0.7 + _square(t, 180.0) * _env(t, 0.08, 60.0) * 0.2)
	_streams["hit_rocket"] = _make(0.32, func(t, n): return _noise(n) * _env(t, 0.32, 9.0) * 0.55 + sin(TAU * (60.0 - 25.0 * t) * t) * _env(t, 0.32, 8.0) * 0.85)
	_streams["hit_energy"] = _make(0.16, func(t, n): return (_square(t, 220.0 + 900.0 * exp(-25.0 * t)) * 0.22 + sin(TAU * 1800.0 * t) * 0.12) * _env(t, 0.16, 16.0))
	# a soft two-tone alarm: your HP has dropped low
	_streams["low_hp"] = _make(0.6, func(t, n): return sin(TAU * (520.0 if t < 0.3 else 390.0) * t) * 0.16 * _env(t, 0.6, 1.5) * (1.0 if fmod(t, 0.3) < 0.24 else 0.0))
	# the quietest tick: hovering a card
	_streams["hover"] = _make(0.02, func(t, n): return sin(TAU * 2600.0 * t) * 0.12 * _env(t, 0.02, 140.0))
	_streams["defeat"] = _make(0.8, func(t, n): return _arp(t, [392.0, 311.0, 262.0, 196.0], 0.18) * 0.3 * _env(t, 0.8, 2.0))

## `fn(t, n)` gives a sample in [-1, 1] for time t (seconds) and index n.
func _make(seconds: float, fn: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for n in range(count):
		var v: float = clampf(fn.call(float(n) / RATE, n), -1.0, 1.0)
		data.encode_s16(n * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

## A short attack then an exponential decay.
static func _env(t: float, length: float, decay: float) -> float:
	var attack := minf(1.0, t / 0.004)
	return attack * exp(-decay * t) * clampf((length - t) / 0.01, 0.0, 1.0)

static func _noise(n: int) -> float:
	var x := sin(float(n) * 12.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0

static func _square(t: float, f: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0

static func _arp(t: float, notes: Array, step: float) -> float:
	var i := mini(int(t / step), notes.size() - 1)
	return sin(TAU * float(notes[i]) * t)
