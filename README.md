# HTML Viewer for iOS

A small native iPhone/iPad app (SwiftUI + WebKit) for opening and reading `.html` / `.htm` files.

## Features

- **Folders**: add any folder from iCloud Drive, On My iPhone, Dropbox, a USB drive or another Files location. The app remembers it across launches, so you can browse every HTML file inside it.
  - **Browse** mode lets you go through the folder and its subfolders one level at a time.
  - **All HTML Files** mode lists every HTML file in the folder and all its subfolders in one list.
  - **Search** finds files by name or path across all subfolders.
  - In the viewer, **Previous / Next File** buttons step through the list, and the "3 of 12" button lets you jump to any file.
- **Relative links work inside folders.** Linked CSS, JavaScript, images, fonts and other pages in the folder all load, and links between pages navigate.
- **Single files** can also be opened in place with *Open Single File…*.
- **File sharing**
  - **Receive:** share an `.html` or `.zip` file to **HTML Viewer** from Mail, Messages, AirDrop, Safari downloads or Files. A copy is saved in the app's folder, and zips are unpacked into a folder.
  - **Wi-Fi Transfer:** open the address the app shows in any browser on your computer. You can upload files or whole folders (drag and drop works, and `.zip` files can be unpacked), download files or folders as `.zip`, and create or delete folders.
  - **Share out:** long-press any file to share it, or any folder to share it as a `.zip`. The share button on a folder screen shares the whole folder.
  - **Files app & Finder:** the app's folder appears under *On My iPhone → HTML Viewer* in Files, and under your device in Finder (or iTunes on Windows).
- **Manage files** in the app's own folder: New Folder, Import Files…, Import Folder…, Rename, Move…, Delete (long-press or swipe).
- **Full-screen browser:** pages fill the whole display, with no navigation bar or status bar.
  - A small floating control bar slides away as you scroll down and comes back when you scroll up or reach the top or bottom. When it's hidden, tap the little handle at the bottom to bring it back. *Hide Controls* tucks it away on demand.
  - **Page Size** (− / % / +) zooms the page from 50% to 300%; smaller fits more on screen. It's remembered across pages and launches.
  - **Edge to Edge** lets pages draw under the notch and home indicator. **Desktop Site** asks for the wider desktop layout.
  - Pull down to reload. Back / Forward, swipe gestures and **Find on Page** work as usual.
  - Web links open inside the browser (Open in Safari is in the ⋯ menu). **Go to Address…** opens any website or searches, and so does **Open Web Address…** on the home screen.
- **View Source** with selectable monospaced text, search, and Copy.
- **JavaScript on/off** switch (⋯ menu) for untrusted files.
- `mailto:`/`tel:` links open the right app. Web pages can't open or read your local files.
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

Every push runs the **Build** GitHub Actions workflow, which runs the tests and uploads an unsigned
`HTMLViewer-unsigned.ipa` as a build artifact. You can sideload it with a tool
like AltStore or Sideloadly, which signs it with your own Apple ID.

## Using it

1. Launch the app → **Add Folder…** → pick the folder that holds your HTML files.
2. Tap the folder, then tap any file. Switch to **All HTML Files** to see everything in its subfolders, or pull down to search.
3. Inside a page, use the floating bar's ↑ / ↓ buttons to go to the previous or next file in the list, or tap "3 / 12" to jump to any file. Tap ✕ to go back to the list.

Swipe left on a saved folder to remove it. The app only forgets the folder; nothing is deleted.

### Getting files onto the device

- **From another app:** share the `.html` or `.zip` → **HTML Viewer**. It's saved under **On This Device → HTML Viewer Folder** and opened.
- **From a computer over Wi-Fi:** **On This Device → Wi-Fi Transfer**, then open the address shown (e.g. `http://192.168.1.20:8080`) in a browser on the same network. The server only runs while that screen is open, and anyone on the same network can reach it during that time.
- **From a computer by cable:** in Finder (Mac) or iTunes (Windows), select the device → *Files* → *HTML Viewer*, and drag files in.
- **Inside the app:** in **HTML Viewer Folder**, tap **+** → *Import Files…* or *Import Folder…*.

**Single files vs. folders:** iOS only lets the app read what you pick. A single
file opened on its own can't load CSS, JS or images that sit next to it,
unless they're inline or come from `https://`. Add the containing folder instead
to get everything.

## Project layout

```
HTMLViewer/
  HTMLViewerApp.swift          App entry
  ContentView.swift            Navigation, folder/file pickers, saving files shared to the app
  Library.swift                Saved folders (security-scoped bookmarks)
  HomeView.swift               Folder list
  FolderView.swift             Browse / All HTML Files / search, sharing and file management
  MoveSheet.swift              Destination picker for Move…
  DocumentPicker.swift         System picker for Import Files / Import Folder
  AppFiles.swift               Import (with unzip), rename, move, delete in the app's folder
  ZipArchive.swift             Zip extraction (stored/deflate) and folder-to-zip
  TransferServer.swift         Wi-Fi Transfer HTTP API (Network framework)
  HTTPConnection.swift         Minimal HTTP/1.1 request/response handling
  TransferWebPage.swift        The browser page served by Wi-Fi Transfer
  TransferView.swift           Wi-Fi Transfer screen
  FileSystem.swift             Directory scanning, coordinated (iCloud-aware) reads
  HTMLViewerScreen.swift       Full-screen browser UI and floating controls
  WebViewStore.swift           WKWebView owner: navigation, auto-hide, zoom, viewer settings
  LocalFileSchemeHandler.swift Serves files in the granted folder to WebKit
  SourceView.swift             "View Source" sheet
Config/Info.plist              Document types (HTML, zip), file sharing, local network
HTMLViewerTests/               Unit tests: zip, file operations, Wi-Fi Transfer server, browser
```

Run the tests with ⌘U in Xcode. CI also runs them on a simulator.
