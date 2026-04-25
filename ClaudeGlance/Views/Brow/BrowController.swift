//
//  BrowController.swift
//  ClaudeGlance
//
//  Drives the dormant ↔ peek ↔ expanded transitions for the ledge HUD.
//  Hover detection runs on a 100ms RunLoop timer because global mouse-
//  moved events are unreliable: they stop firing the moment the cursor
//  parks and can be swallowed by foreground windows. Polling the mouse
//  location is cheap and consistent.
//

import AppKit
import Combine
import Foundation

enum BrowPhase {
    case dormant   // Idle pill / side chips
    case peek      // Brief flash (e.g. when a session updates)
    case expanded  // Full session-list panel
}

final class BrowController: ObservableObject {
    @Published var phase: BrowPhase = .dormant
    @Published var isPulsing: Bool = false

    @Published private(set) var dormantSize: CGSize
    @Published private(set) var expandedSize: CGSize
    @Published private(set) var displayBounds: CGRect
    @Published private(set) var hasHardwareLedge: Bool = false

    private var pendingExpand: DispatchWorkItem?
    private var clickMonitorGlobal: Any?
    private var clickMonitorLocal: Any?
    private var hoverPoll: Timer?
    private var hoverArmedAt: Date?
    private var leftAt: Date?
    /// While set in the future, the hover poll will not auto-collapse.
    /// Used to hold a transient "peek" expansion open long enough for
    /// the user to register that something happened.
    private var peekDeadline: Date?

    /// Dwell required before hover triggers expand.
    private let expandDwell: TimeInterval = 0.35
    /// Time the cursor must be outside before auto-collapse.
    private let collapseDwell: TimeInterval = 0.45

    init(dormantSize: CGSize, expandedSize: CGSize, displayBounds: CGRect,
         hasHardwareLedge: Bool) {
        self.dormantSize = dormantSize
        self.expandedSize = expandedSize
        self.displayBounds = displayBounds
        self.hasHardwareLedge = hasHardwareLedge
        installClickMonitors()
        startHoverPoll()
    }

    deinit {
        teardownClickMonitors()
        hoverPoll?.invalidate()
        pendingExpand?.cancel()
    }

    // MARK: - Geometry (screen coordinates, AppKit origin = bottom-left)

    /// Width of each side chip flanking a hardware ledge.
    static let chipFlankWidth: CGFloat = 130

    /// Hit-test region for the dormant state. Inflated to include the
    /// adjacent chips on hardware-ledge displays plus a downward buffer
    /// so the hover target is forgiving.
    var dormantHitRegion: CGRect {
        let core = CGRect(
            x: displayBounds.midX - dormantSize.width / 2,
            y: displayBounds.maxY - dormantSize.height,
            width: dormantSize.width,
            height: dormantSize.height
        )
        let flankPad: CGFloat = hasHardwareLedge ? Self.chipFlankWidth : 12
        return CGRect(
            x: core.minX - flankPad,
            y: core.minY - 14,
            width: core.width + flankPad * 2,
            height: core.height + 14
        )
    }

    /// Hit-test region for the expanded panel.
    var expandedHitRegion: CGRect {
        CGRect(
            x: displayBounds.midX - expandedSize.width / 2,
            y: displayBounds.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    func contains(_ point: CGPoint, in region: BrowPhase) -> Bool {
        switch region {
        case .expanded: return expandedHitRegion.contains(point)
        default:        return dormantHitRegion.contains(point)
        }
    }

    // MARK: - Phase transitions

    func expand(via reason: String = "manual") {
        pendingExpand?.cancel()
        guard phase != .expanded else { return }
        NSLog("[ClaudeGlance][Brow] expand(via=%@) hit=%@",
              reason, NSStringFromRect(dormantHitRegion))
        phase = .expanded
    }

    func collapse() {
        pendingExpand?.cancel()
        guard phase != .dormant else { return }
        NSLog("[ClaudeGlance][Brow] collapse()")
        phase = .dormant
    }

    /// Re-target the controller to a different display geometry.
    func retarget(dormantSize: CGSize, expandedSize: CGSize, displayBounds: CGRect,
                  hasHardwareLedge: Bool) {
        if phase == .expanded { collapse() }
        self.dormantSize = dormantSize
        self.expandedSize = expandedSize
        self.displayBounds = displayBounds
        self.hasHardwareLedge = hasHardwareLedge
        hoverArmedAt = nil
        leftAt = nil
    }

    func pulseOnce() {
        isPulsing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.isPulsing = false
        }
    }

    /// Briefly expand to surface a meaningful state change. The hover
    /// poll respects `peekDeadline` so the panel is held open for the
    /// full duration even when the cursor is nowhere near it. After the
    /// deadline expires, normal collapse-on-leave behaviour resumes —
    /// so if the user moved the cursor onto the panel during the peek,
    /// it will keep the panel open via the regular hover path.
    func peekTransiently(duration: TimeInterval = 2.5) {
        guard phase == .dormant else { return }
        let deadline = Date().addingTimeInterval(duration)
        peekDeadline = deadline
        expand(via: "peek")
        NSLog("[ClaudeGlance][Brow] peek for %.1fs", duration)

        // After the hold expires, let the hover poll decide what to do.
        // If the cursor isn't engaged we collapse here directly so the
        // user doesn't have to wait for the next 100ms tick.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self = self, self.peekDeadline == deadline else { return }
            self.peekDeadline = nil
            let mouse = NSEvent.mouseLocation
            let engaged =
                self.contains(mouse, in: .expanded) ||
                self.contains(mouse, in: .dormant)
            if self.phase == .expanded, !engaged {
                self.collapse()
            }
        }
    }

    // MARK: - Input

    private func installClickMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown]

        clickMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.onClick(NSEvent.mouseLocation)
        }
        clickMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.onClick(NSEvent.mouseLocation)
            return event
        }
    }

    private func teardownClickMonitors() {
        if let g = clickMonitorGlobal { NSEvent.removeMonitor(g) }
        if let l = clickMonitorLocal { NSEvent.removeMonitor(l) }
        clickMonitorGlobal = nil
        clickMonitorLocal = nil
    }

    private func startHoverPoll() {
        hoverPoll?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sampleHover()
        }
        RunLoop.main.add(t, forMode: .common)
        hoverPoll = t
    }

    private func sampleHover() {
        let mouse = NSEvent.mouseLocation
        let overDormant = contains(mouse, in: .dormant)
        let overExpanded = (phase == .expanded) && contains(mouse, in: .expanded)
        let isOver = overDormant || overExpanded

        let now = Date()
        if isOver {
            leftAt = nil
            if hoverArmedAt == nil { hoverArmedAt = now }
            if phase == .dormant,
               let armed = hoverArmedAt,
               now.timeIntervalSince(armed) >= expandDwell {
                expand(via: "hover")
            }
        } else {
            hoverArmedAt = nil
            if phase == .expanded {
                // Peek hold suppresses auto-collapse so transient
                // notifications stay visible long enough to register.
                if let until = peekDeadline, now < until {
                    leftAt = nil
                    return
                }
                if leftAt == nil { leftAt = now }
                if let gone = leftAt,
                   now.timeIntervalSince(gone) >= collapseDwell {
                    collapse()
                }
            } else {
                leftAt = nil
            }
        }
    }

    private func onClick(_ at: CGPoint) {
        switch phase {
        case .expanded:
            if !contains(at, in: .expanded) { collapse() }
        case .dormant, .peek:
            if contains(at, in: .dormant) { expand(via: "click") }
        }
    }
}
