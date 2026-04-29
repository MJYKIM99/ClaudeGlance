//
//  AppLog.swift
//  ClaudeGlance
//
//  Centralized `os.Logger` instances. Replaces ad-hoc `print(...)`
//  and `NSLog(...)` calls scattered across the codebase.
//
//  Why bother:
//   - Console.app filtering by subsystem/category becomes trivial
//     (`subsystem:com.claudeglance category:ipc`).
//   - Release builds elide debug-level logs by default, so we no
//     longer pay the formatting cost in production.
//   - Categories give us a quick mental map of where a log line
//     originated when triaging user reports.
//

import Foundation
import os

enum AppLog {
    /// Reverse-DNS subsystem identifier shown in Console.app.
    static let subsystem = "com.claudeglance"

    /// IPC layer — Unix socket + HTTP listener.
    static let ipc = Logger(subsystem: subsystem, category: "ipc")

    /// Session state machine, statistics, hook event processing.
    static let session = Logger(subsystem: subsystem, category: "session")

    /// Notch HUD overlay (controller, window, surface).
    static let brow = Logger(subsystem: subsystem, category: "brow")

    /// Floating multi-session HUD window.
    static let hud = Logger(subsystem: subsystem, category: "hud")

    /// Claude Code hook auto-install / diagnostics.
    static let hooks = Logger(subsystem: subsystem, category: "hooks")

    /// AppDelegate lifecycle, menu bar, settings.
    static let app = Logger(subsystem: subsystem, category: "app")
}
