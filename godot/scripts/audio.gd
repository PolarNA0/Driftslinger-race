extends Node
class_name GameAudio

# The game's sound: one pooled set of one-shot players, two continuous loops
# (engine and tyre) and a music channel. Everything is CC0; see
# `assets/audio/CREDITS.md` for the sources.
#
# The audio never owns game state. `attach_game` gives it a read-only view of the
# car, and the engine/tyre loops are driven from that every frame; discrete
# events arrive as `Game.sfx` signals. That keeps the physics free of audio calls
# and means a headless verifier can run the game with no AudioServer at all.

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# One-shots. `db` is the trim for that cue at full volume; the mix is deliberately
# conservative because a one-button game is mostly engine and tyres.
const SOUNDS := {
        "grab": {"path": "res://assets/audio/grab.ogg", "db": -9.0},
        "release": {"path": "res://assets/audio/release.ogg", "db": -8.0},
        "slingshot": {"path": "res://assets/audio/slingshot.ogg", "db": -5.0},
        "crash": {"path": "res://assets/audio/crash.ogg", "db": -4.0},
        "finish": {"path": "res://assets/audio/finish.ogg", "db": -3.0},
        "pb": {"path": "res://assets/audio/pb.ogg", "db": -3.0},
        "ui_click": {"path": "res://assets/audio/ui_click.ogg", "db": -12.0},
        "ui_back": {"path": "res://assets/audio/ui_back.ogg", "db": -12.0},
}

# Continuous sounds. The engine and tyre loops are started/stopped by the game
# state; the two music tracks are switched by App.
const LOOPS := {
        "engine": {"path": "res://assets/audio/engine_loop.ogg", "bus": BUS_SFX},
        "tire": {"path": "res://assets/audio/tire_loop.ogg", "bus": BUS_SFX},
        "music_menu": {"path": "res://assets/audio/music_menu.ogg", "bus": BUS_MUSIC},
        "music_race": {"path": "res://assets/audio/music_race.ogg", "bus": BUS_MUSIC},
}

const POOL_SIZE := 10
const SILENT_DB := -80.0

var game: Game = null

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}                 # name -> AudioStreamPlayer
var _loop_db := {}               # name -> the volume the current state wants
var _music_name := ""
var _music: AudioStreamPlayer
var _master := 0.85
var _music_vol := 0.65
var _sfx_vol := 0.9
var _paused := false


func _ready() -> void:
        _ensure_buses()
        for i in range(POOL_SIZE):
                var p := AudioStreamPlayer.new()
                p.bus = BUS_SFX
                add_child(p)
                _pool.append(p)
        _music = AudioStreamPlayer.new()
        _music.bus = BUS_MUSIC
        add_child(_music)
        set_volumes(_master, _music_vol, _sfx_vol)


func _ensure_buses() -> void:
        for name in [BUS_MUSIC, BUS_SFX]:
                if AudioServer.get_bus_index(name) == -1:
                        AudioServer.add_bus()
                        var idx := AudioServer.bus_count - 1
                        AudioServer.set_bus_name(idx, name)
                        AudioServer.set_bus_send(idx, "Master")
        # A limiter on Master catches the crash + tyre + music stack without
        # squashing the quiet cues.
        if ClassDB.class_exists("AudioEffectLimiter"):
                var has_limiter := false
                for i in range(AudioServer.get_bus_effect_count(0)):
                        if AudioServer.get_bus_effect(0, i) is AudioEffectLimiter:
                                has_limiter = true
                                break
                if not has_limiter:
                        var lim := AudioEffectLimiter.new()
                        lim.ceiling_db = -0.5
                        lim.threshold_db = -3.0
                        AudioServer.add_bus_effect(0, lim)


# --- volume -----------------------------------------------------------------

func set_volumes(master: float, music: float, sfx: float) -> void:
        _master = clampf(master, 0.0, 1.0)
        _music_vol = clampf(music, 0.0, 1.0)
        _sfx_vol = clampf(sfx, 0.0, 1.0)
        _apply_bus(BUS_MUSIC, _master * _music_vol)
        _apply_bus(BUS_SFX, _master * _sfx_vol)


func _apply_bus(bus: String, linear: float) -> void:
        var idx := AudioServer.get_bus_index(bus)
        if idx == -1:
                return
        AudioServer.set_bus_mute(idx, linear <= 0.001)
        AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func volumes() -> Dictionary:
        return {"master": _master, "music": _music_vol, "sfx": _sfx_vol}


# --- one-shots --------------------------------------------------------------

func play(name: String, extra_db: float = 0.0, pitch: float = 1.0) -> void:
        if not SOUNDS.has(name):
                return
        var stream := _stream(name)
        if stream == null:
                return
        var p := _pool[_next]
        _next = (_next + 1) % _pool.size()
        p.stream = stream
        p.volume_db = float(SOUNDS[name]["db"]) + extra_db
        p.pitch_scale = clampf(pitch, 0.5, 2.0)
        p.play()


# --- loops ------------------------------------------------------------------

func start_loop(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
        var p := _loop_player(name)
        if p == null:
                return
        p.volume_db = db
        p.pitch_scale = clampf(pitch, 0.5, 2.0)
        if not p.playing:
                p.play()


func set_loop(name: String, db: float, pitch: float = 1.0) -> void:
        if not _loops.has(name):
                if db > SILENT_DB:
                        start_loop(name, db, pitch)
                return
        var p: AudioStreamPlayer = _loops[name]
        p.volume_db = db
        p.pitch_scale = clampf(pitch, 0.5, 2.0)
        if db <= SILENT_DB and p.playing:
                p.stop()
        elif db > SILENT_DB and not p.playing:
                p.play()


func stop_loop(name: String) -> void:
        if _loops.has(name):
                var p: AudioStreamPlayer = _loops[name]
                p.stop()


func _loop_player(name: String) -> AudioStreamPlayer:
        if _loops.has(name):
                return _loops[name]
        if not LOOPS.has(name):
                return null
        var stream := _stream(name)
        if stream == null:
                return null
        var p := AudioStreamPlayer.new()
        p.bus = str(LOOPS[name]["bus"])
        p.stream = stream
        add_child(p)
        _loops[name] = p
        return p


# --- music ------------------------------------------------------------------

func music(name: String) -> void:
        if _music_name == name and _music.playing:
                return
        _music_name = name
        if name == "":
                _music.stop()
                return
        var stream := _stream(name)
        if stream == null:
                _music.stop()
                return
        _music.stream = stream
        _music.volume_db = -6.0 if name == "music_menu" else -9.0
        _music.play()


func pause_all(on: bool) -> void:
        _paused = on
        _music.stream_paused = on
        for name in _loops:
                (_loops[name] as AudioStreamPlayer).stream_paused = on


# --- the engine and tyre loops ---------------------------------------------

func attach_game(g: Game) -> void:
        game = g


func _process(_delta: float) -> void:
        if game == null or game.car == null or _paused:
                _silence_loops()
                return
        var car := game.car
        var live := game.state == "running" and car.alive and not car.finished
        if not live:
                _silence_loops()
                return
        var speed := _speed_scale(car)
        var pitch := 0.85 + 0.75 * clampf(speed - 1.0, 0.0, 0.5)
        var engine_db := -14.0 + 4.0 * clampf((speed - 1.0) / 0.35, 0.0, 1.0)
        set_loop("engine", engine_db, pitch)
        # Tyres only sing while the car is on a pole. A wider orbit is reeling in,
        # which is exactly when a real tyre protests; a settled line is quieter.
        if car.attached:
                var road_r := float(car.track.fillets[car.corner]["r"]) if car.track != null else car.radius
                var strain := clampf(absf(car.radius - road_r) / 18.0, 0.0, 1.0)
                var tire_db := -15.0 + 4.0 * strain
                set_loop("tire", tire_db, 0.95 + 0.10 * strain)
        else:
                set_loop("tire", SILENT_DB)


func _silence_loops() -> void:
        set_loop("engine", SILENT_DB)
        set_loop("tire", SILENT_DB)


func _speed_scale(car: Car) -> float:
        var ramp := 1.0
        if car.track != null:
                ramp = car.track.speed_scale_at(car.s)
        return car.speed_scale * ramp


# --- loading ----------------------------------------------------------------

func _stream(name: String) -> AudioStream:
        if _streams.has(name):
                return _streams[name]
        var def: Dictionary = SOUNDS[name] if SOUNDS.has(name) else LOOPS.get(name, {})
        if def.is_empty():
                return null
        var s: Resource = load(str(def["path"]))
        if s == null or not (s is AudioStream):
                _streams[name] = null
                return null
        var stream := s as AudioStream
        if LOOPS.has(name):
                _make_loop(stream)
        _streams[name] = stream
        return stream


func _make_loop(stream: AudioStream) -> void:
        if stream is AudioStreamOggVorbis:
                (stream as AudioStreamOggVorbis).loop = true
        elif stream is AudioStreamMP3:
                (stream as AudioStreamMP3).loop = true
        elif stream is AudioStreamWAV:
                var w := stream as AudioStreamWAV
                w.loop_mode = AudioStreamWAV.LOOP_FORWARD
                w.loop_end = int(w.get_length() * w.mix_rate)
