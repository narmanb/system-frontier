extends Node
## Synthesised retro sound cues, replacing the legacy Web Audio `beep(freq,dur,type,vol)`.
## Each cue is rendered once to an AudioStreamWAV and cached.

const MIX_RATE := 22050
const VOICES := 10

var enabled := true
var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func beep(freq := 440.0, dur := 0.07, wave := "square", vol := 0.035) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var key := "%d:%d:%s:%d" % [int(freq), int(dur * 1000), wave, int(vol * 1000)]
	var stream: AudioStreamWAV = _cache.get(key)
	if stream == null:
		stream = _render(freq, dur, wave, vol)
		_cache[key] = stream
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.play()


func _render(freq: float, dur: float, wave: String, vol: float) -> AudioStreamWAV:
	var n := maxi(1, int(dur * MIX_RATE))
	var data := PackedByteArray()
	data.resize(n * 2)
	var amp := clampf(vol * 6.0, 0.0, 0.6)  # Web Audio gain → comfortable sample level
	for i in n:
		var t := float(i) / MIX_RATE
		var phase := fmod(t * freq, 1.0)
		var s := 0.0
		match wave:
			"sawtooth": s = phase * 2.0 - 1.0
			"sine": s = sin(phase * TAU)
			"triangle": s = 1.0 - 4.0 * absf(phase - 0.5)
			_: s = 1.0 if phase < 0.5 else -1.0
		# exponential decay to ~0.0001 like exponentialRampToValueAtTime
		var env := pow(0.0001, float(i) / n)
		data.encode_s16(i * 2, int(clampf(s * env * amp, -1, 1) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
