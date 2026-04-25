//
//  RegionalHitHost.swift
//  ClaudeGlance
//
//  NSHostingView that limits hit-testing to a caller-provided region so
//  clicks that land outside the visible silhouette pass through to the
//  windows beneath. The full-screen-width host is otherwise opaque to
//  AppKit's hit-test pipeline.
//

import AppKit
import SwiftUI

final class RegionalHitHost<Content: View>: NSHostingView<Content> {
    /// Returns the active hit region in window-local coordinates.
    /// Anything outside the rect lets the click fall through.
    var activeRegion: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeRegion().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
