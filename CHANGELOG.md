# Changelog

## [1.7.0] - 2026-11-22

### Added

- **Full lifecycle hook coverage** — Claude Code now installs all 13 hook
  events (`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`,
  `SubagentStart`, `SubagentStop`, `PreCompact`, `Stop`, `StopFailure`) and
  Codex installs its real 11-event set including `Interrupt` and
  `SessionEnd`. Session end interrupts now remove or settle cards
  immediately.
- **macOS Notification Center integration** — waiting / needs-permission
  sessions post a banner carrying the project name and current action;
  clicking the banner shows the HUD and focuses that session's terminal.
- **Session labels** — right-click a card to attach a custom label chip.
- **Pin to top** — right-click a card to pin a session above all others.
- **Full tool timeline** — expanded cards scroll the complete tool-call
  history (up to 50 entries) instead of the last 5.
- **HUD header bar** — session count plus collapse-all and dismiss-all
  (completed/idle only) buttons.
- **中文 / English UI switch** — all HUD, card, and menu bar strings are
  localized; pick the language in Settings.
- **HUD width control** in Settings (260–520pt).

### Changed

- **Adaptive frosted HUD** — native `.popover` material follows system
  light/dark appearance instead of a fixed black window.
- **Priority ordering** — waiting/error sessions always sort to the top;
  cards cap at ~6 with scrolling instead of unbounded height.
- **Attention pulse** — the left edge of waiting/error cards breathes in the
  status color; status meaning moved from colored text to a small dot so
  text stays readable on translucent backgrounds.
- **Solid badges** — terminal and platform badges are filled color chips
  with white glyphs.
- **Compact done cards** — completed and idle sessions render as a single
  row; close button appears on hover.
- **Waiting sessions degrade to idle** after the timeout instead of being
  removed, so requests you missed stay visible.
- **Terminal focus** — clicking the terminal badge or "Focus Terminal"
  activates the session's terminal app.

### Fixed

- **HTTP fallback now binds to loopback** instead of `0.0.0.0`, so other
  machines on the LAN can no longer POST session state.
- **Interrupt events** (`Stop` for Codex / `Interrupt`) settle sessions to
  `completed` instead of leaving stale working cards.
- Codex hook list no longer includes the nonexistent `Notification` event.

### Notes

- Requires **macOS 15.7+**.
- Codex 0.16x+ requires approving hooks once via `/hooks` or Settings.
- Notification banners require a properly signed build; ad-hoc builds can
  construct requests but macOS will not deliver them.
