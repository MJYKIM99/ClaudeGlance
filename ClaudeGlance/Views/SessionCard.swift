//
//  SessionCard.swift
//  ClaudeGlance
//
//  单个会话卡片视图
//

import SwiftUI

struct SessionCard: View {
    let session: SessionState
    var isAnimating: Bool = true
    var onTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var animatedStatus: SessionStatus = .idle
    @AppStorage("showToolHistory") private var showToolHistory: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // 主卡片内容
            HStack(spacing: 12) {
                // 像素动画图标
                PixelSpinner(status: animatedStatus, isAnimating: isAnimating)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    // 主标题：当前动作
                    if session.isStillThinking {
                        Text("Still thinking...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.yellow.opacity(0.9))
                            .lineLimit(1)
                    } else if session.isStillWaiting {
                        Text("Waiting for response...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange.opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text(session.currentAction)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    // 副标题：项目名 + 元数据
                    HStack(spacing: 4) {
                        Text(session.project)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .underline(color: .white.opacity(0.2))
                            .onTapGesture {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
                            }
                            .help(session.cwd)

                        if !session.metadata.isEmpty && !session.isStillWaiting {
                            Text("·")
                                .foregroundColor(.white.opacity(0.4))
                            Text(session.metadata)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        // 长时间思考时显示已用时间
                        if session.isStillThinking {
                            Text("·")
                                .foregroundColor(.white.opacity(0.4))
                            Text(formatElapsedTime(session.lastUpdate))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.7))
                        }

                        // 长时间等待时显示剩余时间
                        if session.isStillWaiting, let remaining = session.waitingSecondsRemaining {
                            Text("·")
                                .foregroundColor(.white.opacity(0.4))
                            Text("auto-hide in \(remaining)s")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // 展开指示器
                if showToolHistory && !session.toolHistory.isEmpty {
                    Image(systemName: session.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }

                // 终端标识
                TerminalBadge(terminal: session.terminal)

                // 关闭按钮（长时间思考或等待时显示）
                if session.isStillThinking || session.isStillWaiting {
                    Button(action: {
                        onDismiss?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this session")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }

            // 展开的详情面板
            if showToolHistory && session.isExpanded && !session.toolHistory.isEmpty {
                ToolHistoryPanel(history: session.toolHistory)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(
            ZStack {
                // 深色底层，确保在浅色背景下也有足够对比度
                Color.black.opacity(0.4)
                // 轻微的白色叠加
                Color.white.opacity(0.03)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            Button("Copy Project Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.cwd, forType: .string)
            }
            Button("Open in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            }
            if !session.transcriptPath.isEmpty {
                Divider()
                Button("View Transcript") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: session.transcriptPath))
                }
            }
            Divider()
            Button("Dismiss") {
                onDismiss?()
            }
        }
        .onChange(of: session.status) { oldValue, newValue in
            // 状态转换动画
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animatedStatus = newValue
            }
        }
        .onAppear {
            animatedStatus = session.status
        }
    }

    // 格式化经过的时间
    private func formatElapsedTime(_ since: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(since))
        if elapsed < 60 {
            return "\(elapsed)s"
        } else if elapsed < 3600 {
            return "\(elapsed / 60)m \(elapsed % 60)s"
        } else {
            return "\(elapsed / 3600)h \(elapsed % 3600 / 60)m"
        }
    }
}

// MARK: - Tool History Panel
struct ToolHistoryPanel: View {
    let history: [ToolEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .background(Color.white.opacity(0.1))

            ForEach(history.suffix(5).reversed()) { event in
                HStack(spacing: 8) {
                    // 工具图标
                    Image(systemName: iconForTool(event.tool))
                        .font(.system(size: 10))
                        .foregroundColor(colorForTool(event.tool))
                        .frame(width: 16)

                    // 工具名称
                    Text(event.tool)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    // 目标
                    if !event.target.isEmpty {
                        Text(event.target)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    Spacer()

                    // 时间戳
                    Text(formatTime(event.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
    }

    private func iconForTool(_ tool: String) -> String {
        switch tool {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Glob": return "magnifyingglass"
        case "Grep": return "text.magnifyingglass"
        case "Task": return "person.2"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass.circle"
        default: return "wrench"
        }
    }

    private func colorForTool(_ tool: String) -> Color {
        switch tool {
        case "Read", "Glob", "Grep": return .blue
        case "Write", "Edit": return .purple
        case "Bash": return .orange
        case "Task": return .cyan
        case "WebFetch", "WebSearch": return .green
        default: return .gray
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Terminal Badge
struct TerminalBadge: View {
    let terminal: String

    private var abbreviation: String {
        switch terminal.lowercased() {
        case let t where t.contains("iterm"):
            return "iT"
        case let t where t.contains("warp"):
            return "W"
        case let t where t.contains("hyper"):
            return "H"
        case let t where t.contains("alacritty"):
            return "A"
        case let t where t.contains("kitty"):
            return "K"
        case let t where t.contains("vscode"), let t where t.contains("code"):
            return "VS"
        case let t where t.contains("cursor"):
            return "Cu"
        case let t where t.contains("apple_terminal"):
            return "Tm"
        case let t where t.contains("ghostty"):
            return "Gh"
        case let t where t.contains("wezterm"):
            return "Wz"
        case let t where t.contains("zed"):
            return "Zd"
        default:
            return "T"
        }
    }

    private var badgeColor: Color {
        switch terminal.lowercased() {
        case let t where t.contains("iterm"):
            return .green
        case let t where t.contains("warp"):
            return .purple
        case let t where t.contains("vscode"), let t where t.contains("code"):
            return .blue
        case let t where t.contains("cursor"):
            return .cyan
        case let t where t.contains("apple_terminal"):
            return .mint
        case let t where t.contains("ghostty"):
            return .indigo
        case let t where t.contains("wezterm"):
            return .teal
        case let t where t.contains("zed"):
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        Text(abbreviation)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(badgeColor.opacity(0.8))
            .frame(width: 22, height: 22)
            .background(badgeColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 8) {
        SessionCard(session: SessionState(
            id: "1",
            terminal: "iTerm2",
            project: "ClaudeGlance",
            status: .reading,
            currentAction: "Reading file",
            metadata: "SessionCard.swift",
            toolHistory: [
                ToolEvent(tool: "Read", target: "test.swift", status: .completed),
                ToolEvent(tool: "Bash", target: "npm install", status: .completed)
            ],
            isExpanded: true
        ))

        SessionCard(session: SessionState(
            id: "2",
            terminal: "VS Code",
            project: "my-app",
            status: .thinking,
            currentAction: "Processing request",
            metadata: "npm install"
        ))

        SessionCard(session: SessionState(
            id: "3",
            terminal: "Terminal",
            project: "backend",
            status: .writing,
            currentAction: "Writing file",
            metadata: "api.py"
        ))
    }
    .padding()
    .background(Color.black)
}
