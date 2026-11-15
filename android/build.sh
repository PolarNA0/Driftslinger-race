#!/usr/bin/env bash
# Build a debug-signed APK from the web app plus the WebView shell in android/.
#
# This deliberately does not use Gradle: the project has no Java dependencies
# beyond the framework, so aapt2 + javac + d8 + apksigner is the whole toolchain.
# Set ANDROID_HOME (and JAVA_HOME) or pass SDK= and JDK= on the command line.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SDK="${SDK:-${ANDROID_HOME:-}}"
JDK="${JDK:-${JAVA_HOME:-}}"
BT="$SDK/build-tools/34.0.0"
PLATFORM="$SDK/platforms/android-34/android.jar"
OUT="${OUT:-$HERE/build}"

[ -x "$BT/aapt2" ] || { echo "aapt2 not found; set SDK/ANDROID_HOME" >&2; exit 1; }
[ -f "$PLATFORM" ] || { echo "android.jar not found; set SDK/ANDROID_HOME" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/res" "$OUT/gen" "$OUT/classes" "$OUT/dex" "$OUT/assets/www"

# 1. Stage the game as assets/www, which is where MainActivity serves it from.
cd "$ROOT"
cp index.html manifest.webmanifest "$OUT/assets/www/"
cp -r css js icons "$OUT/assets/www/"

# 2. Compile resources, then link them with the manifest and the asset dir.
"$BT/aapt2" compile --dir "$HERE/res" -o "$OUT/res.zip"
"$BT/aapt2" link \
  -o "$OUT/base.apk" \
  -I "$PLATFORM" \
  --manifest "$HERE/AndroidManifest.xml" \
  -A "$OUT/assets" \
  --java "$OUT/gen" \
  --min-sdk-version 24 \
  --target-sdk-version 34 \
  --version-code 2 --version-name 1.1 \
  "$OUT/res.zip"

# 3. Compile the Java, dex it, and fold the dex into the APK.
javac -source 8 -target 8 -bootclasspath "$PLATFORM" -classpath "$PLATFORM" \
  -d "$OUT/classes" $(find "$HERE/java" "$OUT/gen" -name '*.java') 2>/dev/null
"$BT/d8" --lib "$PLATFORM" --min-api 24 --output "$OUT/dex" \
  $(find "$OUT/classes" -name '*.class')
cd "$OUT/dex" && "$BT/aapt" add -f "$OUT/base.apk" classes.dex >/dev/null
cd "$ROOT"

# 4. zipalign then sign with a throwaway debug key (created once, kept out of VCS).
KEY="$HERE/debug.keystore"
if [ ! -f "$KEY" ]; then
  "$JDK/bin/keytool" -genkeypair -keystore "$KEY" -alias dbg \
    -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Sling Drift Debug,O=Local,C=GB" >/dev/null 2>&1
fi
"$BT/zipalign" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias dbg --out "$OUT/slingdrift.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify "$OUT/slingdrift.apk"

echo
echo "APK: $OUT/slingdrift.apk ($(du -h "$OUT/slingdrift.apk" | cut -f1))"
