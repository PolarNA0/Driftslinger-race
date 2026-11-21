extends SceneTree

# Headless check of the run HUD and the settings screen: the PB/WR delta text and
# colours, the speedrun progress bar, the focus-out pause, and the audio /
# feedback controls actually reaching their owners.

var failures := 0


func _check(label: String, cond: bool) -> void:
        print("  %-56s %s" % [label, "ok " if cond else "FAIL"])
        if not cond:
                failures += 1


func _initialize() -> void:
        var sub := SubViewport.new()
        sub.size = Vector2i(420, 820)
        sub.disable_3d = true
        get_root().add_child(sub)

        var scene: PackedScene = load("res://scenes/main.tscn")
        var app := scene.instantiate()
        sub.add_child(app)
        for i in range(3):
                await process_frame

        print("-- PB/WR delta --")
        app._set_delta(app.hud_pb_delta, "PB", 9.75, 10.0, true, "s")
        _check("ahead of PB reads -0.250s", app.hud_pb_delta.text == "PB -0.250s")
        _check("ahead of PB is green", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.GOOD)
        app._set_delta(app.hud_pb_delta, "PB", 10.25, 10.0, true, "s")
        _check("behind PB reads +0.250s", app.hud_pb_delta.text == "PB +0.250s")
        _check("behind PB is red", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.DANGER)
        app._set_delta(app.hud_pb_delta, "PB", 10.0, 10.0, true, "s")
        _check("level PB is neutral", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.INK_DIM)
        app._set_delta(app.hud_wr_delta, "WR", 9.5, null, true, "s")
        _check("no WR reads --", app.hud_wr_delta.text == "WR --")
        app._set_delta(app.hud_pb_delta, "PB", 120.0, 100.0, false, "m")
        _check("endless ahead reads +20 m", app.hud_pb_delta.text == "PB +20 m")
        _check("endless ahead is green", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.GOOD)

        print("-- speedrun HUD --")
        app.game.load_track(1, "speedrun")
        app._hud_reset()
        app.game.car.s = app.game.track.finish_s * 0.5
        app._on_tick()
        _check("mode says speedrun", app.hud_mode.text.begins_with("SPEEDRUN"))
        _check("progress bar is shown", app.hud_progress.visible)
        _check("progress is half the road", absf(app.hud_progress.value - 0.5) < 0.02)
        app.game.car.s = app.game.track.finish_s
        app._on_tick()
        _check("progress reaches one at the line", app.hud_progress.value >= 0.999)

        print("-- endless HUD --")
        app.game.load_track(1, "endless")
        app._hud_reset()
        _check("mode says endless", app.hud_mode.text == "ENDLESS")
        _check("endless hides the progress bar", not app.hud_progress.visible)
        _check("endless score is metres", app.hud_dist.text.ends_with(" m"))

        print("-- feedback --")
        app.game.reduced_motion = true
        app.game.renderer.shake = 0.0
        app.game.kick(18.0)
        _check("reduce motion suppresses shake", app.game.renderer.shake == 0.0)
        app.game.reduced_motion = false
        app.game.kick(18.0)
        _check("a crash reaches the renderer", app.game.renderer.shake > 0.0)
        app.game.renderer.flash = 0.0
        app.game.renderer.flash_hit(0.3)
        _check("a crash flashes the screen", app.game.renderer.flash > 0.0)
        app.game.renderer.pulse = 0.0
        app.game.renderer.zoom_pulse(0.02)
        _check("a slingshot pulses the zoom", app.game.renderer.pulse > 0.0)

        print("-- focus-out pause --")
        app.game.load_track(1, "speedrun")
        app.game.state = "running"
        app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
        _check("focus out pauses a live run", app.game.state == "paused" and app.overlay == "pause")
        app._toggle_pause()
        _check("the pause can be resumed", app.game.state == "running" and app.overlay == "")
        app.game.mode = "replay"
        app.game.state = "running"
        app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
        _check("focus out leaves a replay alone", app.game.state == "running")
        app.game.mode = "speedrun"

        print("-- tutorial --")
        app._show_tutorial()
        _check("tutorial opens", app.overlay == "tutorial" and app.overlays["tutorial"].visible)
        app._tutorial_back()
        _check("tutorial back marks it seen", app.tutorial_done and app.overlay == "menu")
        app._show_tutorial()
        app._tutorial_start()
        _check("tutorial start begins a run", app.overlay == "" and app.game.state == "running")
        app.game.state = "paused"

        print("-- settings --")
        app._open_settings()
        _check("settings has a master slider", app.settings_master != null)
        _check("settings has a music slider", app.settings_music != null)
        _check("settings has an effects slider", app.settings_sfx != null)
        _check("settings has a haptics toggle", app.settings_haptics != null)
        _check("settings has a motion toggle", app.settings_motion != null)
        app.settings_master.value = 0.4
        await process_frame
        _check("master slider reaches the mixer", absf(app.audio_master - 0.4) < 0.001)
        _check("master slider is persisted", absf(float(Storage.get_pref("audioMaster", -1.0)) - 0.4) < 0.001)
        app.settings_haptics.button_pressed = false
        app.settings_haptics.pressed.emit()
        _check("haptics toggle reaches the gate", not Haptics.enabled and not app.haptics_on)
        app.settings_motion.button_pressed = true
        app.settings_motion.pressed.emit()
        _check("motion toggle reaches the game", app.reduced_motion and app.game.reduced_motion)
        app.settings_haptics.button_pressed = true
        app.settings_haptics.pressed.emit()
        app.settings_motion.button_pressed = false
        app.settings_motion.pressed.emit()
        _check("toggles can be restored", Haptics.enabled and not app.game.reduced_motion)

        print("HUD %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
        quit(0 if failures == 0 else 1)
