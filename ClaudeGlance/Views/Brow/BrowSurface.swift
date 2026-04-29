//
//  BrowSurface.swift
//  ClaudeGlance
//
//  SwiftUI surface rendered inside the ledge overlay panel.
//
//  Dormant layout:
//   • Hardware-ledge displays — completely empty when no session is
//     active so the system menu bar is unobstructed. When live content
//     appears (`brow.hasLiveContent == true`), a single status chip
//     grows out of the cutout's right edge with a leading-anchored
//     spring animation (no left-side chip; intentional asymmetry).
//   • Other displays — a single Dynamic-Island-style virtual pill.
//  Expanded layout:
//   • Header strip + reused SessionCard list (project's existing UI).
//

import SwiftUI
import Combine

struct BrowSurface: View {
    @ObservedObject var brow: BrowController
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var visibility: WindowVisibility

    @State private var nowTick: Date = Date()
    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private let expandSpring = Animation.spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)
    private let collapseSpring = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    private var isExpanded: Bool { brow.phase == .expanded }
    private var headSession: SessionState? { sessionManager.activeSessions.first }
    private var extraCount: Int { max(0, sessionManager.activeSessions.count - 1) }

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedPanel
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if brow.hasHardwareLedge {
                ledgeFlank
                    .transition(.opacity)
            } else {
                virtualPill
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(isExpanded ? expandSpring : collapseSpring, value: brow.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: brow.isPulsing)
        .onReceive(secondTimer) { now in nowTick = now }
    }

    // MARK: - Dormant flank chips (hardware ledge)

    /// Asymmetric dormant surface: empty when there are no live
    /// sessions, otherwise a single right-side status chip that grows
    /// out of the ledge's right edge. The left half is intentionally
    /// always empty so the system menu bar stays unobstructed.
    ///
    /// Layout strategy: the row is centred via `.frame(alignment: .center)`,
    /// so we balance the right-side chip slot with a transparent
    /// placeholder of equal width on the left. That keeps the ledge
    /// spacer perfectly centred under the hardware cutout regardless
    /// of whether the chip is currently rendered.
    private var ledgeFlank: some View {
        let chipW = BrowController.chipFlankWidth
        return HStack(spacing: 0) {
            // Left balance — never draws anything.
            Color.clear
                .frame(width: chipW + 4, height: brow.dormantSize.height)

            // Reserve the physical ledge area, expanding briefly on pulse.
            Spacer()
                .frame(width: brow.dormantSize.width + (brow.isPulsing ? 12 : 0))

            // Right chip — appears only when live content exists, and
            // grows from its leading edge so the motion reads as
            // "emerging from the ledge cutout outward to the right".
            ZStack(alignment: .leading) {
                if brow.hasLiveContent {
                    rightFlank
                        .frame(width: chipW, height: brow.dormantSize.height)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.02, anchor: .leading)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.05, anchor: .leading)
                                .combined(with: .opacity)
                        ))
                }
            }
            .frame(width: chipW, height: brow.dormantSize.height,
                   alignment: .leading)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.45, dampingFraction: 0.85,
                           blendDuration: 0),
                   value: brow.hasLiveContent)
    }

    /// Right chip — single short status word or live timer.
    /// Total width budget keeps text under ~9 glyphs.
    private var rightFlank: some View {
        chipShell {
            HStack(spacing: 5) {
                Spacer(minLength: 0)

                if let s = headSession {
                    statusDot(for: s.status)
                    Text(microStatus(for: s))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .id("micro-\(microStatus(for: s))")
                        .transition(.opacity)

                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 4, height: 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: headSession?.id)
        }
    }

    private func chipShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
            content()
        }
    }

    // MARK: - Dormant virtual pill (no hardware ledge)
    //
    // External displays have no camera bezel to mask, so a single
    // Dynamic-Island-style pill reads cleaner than three split chips.
    // The pill width grows briefly while pulsing.

    private var virtualPill: some View {
        let extra: CGFloat = brow.isPulsing ? 14 : 0
        let width = max(120, brow.dormantSize.width + extra)
        return ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

            HStack(spacing: 6) {
                PixelSpinner(
                    status: headSession?.status ?? .idle,
                    isAnimating: visibility.isVisible
                )
                .frame(width: 14, height: 14)

                if let s = headSession {
                    statusDot(for: s.status)
                    Text(microStatus(for: s))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .id("vp-\(microStatus(for: s))")
                        .transition(.opacity)

                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: headSession?.id)
        }
        .frame(width: width, height: brow.dormantSize.height)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        let size = brow.expandedSize
        return ZStack(alignment: .top) {
            BrowSilhouette(shoulderRadius: 14, skirtRadius: 22)
                .fill(Color.black)
                .overlay(
                    BrowSilhouette(shoulderRadius: 14, skirtRadius: 22)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 10) {
                expandedHeader
                expandedBody
            }
            // Inner inset must clear the shoulder curve (radius 14) and
            // leave breathing room. Skirt flare at the bottom adds ~22pt
            // below the body, so bottom padding stays modest.
            .padding(.horizontal, 26)
            .padding(.top, brow.dormantSize.height + 10)
            .padding(.bottom, 16)
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            PixelSpinner(
                status: headSession?.status ?? .idle,
                isAnimating: visibility.isVisible
            )
            .frame(width: 18, height: 18)
            Text("Claude Glance")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text("\(sessionManager.activeSessions.count) active")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        let sessions = sessionManager.activeSessions
        if sessions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
                Text("No active sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(sessions) { session in
                        SessionCard(
                            session: session,
                            isAnimating: visibility.isVisible,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    sessionManager.toggleExpand(sessionId: session.id)
                                }
                            },
                            onDismiss: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    sessionManager.dismissSession(sessionId: session.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Status copy

    /// Compact status: live timer for long-running attention states,
    /// otherwise a single lower-case word. Capped at ~8 glyphs so the
    /// chip width never overflows the side flank budget.
    private func microStatus(for s: SessionState) -> String {
        if s.isStillThinking {
            return shortElapsed(since: s.lastUpdate)
        }
        if s.isStillWaiting {
            if let r = s.waitingSecondsRemaining { return "\(r)s" }
            return "wait"
        }
        switch s.status {
        case .reading:   return "reading"
        case .writing:   return "writing"
        case .thinking:  return "thinking"
        case .waiting:   return "waiting"
        case .completed: return "done"
        case .error:     return "error"
        case .idle:      return "idle"
        }
    }

    private func shortElapsed(since date: Date) -> String {
        let elapsed = max(0, Int(nowTick.timeIntervalSince(date)))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m\(elapsed % 60)s" }
        return "\(elapsed / 3600)h"
    }

    private func statusDot(for status: SessionStatus) -> some View {
        Circle()
            .fill(tint(for: status))
            .frame(width: 5, height: 5)
    }

    private func tint(for status: SessionStatus) -> Color {
        switch status {
        case .thinking:           return .yellow
        case .reading, .writing:  return .cyan
        case .waiting:            return .orange
        case .completed:          return .green
        case .error:              return .red
        case .idle:               return .gray
        }
    }
}
