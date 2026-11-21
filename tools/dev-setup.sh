#!/usr/bin/env bash
# Install the Godot the project builds with, so `make check` works from a clean
# checkout. Linux x86_64 only; on anything else, install Godot 4.5.2 and the
# export templates yourself and put `godot` on PATH.
#
#   tools/dev-setup.sh
#
# It is idempotent: a matching `godot` already on PATH is left alone, and an
# already-installed template set is not downloaded again.
set -eu

GODOT_VERSION="4.5.2-stable"
GODOT_SHORT="4.5.2.stable"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}"
BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/bin}"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_SHORT}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing $1; install it first" >&2
    exit 1
  }
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *)
    echo "this script supports Linux x86_64 only" >&2
    echo "install Godot ${GODOT_VERSION} and its export templates, then put godot on PATH" >&2
    exit 1
    ;;
esac

need curl
need unzip

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if command -v godot >/dev/null 2>&1; then
  have="$(godot --version 2>/dev/null | head -1 || true)"
  case "$have" in
    "${GODOT_SHORT}"*)
      echo "godot ${have} is already on PATH"
      ;;
    *)
      echo "warning: godot ${have:-unknown} is on PATH, but the project builds with ${GODOT_SHORT}" >&2
      ;;
  esac
else
  echo "installing Godot ${GODOT_VERSION} into ${BIN_DIR}"
  mkdir -p "$BIN_DIR"
  curl -sSL -o "$tmp/godot.zip" "$BASE/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  install -m 755 "$tmp/Godot_v${GODOT_VERSION}_linux.x86_64" "$BIN_DIR/godot"
  echo "installed $BIN_DIR/godot"
fi

if [ -f "$TPL_DIR/version.txt" ]; then
  echo "export templates already installed in $TPL_DIR"
else
  echo "installing export templates into $TPL_DIR"
  mkdir -p "$TPL_DIR"
  curl -sSL -o "$tmp/templates.tpz" "$BASE/Godot_v${GODOT_VERSION}_export_templates.tpz"
  unzip -q "$tmp/templates.tpz" -d "$tmp"
  cp -R "$tmp/templates/." "$TPL_DIR/"
  echo "installed export templates"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "add $BIN_DIR to PATH, or run: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo
echo "next: make check"
