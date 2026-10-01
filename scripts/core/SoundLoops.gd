class_name SoundLoops
extends RefCounted
## Placeholder music and ambience, synthesized (no audio files yet), each a
## seamless loop: every sound in it repeats on a period that divides the
## loop's length. Rendered off the main thread by Sfx the first time a key
## is asked for (render() is pure, so it's safe on a worker thread).
##
## Music: "hub" (a quiet drone pad), "map" (slow minor pads and a plucked
## arpeggio), "combat" (bass, kick and hats at 120 bpm), "boss" (heavier,
## darker, with a snare). Ambience: "hub" (bunker ventilation), "coast"
## (surf swells), "flank" (the mine: rumble and distant metal), "backline"
## (the data archive's hum and chirps), "rain".

const RATE := 22050
const MUSIC := ["hub", "map", "combat", "boss"]
const AMBIENCE := ["hub", "coast", "flank", "backline", "rain"]

## A loop as a WAV stream, or null for an unknown key. `kind`: "music" or
## "ambience".
static func render(kind: String, key: String) -> AudioStreamWAV:
	var buf: PackedFloat32Array
	match kind + ":" + key:
		"music:hub": buf = _music_hub()
		"music:map": buf = _music_map()
		"music:combat": buf = _music_combat(false)
		"music:boss": buf = _music_combat(true)
		"ambience:hub": buf = _amb_hub()
		"ambience:coast": buf = _amb_coast()
		"ambience:flank": buf = _amb_flank()
		"ambience:backline": buf = _amb_backline()
		"ambience:rain": buf = _amb_rain()
		_: return null
	return _to_stream(buf)

# ---------- music ----------

## A slow drone: D minor 9, breathing on an 8-second swell.
static func _music_hub() -> PackedFloat32Array:
	var b := _buffer(16.0)
	for f in [73.42, 110.0, 146.83, 174.61, 220.0, 329.63]:
		_pad(b, 0.0, 16.0, f, 0.045, 2.0)
	_swell(b, 8.0, 0.35)
	return b

## Am – F – C – G pads (4 s each) and an eighth-note pluck arpeggio.
static func _music_map() -> PackedFloat32Array:
	var b := _buffer(16.0)
	var chords := [[110.0, 130.81, 164.81], [87.31, 110.0, 130.81], [65.41, 98.0, 130.81], [98.0, 123.47, 146.83]]
	for i in range(4):
		for f in chords[i]:
			_pad(b, i * 4.0, 4.0, f, 0.05, 0.8)
		for j in range(8):
			var f2: float = chords[i][[0, 1, 2, 1, 2, 0, 1, 2][j]] * 4.0
			_pluck(b, i * 4.0 + j * 0.5, 0.45, f2, 0.06)
	return b

## 120 bpm, 16 beats: an A minor bass line in eighths, kick on the beat,
## hats off it; the boss version is D minor, square bass, snare on 2 and 4.
static func _music_combat(boss: bool) -> PackedFloat32Array:
	var b := _buffer(8.0)
	var root := 73.42 if boss else 55.0
	var line := [1.0, 1.0, 1.189, 1.0, 0.891, 1.0, 1.498, 0.891] # semitone ratios of the root
	for i in range(32):
		var f: float = root * line[i % line.size()] * (0.5 if boss and i % 8 == 0 else 1.0)
		_bass(b, i * 0.25, 0.22, f, 0.16 if boss else 0.13, boss)
	for beat in range(16):
		_kick(b, beat * 0.5, 0.22)
		_hat(b, beat * 0.5 + 0.25, 0.05)
		if boss and beat % 2 == 1:
			_snare(b, beat * 0.5, 0.12)
	for f in ([146.83, 174.61, 220.0] if boss else [110.0, 130.81, 164.81]):
		_pad(b, 0.0, 8.0, f, 0.025, 1.0)
	return b

# ---------- ambience ----------

static func _amb_hub() -> PackedFloat32Array:
	var b := _buffer(8.0)
	_brown(b, 0.35, 11)
	_tone(b, 0.0, 8.0, 50.0, 0.04)
	_tone(b, 0.0, 8.0, 100.0, 0.015)
	return b

static func _amb_coast() -> PackedFloat32Array:
	var b := _buffer(8.0)
	_brown(b, 0.55, 23)
	_swell(b, 4.0, 0.8) # two waves a loop
	return b

static func _amb_flank() -> PackedFloat32Array:
	var b := _buffer(8.0)
	_brown(b, 0.45, 37)
	_tone(b, 0.0, 8.0, 41.0, 0.05)
	for hit in [[1.3, 2350.0], [4.1, 1870.0], [6.7, 2690.0]]:
		_ping(b, hit[0], hit[1], 0.05)
	return b

static func _amb_backline() -> PackedFloat32Array:
	var b := _buffer(8.0)
	_brown(b, 0.15, 51)
	_tone(b, 0.0, 8.0, 60.0, 0.035)
	_tone(b, 0.0, 8.0, 120.0, 0.02)
	_tone(b, 0.0, 8.0, 180.0, 0.01)
	for t0 in [0.8, 0.95, 3.3, 5.6, 5.72, 5.84]:
		_pluck(b, t0, 0.06, 2637.0, 0.03)
	return b

static func _amb_rain() -> PackedFloat32Array:
	var b := _buffer(8.0)
	var x := 0.0
	var seed := 71
	for n in range(b.size()):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var w := float(seed) / 0x7fffffff * 2.0 - 1.0
		x = 0.6 * x + 0.4 * w # a light low-pass: hiss, not static
		b[n] += x * 0.12
	return b

# ---------- building blocks ----------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## A soft sustained tone (three detuned sines) with attack/release `fade`.
static func _pad(b: PackedFloat32Array, start: float, dur: float, f: float, amp: float, fade: float) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	for i in range(n):
		var t := float(i) / RATE
		var env := minf(1.0, minf(t / fade, (dur - t) / fade))
		var tt := (s0 + i) / float(RATE)
		b[(s0 + i) % b.size()] += amp * env * (sin(TAU * f * tt) + 0.5 * sin(TAU * f * 1.003 * tt) + 0.3 * sin(TAU * f * 2.0 * tt))

## A plucked note: a quick attack and exponential decay.
static func _pluck(b: PackedFloat32Array, start: float, dur: float, f: float, amp: float) -> void:
	var s0 := int(start * RATE)
	for i in range(int(dur * RATE)):
		var t := float(i) / RATE
		b[(s0 + i) % b.size()] += amp * minf(1.0, t / 0.004) * exp(-7.0 * t) * (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t))

static func _bass(b: PackedFloat32Array, start: float, dur: float, f: float, amp: float, square: bool) -> void:
	var s0 := int(start * RATE)
	for i in range(int(dur * RATE)):
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.005) * exp(-5.0 * t)
		var w := (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.6 if square else sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)
		b[(s0 + i) % b.size()] += amp * env * w

static func _kick(b: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var phase := 0.0
	for i in range(int(0.25 * RATE)):
		var t := float(i) / RATE
		phase += TAU * (48.0 + 110.0 * exp(-30.0 * t)) / RATE
		b[(s0 + i) % b.size()] += amp * exp(-11.0 * t) * sin(phase)

static func _hat(b: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var seed := s0 + 3
	var last := 0.0
	for i in range(int(0.05 * RATE)):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var w := float(seed) / 0x7fffffff * 2.0 - 1.0
		var hp := w - last # a crude high-pass
		last = w
		b[(s0 + i) % b.size()] += amp * exp(-60.0 * float(i) / RATE) * hp

static func _snare(b: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var seed := s0 + 9
	for i in range(int(0.18 * RATE)):
		var t := float(i) / RATE
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var w := float(seed) / 0x7fffffff * 2.0 - 1.0
		b[(s0 + i) % b.size()] += amp * exp(-18.0 * t) * (w * 0.8 + 0.4 * sin(TAU * 190.0 * t))

## A distant metallic ping.
static func _ping(b: PackedFloat32Array, start: float, f: float, amp: float) -> void:
	var s0 := int(start * RATE)
	for i in range(int(0.9 * RATE)):
		var t := float(i) / RATE
		b[(s0 + i) % b.size()] += amp * exp(-5.0 * t) * (sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.51 * t))

static func _tone(b: PackedFloat32Array, start: float, dur: float, f: float, amp: float) -> void:
	var s0 := int(start * RATE)
	for i in range(int(dur * RATE)):
		b[(s0 + i) % b.size()] += amp * sin(TAU * f * (s0 + i) / float(RATE))

## Brown noise (a rumble) across the whole loop. It's rendered a little
## past the end and that overhang is crossfaded onto the start, so the loop
## point continues the noise instead of clicking.
static func _brown(b: PackedFloat32Array, amp: float, seed_value: int) -> void:
	var seed := seed_value
	var x := 0.0
	var blend := int(0.25 * RATE)
	var tmp := PackedFloat32Array()
	tmp.resize(b.size() + blend)
	for n in range(tmp.size()):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		x = clampf(x * 0.995 + (float(seed) / 0x7fffffff * 2.0 - 1.0) * 0.05, -1.0, 1.0)
		tmp[n] = x
	for n in range(b.size()):
		var v := tmp[n]
		if n < blend:
			var k := float(n) / blend
			v = v * k + tmp[b.size() + n] * (1.0 - k)
		b[n] += v * amp

## Multiplies the whole buffer by a slow swell (period in seconds).
static func _swell(b: PackedFloat32Array, period: float, depth: float) -> void:
	for n in range(b.size()):
		var t := float(n) / RATE
		b[n] *= 1.0 - depth * 0.5 * (1.0 + cos(TAU * t / period))

static func _to_stream(b: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for v in b:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for n in range(b.size()):
		data.encode_s16(n * 2, int(clampf(b[n] * gain, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = b.size()
	return s
