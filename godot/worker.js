// Cloudflare Workers caps a static asset at 25 MiB, and the Godot web export's
// index.wasm is ~36 MiB, so deploying the raw file is rejected with "Asset too
// large". The build therefore stores the wasm gzipped (index.wasm.gz, ~9 MiB,
// under the cap) and this Worker hands the real module back at /index.wasm.
//
// The stored bytes are decompressed here rather than served with a
// Content-Encoding header: setting that header on top of an already-gzipped body
// encodes it a second time, and the browser would receive a gzip blob it cannot
// compile. The gzip magic is checked first so this also does the right thing if
// the runtime has already decoded the asset for us.

const GZIP_MAGIC = [0x1f, 0x8b];

// Stable download URL for the Android build. The APK is attached to a rolling
// `android-latest` release by .github/workflows/build-godot-android.yml.
const ANDROID_APK_URL =
  "https://github.com/PolarNA0/Driftslinger-race/releases/download/android-latest/drift-slinger.apk";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/android" || url.pathname === "/android/") {
      return Response.redirect(ANDROID_APK_URL, 302);
    }

    if (url.pathname === "/index.wasm") {
      const asset = await env.ASSETS.fetch(new URL("/index.wasm.gz", url));
      if (!asset.ok) return asset;

      const stored = new Uint8Array(await asset.arrayBuffer());
      const isGzip =
        stored[0] === GZIP_MAGIC[0] && stored[1] === GZIP_MAGIC[1];
      const body = isGzip
        ? new Response(stored).body.pipeThrough(new DecompressionStream("gzip"))
        : stored;

      return new Response(body, {
        headers: {
          "Content-Type": "application/wasm",
          "Cache-Control": "public, max-age=31536000, immutable",
        },
      });
    }

    return env.ASSETS.fetch(request);
  },
};
