//
//  BrowOverlayPanel.swift
//  ClaudeGlance
//
//  Borderless non-activating panel that floats above the menu bar so the
//  ledge HUD can render against the camera bezel. Click-through is the
//  default; the controller flips it off when the panel is expanded.
//

import AppKit

final class BrowOverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        // Sit above the system menu bar so the ledge artwork is not
        // clipped. NSWindow.Level arithmetic mirrors the project's main
        // HUD panel rather than the CGWindowLevel C bridge.
        level = .mainMenu + 3

        // Default to pass-through so the menu bar / desktop receive
        // clicks. The controller toggles this when the panel expands.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
