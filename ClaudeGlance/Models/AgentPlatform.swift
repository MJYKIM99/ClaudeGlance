//
//  AgentPlatform.swift
//  ClaudeGlance
//
//  Supported coding-agent runtimes.
//

import Foundation

enum AgentPlatform: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        }
    }

    var badge: String {
        switch self {
        case .claudeCode: return "CC"
        case .codex: return "CX"
        }
    }

    var sessionKeyPrefix: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        }
    }

    static func parse(_ value: String?) -> AgentPlatform {
        guard let value = value?.lowercased() else { return .claudeCode }
        switch value {
        case "codex", "openai_codex", "openai-codex":
            return .codex
        case "claude", "claude_code", "claude-code", "claudecode":
            return .claudeCode
        default:
            return .claudeCode
        }
    }
}
