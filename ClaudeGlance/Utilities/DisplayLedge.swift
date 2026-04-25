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
    /// Strategy: the menu bar is split by the ledge into two auxiliary
    /// regions (`auxiliaryTopLeftArea` and `auxiliaryTopRightArea`). The
    /// horizontal distance between their inner edges *is* the ledge width.
    /// Falls back to a conservative pill size on displays without a real
    /// ledge so the HUD still has a sensible footprint.
    var ledgeSize: CGSize {
        let fallback = CGSize(width: 220, height: 32)
        guard hasHardwareLedge else { return fallback }

        let height = safeAreaInsets.top
        let leftAux = auxiliaryTopLeftArea
        let rightAux = auxiliaryTopRightArea

        // Inner-edge measurement. Both regions share the screen's
        // coordinate space, so the right region's leading edge minus the
        // left region's trailing edge equals the ledge cutout width.
        if let left = leftAux, let right = rightAux {
            let inner = right.minX - left.maxX
            // Conservative floor in case AppKit reports a too-small gap.
            let width = max(inner, 180)
            return CGSize(width: width, height: height)
        }

        // Auxiliary regions weren't reported (rare). Use a sane default
        // sized to the typical 14"/16" MacBook Pro ledge.
        return CGSize(width: 200, height: height)
    }
}
