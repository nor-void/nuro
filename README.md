# nuro（ニューロ）
nuro is a minimal, scoop-like runner for distributing PowerShell scripts. Fetch and run `cmds/<name>.ps1` directly from remote repositories like GitHub, with optional commit pinning and simple local caching.

CONFIGURATION
- App config: `~/.nuro/config/config.json`
  - `official_bucket_base` (string): Base URL for the official bucket. Default `https://raw.githubusercontent.com/nor-void/nuro/main`.
  - Created automatically on first run if missing.
- Registry: `~/.nuro/config/buckets.json`
  - `buckets`: Array of bucket objects. Example:
    - `{ "name": "official", "uri": "raw::https://raw.githubusercontent.com/nor-void/nuro/main", "priority": 100, "trusted": true }`
    - Optional: add `"sha1-hash": "<commit-sha>"` to pin the bucket to a specific commit.
  - `pins`: Object mapping `command` to `bucketName` to force which bucket to use per command.
  - File is created automatically if missing and normalized on updates.

COMMAND RESOLUTION
- Resolution order: `bucket hint (name:cmd)` → `pins[cmd]` → highest `priority` bucket.
- Each bucket `uri` supports:
  - `github::owner/repo@ref` → fetch from GitHub raw at that branch/tag; `sha1-hash` overrides `ref`.
  - `raw::https://host/base` → treated as `{base}/cmds/<name>.ps1`.
  - `local::<path>` → treated as `<path>/cmds/<name>.ps1`.

USAGE DISPLAY
- Python (`nuro`): Shows a fixed-width table with columns “コマンド  種別  使用例” and pads each column so it aligns in monospaced CUI (full-width characters accounted for).
  - Command list: By default uses local cache only; if the cache is empty, fetches the list from GitHub. Use `--refresh` to force listing from GitHub.
  - Usage text: Cached in `~/.nuro/cache/usage/<bucket>/<name>.txt`. When available, it is used directly without executing PowerShell. If missing or when `--refresh` is specified, runs the PowerShell `NuroUsage_<name>` to refresh the cache.
  - Script cache: `.ps1` files are cached in `~/.nuro/cache/cmds/ps1/<bucket>/` and fetched on-demand only when missing, respecting `sha1-hash`.
  - `--refresh` clears both caches (script and usage) before recreating them.
- PowerShell (`bootstrap/nuro.ps1`): Prints a simple list when called without args and honors `sha1-hash` for the official bucket when listing and executing commands.

LOG FILES
- Detailed activity is appended to `~/.nuro/logs/nuro-debug.log` automatically for troubleshooting.

POWERSHELL INTEGRATION
- Invoking via `bootstrap/nuro.ps1` uses the current PowerShell session to execute `.ps1` (dot-source + `NuroCmd_<name>`), so changes persist in the session.
- To force Python dispatch (spawn a separate PowerShell), set environment `NURO_USE_CURRENT_POWERSHELL=0` before invoking the bootstrap script.

PINNING EXAMPLE
- To pin the official bucket to a commit:
  1. Edit `~/.nuro/config/buckets.json` and add `"sha1-hash": "<commit-sha>"` to the `official` bucket.
  2. Run `nuro` (Python) or `pwsh bootstrap/nuro.ps1` (PowerShell). Listing and command resolution use the pinned commit.
