//
//  BrowOverlayWindow.swift
//  ClaudeGlance
//
//  Owns the BrowOverlayPanel + SwiftUI host and reacts to display
//  changes. Click-through is toggled based on the controller's phase so
//  the system menu bar stays interactive in the dormant state.
//

import AppKit
import Combine
import SwiftUI
import os

final class BrowOverlayWindow: NSWindowController {
    private let sessionManager: SessionManager
    private let visibility = WindowVisibility()
    private let brow: BrowController
    private var subscriptions = Set<AnyCancellable>()
    private weak var host: RegionalHitHost<BrowSurface>?
    private var hostScreen: NSScreen
    private var displayFollowTimer: Timer?
    private var lastSessionCount: Int = 0
    private var lastStatusByID: [String: SessionStatus] = [:]
    private var observedFirstEmission: Bool = false

    /// Status transitions that should briefly surface the HUD when the
    /// user has auto-peek enabled. Routine flow states (reading/writing/
    /// thinking/idle) intentionally do not peek.
    private static let peekWorthyStatuses: Set<SessionStatus> = [
        .waiting, .completed, .error
    ]

    /// Pill footprint used when the host display has no hardware ledge.
    /// Height matches the system menu bar so the pill sits flush rather
    /// than dropping below it.
    private static let virtualLedgeSize = CGSize(width: 200, height: 24)
    private static let panelHostHeight: CGFloat = 600

    private static func ledgeFootprint(for screen: NSScreen) -> CGSize {
        screen.hasHardwareLedge ? screen.ledgeSize : virtualLedgeSize
    }

    private static func panelSize(forLedge ledge: CGSize, sessionCount: Int) -> CGSize {
        // Header strip + per-card height + paddings, capped around 5 cards.
        let headerStrip: CGFloat = 56
        let cardHeight: CGFloat = 68
        let emptyHeight: CGFloat = 60
        let body = sessionCount == 0
            ? emptyHeight
            : min(CGFloat(sessionCount) * cardHeight, 360)
        let totalHeight = ledge.height + headerStrip + body
        return CGSize(width: max(ledge.width + 360, 540), height: totalHeight)
    }

    private static func hostFrame(for screen: NSScreen) -> NSRect {
        let f = screen.frame
        return NSRect(x: f.origin.x, y: f.maxY - panelHostHeight,
                      width: f.width, height: panelHostHeight)
    }

    init(sessionManager: SessionManager, screen: NSScreen) {
        self.sessionManager = sessionManager
        self.hostScreen = screen

        let ledge = Self.ledgeFootprint(for: screen)
        let panel = Self.panelSize(forLedge: ledge,
                                   sessionCount: sessionManager.activeSessions.count)
        let frame = Self.hostFrame(for: screen)

        self.brow = BrowController(
            dormantSize: ledge,
            expandedSize: panel,
            displayBounds: screen.frame,
            hasHardwareLedge: screen.hasHardwareLedge
        )

        let panelWindow = BrowOverlayPanel(contentRect: frame)
        panelWindow.setFrame(frame, display: false)

        super.init(window: panelWindow)

        let surface = BrowSurface(
            brow: brow,
            sessionManager: sessionManager,
            visibility: visibility
        )
        let host = RegionalHitHost(rootView: surface)
        host.frame = panelWindow.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        host.activeRegion = { [weak self] in
            guard let self = self, let win = self.window else { return .zero }
            let region = self.brow.phase == .expanded
                ? self.brow.expandedHitRegion
                : self.brow.dormantHitRegion
            return win.convertFromScreen(region)
        }
        panelWindow.contentView = host
        self.host = host

        visibility.isVisible = true
        observePhase()
        observeSessionFlow()
        startDisplayFollow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func observePhase() {
        brow.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self = self, let win = self.window else { return }
                switch phase {
                case .expanded:
                    win.ignoresMouseEvents = false
                    // CRITICAL: never call NSApp.activate(...) here. The
                    // overlay panel uses `.nonactivatingPanel` precisely
                    // so an event-driven peek does not yank the system
                    // key window away from whatever app the user is
                    // typing into. We also gate makeKey() on the
                    // expansion reason: only when the user themselves
                    // engaged the brow (hover/click/manual) do we take
                    // the key window. A passive `.peek` (triggered by a
                    // hook event) renders silently.
                    if self.brow.lastExpandReason != .peek {
                        win.makeKey()
                    }
                case .dormant, .peek:
                    win.ignoresMouseEvents = true
                }
            }
            .store(in: &subscriptions)
    }

    private func observeSessionFlow() {
        sessionManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.handleSessionUpdate(sessions)
            }
            .store(in: &subscriptions)
    }

    private func handleSessionUpdate(_ sessions: [SessionState]) {
        let currCount = sessions.count
        let autoPeek = UserDefaults.standard.bool(forKey: Defaults.browAutoPeekEnabled)
        let statusList = sessions.map { "\($0.id):\($0.status.rawValue)" }.joined(separator: ", ")
        AppLog.brow.debug("sessionUpdate count=\(currCount, privacy: .public) firstEmitted=\(self.observedFirstEmission ? "Y" : "N", privacy: .public) autoPeek=\(autoPeek ? "Y" : "N", privacy: .public) statuses=[\(statusList, privacy: .public)]")

        // Drive the dormant surface visibility. While live content is
        // false the brow renders nothing on hardware-ledge displays so
        // the system menu bar stays unobstructed.
        brow.hasLiveContent = currCount > 0

        // Pulse + recompute panel size whenever the count changes.
        if currCount != lastSessionCount {
            brow.pulseOnce()
            let panel = Self.panelSize(forLedge: brow.dormantSize,
                                       sessionCount: currCount)
            brow.retarget(
                dormantSize: brow.dormantSize,
                expandedSize: panel,
                displayBounds: brow.displayBounds,
                hasHardwareLedge: brow.hasHardwareLedge
            )
        }

        // Detect peek-worthy transitions before updating the snapshot.
        // The first emission only seeds state — we do not peek for
        // sessions that already existed when the overlay started.
        if observedFirstEmission, autoPeek {
            let currentIDs = Set(sessions.map { $0.id })
            for s in sessions {
                let prev = lastStatusByID[s.id]
                let isNew = !lastStatusByID.keys.contains(s.id)
                let transitionedIntoPeekState =
                    prev != s.status &&
                    Self.peekWorthyStatuses.contains(s.status)
                if isNew || transitionedIntoPeekState {
                    AppLog.brow.info("auto-peek session=\(s.id, privacy: .public) prev=\(prev?.rawValue ?? "<new>", privacy: .public) → \(s.status.rawValue, privacy: .public)")
                    brow.peekTransiently()
                    break
                }
            }
            // Drop tracking entries for sessions that disappeared.
            lastStatusByID = lastStatusByID.filter { currentIDs.contains($0.key) }
        }

        // Record snapshot for next diff.
        for s in sessions { lastStatusByID[s.id] = s.status }
        lastSessionCount = currCount
        observedFirstEmission = true
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        displayFollowTimer?.invalidate()
        displayFollowTimer = nil
        brow.collapse()
        window?.orderOut(nil)
    }

    // MARK: - Follow the cursor across displays

    private func startDisplayFollow() {
        displayFollowTimer?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.maybeMigrate()
        }
        RunLoop.main.add(t, forMode: .common)
        displayFollowTimer = t
    }

    private func maybeMigrate() {
        // Avoid retargeting while expanded — the visual jump is jarring.
        guard brow.phase != .expanded else { return }
        let mouse = NSEvent.mouseLocation
        guard let next = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              next != hostScreen else { return }
        migrate(to: next)
    }

    private func migrate(to screen: NSScreen) {
        hostScreen = screen
        let ledge = Self.ledgeFootprint(for: screen)
        let panel = Self.panelSize(forLedge: ledge,
                                   sessionCount: sessionManager.activeSessions.count)
        let frame = Self.hostFrame(for: screen)

        window?.setFrame(frame, display: true)
        brow.retarget(
            dormantSize: ledge,
            expandedSize: panel,
            displayBounds: screen.frame,
            hasHardwareLedge: screen.hasHardwareLedge
        )
    }
}
