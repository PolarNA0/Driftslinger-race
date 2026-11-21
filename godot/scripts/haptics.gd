extends RefCounted
class_name Haptics

# Short, distinct vibration patterns for the one-button loop. Godot exposes a
# single duration call, so the "pattern" is a sequence of short pulses. It is
# deliberately a separate module from audio: a desktop has no vibrator, a web
# page must not try, and a headless verifier needs to record calls without
# touching a device.
#
# The pref is owned by App (Storage `haptics`), not this module, so the same
# toggle covers every call site.

static var enabled := true
static var log_only := false
static var calls: Array[String] = []


static func fire(kind: String) -> void:
        calls.append(kind)
        if log_only or not enabled:
                return
        if OS.has_feature("web"):
                return
        if not DisplayServer.is_touchscreen_available():
                return
        match kind:
                "grab":
                        Input.vibrate_handheld(12)
                "release":
                        Input.vibrate_handheld(8)
                "slingshot":
                        # Two quick pulses read as a kick rather than a buzz.
                        Input.vibrate_handheld(20)
                        _later(28, 26)
                "crash":
                        Input.vibrate_handheld(180)
                "finish":
                        Input.vibrate_handheld(60)
                "pb":
                        Input.vibrate_handheld(40)
                        _later(60, 35)
                _:
                        Input.vibrate_handheld(10)


static func _later(delay_ms: int, duration_ms: int) -> void:
        var loop := Engine.get_main_loop()
        if not (loop is SceneTree):
                return
        var tree := loop as SceneTree
        if tree.root == null:
                return
        var timer := tree.create_timer(float(delay_ms) / 1000.0)
        timer.timeout.connect(func(): Input.vibrate_handheld(duration_ms))
