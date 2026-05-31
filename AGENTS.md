# AGENTS.md

Guidance for agents working in this folder.

## Project Shape

This folder contains a Single Player Tarkov setup plus a small web controller.

- Single-player EFT/SPT install: `C:\Games\EscapeFromTarkov\EscapeFromTarkov`
- Coop SPT server install: `C:\Games\EscapeFromTarkov\EFT coop`
- Web controller project: `C:\Games\EscapeFromTarkov\Web Server`
- Original PowerShell launcher: `C:\Games\EscapeFromTarkov\Launch-SPT.ps1`

The web controller is the main maintained code here. It serves a dark web UI for launching/stopping SPT servers, headless EFT, live logs, and browsing/editing selected EFT folders.

## Ownership Rules

Be conservative. Do not modify game/SPT install files unless the user explicitly asks for that exact file.

Files created or maintained by this assistant are:

- `C:\Games\EscapeFromTarkov\Launch-SPT.cmd`
- `C:\Games\EscapeFromTarkov\Launch-SPT.ps1`
- Everything under `C:\Games\EscapeFromTarkov\Web Server`

Avoid touching:

- `C:\Games\EscapeFromTarkov\EscapeFromTarkov`
- `C:\Games\EscapeFromTarkov\EFT coop`
- `C:\Games\EscapeFromTarkov\mods`

Exception: read from these folders when needed for file listings, logs, or verification. User-requested file edits through the web UI may target the SP/Coop roots, but agent code changes should stay in the launcher/web-controller files unless clearly approved.

## Web Controller

Important files:

- `Web Server\Start-SPT-Web-Control.cmd`: starts the web controller.
- `Web Server\SPT-Web-Control.ps1`: lightweight HTTP server and request router.
- `Web Server\SPT-Web-Control.psm1`: process control, file API, logs, config/state helpers.
- `Web Server\Tests-SPT-Web-Control.ps1`: helper tests.
- `Web Server\config.json`: web port and password. Defaults are port `8787`, password `0000`.
- `Web Server\state.json`: runtime state. Avoid hand-editing unless debugging state.
- `Web Server\www\index.html`: UI structure.
- `Web Server\www\style.css`: dark theme and layouts.
- `Web Server\www\app.js`: browser-side behavior.

The web UI currently supports:

- Launch SP + headless.
- Launch Coop + headless.
- Restart server + headless.
- Restart only headless.
- Stop server + headless.
- Live split logs for server and BepInEx.
- File manager tab for SP and Coop roots.
- Split view toggles for SP/Coop folder panes.
- Upload, drag/drop upload, move-to-trash delete, editable text files, Ctrl+S save, and current-folder search.

Deletion in the web UI must move files into `Web Server\Trash`; do not permanently delete user files unless specifically requested.

## Process Control Notes

Server executables:

- SP server: `C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\SPT.Server.exe`
- Coop server: `C:\Games\EscapeFromTarkov\EFT coop\SPT\SPT.Server.exe`
- Headless manager: `C:\Games\EscapeFromTarkov\EscapeFromTarkov\FikaHeadlessManager.exe`

Headless stop must account for `EscapeFromTarkov.exe`, not only the manager process.

Server readiness is based on `127.0.0.1:6969`.

If stopping/restarting processes, be careful to target only SPT server/headless/EFT processes involved in this setup.

## Logs

Server logs:

- SP: `C:\Games\EscapeFromTarkov\EscapeFromTarkov\SPT\user\logs\spt`
- Coop: `C:\Games\EscapeFromTarkov\EFT coop\SPT\user\logs\spt`

Use the newest SPT log file, for example `spt20260512.log`. Do not use `launcher.log` as the server log.

BepInEx log:

- `C:\Games\EscapeFromTarkov\EscapeFromTarkov\BepInEx\FullLogOutput.log`

The UI should show only log lines created after the web controller starts a session; do not dump previous historical logs before launch.

## Coding Guidelines

- Keep the web controller lightweight. Avoid unbounded polling, unbounded in-memory log growth, or repeated full-file reads where a small tail is enough.
- Keep the UI simple, dark, and practical.
- Preserve the left/right log split: server logs on the left, BepInEx logs on the right.
- Preserve the Files tab split behavior:
  - SP and Coop toggles on: both folder panes plus editor.
  - One toggle on: one folder pane plus editor.
  - Both toggles off: editor only.
- For text returned to the browser, return plain strings where the UI expects strings. Prior bugs showed `[object Object]` when objects were assigned to log/editor text.
- Non-editable files should be grayed out, sorted below editable files, and should use the normal cursor.
- Use `apply_patch` for manual edits.
- Avoid unrelated formatting churn.

## Verification

Useful checks from this project:

```powershell
node --check 'C:\Games\EscapeFromTarkov\Web Server\www\app.js'

powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Games\EscapeFromTarkov\Web Server\Tests-SPT-Web-Control.ps1'

$files = @(
  'C:\Games\EscapeFromTarkov\Web Server\SPT-Web-Control.ps1',
  'C:\Games\EscapeFromTarkov\Web Server\SPT-Web-Control.psm1',
  'C:\Games\EscapeFromTarkov\Web Server\Tests-SPT-Web-Control.ps1'
)
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "$file parser errors: $($errors | Out-String)" }
}
```

For UI/layout changes, start the web controller and verify in a browser at:

```text
http://127.0.0.1:8787/
```

If port `8787` is already in use, do not kill it casually. First identify whether it is the user's running web controller.

## User Preference

The user has repeatedly emphasized:

- Do not modify files you did not create unless asked.
- Keep it simple.
- Ask when clarification is truly needed, but implement approved changes directly.
- The tool is for local LAN use from another PC, so keep network access working via the configured port.
