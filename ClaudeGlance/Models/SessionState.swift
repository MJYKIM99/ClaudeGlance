//
//  SessionState.swift
//  ClaudeGlance
//
//  会话状态和工具事件数据模型
//

import Foundation

// MARK: - Session Status
enum SessionStatus: String, Codable {
    case idle = "idle"
    case reading = "reading"
    case thinking = "thinking"
    case writing = "writing"
    case waiting = "waiting"
    case completed = "completed"
    case error = "error"

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .reading: return "Reading"
        case .thinking: return "Thinking"
        case .writing: return "Writing"
        case .waiting: return "Waiting"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
}

// MARK: - Session State
struct SessionState: Identifiable, Codable {
    let id: String
    var terminal: String
    var project: String
    var cwd: String
    var status: SessionStatus
    var currentAction: String
    var metadata: String
    var lastUpdate: Date
    var toolHistory: [ToolEvent]

    // 用于渐隐动画
    var opacity: Double = 1.0
    var isExpanded: Bool = false
    var transcriptPath: String = ""

    // 延迟显示：新会话需要等待一段时间才显示（过滤快速的预测操作）
    var displayAfter: Date = Date()

    // MARK: - Timeout Constants
    private static let completedTimeout: TimeInterval = 30      // completed/error 状态 30 秒后消失
    private static let waitingTimeout: TimeInterval = 90        // waiting 状态 90 秒后自动视为结束
    private static let activeTimeout: TimeInterval = 60         // thinking/reading/writing 60秒无更新后消失
    private static let longOperationThreshold: TimeInterval = 30 // 超过 30 秒视为长时间操作

    // 是否已经过了延迟显示时间
    var isReadyToDisplay: Bool {
        return Date() >= displayAfter
    }

    // 简短的 session 标识符（用于区分同一项目的多个终端）
    var shortId: String {
        // 取 session id 的前 4 个字符作为标识
        let prefix = String(id.prefix(4))
        return "#\(prefix)"
    }

    // 会话是否仍然活跃（是否应该显示）
    var isActive: Bool {
        let elapsed = Date().timeIntervalSince(lastUpdate)

        switch status {
        case .completed, .error:
            // 已完成或出错的会话，30秒后消失
            return elapsed < Self.completedTimeout
        case .waiting:
            // waiting 状态 90 秒后消失（假设对话已结束）
            return elapsed < Self.waitingTimeout
        case .thinking, .reading, .writing:
            // 工作状态保持更长时间（Claude 可能在长时间思考）
            return elapsed < Self.activeTimeout
        case .idle:
            return elapsed < Self.completedTimeout
        }
    }

    // 是否应该显示超时提示
    var hasTimedOut: Bool {
        let elapsed = Date().timeIntervalSince(lastUpdate)
        return elapsed > Self.longOperationThreshold && status != .completed && status != .error
    }

    // 是否正在长时间思考（thinking/reading/writing 状态超过 30 秒）
    var isStillThinking: Bool {
        guard hasTimedOut else { return false }
        return status == .thinking || status == .reading || status == .writing
    }

    // 是否在长时间等待用户输入（waiting 状态超过 30 秒）
    var isStillWaiting: Bool {
        guard hasTimedOut else { return false }
        return status == .waiting
    }

    // waiting 状态是否即将超时（用于显示倒计时或提示）
    var waitingSecondsRemaining: Int? {
        guard status == .waiting else { return nil }
        let elapsed = Date().timeIntervalSince(lastUpdate)
        let remaining = Self.waitingTimeout - elapsed
        return remaining > 0 ? Int(remaining) : 0
    }

    // 计算会话是否正在消失（完成后 5 秒开始渐隐）
    var isFading: Bool {
        guard status == .completed else { return false }
        return Date().timeIntervalSince(lastUpdate) > 5
    }

    // 透明度（不再渐变，直接消失由 SessionManager 处理）
    var calculatedOpacity: Double {
        return 1.0
    }

    init(
        id: String,
        terminal: String = "Terminal",
        project: String = "",
        cwd: String = "",
        status: SessionStatus = .idle,
        currentAction: String = "",
        metadata: String = "",
        lastUpdate: Date = Date(),
        toolHistory: [ToolEvent] = [],
        isExpanded: Bool = false,
        displayAfter: Date = Date()
    ) {
        self.id = id
        self.terminal = terminal
        self.project = project
        self.cwd = cwd
        self.status = status
        self.currentAction = currentAction
        self.metadata = metadata
        self.lastUpdate = lastUpdate
        self.toolHistory = toolHistory
        self.isExpanded = isExpanded
        self.displayAfter = displayAfter
    }

    // CodingKeys to exclude non-persistent properties
    enum CodingKeys: String, CodingKey {
        case id, terminal, project, cwd, status, currentAction, metadata, lastUpdate, toolHistory
    }
}

// MARK: - Tool Event
struct ToolEvent: Identifiable, Codable {
    let id: UUID
    let tool: String
    let target: String
    let status: ToolStatus
    let timestamp: Date

    init(tool: String, target: String, status: ToolStatus) {
        self.id = UUID()
        self.tool = tool
        self.target = target
        self.status = status
        self.timestamp = Date()
    }
}

enum ToolStatus: String, Codable {
    case started, completed, failed
}

// MARK: - Hook Message (from our shell script)
struct HookMessage: Codable {
    let sessionId: String
    let terminal: String
    let project: String
    let cwd: String
    let event: String
    let data: ClaudeHookData

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case terminal, project, cwd, event, data
    }
}

// MARK: - Claude Hook Data (actual format from Claude Code)
struct ClaudeHookData: Codable {
    // Common fields
    let sessionId: String?
    let transcriptPath: String?
    let hookEventName: String?

    // PreToolUse / PostToolUse fields
    let toolName: String?
    let toolInput: [String: AnyCodableValue]?

    // Notification fields
    let message: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case notificationType = "notification_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        hookEventName = try container.decodeIfPresent(String.self, forKey: .hookEventName)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .toolInput)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
    }
}

// MARK: - AnyCodableValue for dynamic JSON parsing
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if container.decodeNil() {
            self = .null
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
