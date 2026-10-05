// The page a computer's browser sees when it opens the Wi-Fi Transfer address.
enum TransferWebPage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>HTML Viewer · Wi-Fi Transfer</title>
<style>
:root{--bg:#f5f5f7;--card:#fff;--text:#1d1d1f;--muted:#6e6e73;--line:#e5e5ea;--accent:#e2503f;--accent-soft:#fdebe7;--danger:#d70015}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#f5f5f7;--muted:#98989d;--line:#38383a;--accent:#ff6a4d;--accent-soft:#3a1d17;--danger:#ff453a}}
*{box-sizing:border-box}
body{margin:0;font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--text)}
main{max-width:880px;margin:0 auto;padding:28px 16px 64px}
header{display:flex;align-items:center;gap:14px;margin-bottom:22px}
header h1{font-size:22px;margin:0}
header p{margin:0;color:var(--muted);font-size:13px}
.logo{width:44px;height:44px;border-radius:11px;background:linear-gradient(#f26b33,#d63447);display:grid;place-items:center;color:#fff;font-weight:700;font-size:14px;flex:none}
.drop{border:2px dashed var(--line);border-radius:16px;padding:28px 20px;text-align:center;background:var(--card);transition:border-color .15s,background .15s}
.drop.over{border-color:var(--accent);background:var(--accent-soft)}
.drop p{margin:0 0 14px;color:var(--muted)}
.actions{display:flex;flex-wrap:wrap;gap:8px;justify-content:center}
button{font:inherit;border:0;border-radius:9px;padding:8px 15px;background:var(--accent);color:#fff;cursor:pointer}
button:hover{filter:brightness(1.07)}
button.secondary{background:var(--line);color:var(--text)}
button.link{background:none;color:var(--accent);padding:4px 8px}
button.danger{background:none;color:var(--danger);padding:4px 8px}
label.check{display:inline-flex;gap:6px;align-items:center;color:var(--muted);font-size:13px;margin-top:14px;cursor:pointer}
.progress{margin-top:16px;display:none;text-align:left}
.bar{height:6px;background:var(--line);border-radius:3px;overflow:hidden}
.bar div{height:100%;width:0;background:var(--accent);transition:width .1s}
.progress small{display:block;margin-top:6px;color:var(--muted);overflow-wrap:anywhere}
.error{color:var(--danger);margin-top:12px;display:none;overflow-wrap:anywhere}
.card{background:var(--card);border-radius:16px;margin-top:20px;overflow:hidden}
.toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:8px;padding:12px 16px;border-bottom:1px solid var(--line)}
.crumbs{flex:1;min-width:180px;overflow-wrap:anywhere;font-weight:600}
.crumbs a{color:var(--accent);cursor:pointer}
.crumbs a:last-child{color:var(--text);cursor:default}
.crumbs .sep{color:var(--muted);margin:0 6px;font-weight:400}
table{width:100%;border-collapse:collapse}
td{padding:10px 16px;border-bottom:1px solid var(--line);vertical-align:middle}
tr:last-child td{border-bottom:0}
td.name{overflow-wrap:anywhere}
td.name a{color:var(--text);text-decoration:none;cursor:pointer}
td.name a:hover{color:var(--accent)}
td.meta{color:var(--muted);font-size:13px;white-space:nowrap;text-align:right}
td.ops{white-space:nowrap;text-align:right;width:1%}
.empty{padding:36px 16px;text-align:center;color:var(--muted)}
@media (max-width:600px){td.meta{display:none}}
</style>
</head>
<body>
<main>
<header>
  <div class="logo">&lt;/&gt;</div>
  <div><h1>HTML Viewer</h1><p>Wi-Fi Transfer · keep the Wi-Fi Transfer screen open on your device</p></div>
</header>

<section class="drop" id="drop">
  <p>Drag files or folders here, or</p>
  <div class="actions">
    <button id="pickFiles">Upload Files</button>
    <button id="pickFolder" class="secondary">Upload Folder</button>
  </div>
  <label class="check"><input type="checkbox" id="unzip" checked> Unpack .zip files into folders</label>
  <input type="file" id="files" multiple hidden>
  <input type="file" id="folder" webkitdirectory multiple hidden>
  <div class="progress" id="progress"><div class="bar"><div id="barFill"></div></div><small id="progressText"></small></div>
  <div class="error" id="error"></div>
</section>

<section class="card">
  <div class="toolbar">
    <div class="crumbs" id="crumbs"></div>
    <button class="secondary" id="newFolder">New Folder</button>
    <button class="secondary" id="downloadAll">Download as ZIP</button>
  </div>
  <table><tbody id="list"></tbody></table>
  <div class="empty" id="empty" hidden>This folder is empty. Upload something above.</div>
</section>
</main>

<script>
let current = "";
const $ = id => document.getElementById(id);
const join = (a, b) => a ? a + "/" + b : b;
const enc = p => encodeURIComponent(p);
const downloadURL = p => "/api/download?path=" + enc(p);

function showError(message) {
  const el = $("error");
  el.textContent = message || "";
  el.style.display = message ? "block" : "none";
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  const units = ["KB", "MB", "GB"];
  let i = -1;
  do { bytes /= 1024; i++; } while (bytes >= 1024 && i < units.length - 1);
  return bytes.toFixed(bytes < 10 ? 1 : 0) + " " + units[i];
}

async function errorFrom(response) {
  try { return (await response.json()).error || response.statusText; } catch { return response.statusText; }
}

async function load(path) {
  try {
    const response = await fetch("/api/list?path=" + enc(path));
    if (!response.ok) { showError(await errorFrom(response)); if (path) load(""); return; }
    const data = await response.json();
    current = data.path;
    renderCrumbs();
    renderList(data.entries);
  } catch {
    showError("Can't reach the app. Make sure the Wi-Fi Transfer screen is still open on your device.");
  }
}

function renderCrumbs() {
  const crumbs = $("crumbs");
  crumbs.textContent = "";
  const parts = current ? current.split("/") : [];
  const add = (label, path) => {
    const a = document.createElement("a");
    a.textContent = label;
    a.onclick = () => load(path);
    crumbs.appendChild(a);
  };
  add("HTML Viewer", "");
  parts.forEach((part, i) => {
    const sep = document.createElement("span");
    sep.className = "sep";
    sep.textContent = "›";
    crumbs.appendChild(sep);
    add(part, parts.slice(0, i + 1).join("/"));
  });
}

function renderList(entries) {
  const list = $("list");
  list.textContent = "";
  $("empty").hidden = entries.length > 0;
  for (const entry of entries) {
    const path = join(current, entry.name);
    const row = document.createElement("tr");

    const name = document.createElement("td");
    name.className = "name";
    const link = document.createElement("a");
    link.textContent = (entry.dir ? "📁  " : "📄  ") + entry.name;
    if (entry.dir) link.onclick = () => load(path); else link.href = downloadURL(path);
    name.appendChild(link);

    const meta = document.createElement("td");
    meta.className = "meta";
    const date = entry.modified ? new Date(entry.modified * 1000).toLocaleString() : "";
    meta.textContent = entry.dir ? date : formatSize(entry.size) + " · " + date;

    const ops = document.createElement("td");
    ops.className = "ops";
    const download = document.createElement("button");
    download.className = "link";
    download.textContent = entry.dir ? "Download ZIP" : "Download";
    download.onclick = () => { location.href = downloadURL(path); };
    const remove = document.createElement("button");
    remove.className = "danger";
    remove.textContent = "Delete";
    remove.onclick = () => removeItem(path, entry.name, entry.dir);
    ops.append(download, remove);

    row.append(name, meta, ops);
    list.appendChild(row);
  }
}

async function post(url) {
  const response = await fetch(url, { method: "POST" });
  if (!response.ok) throw new Error(await errorFrom(response));
}

async function removeItem(path, name, isFolder) {
  const what = isFolder ? `the folder “${name}” and everything in it` : `“${name}”`;
  if (!confirm(`Delete ${what}? This can't be undone.`)) return;
  try { await post("/api/delete?path=" + enc(path)); showError(""); } catch (e) { showError(e.message); }
  load(current);
}

$("newFolder").onclick = async () => {
  const name = prompt("New folder name");
  if (!name) return;
  try { await post("/api/mkdir?path=" + enc(join(current, name))); showError(""); } catch (e) { showError(e.message); }
  load(current);
};
$("downloadAll").onclick = () => { location.href = downloadURL(current); };
$("pickFiles").onclick = () => $("files").click();
$("pickFolder").onclick = () => $("folder").click();
$("files").onchange = e => {
  upload([...e.target.files].map(file => ({ file, path: file.name })));
  e.target.value = "";
};
$("folder").onchange = e => {
  upload([...e.target.files].map(file => ({ file, path: file.webkitRelativePath || file.name })));
  e.target.value = "";
};

function uploadOne(item, base, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const unzip = $("unzip").checked ? "&unzip=1" : "";
    xhr.open("PUT", "/api/upload?path=" + enc(join(base, item.path)) + unzip);
    xhr.upload.onprogress = e => onProgress(e.loaded);
    xhr.onload = () => {
      if (xhr.status < 300) return resolve();
      let message = xhr.statusText;
      try { message = JSON.parse(xhr.responseText).error || message; } catch {}
      reject(new Error(message));
    };
    xhr.onerror = () => reject(new Error("Connection lost. Is the Wi-Fi Transfer screen still open?"));
    xhr.send(item.file);
  });
}

let uploading = false;
async function upload(items) {
  // Skip hidden files such as .DS_Store.
  items = items.filter(item => !item.path.split("/").some(part => part.startsWith(".")));
  if (!items.length || uploading) return;
  uploading = true;
  showError("");
  const base = current;
  const total = items.reduce((sum, item) => sum + item.file.size, 0) || 1;
  let done = 0, failed = false;
  $("progress").style.display = "block";
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    $("progressText").textContent = `Uploading ${i + 1} of ${items.length}: ${item.path}`;
    try {
      await uploadOne(item, base, loaded => {
        $("barFill").style.width = Math.min(100, (done + loaded) / total * 100) + "%";
      });
    } catch (e) {
      showError(`${item.path}: ${e.message}`);
      failed = true;
      break;
    }
    done += item.file.size;
  }
  $("barFill").style.width = failed ? $("barFill").style.width : "100%";
  $("progressText").textContent = failed ? "Upload stopped." : `Uploaded ${items.length} ${items.length === 1 ? "file" : "files"}.`;
  setTimeout(() => { $("progress").style.display = "none"; $("barFill").style.width = "0"; }, failed ? 4000 : 2000);
  uploading = false;
  load(current);
}

async function walk(entry, prefix, out) {
  const path = join(prefix, entry.name);
  if (entry.isFile) {
    out.push({ file: await new Promise((resolve, reject) => entry.file(resolve, reject)), path });
  } else if (entry.isDirectory) {
    const reader = entry.createReader();
    let batch;
    do {
      batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject));
      for (const child of batch) await walk(child, path, out);
    } while (batch.length);
  }
}

const drop = $("drop");
let dragDepth = 0;
document.addEventListener("dragenter", e => { e.preventDefault(); dragDepth++; drop.classList.add("over"); });
document.addEventListener("dragover", e => e.preventDefault());
document.addEventListener("dragleave", () => { if (--dragDepth <= 0) { dragDepth = 0; drop.classList.remove("over"); } });
document.addEventListener("drop", async e => {
  e.preventDefault();
  dragDepth = 0;
  drop.classList.remove("over");
  // Entries must be read before the first await, or the browser drops them.
  const entries = [...e.dataTransfer.items]
    .map(item => item.webkitGetAsEntry ? item.webkitGetAsEntry() : null)
    .filter(Boolean);
  const files = [...e.dataTransfer.files];
  const items = [];
  if (entries.length) {
    for (const entry of entries) await walk(entry, "", items);
  } else {
    for (const file of files) items.push({ file, path: file.name });
  }
  upload(items);
});

load("");
</script>
</body>
</html>
"""#
}
