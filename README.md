# HTML Viewer for iOS

A small native iPhone/iPad app (SwiftUI + WebKit) for opening and reading `.html` / `.htm` files.

## Features

- **Folders**: add any folder from iCloud Drive, On My iPhone, Dropbox, a USB drive or another Files location. The app remembers it across launches, so you can browse every HTML file inside it.
  - **Browse** mode lets you go through the folder and its subfolders one level at a time.
  - **All HTML Files** mode lists every HTML file in the folder and all its subfolders in one list.
  - **Search** finds files by name or path across all subfolders.
  - In the viewer, **Previous / Next File** buttons step through the list, and the "3 of 12" button lets you jump to any file.
- **Relative links work inside folders.** Linked CSS, JavaScript, images, fonts and other pages in the folder all load, and links between pages navigate.
- **Single files** can also be opened with *Open Single File…* or **Share → HTML Viewer** from Mail, Messages, Safari downloads and other apps.
- **Full rendering** with WebKit, with Back / Forward for links, swipe gestures, and **Find in page**.
- **View Source** with selectable monospaced text, search, and Copy.
- **JavaScript on/off** switch (⋯ menu) for untrusted files.
- Web links open in Safari; `mailto:`/`tel:` links open the right app.
- Files are opened read-only. The app never changes them.
- iCloud files that aren't downloaded yet are fetched when you open them.

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

1. Launch the app → **Add Folder…** → pick the folder that holds your HTML files.
2. Tap the folder, then tap any file. Switch to **All HTML Files** to see everything in its subfolders, or pull down to search.
3. Inside a page, use the bottom bar to go to the previous or next file in the list.

Swipe left on a saved folder to remove it. The app only forgets the folder; nothing is deleted.
Files you copy into *Files → On My iPhone → HTML Viewer* appear under **On This Device**.

**Single files vs. folders:** iOS only lets the app read what you pick. A single
file opened on its own can't load CSS, JS or images that sit next to it,
unless they're inline or come from `https://`. Add the containing folder instead
to get everything.

## Project layout

```
HTMLViewer/
  HTMLViewerApp.swift          App entry
  ContentView.swift            Navigation, folder/file pickers, "Open in" handling
  Library.swift                Saved folders (security-scoped bookmarks)
  HomeView.swift               Folder list
  FolderView.swift             Browse / All HTML Files / search
  FileSystem.swift             Directory scanning, coordinated (iCloud-aware) reads
  HTMLViewerScreen.swift       Viewer UI, toolbars, previous/next file
  WebViewStore.swift           WKWebView owner, navigation and link policy
  LocalFileSchemeHandler.swift Serves files in the granted folder to WebKit
  SourceView.swift             "View Source" sheet
Config/Info.plist              Document types, Files app / Open In support
```
