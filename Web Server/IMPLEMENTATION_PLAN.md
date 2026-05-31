# SPT Web Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a LAN-accessible dark web dashboard for starting, restarting, stopping, and monitoring SPT server/headless processes.

**Architecture:** A PowerShell `HttpListener` backend serves static frontend files and JSON API routes. A helper module owns config, process, log, and classification logic so non-destructive behavior can be tested without starting game processes.

**Tech Stack:** Windows PowerShell, .NET `HttpListener`, HTML/CSS/vanilla JavaScript, JSON config/state files.

---

### Task 1: Testable Helper Module

**Files:**
- Create: `C:\Games\EscapeFromTarkov\Web Server\Tests-SPT-Web-Control.ps1`
- Create: `C:\Games\EscapeFromTarkov\Web Server\SPT-Web-Control.psm1`

- [ ] Write tests for default config creation, route path constants, log line classification, and newest log selection.
- [ ] Run tests and confirm they fail because the module is missing.
- [ ] Implement helper module functions.
- [ ] Run tests and confirm they pass.

### Task 2: Web Server

**Files:**
- Create: `C:\Games\EscapeFromTarkov\Web Server\SPT-Web-Control.ps1`
- Create: `C:\Games\EscapeFromTarkov\Web Server\Start-SPT-Web-Control.cmd`
- Create: `C:\Games\EscapeFromTarkov\Web Server\config.json`
- Create: `C:\Games\EscapeFromTarkov\Web Server\state.json`

- [ ] Add config-backed server startup on configurable port, default `8787`.
- [ ] Add password-protected JSON API routes.
- [ ] Add launch/restart/stop actions that kill existing SPT/headless processes before starting selected components.
- [ ] Add log APIs for newest active server log and BepInEx `FullLogOutput.log`.

### Task 3: Frontend Dashboard

**Files:**
- Create: `C:\Games\EscapeFromTarkov\Web Server\www\index.html`
- Create: `C:\Games\EscapeFromTarkov\Web Server\www\style.css`
- Create: `C:\Games\EscapeFromTarkov\Web Server\www\app.js`

- [ ] Add dark dashboard layout with controls at the top.
- [ ] Add left/right log panes: server on the left, BepInEx on the right.
- [ ] Add simple password gate and live polling.
- [ ] Add colored log rows for errors, warnings, debug/trace, and normal lines.

### Task 4: Verification

**Files:**
- Verify all created files under `C:\Games\EscapeFromTarkov\Web Server`.

- [ ] Run helper tests.
- [ ] Parse PowerShell scripts for syntax errors.
- [ ] Confirm expected config, paths, routes, and UI files exist.
- [ ] Do not start real SPT/headless processes during automated verification.
