//
//  Defaults.swift
//  ClaudeGlance
//
//  Single source of truth for every UserDefaults / @AppStorage key
//  used across the app. The string literals were previously scattered
//  across SessionManager, ClaudeGlanceApp, HUDWindowController, and
//  the Brow overlay; a typo in any one of them was a silent failure
//  mode (a "missing" preference that was actually mis-keyed).
//
//  All values are namespace-prefixed `String` constants — usable as
//  arguments to UserDefaults APIs and to @AppStorage initializers
//  alike.
//

import Foundation

enum Defaults {
    // MARK: - Notch HUD (experimental)
    static let browHUDEnabled        = "browHUDEnabled"
    static let browAutoPeekEnabled   = "browAutoPeekEnabled"

    // MARK: - Notifications
    static let soundEnabled          = "soundEnabled"
    static let notificationsEnabled  = "notificationsEnabled"

    // MARK: - Statistics (rolling 7-day store)
    static let weeklyStats           = "weeklyStats"

    // Legacy single-day keys, kept readable for migration in
    // SessionManager.loadTodayStats. New code should not write these.
    static let legacyTodayToolCalls       = "todayToolCalls"
    static let legacyTodaySessionsCount   = "todaySessionsCount"
    static let legacyTodayStatsLastReset  = "todayStatsLastReset"

    // MARK: - HUD window
    static let hudPositionX          = "hudPositionX"
    static let hudPositionY          = "hudPositionY"
    static let hudScreenHash         = "hudScreenHash"
    static let hudOpacity            = "hudOpacity"
    static let autoHideIdle          = "autoHideIdle"
    static let idleTimeout           = "idleTimeout"
    static let showToolHistory       = "showToolHistory"
}
