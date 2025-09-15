# nuro（ニューロ）
nuro is a minimal, scoop-like runner for distributing PowerShell scripts. With a single command, you can fetch, verify, and run scripts directly from remote sources like GitHub or S3. Lightweight yet flexible, nuro manages versions, hashes, and shims to keep your automation clean and fast.

CONFIGURATION
- GitHub settings are now read from `~/.nuro/config/github.json`.
- Keys:
  - `owner` (string): GitHub owner/user name. Default `nor-void`.
  - `repo` (string): Repository name. Default `nuro`.
  - `ref` (string): Branch or tag name. Default `main` (overridden by `NURO_REF`).
  - `sha` (string, optional): Commit SHA. If non-empty, it takes precedence over `ref`.
- The file is created automatically on first run with defaults.

DEBUG LOGGING
- Default: OFF. Enable with `--debug` or `NURO_DEBUG=1`.
- When enabled, attempted GitHub URLs and PowerShell invocation commands are printed to console and appended to `~/.nuro/logs/nuro-debug.log`.
- Disable explicitly with `--no-debug`.

- PowerShell integration
- When invoked from PowerShell via `bootstrap/nuro.ps1`, the current shell session is used to execute `.ps1` (dot-sourcing + calling `NuroCmd_<name>`), so host-level changes persist in your session.
- To force Python dispatch (spawn a separate PowerShell), set `NURO_USE_CURRENT_POWERSHELL=0` before invoking the bootstrap script.
