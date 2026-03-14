//
//  ClaudeGlanceApp.swift
//  ClaudeGlance
//
//  Claude Code HUD - 多终端状态悬浮窗
//

import SwiftUI
import Combine
import ServiceManagement
import UserNotifications

@main
struct ClaudeGlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用空的 Settings scene，不自动打开任何窗口
        // 设置窗口通过 AppDelegate 的 SettingsWindowController 管理
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var hudWindowController: HUDWindowController?
    var settingsWindowController: SettingsWindowController?
    let sessionManager = SessionManager()
    let ipcServer = IPCServer()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHUDWindow()

        // 自动安装 hook 脚本（在启动服务之前）
        autoInstallHookIfNeeded()

        startIPCServer()

        // 请求通知权限
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
    }

    // 关闭窗口时不退出应用
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // 退出时清理资源
    func applicationWillTerminate(_ notification: Notification) {
        ipcServer.stop()
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Menu Bar
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = createGridIcon()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        // 服务状态（新增）
        let serviceStatusItem = NSMenuItem(title: "Service: Checking...", action: nil, keyEquivalent: "")
        serviceStatusItem.tag = 200
        serviceStatusItem.isEnabled = false
        menu.addItem(serviceStatusItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Show HUD", action: #selector(showHUD), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Hide HUD", action: #selector(hideHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // 今日统计
        let statsHeaderItem = NSMenuItem(title: "Today's Stats", action: nil, keyEquivalent: "")
        statsHeaderItem.isEnabled = false
        menu.addItem(statsHeaderItem)

        let toolCallsItem = NSMenuItem(title: "  Tool Calls: 0", action: nil, keyEquivalent: "")
        toolCallsItem.tag = 101
        toolCallsItem.isEnabled = false
        menu.addItem(toolCallsItem)

        let sessionsStatsItem = NSMenuItem(title: "  Sessions: 0", action: nil, keyEquivalent: "")
        sessionsStatsItem.tag = 102
        sessionsStatsItem.isEnabled = false
        menu.addItem(sessionsStatsItem)

        let topToolsItem = NSMenuItem(title: "  Top: —", action: nil, keyEquivalent: "")
        topToolsItem.tag = 103
        topToolsItem.isEnabled = false
        menu.addItem(topToolsItem)

        let durationItem = NSMenuItem(title: "  Active Time: —", action: nil, keyEquivalent: "")
        durationItem.tag = 104
        durationItem.isEnabled = false
        menu.addItem(durationItem)

        // 7 天趋势
        menu.addItem(NSMenuItem.separator())

        let trendHeaderItem = NSMenuItem(title: "7-Day Trend", action: nil, keyEquivalent: "")
        trendHeaderItem.isEnabled = false
        menu.addItem(trendHeaderItem)

        let trendItem = NSMenuItem(title: "  ▁▁▁▁▁▁▁  (no data)", action: nil, keyEquivalent: "")
        trendItem.tag = 300
        trendItem.isEnabled = false
        menu.addItem(trendItem)

        menu.addItem(NSMenuItem.separator())

        let sessionsItem = NSMenuItem(title: "Active Sessions: 0", action: nil, keyEquivalent: "")
        sessionsItem.tag = 100
        menu.addItem(sessionsItem)

        menu.addItem(NSMenuItem.separator())

        // 服务操作
        menu.addItem(NSMenuItem(title: "Restart Service", action: #selector(restartService), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu

        // 监听服务状态变化（新增）
        ipcServer.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateServiceStatus(status)
            }
            .store(in: &cancellables)

        // 监听会话变化更新菜单
        sessionManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateMenuSessionCount(sessions.count)
            }
            .store(in: &cancellables)

        // 监听今日统计变化
        sessionManager.$todayStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateMenuStats(stats)
            }
            .store(in: &cancellables)

        // 监听 7 天统计变化
        sessionManager.$weeklyStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] weekly in
                self?.updateWeeklyTrend(weekly)
            }
            .store(in: &cancellables)
    }

    // MARK: - Custom Grid Icon
    private func createGridIcon() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        NSColor.black.setFill()

        let dotSize: CGFloat = 3.0
        let spacing: CGFloat = 2.0
        let totalGridSize = dotSize * 3 + spacing * 2
        let startX = (size - totalGridSize) / 2
        let startY = (size - totalGridSize) / 2

        // 3x3 grid
        for row in 0..<3 {
            for col in 0..<3 {
                let x = startX + CGFloat(col) * (dotSize + spacing)
                let y = startY + CGFloat(row) * (dotSize + spacing)

                let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                let dotPath = NSBezierPath(ovalIn: dotRect)
                dotPath.fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateServiceStatus(_ status: IPCServer.ConnectionStatus) {
        guard let menu = statusItem?.menu,
              let item = menu.item(withTag: 200) else { return }

        let title: String
        switch status {
        case .disconnected:
            title = "Service: Not Running"
        case .connecting:
            title = "Service: Starting..."
        case .connected:
            title = "Service: Running"
        case .error:
            title = "Service: Error"
        }

        item.title = title
        lastServiceHealthy = status.isHealthy

        if let button = statusItem?.button {
            if status.isHealthy {
                // 恢复正常图标（考虑当前会话数）
                let count = sessionManager.activeSessions.count
                if count > 0 {
                    button.image = createGridIconWithBadge(count)
                    button.image?.isTemplate = false
                } else {
                    button.image = createGridIcon()
                    button.image?.isTemplate = true
                }
            } else {
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: title)
                button.image?.isTemplate = false
            }
        }
    }

    private var lastServiceHealthy = true

    private func updateMenuSessionCount(_ count: Int) {
        if let menu = statusItem?.menu,
           let item = menu.item(withTag: 100) {
            item.title = "Active Sessions: \(count)"
        }

        // error 状态时不覆盖警告图标
        guard lastServiceHealthy, let button = statusItem?.button else { return }

        if count > 0 {
            button.image = createGridIconWithBadge(count)
            button.image?.isTemplate = false
        } else {
            button.image = createGridIcon()
            button.image?.isTemplate = true
        }
    }

    private func createGridIconWithBadge(_ count: Int) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        // 画 3x3 grid（与 createGridIcon 相同）
        NSColor.black.setFill()
        let dotSize: CGFloat = 3.0
        let spacing: CGFloat = 2.0
        let totalGridSize = dotSize * 3 + spacing * 2
        let startX = (size - totalGridSize) / 2
        let startY = (size - totalGridSize) / 2

        for row in 0..<3 {
            for col in 0..<3 {
                let x = startX + CGFloat(col) * (dotSize + spacing)
                let y = startY + CGFloat(row) * (dotSize + spacing)
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
            }
        }

        // 画徽标
        let badgeSize: CGFloat = 10
        let badgeX = size - badgeSize
        let badgeY = size - badgeSize
        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let text = count > 9 ? "9+" : "\(count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: count > 9 ? 6 : 7, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let textX = badgeX + (badgeSize - textSize.width) / 2
        let textY = badgeY + (badgeSize - textSize.height) / 2
        attrStr.draw(at: NSPoint(x: textX, y: textY))

        image.unlockFocus()
        return image
    }

    private func updateMenuStats(_ stats: TodayStats) {
        guard let menu = statusItem?.menu else { return }

        if let toolCallsItem = menu.item(withTag: 101) {
            toolCallsItem.title = "  Tool Calls: \(stats.toolCalls)"
        }

        if let sessionsItem = menu.item(withTag: 102) {
            sessionsItem.title = "  Sessions: \(stats.sessionsCount)"
        }

        if let topToolsItem = menu.item(withTag: 103) {
            let top3 = stats.toolBreakdown.sorted { $0.value > $1.value }.prefix(3)
            if top3.isEmpty {
                topToolsItem.title = "  Top: —"
            } else {
                let parts = top3.map { "\($0.key)(\($0.value))" }
                topToolsItem.title = "  Top: \(parts.joined(separator: " "))"
            }
        }

        if let durationItem = menu.item(withTag: 104) {
            let total = stats.totalDurationSeconds
            if total <= 0 {
                durationItem.title = "  Active Time: —"
            } else {
                let hours = total / 3600
                let minutes = (total % 3600) / 60
                if hours > 0 {
                    durationItem.title = "  Active Time: \(hours)h \(minutes)m"
                } else {
                    durationItem.title = "  Active Time: \(minutes)m"
                }
            }
        }
    }

    private func updateWeeklyTrend(_ weekly: [DayStats]) {
        guard let menu = statusItem?.menu,
              let trendItem = menu.item(withTag: 300) else { return }

        let values = paddedWeekValues(from: weekly)
        let spark = sparkline(from: values)
        let todayVal = values.last ?? 0
        trendItem.title = "  \(spark)  (\(todayVal) today)"
    }

    private func paddedWeekValues(from weekly: [DayStats]) -> [Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        var result: [Int] = []
        for i in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = formatter.string(from: date)
            let calls = weekly.first(where: { $0.dateString == dateStr })?.toolCalls ?? 0
            result.append(calls)
        }
        return result
    }

    private func sparkline(from values: [Int]) -> String {
        let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        guard let maxVal = values.max(), maxVal > 0 else {
            return String(repeating: "▁", count: values.count)
        }
        return values.map { val in
            let index = min(bars.count - 1, Int(Double(val) / Double(maxVal) * Double(bars.count - 1)))
            return bars[index]
        }.joined()
    }

    // MARK: - HUD Window
    private func setupHUDWindow() {
        hudWindowController = HUDWindowController(sessionManager: sessionManager)
        hudWindowController?.showWindow(nil)
    }

    // MARK: - IPC Server
    private func startIPCServer() {
        ipcServer.onMessage = { [weak self] data in
            self?.sessionManager.processEvent(data)
        }

        do {
            try ipcServer.start()
        } catch {
            print("Failed to start IPC server: \(error)")
        }
    }

    // MARK: - Auto Install Hook
    private func autoInstallHookIfNeeded() {
        guard let scriptContent = HookInstaller.bundledScriptContent() else {
            print("Hook script not found in bundle, skipping auto-install")
            return
        }

        let hooksDir = NSString(string: "~/.claude/hooks").expandingTildeInPath
        let targetPath = (hooksDir as NSString).appendingPathComponent("claude-glance-reporter.sh")
        let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath

        do {
            try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

            // 1. 脚本更新：比较内容，有变化才写入
            let needsScriptUpdate: Bool
            if FileManager.default.fileExists(atPath: targetPath) {
                let existingContent = try String(contentsOfFile: targetPath, encoding: .utf8)
                needsScriptUpdate = (existingContent != scriptContent)
            } else {
                needsScriptUpdate = true
            }

            if needsScriptUpdate {
                try scriptContent.write(toFile: targetPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetPath)
                print("Hook script installed to: \(targetPath)")
            }

            // 2. settings.json 校验：每次启动都检查，缺条目就补
            if !HookInstaller.settingsHasAllHooks(at: settingsPath) {
                try HookInstaller.updateSettingsJson(at: settingsPath)
                print("Settings.json hooks repaired")
            } else {
                print("Hook configuration verified")
            }
        } catch {
            print("Failed to auto-install hook: \(error)")
        }
    }

    // MARK: - Actions
    @objc func showHUD() {
        hudWindowController?.manuallyHidden = false
        hudWindowController?.window?.orderFront(nil)
    }

    @objc func hideHUD() {
        hudWindowController?.manuallyHidden = true
        hudWindowController?.window?.orderOut(nil)
    }

    @objc func addDebugSession() {
        sessionManager.addDebugSession()
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(ipcServer: ipcServer, sessionManager: sessionManager)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func restartService() {
        ipcServer.stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            do {
                try self?.ipcServer.start()
            } catch {
                print("Failed to restart IPC server: \(error)")
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Settings Window Controller
class SettingsWindowController: NSWindowController {
    private var ipcServer: IPCServer?
    private var sessionManager: SessionManager?

    init(ipcServer: IPCServer? = nil, sessionManager: SessionManager? = nil) {
        self.ipcServer = ipcServer
        self.sessionManager = sessionManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Glance Settings"
        window.center()
        window.toolbarStyle = .preference

        let hostingView = NSHostingView(rootView: SettingsView(ipcServer: ipcServer, sessionManager: sessionManager))
        window.contentView = hostingView

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var ipcServer: IPCServer?
    var sessionManager: SessionManager?

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            ConnectionSettingsTab(
                ipcServer: ipcServer,
                knownCwds: sessionManager?.knownCwds ?? []
            )
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 450)
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable sound notifications", isOn: $soundEnabled)
                Text("Play sounds when Claude needs input or completes a task")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable macOS notifications", isOn: $notificationsEnabled)
                Text("Show notification banners in Notification Center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Notifications", systemImage: "bell")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                        }
                    }
                ))

                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Automatically start Claude Glance when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Startup", systemImage: "power")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Appearance Settings Tab
struct AppearanceSettingsTab: View {
    @AppStorage("autoHideIdle") private var autoHideIdle: Bool = true
    @AppStorage("idleTimeout") private var idleTimeout: Double = 60
    @AppStorage("hudOpacity") private var hudOpacity: Double = 1.0
    @AppStorage("showToolHistory") private var showToolHistory: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Auto-hide HUD when idle", isOn: $autoHideIdle)

                if autoHideIdle {
                    HStack {
                        Text("Idle timeout")
                        Spacer()
                        Slider(value: $idleTimeout, in: 30...300, step: 30) {
                            Text("Timeout")
                        }
                        .frame(width: 150)
                        Text("\(Int(idleTimeout))s")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Label("HUD Behavior", systemImage: "rectangle.on.rectangle")
            }

            Section {
                HStack {
                    Text("HUD opacity")
                    Spacer()
                    Slider(value: $hudOpacity, in: 0.5...1.0, step: 0.1) {
                        Text("Opacity")
                    }
                    .frame(width: 150)
                    Text("\(Int(hudOpacity * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Toggle("Show tool history in expanded view", isOn: $showToolHistory)
            } header: {
                Label("Display", systemImage: "eye")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: - Connection Settings Tab
struct ConnectionSettingsTab: View {
    @ObservedObject var ipcServer: IPCServer
    @State private var hookStatus: HookStatus = .unknown
    @State private var isCheckingHook = false
    @State private var diagnostic: HookDiagnostic?
    @State private var isInstallingForProjects = false
    var knownCwds: [String]

    init(ipcServer: IPCServer?, knownCwds: [String] = []) {
        self._ipcServer = ObservedObject(wrappedValue: ipcServer ?? IPCServer())
        self.knownCwds = knownCwds
    }

    enum HookStatus {
        case unknown
        case installed
        case notInstalled
        case misconfigured(String)
        case partialInstall(shadowedBy: [String])

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .installed: return "Installed"
            case .notInstalled: return "Not Installed"
            case .misconfigured(let msg): return "Error: \(msg)"
            case .partialInstall(let projects):
                return "Partial (\(projects.count) project\(projects.count == 1 ? "" : "s") shadowed)"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .orange
            case .installed: return .green
            case .notInstalled, .misconfigured: return .red
            case .partialInstall: return .yellow
            }
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Unix Socket") {
                    HStack {
                        Text("/tmp/claude-glance.sock")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(status: ipcServer.connectionStatus.isHealthy ? "Connected" : "Disconnected")
                    }
                }

                LabeledContent("HTTP Port") {
                    HStack {
                        Text("\(ipcServer.currentPort)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(status: ipcServer.connectionStatus.isHealthy ? "Listening" : "Error")
                    }
                }

                if !ipcServer.statusMessage.isEmpty {
                    Text(ipcServer.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Server Status", systemImage: "server.rack")
            }

            Section {
                LabeledContent("Hook Script") {
                    HStack {
                        Text("claude-glance-reporter.sh")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isCheckingHook {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            HookStatusBadge(status: hookStatus)
                        }
                    }
                }

                LabeledContent("Settings Config") {
                    HStack {
                        Text("~/.claude/settings.json")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check") {
                            checkHookStatus()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Label("Hook Status", systemImage: "terminal")
            }

            // 诊断详情
            if let diag = diagnostic {
                Section {
                    LabeledContent("Script") {
                        HStack(spacing: 8) {
                            diagBadge(diag.scriptExists, label: "Exists")
                            diagBadge(diag.scriptExecutable, label: "Executable")
                            diagBadge(diag.scriptMatchesBundle, label: "Up-to-date")
                        }
                    }

                    LabeledContent("Global Config") {
                        if diag.globalSettingsOK {
                            diagBadge(true, label: "All hooks configured")
                        } else {
                            Text("Missing: \(diag.globalMissingHooks.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if !diag.shadowedProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Projects with local settings that shadow global hooks:")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            ForEach(diag.shadowedProjects, id: \.self) { path in
                                Text(shortenPath(path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("Diagnostic", systemImage: "stethoscope")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button("Install / Update Hook") {
                            installHook()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Hooks Folder") {
                            let path = NSString(string: "~/.claude/hooks").expandingTildeInPath
                            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }
                        .buttonStyle(.bordered)
                    }

                    if case .partialInstall(let projects) = hookStatus {
                        Button("Install for \(projects.count) Shadowed Project\(projects.count == 1 ? "" : "s")") {
                            installForProjects(projects)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInstallingForProjects)
                    }

                    if case .misconfigured(let msg) = hookStatus {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Label("Actions", systemImage: "wrench.and.screwdriver")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            checkHookStatus()
        }
    }

    private func checkHookStatus() {
        isCheckingHook = true

        let cwds = knownCwds
        DispatchQueue.global(qos: .userInitiated).async {
            let diag = HookChecker.runDiagnostic(knownCwds: cwds)
            let status = HookChecker.checkHookInstallation(knownCwds: cwds)
            DispatchQueue.main.async {
                self.diagnostic = diag
                self.hookStatus = status
                self.isCheckingHook = false
            }
        }
    }

    private func installHook() {
        HookInstaller.install { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.checkHookStatus()
                case .failure(let error):
                    self.hookStatus = .misconfigured(error.localizedDescription)
                }
            }
        }
    }

    private func installForProjects(_ projects: [String]) {
        isInstallingForProjects = true
        DispatchQueue.global(qos: .userInitiated).async {
            for project in projects {
                try? HookInstaller.installForProject(at: project)
            }
            DispatchQueue.main.async {
                self.isInstallingForProjects = false
                self.checkHookStatus()
            }
        }
    }

    private func diagBadge(_ ok: Bool, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Hook Status Badge
struct HookStatusBadge: View {
    let status: ConnectionSettingsTab.HookStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hook Diagnostic Info
struct HookDiagnostic {
    var scriptExists: Bool = false
    var scriptExecutable: Bool = false
    var scriptMatchesBundle: Bool = false
    var globalSettingsOK: Bool = false
    var globalMissingHooks: [String] = []
    var shadowedProjects: [String] = []  // 项目级 settings.json 遮蔽全局 hooks 的项目路径
}

// MARK: - Hook Checker
struct HookChecker {
    static func checkHookInstallation() -> ConnectionSettingsTab.HookStatus {
        let diag = runDiagnostic(knownCwds: [])
        return statusFromDiagnostic(diag)
    }

    static func checkHookInstallation(knownCwds: [String]) -> ConnectionSettingsTab.HookStatus {
        let diag = runDiagnostic(knownCwds: knownCwds)
        return statusFromDiagnostic(diag)
    }

    static func runDiagnostic(knownCwds: [String]) -> HookDiagnostic {
        var diag = HookDiagnostic()

        let hooksDir = NSString(string: "~/.claude/hooks").expandingTildeInPath
        let scriptPath = (hooksDir as NSString).appendingPathComponent("claude-glance-reporter.sh")
        let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath

        // 脚本检查
        diag.scriptExists = FileManager.default.fileExists(atPath: scriptPath)
        diag.scriptExecutable = FileManager.default.isExecutableFile(atPath: scriptPath)

        if diag.scriptExists, let bundled = HookInstaller.bundledScriptContent() {
            let existing = (try? String(contentsOfFile: scriptPath, encoding: .utf8)) ?? ""
            diag.scriptMatchesBundle = (existing == bundled)
        }

        // 全局 settings.json 检查
        diag.globalMissingHooks = HookInstaller.missingHookTypes(at: settingsPath)
        diag.globalSettingsOK = diag.globalMissingHooks.isEmpty

        // 项目级遮蔽检查
        let uniqueCwds = Set(knownCwds)
        for cwd in uniqueCwds {
            let projectSettings = findProjectSettings(from: cwd)
            if let projectPath = projectSettings {
                // 项目有自己的 settings.json 且该文件有 hooks 字段
                if let data = try? Data(contentsOf: URL(fileURLWithPath: projectPath)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["hooks"] != nil {
                    // 项目级有 hooks 字段，检查是否包含 glance hooks
                    if !HookInstaller.settingsHasAllHooks(at: projectPath) {
                        diag.shadowedProjects.append(cwd)
                    }
                }
            }
        }

        return diag
    }

    private static func statusFromDiagnostic(_ diag: HookDiagnostic) -> ConnectionSettingsTab.HookStatus {
        if !diag.scriptExists { return .notInstalled }
        if !diag.scriptExecutable { return .misconfigured("Script not executable") }
        if !diag.globalSettingsOK {
            let missing = diag.globalMissingHooks.joined(separator: ", ")
            return .misconfigured("Missing hooks: \(missing)")
        }
        if !diag.shadowedProjects.isEmpty {
            return .partialInstall(shadowedBy: diag.shadowedProjects)
        }
        return .installed
    }

    // 从 cwd 向上查找 .claude/settings.json
    private static func findProjectSettings(from cwd: String) -> String? {
        var dir = cwd
        let home = NSHomeDirectory()
        while dir.count > 1 && dir != home {
            let candidate = (dir as NSString).appendingPathComponent(".claude/settings.json")
            if FileManager.default.fileExists(atPath: candidate) {
                // 排除全局 ~/.claude/settings.json
                let globalPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath
                if candidate != globalPath {
                    return candidate
                }
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}

// MARK: - Hook Installer
struct HookInstaller {
    static let glanceCommand = "claude-glance-reporter.sh"
    static let hookTypes = ["PreToolUse", "PostToolUse", "Notification", "Stop"]

    static func install(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try performInstallation()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // 从 Bundle 读取脚本内容（唯一来源）
    static func bundledScriptContent() -> String? {
        guard let url = Bundle.main.url(
            forResource: "claude-glance-reporter",
            withExtension: "sh",
            subdirectory: "Scripts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func performInstallation() throws {
        guard let scriptContent = bundledScriptContent() else {
            throw NSError(domain: "ClaudeGlance", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Hook script not found in app bundle"])
        }

        let hooksDir = NSString(string: "~/.claude/hooks").expandingTildeInPath
        let scriptPath = (hooksDir as NSString).appendingPathComponent("claude-glance-reporter.sh")
        let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath

        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        try updateSettingsJson(at: settingsPath)
    }

    // 检查指定 settings.json 是否已包含所有 glance hooks
    static func settingsHasAllHooks(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for hookType in hookTypes {
            guard let hookArray = hooks[hookType] as? [[String: Any]] else { return false }
            let hasGlance = hookArray.contains { matcher in
                guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return false }
                return hooksList.contains { hook in
                    (hook["command"] as? String)?.contains(glanceCommand) == true
                }
            }
            if !hasGlance { return false }
        }
        return true
    }

    // 返回 settings.json 中缺失的 hook 类型
    static func missingHookTypes(at path: String) -> [String] {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return hookTypes
        }

        return hookTypes.filter { hookType in
            guard let hookArray = hooks[hookType] as? [[String: Any]] else { return true }
            return !hookArray.contains { matcher in
                guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return false }
                return hooksList.contains { hook in
                    (hook["command"] as? String)?.contains(glanceCommand) == true
                }
            }
        }
    }

    static func updateSettingsJson(at path: String) throws {
        var settings: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: path) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let existingSettings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existingSettings
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for hookType in hookTypes {
            let glanceEntry: [String: Any] = [
                "matcher": "*",
                "hooks": [
                    ["type": "command", "command": "~/.claude/hooks/claude-glance-reporter.sh \(hookType)"]
                ]
            ]

            if var existingArray = hooks[hookType] as? [[String: Any]] {
                let glanceIndex = existingArray.firstIndex { matcher in
                    guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return false }
                    return hooksList.contains { hook in
                        (hook["command"] as? String)?.contains(glanceCommand) == true
                    }
                }

                if let index = glanceIndex {
                    existingArray[index] = glanceEntry
                } else {
                    existingArray.append(glanceEntry)
                }
                hooks[hookType] = existingArray
            } else {
                hooks[hookType] = [glanceEntry]
            }
        }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    // 为指定项目目录安装 hooks
    static func installForProject(at projectDir: String) throws {
        let settingsPath = (projectDir as NSString).appendingPathComponent(".claude/settings.json")
        if FileManager.default.fileExists(atPath: settingsPath) {
            try updateSettingsJson(at: settingsPath)
        }
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "connected", "listening":
            return .green
        case "disconnected", "error":
            return .red
        default:
            return .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About Settings Tab
struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            // App Name & Version
            VStack(spacing: 4) {
                Text("Claude Glance")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("Multi-terminal Claude Code status HUD")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Author
            Text("Created by Kim")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Links
            HStack(spacing: 20) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/MJYKIM99/ClaudeGlance") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                Button("Report Issue") {
                    if let url = URL(string: "https://github.com/MJYKIM99/ClaudeGlance/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }

            // Copyright
            Text("© 2025 Kim. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
