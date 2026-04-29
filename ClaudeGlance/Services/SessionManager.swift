//
//  SessionManager.swift
//  ClaudeGlance
//
//  多会话状态管理器
//

import Foundation
import Combine
import AppKit
import UserNotifications
import os

// MARK: - UserDefaults Extension
extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

// MARK: - Day Statistics
struct DayStats: Codable, Identifiable {
    var id: String { dateString }
    let dateString: String  // "yyyy-MM-dd"
    var toolCalls: Int
    var sessionsCount: Int
    var toolBreakdown: [String: Int]
    var totalDurationSeconds: Int

    init(dateString: String, toolCalls: Int = 0, sessionsCount: Int = 0, toolBreakdown: [String: Int] = [:], totalDurationSeconds: Int = 0) {
        self.dateString = dateString
        self.toolCalls = toolCalls
        self.sessionsCount = sessionsCount
        self.toolBreakdown = toolBreakdown
        self.totalDurationSeconds = totalDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateString = try container.decode(String.self, forKey: .dateString)
        toolCalls = try container.decode(Int.self, forKey: .toolCalls)
        sessionsCount = try container.decode(Int.self, forKey: .sessionsCount)
        toolBreakdown = try container.decodeIfPresent([String: Int].self, forKey: .toolBreakdown) ?? [:]
        totalDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .totalDurationSeconds) ?? 0
    }

    static var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Today Statistics (backward-compatible wrapper)
struct TodayStats {
    var toolCalls: Int = 0
    var sessionsCount: Int = 0
    var toolBreakdown: [String: Int] = [:]
    var totalDurationSeconds: Int = 0
    var lastReset: Date = Date()

    mutating func incrementToolCalls() {
        checkAndResetIfNewDay()
        toolCalls += 1
    }

    mutating func incrementSessions() {
        checkAndResetIfNewDay()
        sessionsCount += 1
    }

    mutating func incrementTool(_ name: String) {
        checkAndResetIfNewDay()
        toolBreakdown[name, default: 0] += 1
    }

    mutating func addDuration(_ seconds: Int) {
        checkAndResetIfNewDay()
        totalDurationSeconds += seconds
    }

    private mutating func checkAndResetIfNewDay() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastReset) {
            toolCalls = 0
            sessionsCount = 0
            toolBreakdown = [:]
            totalDurationSeconds = 0
            lastReset = Date()
        }
    }
}

class SessionManager: ObservableObject {
    @Published var sessions: [String: SessionState] = [:]
    @Published var activeSessions: [SessionState] = []

    // 统计
    @Published var todayStats = TodayStats()
    @Published var weeklyStats: [DayStats] = []

    // 用户设置
    @Published var soundEnabled: Bool = true

    // 已记录的会话（用于统计唯一会话数）
    private var recordedSessionKeys: Set<String> = []

    // 记录每个会话的最后 Stop 时间，用于 5 秒静默期
    private var sessionStopTimes: [String: Date] = [:]
    private var lastNotificationTime: [NotificationSoundType: Date] = [:]
    private var sessionStartTimes: [String: Date] = [:]

    private var cleanupTimer: Timer?
    private var fadeTimer: Timer?

    init() {
        // 从 UserDefaults 读取设置
        soundEnabled = UserDefaults.standard.bool(forKey: Defaults.soundEnabled)
        if !UserDefaults.standard.contains(key: "soundEnabled") {
            soundEnabled = true
            UserDefaults.standard.set(true, forKey: Defaults.soundEnabled)
        }

        // 读取今日统计
        loadTodayStats()

        // 清理过期会话的定时器 (优化: 从 5s 改为 10s)
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.cleanupStaleSessions()
        }

        // fadeTimer 按需启动，不在 init 中创建
    }

    deinit {
        cleanupTimer?.invalidate()
        fadeTimer?.invalidate()
    }

    // MARK: - Stats Persistence
    private func loadTodayStats() {
        // 读取 weeklyStats
        if let data = UserDefaults.standard.data(forKey: Defaults.weeklyStats),
           let decoded = try? JSONDecoder().decode([DayStats].self, from: data) {
            weeklyStats = decoded
        }

        // 从旧格式迁移（如果 weeklyStats 为空但旧 key 有数据）
        if weeklyStats.isEmpty {
            let oldToolCalls = UserDefaults.standard.integer(forKey: Defaults.legacyTodayToolCalls)
            let oldSessions = UserDefaults.standard.integer(forKey: Defaults.legacyTodaySessionsCount)
            let oldTimestamp = UserDefaults.standard.double(forKey: Defaults.legacyTodayStatsLastReset)
            if oldToolCalls > 0 || oldSessions > 0 {
                let oldDate = oldTimestamp > 0 ? Date(timeIntervalSince1970: oldTimestamp) : Date()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let dateStr = formatter.string(from: oldDate)
                weeklyStats = [DayStats(dateString: dateStr, toolCalls: oldToolCalls, sessionsCount: oldSessions)]
            }
        }

        // 清理超过 7 天的记录
        pruneWeeklyStats()

        // 同步 todayStats
        syncTodayFromWeekly()
    }

    private func saveTodayStats() {
        // 更新 weeklyStats 中今天的条目
        let today = DayStats.todayString
        if let idx = weeklyStats.firstIndex(where: { $0.dateString == today }) {
            weeklyStats[idx] = DayStats(dateString: today, toolCalls: todayStats.toolCalls, sessionsCount: todayStats.sessionsCount, toolBreakdown: todayStats.toolBreakdown, totalDurationSeconds: todayStats.totalDurationSeconds)
        } else {
            weeklyStats.append(DayStats(dateString: today, toolCalls: todayStats.toolCalls, sessionsCount: todayStats.sessionsCount, toolBreakdown: todayStats.toolBreakdown, totalDurationSeconds: todayStats.totalDurationSeconds))
        }

        pruneWeeklyStats()

        // 持久化 weeklyStats
        if let data = try? JSONEncoder().encode(weeklyStats) {
            UserDefaults.standard.set(data, forKey: Defaults.weeklyStats)
        }

        // 向后兼容旧 key
        UserDefaults.standard.set(todayStats.toolCalls, forKey: Defaults.legacyTodayToolCalls)
        UserDefaults.standard.set(todayStats.sessionsCount, forKey: Defaults.legacyTodaySessionsCount)
        UserDefaults.standard.set(todayStats.lastReset.timeIntervalSince1970, forKey: Defaults.legacyTodayStatsLastReset)
    }

    private func syncTodayFromWeekly() {
        let today = DayStats.todayString
        if let todayEntry = weeklyStats.first(where: { $0.dateString == today }) {
            todayStats = TodayStats(toolCalls: todayEntry.toolCalls, sessionsCount: todayEntry.sessionsCount, toolBreakdown: todayEntry.toolBreakdown, totalDurationSeconds: todayEntry.totalDurationSeconds, lastReset: Date())
        } else {
            todayStats = TodayStats(toolCalls: 0, sessionsCount: 0, toolBreakdown: [:], totalDurationSeconds: 0, lastReset: Date())
        }
    }

    private func pruneWeeklyStats() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        weeklyStats = weeklyStats.filter { entry in
            guard let date = formatter.date(from: entry.dateString) else { return false }
            return date >= calendar.startOfDay(for: cutoff)
        }
        weeklyStats.sort { $0.dateString < $1.dateString }
    }

    // MARK: - Process Hook Event
    func processEvent(_ data: Data) {
        // 调试：打印收到的原始数据
        if let jsonString = String(data: data, encoding: .utf8) {
            AppLog.session.debug("Received: \(jsonString.prefix(200))...")
        }

        guard let message = try? JSONDecoder().decode(HookMessage.self, from: data) else {
            AppLog.session.error("Failed to decode hook message")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.handleMessage(message)
        }
    }

    private func handleMessage(_ message: HookMessage) {
        // 使用 session_id 作为主键，每个终端独立显示
        let sessionKey = message.sessionId

        // 统计唯一会话数
        if !recordedSessionKeys.contains(sessionKey) {
            recordedSessionKeys.insert(sessionKey)
            sessionStartTimes[sessionKey] = Date()
            todayStats.incrementSessions()
            saveTodayStats()
        }

        var session = sessions[sessionKey] ?? SessionState(
            id: sessionKey,
            terminal: message.terminal,
            project: message.project,
            cwd: message.cwd,
            displayAfter: Date().addingTimeInterval(0.5)  // 新会话延迟 500ms 显示
        )

        let previousStatus = session.status

        session.terminal = message.terminal
        session.project = message.project
        session.cwd = message.cwd
        if let tp = message.data.transcriptPath, !tp.isEmpty {
            session.transcriptPath = tp
        }

        switch message.event {
        case "PreToolUse":
            let tool = message.data.toolName ?? "Unknown"
            let timeSinceLastUpdate = Date().timeIntervalSince(session.lastUpdate)

            // 检查会话是否在静默期（Stop 后 SessionState.postStopSilentPeriod 秒内）
            // 在此期间忽略所有 PreToolUse，保持 completed 状态显示
            if let stopTime = sessionStopTimes[sessionKey] {
                let timeSinceStop = Date().timeIntervalSince(stopTime)

                if timeSinceStop < SessionState.postStopSilentPeriod {
                    // 静默期内，忽略所有 PreToolUse（都可能是预测操作）
                    let remaining = SessionState.postStopSilentPeriod - timeSinceStop
                    AppLog.session.debug("Ignoring PreToolUse (\(tool)) during \(String(format: "%.1f", remaining))s silent period: \(sessionKey)")
                    return
                } else {
                    // 静默期结束，清除标记
                    sessionStopTimes.removeValue(forKey: sessionKey)

                    // 只有当 session 仍然是 completed 状态时，才忽略 PreToolUse
                    // 如果是 idle（新创建的 session），说明是新的交互，应该正常处理
                    if previousStatus == .completed {
                        sessions.removeValue(forKey: sessionKey)
                        updateActiveSessions()
                        AppLog.session.debug("Silent period ended, removing completed session: \(sessionKey)")
                        return
                    }

                    AppLog.session.debug("Silent period ended, starting new interaction: \(sessionKey)")
                    session.toolHistory.removeAll()
                }
            }

            // 判断是否是新的一轮交互（从 waiting 状态恢复）
            // 注意：completed 状态的检测已经在上面的静默期逻辑中处理了
            let isNewInteraction = previousStatus == .waiting && timeSinceLastUpdate > 1

            // 如果是 waiting 状态且时间很短（< 1秒），可能是预测操作，忽略
            if previousStatus == .waiting && timeSinceLastUpdate < 1 {
                AppLog.session.debug("Ignoring speculative PreToolUse for waiting session: \(sessionKey)")
                return
            }

            // 如果是新的交互，重置会话状态
            if isNewInteraction {
                AppLog.session.debug("New interaction detected for \(sessionKey), resetting session")
                session.toolHistory.removeAll()
            }

            session.status = mapToolToStatus(tool)
            session.currentAction = formatAction(tool, message.data.toolInput)
            session.metadata = formatMetadata(tool, message.data.toolInput)

            // 统计工具调用
            todayStats.incrementToolCalls()
            todayStats.incrementTool(tool)
            saveTodayStats()

        case "PostToolUse":
            let tool = message.data.toolName ?? "Unknown"
            session.status = .thinking
            session.currentAction = "Processing..."

            // 添加到历史
            if session.toolHistory.count >= 10 {
                session.toolHistory.removeFirst()
            }
            session.toolHistory.append(ToolEvent(
                tool: tool,
                target: formatMetadata(tool, message.data.toolInput),
                status: .completed
            ))

        case "Notification":
            let notificationMessage = message.data.message ?? "Waiting for input"
            let notificationType = message.data.notificationType ?? ""

            // 检测是否是错误通知
            let isError = notificationType.lowercased().contains("error") ||
                          notificationMessage.lowercased().contains("error") ||
                          notificationMessage.lowercased().contains("failed") ||
                          notificationMessage.lowercased().contains("api error")

            if isError {
                session.status = .error
                session.currentAction = notificationMessage
                session.metadata = "Error"

                // 错误时播放提示音
                if previousStatus != .error {
                    playNotificationSound(.attention)
                }
            } else {
                session.status = .waiting
                session.currentAction = notificationMessage
                session.metadata = notificationType

                // 需要用户交互时播放提示音
                if previousStatus != .waiting {
                    playNotificationSound(.attention)
                }
            }

        case "Stop":
            // 检查是否是因为错误而停止
            let stopMessage = message.data.message ?? ""
            let isError = stopMessage.lowercased().contains("error") ||
                          stopMessage.lowercased().contains("failed") ||
                          stopMessage.lowercased().contains("aborted")

            if isError {
                session.status = .error
                session.currentAction = stopMessage.isEmpty ? "Task failed" : stopMessage
                session.metadata = "Error"

                if previousStatus != .error {
                    playNotificationSound(.attention)
                }
            } else {
                // 一轮交互完成 - 显示完成状态，并记录 Stop 时间
                session.status = .completed
                session.currentAction = "Task completed"
                session.metadata = ""

                // 记录 Stop 时间，用于过滤后续的预测操作
                sessionStopTimes[sessionKey] = Date()

                // 统计会话持续时间
                if let startTime = sessionStartTimes[sessionKey] {
                    let duration = Int(Date().timeIntervalSince(startTime))
                    todayStats.addDuration(duration)
                    sessionStartTimes.removeValue(forKey: sessionKey)
                    saveTodayStats()
                }
                AppLog.session.debug("Session completed: \(sessionKey), recorded stop time")

                // 任务完成时播放提示音
                if previousStatus != .completed {
                    playNotificationSound(.completion)
                }
            }

        default:
            break
        }

        session.lastUpdate = Date()
        sessions[sessionKey] = session
        updateActiveSessions()

        AppLog.session.debug("Updated session: \(sessionKey, privacy: .public) -> \(session.status.rawValue, privacy: .public) - \(session.currentAction, privacy: .public)")
    }

    // MARK: - Fade Animation
    private func updateFadingSessions() {
        // 检查是否有需要更新 UI 的状态（长时间 thinking/waiting 倒计时）
        let hasStillThinking = sessions.values.contains { $0.isStillThinking }
        let hasStillWaiting = sessions.values.contains { $0.isStillWaiting }

        if hasStillThinking || hasStillWaiting {
            updateActiveSessions()
        }

        // 检查是否还需要继续运行 fadeTimer
        updateFadeTimerState()
    }

    // MARK: - Fade Timer Management (按需启动/停止)
    private func updateFadeTimerState() {
        let needsFadeTimer = sessions.values.contains { session in
            // 需要 fadeTimer 的情况：
            // 1. 长时间 thinking（显示 Still thinking...）
            // 2. 长时间 waiting（显示倒计时）
            session.isStillThinking ||
            session.isStillWaiting
        }

        if needsFadeTimer && fadeTimer == nil {
            // 需要但没有运行，启动定时器
            fadeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateFadingSessions()
            }
        } else if !needsFadeTimer && fadeTimer != nil {
            // 不需要但正在运行，停止定时器
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    // MARK: - Toggle Expand
    func toggleExpand(sessionId: String) {
        if var session = sessions[sessionId] {
            session.isExpanded.toggle()
            sessions[sessionId] = session
            updateActiveSessions()
        }
    }

    // MARK: - Dismiss Session (手动关闭僵尸会话)
    func dismissSession(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        sessionStopTimes.removeValue(forKey: sessionId)
        sessionStartTimes.removeValue(forKey: sessionId)
        updateActiveSessions()
        AppLog.session.debug("Dismissed session: \(sessionId)")
    }

    // MARK: - Sound Notifications
    enum NotificationSoundType {
        case attention   // 需要用户交互
        case completion  // 任务完成
    }

    private func playNotificationSound(_ type: NotificationSoundType) {
        // 同类型通知 10 秒内不重复
        let now = Date()
        if let last = lastNotificationTime[type], now.timeIntervalSince(last) < 10 {
            return
        }
        lastNotificationTime[type] = now

        // Sound notification
        if UserDefaults.standard.bool(forKey: Defaults.soundEnabled) {
            let soundName: NSSound.Name
            switch type {
            case .attention:
                soundName = NSSound.Name("Ping")
            case .completion:
                soundName = NSSound.Name("Hero")
            }

            if let sound = NSSound(named: soundName) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        // macOS Notification Center
        if UserDefaults.standard.bool(forKey: Defaults.notificationsEnabled) {
            let content = UNMutableNotificationContent()
            switch type {
            case .attention:
                content.title = "Claude Needs Input"
                content.body = "A Claude session is waiting for your response"
            case .completion:
                content.title = "Claude Completed"
                content.body = "A Claude session finished its task"
            }
            let notificationId = type == .attention ? "claude-glance-attention" : "claude-glance-completion"
            let request = UNNotificationRequest(
                identifier: notificationId,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func toggleSound() {
        soundEnabled.toggle()
        UserDefaults.standard.set(soundEnabled, forKey: Defaults.soundEnabled)
    }

    // MARK: - Tool Mapping
    private func mapToolToStatus(_ tool: String) -> SessionStatus {
        switch tool {
        case "Read", "Glob", "Grep", "WebFetch", "WebSearch":
            return .reading
        case "Write", "Edit", "NotebookEdit":
            return .writing
        case "Bash", "Task", "TodoWrite":
            return .thinking
        default:
            return .thinking
        }
    }

    private func formatAction(_ tool: String, _ input: [String: AnyCodableValue]?) -> String {
        switch tool {
        case "Read":
            return "Reading file"
        case "Write":
            return "Writing file"
        case "Edit":
            return "Editing file"
        case "Bash":
            if let desc = input?["description"]?.stringValue, !desc.isEmpty {
                return desc
            }
            return "Running command"
        case "Glob":
            return "Searching files"
        case "Grep":
            return "Searching content"
        case "Task":
            if let subtype = input?["subagent_type"]?.stringValue {
                return "Agent: \(subtype)"
            }
            return "Spawning agent"
        case "WebFetch":
            return "Fetching web"
        case "WebSearch":
            return "Searching web"
        case "TodoWrite":
            return "Updating todos"
        case "NotebookEdit":
            return "Editing notebook"
        default:
            return tool
        }
    }

    private func formatMetadata(_ tool: String, _ input: [String: AnyCodableValue]?) -> String {
        guard let input = input else { return "" }

        switch tool {
        case "Read", "Write", "Edit":
            if let path = input["file_path"]?.stringValue {
                let filename = (path as NSString).lastPathComponent
                return filename
            }

        case "Bash":
            if let cmd = input["command"]?.stringValue {
                let truncated = String(cmd.prefix(40))
                return truncated + (cmd.count > 40 ? "..." : "")
            }

        case "Glob":
            if let pattern = input["pattern"]?.stringValue {
                return pattern
            }

        case "Grep":
            if let pattern = input["pattern"]?.stringValue {
                return pattern
            }

        case "Task":
            if let subtype = input["subagent_type"]?.stringValue {
                return subtype
            }

        default:
            break
        }

        return ""
    }

    // MARK: - Session Cleanup
    private func cleanupStaleSessions() {
        let now = Date()
        var sessionsToRemove: [String] = []

        // Snapshot and apply: collect mutations during the scan and
        // apply them after the loop. Mutating the dictionary inside
        // the for-in (as we did before) is implementation-defined in
        // Swift even though it tends to work for value updates.
        var promotedToCompleted: [(String, SessionState)] = []

        for (key, session) in sessions {
            let elapsed = now.timeIntervalSince(session.lastUpdate)

            // 对于已完成/错误状态，completedTimeout 秒后移除
            if session.status == .completed || session.status == .error {
                if elapsed > SessionState.completedTimeout {
                    sessionsToRemove.append(key)
                }
            }
            // 对于工作状态（reading/writing/thinking），超过 activeTimeout
            // 秒无更新则视为已完成。
            else if session.status == .reading || session.status == .writing || session.status == .thinking {
                if elapsed > SessionState.activeTimeout {
                    var updatedSession = session
                    updatedSession.status = .completed
                    updatedSession.currentAction = "Task completed"
                    updatedSession.metadata = ""
                    updatedSession.lastUpdate = now  // 重置时间，让它再过 completedTimeout 秒后消失
                    promotedToCompleted.append((key, updatedSession))
                    AppLog.session.debug("Auto-completed stale session: \(key)")

                    // 播放完成提示音
                    playNotificationSound(.completion)
                }
            }
            // 对于 waiting 状态，waitingTimeout 秒后移除
            else if session.status == .waiting {
                if elapsed > SessionState.waitingTimeout {
                    sessionsToRemove.append(key)
                }
            }
        }

        for (key, updated) in promotedToCompleted {
            sessions[key] = updated
        }

        for key in sessionsToRemove {
            sessions.removeValue(forKey: key)
            sessionStopTimes.removeValue(forKey: key)
            sessionStartTimes.removeValue(forKey: key)
        }

        updateActiveSessions()
    }

    private func updateActiveSessions() {
        activeSessions = sessions.values
            .filter { $0.isActive && $0.isReadyToDisplay }
            .sorted { $0.lastUpdate > $1.lastUpdate }

        // 检查是否需要启动/停止 fadeTimer
        updateFadeTimerState()
    }

    // MARK: - Known CWDs (for hook diagnostic)
    var knownCwds: [String] {
        Array(Set(sessions.values.map { $0.cwd }))
    }

    // MARK: - Debug
    func addDebugSession() {
        let session = SessionState(
            id: "debug-\(UUID().uuidString.prefix(4))",
            terminal: "iTerm2",
            project: "ClaudeGlance",
            cwd: "/Users/yi/Documents/code",
            status: .thinking,
            currentAction: "Reading file",
            metadata: "SessionManager.swift"
        )
        sessions[session.id] = session
        updateActiveSessions()
    }
}
