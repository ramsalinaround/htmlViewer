# HTML Viewer for iOS

A small native iPhone/iPad app (SwiftUI + WebKit) for opening and reading `.html` / `.htm` files.

## Features

- **Opens HTML from anywhere**: the built-in file browser (iCloud Drive, On My iPhone, Dropbox and other Files providers), or **Share → HTML Viewer** from Mail, Safari downloads, Messages, etc.
- **Full rendering** with WebKit, including CSS, JavaScript, inline media, and relative CSS/JS/image files sitting next to the HTML (when iOS lets the app read them; see note below).
- **Back / Forward / Reload** for links between local pages, and swipe gestures.
- **Find in page** (magnifying glass in the bottom bar).
- **View Source** with selectable monospaced text, search, and Copy.
- **JavaScript on/off** switch (⋯ menu) for untrusted files.
- Web links open in Safari; `mailto:`/`tel:` links open the right app.
- Files are opened read-only. The app never changes them.
- Web Inspector support, so you can debug pages from Safari on a Mac.

## Building & installing

### With a Mac (Xcode 16 or newer)

1. Open `HTMLViewer.xcodeproj`.
2. Select the **HTMLViewer** target → *Signing & Capabilities* → choose your Team (a free Apple ID works).
   If the bundle ID `com.ramsalinaround.HTMLViewer` is taken, change it to something unique.
3. Plug in your iPhone, pick it as the run destination, and press **Run** (⌘R).
   On first launch, trust the developer profile in *Settings → General → VPN & Device Management*.

Requires iOS 17 or later.

### Without a Mac

Every push runs the **Build** GitHub Actions workflow, which uploads an unsigned
`HTMLViewer-unsigned.ipa` as a build artifact. You can sideload it with a tool
like AltStore or Sideloadly, which signs it with your own Apple ID.

## Using it

- Launch the app → browse to an HTML file → tap it.
- Or in any app: **Share** an `.html` file → **HTML Viewer**.
- Files you copy into *Files → On My iPhone → HTML Viewer* also show up in the app.

**Note on relative resources:** iOS only gives the app access to the file you
opened. Linked CSS, JS, and images next to it load when the app can read them,
for example when the whole folder is inside the app's own *On My iPhone → HTML Viewer*
folder. Single-file HTML (inline styles/scripts, or resources loaded from
`https://`) always works.

## Project layout

```
HTMLViewer/
  HTMLViewerApp.swift          App entry; DocumentGroup in viewer mode
  HTMLDocument.swift           Read-only FileDocument for public.html
  HTMLViewerScreen.swift       Viewer UI and toolbars
  WebViewStore.swift           WKWebView owner, navigation and link policy
  LocalFileSchemeHandler.swift Serves the document and its sibling files to WebKit
  SourceView.swift             "View Source" sheet
Config/Info.plist              Document types, Files app / Open In support
```
