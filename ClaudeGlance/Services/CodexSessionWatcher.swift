//
//  CodexSessionWatcher.swift
//  ClaudeGlance
//
//  Fallback integration for Codex Desktop/CLI session JSONL logs.
//

import Foundation
import os

final class CodexSessionWatcher {
    var onMessage: ((Data) -> Void)?

    private let sessionsRoot: URL
    private var timer: Timer?
    private var offsets: [String: UInt64] = [:]
    private var metadataByPath: [String: SessionMetadata] = [:]
    private var callNamesByPath: [String: [String: String]] = [:]

    private struct SessionMetadata {
        var id: String
        var cwd: String

        var project: String {
            cwd.isEmpty ? "Codex" : (cwd as NSString).lastPathComponent
        }
    }

    init(homeDirectory: String = NSHomeDirectory()) {
        sessionsRoot = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".codex/sessions")
    }

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        guard UserDefaults.standard.bool(forKey: Defaults.codexSessionWatcherEnabled),
              FileManager.default.fileExists(atPath: sessionsRoot.path) else { return }

        for file in recentSessionFiles() {
            readNewLines(from: file)
        }
    }

    private func recentSessionFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-60 * 60 * 12)
        var files: [(URL, Date)] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }
            files.append((url, modified))
        }

        return files
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }

    private func readNewLines(from url: URL) {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let sizeNumber = attrs[.size] as? NSNumber else { return }

        let fileSize = sizeNumber.uint64Value
        let isFirstRead = offsets[path] == nil
        let startOffset = offsets[path] ?? (fileSize > 65_536 ? fileSize - 65_536 : 0)
        guard fileSize >= startOffset else {
            offsets[path] = 0
            return
        }
        guard fileSize > startOffset else { return }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.seek(toOffset: startOffset)
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            offsets[path] = fileSize

            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if isFirstRead && startOffset > 0 && !lines.isEmpty {
                lines.removeFirst()
            }
            for line in lines {
                handleJSONLine(line, path: path)
            }
        } catch {
            AppLog.session.debug("Codex watcher read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleJSONLine(_ line: String, path: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session_meta":
            guard let payload = json["payload"] as? [String: Any] else { return }
            let id = payload["id"] as? String ?? fallbackSessionId(from: path)
            let cwd = payload["cwd"] as? String ?? ""
            metadataByPath[path] = SessionMetadata(id: id, cwd: cwd)
            emit(event: "SessionStart", path: path, data: ["message": "Session started"])

        case "event_msg":
            handleEventMessage(json["payload"] as? [String: Any], path: path)

        case "response_item":
            handleResponseItem(json["payload"] as? [String: Any], path: path)

        default:
            break
        }
    }

    private func handleEventMessage(_ payload: [String: Any]?, path: String) {
        guard let payload, let payloadType = payload["type"] as? String else { return }

        switch payloadType {
        case "task_started", "user_message":
            emit(event: "UserPromptSubmit", path: path, data: ["prompt": payload["text"] as? String ?? ""])
        case "agent_message":
            emit(event: "AgentMessage", path: path, data: ["message": payload["text"] as? String ?? "Agent update"])
        case "web_search_end":
            emit(event: "PostToolUse", path: path, data: ["tool_name": "web_search_call"])
        default:
            break
        }
    }

    private func handleResponseItem(_ payload: [String: Any]?, path: String) {
        guard let payload, let payloadType = payload["type"] as? String else { return }

        switch payloadType {
        case "function_call":
            let toolName = payload["name"] as? String ?? "Unknown"
            if let callId = payload["call_id"] as? String {
                var calls = callNamesByPath[path] ?? [:]
                calls[callId] = toolName
                callNamesByPath[path] = calls
            }
            emit(
                event: "PreToolUse",
                path: path,
                data: [
                    "tool_name": toolName,
                    "tool_input": parseArguments(payload["arguments"])
                ]
            )

        case "function_call_output":
            let callId = payload["call_id"] as? String ?? ""
            let toolName = callNamesByPath[path]?[callId] ?? "Unknown"
            emit(event: "PostToolUse", path: path, data: ["tool_name": toolName])

        case "message":
            let role = payload["role"] as? String
            let phase = payload["phase"] as? String
            if role == "assistant" && (phase == "final" || phase == nil) {
                emit(event: "Stop", path: path, data: ["message": "Task completed"])
            }

        default:
            break
        }
    }

    private func emit(event: String, path: String, data: [String: Any]) {
        let meta = metadataByPath[path] ?? SessionMetadata(id: fallbackSessionId(from: path), cwd: "")
        let payload: [String: Any] = [
            "protocol_version": 1,
            "platform": AgentPlatform.codex.rawValue,
            "session_id": meta.id,
            "terminal": "Codex",
            "project": meta.project,
            "cwd": meta.cwd,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "event": event,
            "data": data
        ]

        guard let output = try? JSONSerialization.data(withJSONObject: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(output)
        }
    }

    private func parseArguments(_ value: Any?) -> [String: Any] {
        guard let value else { return [:] }
        if let dict = value as? [String: Any] { return dict }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        if let string = value as? String { return ["arguments": string] }
        return ["arguments": "\(value)"]
    }

    private func fallbackSessionId(from path: String) -> String {
        let filename = (path as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        if let lastDash = stem.lastIndex(of: "-") {
            return String(stem[stem.index(after: lastDash)...])
        }
        return stem
    }
}
