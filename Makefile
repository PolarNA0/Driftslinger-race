# Local one-command verification. CI runs the same checks (see
# .github/workflows/verify.yml), plus the tracker SQL test on a postgres service.
#
#   make setup   # install the pinned Godot + export templates (Linux x86_64)
#   make test    # JS physics, vendored copies, version, docs
#   make verify  # every Godot verifier
#   make check   # test + verify
#   make web     # export the web build
#   make apk     # export the Android debug APK
#   make notes   # release notes from the commits since the last tag

GODOT ?= godot

VERIFIERS := \
	parity \
	verify_tracks \
	verify_reattach \
	verify_endless \
	verify_board \
	verify_online \
	verify_guard \
	verify_editor \
	verify_ui \
	verify_cars \
	verify_keys \
	verify_medals \
	verify_audio \
	verify_hud \
	verify_storage

.PHONY: setup test verify check web apk notes clean

setup:
	bash tools/dev-setup.sh

test:
	node tools/test.mjs
	node tools/sync-physics.mjs --check
	node tools/version.mjs --check
	node tools/docs-check.mjs
	node tools/toolchain.mjs --check

verify:
	$(GODOT) --headless --path godot --import
	@set -e; for s in $(VERIFIERS); do \
		echo "== $$s"; \
		$(GODOT) --headless --path godot --script "res://tools/$$s.gd"; \
	done

check: test verify
	@echo "check: all green"

web:
	$(GODOT) --headless --path godot --import
	mkdir -p godot/build/web
	cd godot && $(GODOT) --headless --path . --export-release "Web" build/web/index.html

apk:
	mkdir -p godot/build/android
	cd godot && $(GODOT) --headless --path . --export-debug "Android" build/android/drift-slinger.apk

notes:
	node tools/release-notes.mjs

clean:
	rm -rf godot/build
