//
//  CodeRainEffect.swift
//  ClaudeGlance
//
//  代码雨粒子特效 (可选装饰)
//

import SwiftUI

struct CodeRainEffect: View {
    var isAnimating: Bool = true

    @State private var particles: [CodeParticle] = []
    @State private var canvasSize: CGSize = .zero
    private let maxParticles = 30

    private let characters = ["0", "1", "{", "}", ";", "=", "→", "<", ">", "/", "*", "+"]

    var body: some View {
        GeometryReader { geo in
            if isAnimating {
                TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                    Canvas { context, size in
                        for particle in particles {
                            let text = Text(particle.character)
                                .font(.system(size: particle.size, design: .monospaced))
                                .foregroundColor(.green)

                            context.opacity = particle.opacity
                            context.draw(
                                text,
                                at: CGPoint(x: particle.x, y: particle.y)
                            )
                        }
                    }
                    .onChange(of: timeline.date) { _, _ in
                        updateParticles()
                    }
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            } else {
                Canvas { context, size in
                    for particle in particles {
                        let text = Text(particle.character)
                            .font(.system(size: particle.size, design: .monospaced))
                            .foregroundColor(.green)

                        context.opacity = particle.opacity
                        context.draw(
                            text,
                            at: CGPoint(x: particle.x, y: particle.y)
                        )
                    }
                }
            }
        }
    }

    private func updateParticles() {
        let size = canvasSize
        guard size.width > 0, size.height > 0 else { return }

        particles = particles.compactMap { particle in
            var p = particle
            p.y += p.speed
            p.opacity -= 0.015

            if p.opacity <= 0 || p.y > size.height {
                return nil
            }
            return p
        }

        if particles.count < maxParticles && Int.random(in: 0...3) == 0 {
            let newParticle = CodeParticle(
                character: characters.randomElement()!,
                x: CGFloat.random(in: 0...size.width),
                y: 0,
                speed: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.5...1.0),
                size: CGFloat.random(in: 8...12)
            )
            particles.append(newParticle)
        }
    }
}

struct CodeParticle: Identifiable {
    let id = UUID()
    var character: String
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
    var opacity: Double
    var size: CGFloat
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
        CodeRainEffect()
    }
    .frame(width: 320, height: 200)
}
