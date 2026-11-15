package com.slingdrift.app;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import java.io.IOException;
import java.io.InputStream;
import java.net.URLConnection;
import java.util.HashMap;
import java.util.Map;

/**
 * Hosts the Sling Drift web app in a WebView.
 *
 * The game is the same code as the web build; it lives in assets/www and is
 * served through a virtual origin so relative module imports resolve. The game
 * plays entirely offline; the only network use is posting a finished run to the
 * leaderboard, which the app asks for with the INTERNET permission.
 */
public class MainActivity extends Activity {

    private static final String ORIGIN = "https://appassets.androidplatform.net/assets/www/";

    // Legacy hook: the old same-origin leaderboard API used to be pointed at from
    // here. Uploads now go to Supabase, whose URL and anon key are read from the
    // meta tags in the bundled index.html, so this stays empty. It is still
    // exposed to the page as SlingDriftNative.apiBase() for older builds.
    private static final String API_BASE = "";

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF0B0D12);
        webView = new WebView(this);
        root.addView(webView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        // Scores are kept in localStorage; the packaged build never registers a
        // service worker, so a stale offline shell cannot shadow the APK files.
        s.setUserAgentString(s.getUserAgentString() + " SlingDriftApp/1.0");

        webView.setBackgroundColor(0xFF0B0D12);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return serveAsset(request.getUrl().toString());
            }

            @SuppressWarnings("deprecation")
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
                return serveAsset(url);
            }
        });

        // Let the page know where the leaderboard lives. The page's own origin is
        // a virtual one, so a relative /api would resolve to nothing.
        webView.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public String apiBase() { return API_BASE; }
        }, "SlingDriftNative");

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                return true;
            }
        });

        webView.loadUrl(ORIGIN + "index.html");
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    /** Serve the bundled game from assets/www with correct MIME types. */
    private WebResourceResponse serveAsset(String url) {
        if (url == null) return null;
        if (!url.startsWith(ORIGIN)) {
            // Anything outside our own asset origin is a real request (a run being
            // posted to the leaderboard). Returning null lets the WebView handle it
            // normally, which is what makes the upload work.
            return null;
        }
        String path = url.substring(ORIGIN.length());
        int hash = path.indexOf('#');
        if (hash >= 0) path = path.substring(0, hash);
        int q = path.indexOf('?');
        if (q >= 0) path = path.substring(0, q);
        if (path.isEmpty()) path = "index.html";
        try {
            InputStream in = getAssets().open("www/" + path);
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-cache");
            return new WebResourceResponse(guessMime(path), "utf-8", 200, "OK", headers, in);
        } catch (IOException e) {
            return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
                    new HashMap<String, String>(), null);
        }
    }

    private String guessMime(String path) {
        String lower = path.toLowerCase();
        if (lower.endsWith(".html")) return "text/html";
        if (lower.endsWith(".js") || lower.endsWith(".mjs")) return "text/javascript";
        if (lower.endsWith(".css")) return "text/css";
        if (lower.endsWith(".json")) return "application/json";
        if (lower.endsWith(".webmanifest")) return "application/manifest+json";
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".svg")) return "image/svg+xml";
        if (lower.endsWith(".woff2")) return "font/woff2";
        String guess = URLConnection.guessContentTypeFromName(lower);
        return guess != null ? guess : "application/octet-stream";
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            dispatchBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        dispatchBack();
    }

    /** Let the game close its own overlay first; only finish when it has none. */
    private void dispatchBack() {
        if (webView == null) { finish(); return; }
        webView.evaluateJavascript(
                "(function(){try{return window.SlingDriftBack?window.SlingDriftBack():false}catch(e){return false}})()",
                new ValueCallback<String>() {
                    @Override
                    public void onReceiveValue(String value) {
                        boolean handled = value != null && value.contains("true");
                        if (!handled) finish();
                    }
                });
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (webView != null) webView.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.loadUrl("about:blank");
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
