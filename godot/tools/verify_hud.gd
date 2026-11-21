extends SceneTree

# Headless check of the run HUD and the settings screen: the PB/WR delta text and
# colours, the live pace delta, the focus-out pause, and the audio /
# feedback controls actually reaching their owners.

var failures := 0


func _check(label: String, cond: bool) -> void:
        print("  %-56s %s" % [label, "ok " if cond else "FAIL"])
        if not cond:
                failures += 1


func _clean_steps(seed: int) -> String:
        var t := Track.new(seed, Tracks.track_opts(seed))
        var car := Car.new()
        car.reset(t)
        var steps := []
        var i := 0
        while car.alive and not car.finished and i < 200000:
                var held := false
                if car.attached:
                        held = car.remaining() > 0.0
                else:
                        var f: Dictionary = t.fillets[car.corner]
                        held = U.dist(f["c"].x, f["c"].y, car.x, car.y) <= Cfg.GRAB_RANGE
                steps.append(held)
                car.step(1.0 / 120.0, held)
                i += 1
        return Replay.encode_steps(steps)


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
        var ref_steps := _clean_steps(1)
        app.game.set_pace("pb", 1, ref_steps)
        _check("pace starts at zero", float(app.game.pace_time_at("pb", 0.0)) == 0.0)
        var mid_s: float = app.game.track.finish_s * 0.5
        var ref_t: Variant = app.game.pace_time_at("pb", mid_s)
        _check("a pace time exists at mid-track", ref_t != null)
        app.game.car.s = mid_s
        app.game.car.time = float(ref_t) + 0.2
        app._update_hud_marks()
        _check("live PB delta is behind at the same position", app.hud_pb_delta.text == "PB +0.200s")
        _check("a live behind delta is red", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.HUD_BAD)
        app.game.car.time = float(ref_t) - 0.2
        app._update_hud_marks()
        _check("live PB delta is ahead at the same position", app.hud_pb_delta.text == "PB -0.200s")
        _check("a live ahead delta is green", app.hud_pb_delta.get_theme_color("font_color") == UiTheme.HUD_GOOD)
        app.game.clear_pace("pb")
        app._update_hud_marks()
        _check("no replay hides the PB delta", not app.hud_pb_delta.visible)
        _check("the huge progress bar is gone", app.find_children("*", "ProgressBar", true, false).is_empty())
        app.game.load_track(1, "speedrun")
        app._hud_reset()
        app._on_tick()
        _check("mode says speedrun", app.hud_mode.text.begins_with("SPEEDRUN"))

        print("-- endless HUD --")
        app.game.load_track(1, "endless")
        app._hud_reset()
        _check("mode says endless", app.hud_mode.text == "ENDLESS")
        _check("endless score is metres", app.hud_dist.text.ends_with(" m"))
        # The endless comparison is distance at the same elapsed time. A synthetic
        # curve proves the interpolation without needing a full endless replay.
        app.game.pace_t["pb"] = [Vector2(0.0, 0.0), Vector2(1.0, 10.0)]
        app.game.car.time = 0.5
        _check("endless pace is half the reference distance", absf(float(app.game.pace_distance_at("pb", 0.5)) - 5.0) < 0.001)
        _check("endless delta starts at zero", float(app.game.pace_distance_at("pb", 0.0)) == 0.0)

        print("-- feedback --")
        app.game.reduced_motion = true
        app.game.renderer.shake = 0.0
        app.game.kick(18.0)
        _check("reduce motion suppresses shake", app.game.renderer.shake == 0.0)
        app.game.reduced_motion = false
        app.game.renderer.clear_fx()
        app.game.kick(18.0)
        _check("a crash reaches the renderer", app.game.renderer.shake > 0.0)
        # `_die` stops the physics, so the shake has to decay in the renderer's
        # own `_process`. This used to stay at full strength forever.
        for i in range(30):
                app.game.renderer._process(1.0 / 60.0)
        _check("the shake fades without a physics tick", app.game.renderer.shake == 0.0)
        app.game.renderer.shake = 9.0
        app.game.renderer.clear_fx()
        _check("clear_fx stops the shake", app.game.renderer.shake == 0.0)
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
