# Notes Sync App (macOS, SwiftUI)

Native macOS desktop app to keep lecture PDFs synced from public links.

Supported sources:
- Public Yandex Disk links
- Yandex wrapper links (`docs.yandex.ru`, `disk.360.yandex.ru`)
- `ya-disk-public://...` links (with optional inner file path)
- Public Yandex folder links (`disk.yandex.../d/...`, `disk.360.yandex.ru/d/...`)
- Public Google Drive file links
- Public Google Docs/Sheets/Slides links (exported to PDF automatically)
- Dropbox shared links (`dropbox.com/...`, converted to direct download)
- GitHub blob links (`github.com/.../blob/...`, converted to raw)
- Direct PDF links

## Features
- Add, edit, delete note sources in a GUI table.
- Keep each note linked to one source URL.
- Support source links that point to full public folders.
- Auto-sync every N minutes (configurable in the app).
- Compare file hashes and replace local files only if changed.
- Keep an indexed local list of files from folder sources.
- Open any synced local file directly from the app.

## Run
```bash
cd /Users/andrew/.codex/workspaces/default/notes_sync_app
swift run
```

## Launch as macOS app (.app)
```bash
cd /Users/andrew/.codex/workspaces/default/notes_sync_app
./scripts/rebuild_and_install.sh
```

This installs:
- `~/Applications/NotesSyncApp.app` (built app)
- `~/Applications/NotesSyncApp Launcher.app` (auto-update launcher)
- `~/Desktop/NotesSyncApp.app` (shortcut to launcher)

Use `~/Desktop/NotesSyncApp.app` (or drag `~/Applications/NotesSyncApp Launcher.app` to Dock).
Every launch from this shortcut rebuilds from current source, reinstalls, and opens the fresh app.

Manual one-command update + open:

```bash
cd /Users/andrew/.codex/workspaces/default/notes_sync_app
./scripts/update_installed_app.sh
```

## Data storage
The app writes data to:
- `~/.notes-sync-app/config.json`
- `~/.notes-sync-app/pdfs/`

## Notes
- Auto-sync runs while the app is open.
- For Google Drive, use public links to files (for example `https://drive.google.com/file/d/<ID>/view`).
- For Yandex Disk, both direct public links and `docs.yandex.ru` wrappers are accepted.
- If you provide a Yandex public folder link, the app syncs all files from that folder (including nested folders).
