//
//  AgentPetWindowController.swift
//  ClaudeGlance
//
//  Transparent desktop companion driven by agent session state.
//

import AppKit
import SwiftUI
import Combine

final class AgentPetPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?(),
              let contentView else {
            super.rightMouseDown(with: event)
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }
}

final class AgentPetWindowController: NSWindowController {
    private let sessionManager: SessionManager
    private let visibility = WindowVisibility()
    private let contextMenuProvider: (() -> NSMenu)?

    init(sessionManager: SessionManager, contextMenuProvider: (() -> NSMenu)? = nil) {
        self.sessionManager = sessionManager
        self.contextMenuProvider = contextMenuProvider

        let window = AgentPetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 128, height: 128),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow()
        setupContentView()
        positionWindow()
        observeWindowMoved()
        observeWindowVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFront(nil)
        visibility.isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        visibility.isVisible = false
    }

    private func configureWindow() {
        guard let window else { return }
        if let panel = window as? AgentPetPanel {
            panel.contextMenuProvider = contextMenuProvider
        }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = false
    }

    private func setupContentView() {
        let rootView = AgentPetView(sessionManager: sessionManager, visibility: visibility)
        window?.contentView = NSHostingView(rootView: rootView)
    }

    private func positionWindow() {
        guard let window else { return }

        let savedX = UserDefaults.standard.double(forKey: Defaults.desktopPetPositionX)
        let savedY = UserDefaults.standard.double(forKey: Defaults.desktopPetPositionY)
        let savedScreenHash = UserDefaults.standard.integer(forKey: Defaults.desktopPetScreenHash)

        if savedX != 0 || savedY != 0,
           let screen = findScreen(withHash: savedScreenHash) ?? NSScreen.main {
            let frame = screen.visibleFrame
            var origin = NSPoint(x: savedX, y: savedY)
            origin.x = max(frame.minX, min(origin.x, frame.maxX - window.frame.width))
            origin.y = max(frame.minY, min(origin.y, frame.maxY - window.frame.height))
            window.setFrameOrigin(origin)
            return
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.maxX - window.frame.width - 24,
                y: frame.minY + 72
            ))
        }
    }

    private func observeWindowMoved() {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    private func observeWindowVisibility() {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            self.visibility.isVisible = window.occlusionState.contains(.visible) && window.isVisible
        }
    }

    private func savePosition() {
        guard let window else { return }
        UserDefaults.standard.set(window.frame.origin.x, forKey: Defaults.desktopPetPositionX)
        UserDefaults.standard.set(window.frame.origin.y, forKey: Defaults.desktopPetPositionY)
        if let screen = window.screen ?? NSScreen.main {
            UserDefaults.standard.set(screenHash(for: screen), forKey: Defaults.desktopPetScreenHash)
        }
    }

    private func findScreen(withHash hash: Int) -> NSScreen? {
        guard hash != 0 else { return nil }
        return NSScreen.screens.first { screenHash(for: $0) == hash }
    }

    private func screenHash(for screen: NSScreen) -> Int {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return screenNumber.intValue
        }
        return screen.frame.hashValue
    }
}

private enum AgentPetPose {
    case idle
    case coding
    case change
    case request
    case report

    var assetSuffix: String {
        switch self {
        case .idle: return "Idle"
        case .coding: return "Coding"
        case .change: return "Change"
        case .request: return "Request"
        case .report: return "Report"
        }
    }

    func frames(for theme: AgentPetTheme) -> [String] {
        (0..<frameCount).map { "\(theme.assetPrefix)\(assetSuffix)\($0)" }
    }

    var frameCount: Int {
        8
    }

    var interval: Double {
        switch self {
        case .idle: return 0.32
        case .coding: return 0.2
        case .change: return 0.22
        case .request: return 0.28
        case .report: return 0.24
        }
    }
}

struct AgentPetView: View {
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var visibility: WindowVisibility
    @AppStorage(Defaults.desktopPetTheme) private var themeRawValue: String = AgentPetTheme.robot.rawValue
    @AppStorage(Defaults.desktopPetAnimationSpeed) private var animationSpeedRawValue: String = AgentPetAnimationSpeed.normal.rawValue

    private var headSession: SessionState? {
        sessionManager.activeSessions.first
    }

    private var theme: AgentPetTheme {
        AgentPetTheme(rawValue: themeRawValue) ?? .robot
    }

    private var animationSpeed: AgentPetAnimationSpeed {
        AgentPetAnimationSpeed(rawValue: animationSpeedRawValue) ?? .normal
    }

    private var pose: AgentPetPose {
        guard let session = headSession else { return .idle }
        switch session.status {
        case .idle:
            return .idle
        case .reading, .thinking:
            return .coding
        case .writing:
            return .change
        case .waiting, .error:
            return .request
        case .completed:
            return .report
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: currentInterval)) { timeline in
            let frameName = currentFrame(at: timeline.date)
            ZStack {
                Image(frameName)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 8)
                    .scaleEffect(headSession == nil ? 0.94 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: headSession?.id)
            }
            .frame(width: 128, height: 128)
            .contentShape(Rectangle())
            .opacity(visibility.isVisible ? 1 : 0)
            .help(helpText)
        }
    }

    private var helpText: String {
        guard let session = headSession else { return "Claude Glance" }
        return "\(theme.displayName) - \(session.platform.displayName): \(session.currentAction)"
    }

    private func currentFrame(at date: Date) -> String {
        let frames = pose.frames(for: theme)
        let index = Int(date.timeIntervalSinceReferenceDate / currentInterval) % frames.count
        return frames[index]
    }

    private var currentInterval: Double {
        pose.interval * animationSpeed.intervalMultiplier
    }
}

#Preview("Agent Pet") {
    AgentPetView(sessionManager: SessionManager(), visibility: WindowVisibility())
        .frame(width: 128, height: 128)
}
