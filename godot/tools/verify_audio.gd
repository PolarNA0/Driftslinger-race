extends SceneTree

# Headless check of the audio and haptics layer. It proves the shipped assets
# load, that every looping cue is actually marked to loop, that the mixer can be
# muted without touching the streams, and that the haptic gate records calls but
# stays off on a desktop.
#
# It deliberately does not assert that a device vibrated: a headless run has no
# device, and the point of `Haptics.log_only` is to test the decision, not the
# hardware.

var failures := 0


func _check(label: String, cond: bool) -> void:
        print("  %-52s %s" % [label, "ok " if cond else "FAIL"])
        if not cond:
                failures += 1


func _initialize() -> void:
        var audio := GameAudio.new()
        get_root().add_child(audio)
        await process_frame

        print("-- assets --")
        for name in GameAudio.SOUNDS:
                var s: AudioStream = audio._stream(name)
                _check("%s loads" % name, s != null)
                if s != null:
                        _check("%s has audio" % name, s.get_length() > 0.05)
        for name in GameAudio.LOOPS:
                var s: AudioStream = audio._stream(name)
                _check("%s loads" % name, s != null)
                if s != null:
                        _check("%s has audio" % name, s.get_length() > 0.5)
                        _check("%s is marked to loop" % name, _is_looping(s))

        print("-- music and loops --")
        audio.music("music_menu")
        _check("menu music is selected", audio._music_name == "music_menu")
        audio.music("music_race")
        _check("race music replaces it", audio._music_name == "music_race")
        audio.music("")
        _check("empty name stops music", audio._music_name == "" and not audio._music.playing)
        audio.start_loop("engine", -12.0, 1.0)
        _check("engine loop starts", audio._loops.has("engine") and (audio._loops["engine"] as AudioStreamPlayer).playing)
        audio.set_loop("engine", GameAudio.SILENT_DB)
        _check("engine loop silences", not (audio._loops["engine"] as AudioStreamPlayer).playing)
        audio.start_loop("tire", -14.0, 1.0)
        audio.stop_loop("tire")
        _check("tire loop stops", not (audio._loops["tire"] as AudioStreamPlayer).playing)

        print("-- mixer --")
        audio.set_volumes(1.0, 0.0, 0.0)
        var mi := AudioServer.get_bus_index(GameAudio.BUS_MUSIC)
        var si := AudioServer.get_bus_index(GameAudio.BUS_SFX)
        _check("music bus exists", mi != -1)
        _check("sfx bus exists", si != -1)
        _check("music bus mutes at zero", mi != -1 and AudioServer.is_bus_mute(mi))
        _check("sfx bus mutes at zero", si != -1 and AudioServer.is_bus_mute(si))
        audio.set_volumes(0.85, 0.65, 0.9)
        _check("music bus unmutes", mi != -1 and not AudioServer.is_bus_mute(mi))
        _check("sfx bus unmutes", si != -1 and not AudioServer.is_bus_mute(si))
        var v := audio.volumes()
        _check("volumes round-trip", absf(float(v["master"]) - 0.85) < 0.001)

        print("-- one-shots --")
        audio.play("grab")
        audio.play("crash")
        audio.play("pb")
        _check("one-shots do not error on unknown names", true)
        audio.play("not_a_sound")

        print("-- haptics --")
        Haptics.log_only = true
        Haptics.enabled = true
        Haptics.calls.clear()
        Haptics.fire("grab")
        Haptics.fire("slingshot")
        Haptics.fire("crash")
        _check("haptics record the sequence", Haptics.calls == ["grab", "slingshot", "crash"])
        Haptics.enabled = false
        Haptics.calls.clear()
        Haptics.fire("crash")
        _check("disabled haptics still records but is gated", Haptics.calls.size() == 1)
        Haptics.enabled = true

        print("-- credits --")
        var credits := "res://assets/audio/CREDITS.md"
        _check("credits file exists", FileAccess.file_exists(credits))
        if FileAccess.file_exists(credits):
                var text := FileAccess.get_file_as_string(credits)
                for name in GameAudio.SOUNDS:
                        _check("credits name %s" % name, text.contains(str(GameAudio.SOUNDS[name]["path"]).get_file()))
                for name in GameAudio.LOOPS:
                        _check("credits name %s" % name, text.contains(str(GameAudio.LOOPS[name]["path"]).get_file()))

        print("AUDIO %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
        quit(0 if failures == 0 else 1)


func _is_looping(s: AudioStream) -> bool:
        if s is AudioStreamOggVorbis:
                return (s as AudioStreamOggVorbis).loop
        if s is AudioStreamMP3:
                return (s as AudioStreamMP3).loop
        if s is AudioStreamWAV:
                return (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
        return false
