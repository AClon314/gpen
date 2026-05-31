# Browser Extension Host

This host packages the browser-first v0.1 demo as:

- a transparent full-page canvas overlay that scrolls with the document
- a fixed top-right toolbar with `Select`, `Draw`, and `Lasso` tools
- pen-capable pointer input routed through the minimal Zig stroke pipeline in WASM

## Build

```sh
/home/n/.pixi/bin/zig build demo --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
/home/n/.pixi/bin/zig build xpi-firefox --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
/home/n/.pixi/bin/zig build xpi-firefox -Dadb=true --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
```

This produces unpacked extension directories at:

- `zig-out/browser-ext-chrome`
- `zig-out/browser-ext-firefox`

And an unsigned Firefox package at:

- `zig-out/gpen-debug-firefox-unsigned.xpi`
- `zig-out/gpen-debug-firefox-signed.xpi` when `secret.json` is present and AMO signing succeeds

Load either directory as an unpacked extension in the target browser. The overlay injects into
matched pages automatically; `Select` lets the underlying page behave normally, while `Draw` and
`Lasso` capture input on the transparent canvas.

## AMO Signing

The signing flow only looks for a repo-root `secret.json`.

If `secret.json` is missing but `scripts/secret.json` exists, `zig build xpi-firefox` copies that
file to the repo root first and warns that you still need to fill in real AMO JWT credentials from:

- <https://addons.mozilla.org/en-US/developers/addon/api/key/>

Expected shape:

```json
{
  "firefox": {
    "issuer": "user:123456:78",
    "secret": "replace-with-your-amo-jwt-secret"
  }
}
```

The signing script also accepts the older flat key names such as `api_key` / `api_secret`.

Behavior:

- if `secret.json` exists, `zig build xpi-firefox` also uploads the unsigned XPI to AMO and saves
  the signed package to `zig-out/gpen-debug-firefox-signed.xpi`
- if `secret.json` exists but still contains empty placeholder values, the build keeps treating it
  as unsigned-only and prints a warning instead of attempting AMO signing
- if `secret.json` is missing, the build copies `scripts/secret.json` into the repo root when
  available, prints a warning, and only produces the unsigned package for that run
- `adb push` is only executed when you pass `-Dadb=true`

For Firefox on Android, install the AMO-signed `.xpi` from file. The unsigned artifact is only an
intermediate package. The Firefox manifest also declares `browser_specific_settings.gecko_android`
so AMO can mark signed builds as Android-compatible.
