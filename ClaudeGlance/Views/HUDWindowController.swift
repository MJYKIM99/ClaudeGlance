//
//  HUDWindowController.swift
//  ClaudeGlance
//
//  悬浮窗口控制器
//

import AppKit
import SwiftUI
import Combine

// MARK: - HUD Panel (Non-activating window)
class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class HUDWindowController: NSWindowController {
    private var sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    // 窗口可见性状态 - 用于控制动画
    private let windowVisibility = WindowVisibility()

    // 手动隐藏状态：用户通过菜单隐藏后，新会话不会强行弹回
    var manuallyHidden = false
    private var idleTimer: Timer?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager

        // 创建无边框悬浮窗口
        let window = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow()
        setupContentView()
        positionWindow()
        observeSessionChanges()
        observeWindowVisibility()
        observeWindowMoved()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Configuration
    private func configureWindow() {
        guard let window = window else { return }

        // 始终置顶
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 透明背景
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // 可拖动
        window.isMovableByWindowBackground = true

        // 不在 Dock 和 Cmd+Tab 中显示
        window.hidesOnDeactivate = false

        // 圆角
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
    }

    private func setupContentView() {
        let hudView = HUDContentView(sessionManager: sessionManager, windowVisibility: windowVisibility)
        let hostingView = NSHostingView(rootView: hudView)
        window?.contentView = hostingView
    }

    private func positionWindow() {
        guard let window = window else { return }

        // 从 UserDefaults 读取保存的位置和显示器信息
        let savedX = UserDefaults.standard.double(forKey: Defaults.hudPositionX)
        let savedY = UserDefaults.standard.double(forKey: Defaults.hudPositionY)
        let savedScreenHash = UserDefaults.standard.integer(forKey: Defaults.hudScreenHash)

        if savedX != 0 || savedY != 0 {
            // 尝试找到保存时的显示器
            let targetScreen = findScreen(withHash: savedScreenHash) ?? NSScreen.main

            if let screen = targetScreen {
                // 验证位置是否在目标显示器的可见区域内
                let screenFrame = screen.visibleFrame
                var position = NSPoint(x: savedX, y: savedY)

                // 如果保存的位置不在当前显示器范围内，调整到显示器边界内
                if !screenFrame.contains(NSRect(origin: position, size: window.frame.size)) {
                    // 调整 X 坐标
                    position.x = max(screenFrame.minX, min(position.x, screenFrame.maxX - window.frame.width))
                    // 调整 Y 坐标
                    position.y = max(screenFrame.minY, min(position.y, screenFrame.maxY - window.frame.height))
                }

                window.setFrameOrigin(position)
            } else {
                // 如果找不到保存的显示器，使用主显示器的默认位置
                positionWindowOnScreen(NSScreen.main, window: window)
            }
        } else {
            // 没有保存的位置，使用主显示器的默认位置
            positionWindowOnScreen(NSScreen.main, window: window)
        }
    }

    private func positionWindowOnScreen(_ screen: NSScreen?, window: NSWindow) {
        guard let screen = screen else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - window.frame.width / 2
        let y = screenFrame.maxY - window.frame.height - 20
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func findScreen(withHash hash: Int) -> NSScreen? {
        guard hash != 0 else { return nil }
        return NSScreen.screens.first { screenHash(for: $0) == hash }
    }

    private func screenHash(for screen: NSScreen) -> Int {
        // 使用显示器的 deviceDescription 中的 NSScreenNumber 作为唯一标识
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return screenNumber.intValue
        }
        // 备用方案：使用显示器框架的哈希值
        return screen.frame.hashValue
    }

    // MARK: - Session Observation
    private func observeSessionChanges() {
        sessionManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self = self else { return }
                self.updateWindowSize(for: sessions)
                self.handleAutoHide(sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private func handleAutoHide(sessions: [SessionState]) {
        let autoHideIdle = UserDefaults.standard.bool(forKey: Defaults.autoHideIdle)
        let idleTimeout = UserDefaults.standard.double(forKey: Defaults.idleTimeout)
        let timeout = idleTimeout > 0 ? idleTimeout : 60

        if sessions.isEmpty {
            if autoHideIdle {
                // 启动空闲定时器
                idleTimer?.invalidate()
                idleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                    self?.window?.orderOut(nil)
                }
            }
        } else {
            // 有活跃会话，取消空闲定时器
            idleTimer?.invalidate()
            idleTimer = nil

            // 仅在非手动隐藏时自动显示
            if !manuallyHidden {
                window?.orderFront(nil)
            }
        }
    }

    private func updateWindowSize(for sessions: [SessionState]) {
        guard let window = window else { return }

        let newSize: NSSize
        let hudWidth = max(260, CGFloat(UserDefaults.standard.double(forKey: Defaults.hudWidth) == 0
            ? 320 : UserDefaults.standard.double(forKey: Defaults.hudWidth)))
        if sessions.isEmpty {
            newSize = NSSize(width: 48, height: 48)
        } else {
            let fullCardHeight: CGFloat = 56
            let compactCardHeight: CGFloat = 30
            let padding: CGFloat = 16
            let spacing: CGFloat = 8
            // 高度上限：最多展示约 6 张卡 + 一行“还有 N 个”汇总，超出滚动
            let maxHeight: CGFloat = 6 * (fullCardHeight + spacing) + padding + 22
            var height: CGFloat = padding
            for (idx, session) in sessions.enumerated() {
                height += (session.status == .completed || session.status == .idle) && !session.isExpanded
                    ? compactCardHeight : fullCardHeight
                if session.isExpanded && !session.toolHistory.isEmpty {
                    // 完整时间线面板：最多 ~8 行内部滚动 + 分隔线/计数行
                    let rows = CGFloat(min(session.toolHistory.count, 8))
                    height += 26 + rows * 20 + (session.toolHistory.count > 8 ? 14 : 0)
                }
                if idx < sessions.count - 1 { height += spacing }
            }
            height = min(height, maxHeight)
            newSize = NSSize(width: hudWidth, height: height)
        }

        // 动画更新窗口大小
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            // 保持顶部位置不变
            let newOrigin = NSPoint(
                x: window.frame.origin.x + (window.frame.width - newSize.width) / 2,
                y: window.frame.origin.y + window.frame.height - newSize.height
            )

            window.animator().setFrame(
                NSRect(origin: newOrigin, size: newSize),
                display: true
            )
        }
    }

    // MARK: - Save Position
    func savePosition() {
        guard let window = window else { return }

        UserDefaults.standard.set(window.frame.origin.x, forKey: Defaults.hudPositionX)
        UserDefaults.standard.set(window.frame.origin.y, forKey: Defaults.hudPositionY)

        // 保存窗口所在的显示器
        if let screen = window.screen ?? NSScreen.main {
            let hash = screenHash(for: screen)
            UserDefaults.standard.set(hash, forKey: Defaults.hudScreenHash)
        }
    }

    // MARK: - Window Move Observer
    private func observeWindowMoved() {
        guard let window = window else { return }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    // MARK: - Window Visibility
    private func observeWindowVisibility() {
        guard let window = window else { return }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowVisibility()
        }

        // 初始状态
        updateWindowVisibility()
    }

    private func updateWindowVisibility() {
        guard let window = window else { return }
        windowVisibility.isVisible = window.occlusionState.contains(.visible) && window.isVisible
    }
}

// MARK: - Window Visibility Observable
class WindowVisibility: ObservableObject {
    @Published var isVisible: Bool = true
}

// MARK: - HUD Content View
struct HUDContentView: View {
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var windowVisibility: WindowVisibility
    @AppStorage(Defaults.hudOpacity) private var hudOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // 随系统外观的毛玻璃（浅色模式浅、深色模式深），不再是固定黑色
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)

            if sessionManager.activeSessions.isEmpty {
                CodeRainEffect(isAnimating: windowVisibility.isVisible)
                    .opacity(windowVisibility.isVisible ? 0.6 : 0)
            } else {
                // 高度由 updateWindowSize 封顶，超出部分滚动；
                // 置顶的是需要操作的会话，保证它们不被滚动遮挡
                ScrollView(.vertical, showsIndicators: sessionManager.activeSessions.count > 5) {
                    VStack(spacing: 8) {
                        ForEach(sessionManager.activeSessions) { session in
                            SessionCard(
                                session: session,
                                isAnimating: windowVisibility.isVisible,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        sessionManager.toggleExpand(sessionId: session.id)
                                    }
                                },
                                onDismiss: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        sessionManager.dismissSession(sessionId: session.id)
                                    }
                                },
                                onFocusTerminal: {
                                    sessionManager.focusTerminal(for: session)
                                },
                                onSetLabel: {
                                    SessionCardLabelPrompt.ask(session: session) { label in
                                        sessionManager.setLabel(label, for: session.id)
                                    }
                                },
                                onRemoveLabel: {
                                    sessionManager.setLabel(nil, for: session.id)
                                },
                                onTogglePin: {
                                    sessionManager.togglePin(sessionId: session.id)
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                    }
                    .padding(8)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(hudOpacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sessionManager.activeSessions.count)
    }
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

