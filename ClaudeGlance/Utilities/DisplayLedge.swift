//
//  DisplayLedge.swift
//  ClaudeGlance
//
//  Hardware "ledge" detection for the camera housing on internal displays.
//  We measure the ledge by reading the gap between the two auxiliary
//  status-bar regions reported by AppKit, rather than subtracting from
//  the full screen width — this expresses the geometry directly and
//  avoids relying on safeAreaInsets being non-zero on every macOS build.
//

import AppKit

extension NSScreen {
    /// Whether this display has a hardware camera ledge cutout.
    /// The system only assigns a non-zero top safe-area inset on screens
    /// whose physical bezel includes the cutout.
    var hasHardwareLedge: Bool {
        safeAreaInsets.top > 0
    }

    /// Whether this is the machine's internal display panel.
    var isInternalPanel: Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let raw = deviceDescription[key] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(raw) != 0
    }

    /// Pick the internal panel if any is connected, otherwise the system-
    /// designated main display. Used to host the ledge HUD by default.
    static var internalOrMain: NSScreen? {
        screens.first(where: { $0.isInternalPanel }) ?? NSScreen.main
    }

    /// Width × height of the camera ledge in points.
    ///
    /// Strategy: the cutout is horizontally centered on the display, so
    /// we recover its footprint by measuring how far one auxiliary
    /// status-bar region sits from the display centerline and mirroring
    /// across that line. This avoids relying on full-width arithmetic
    /// and works even when only one auxiliary region is reported.
    var ledgeSize: CGSize {
        let fallback = CGSize(width: 220, height: 32)
        guard hasHardwareLedge else { return fallback }

        let height = safeAreaInsets.top
        let centerline = frame.midX
        let halfSpan: CGFloat

        if let trailing = auxiliaryTopRightArea?.minX {
            // Trailing region's leading edge is the cutout's right edge.
            halfSpan = max(0, trailing - centerline)
        } else if let leading = auxiliaryTopLeftArea?.maxX {
            // Fall back to the leading region if the trailing one is
            // unavailable; the cutout is symmetric so either side works.
            halfSpan = max(0, centerline - leading)
        } else {
            return CGSize(width: 200, height: height)
        }

        // Mirror across the centerline. Floor to a usable footprint in
        // case AppKit reports a degenerately narrow span.
        let footprint = max(halfSpan * 2, 180)
        return CGSize(width: footprint, height: height)
    }
}
