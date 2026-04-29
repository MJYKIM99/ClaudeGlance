//
//  BrowSilhouette.swift
//  ClaudeGlance
//
//  Silhouette of the camera-ledge "brow" rendered behind the HUD.
//  Built from tangent-arc segments so the corner geometry is expressed
//  as "where the curve passes through" rather than as Bézier control
//  points. The two radii are independent: a small `shoulderRadius`
//  hugging the screen edge at the top and a larger `skirtRadius`
//  flaring outward at the bottom.
//

import SwiftUI

struct BrowSilhouette: Shape {
    /// Inner radius at the screen-edge corners (top-left / top-right).
    var shoulderRadius: CGFloat
    /// Outer radius at the lower flare (bottom-left / bottom-right).
    var skirtRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, skirtRadius) }
        set {
            shoulderRadius = newValue.first
            skirtRadius = newValue.second
        }
    }

    init(shoulderRadius: CGFloat = 5, skirtRadius: CGFloat = 12) {
        self.shoulderRadius = shoulderRadius
        self.skirtRadius = skirtRadius
    }

    func path(in rect: CGRect) -> Path {
        // Clamp radii so they cannot collectively exceed half the width;
        // protects against degenerate paths at narrow sizes.
        let halfWidth = rect.width / 2
        let s = min(shoulderRadius, halfWidth)
        let k = min(skirtRadius, max(0, halfWidth - s))

        // Pre-compute landmark abscissas so the two halves can be walked
        // symmetrically from the base midpoint outward.
        let baseY = rect.maxY
        let topY = rect.minY
        let leftFlank = rect.minX + s
        let rightFlank = rect.maxX - s

        var path = Path()

        // Trace from the base centerline outward. Walking the left half
        // first, crossing the screen-edge top, and returning down the
        // right half lets the path honour the silhouette's vertical
        // symmetry instead of being anchored to a corner.
        path.move(to: CGPoint(x: rect.midX, y: baseY))

        // ── Left half ────────────────────────────────────────────────
        path.addLine(to: CGPoint(x: leftFlank + k, y: baseY))
        path.addArc(                                       // skirt convex
            tangent1End: CGPoint(x: leftFlank, y: baseY),
            tangent2End: CGPoint(x: leftFlank, y: baseY - k),
            radius: k
        )
        path.addLine(to: CGPoint(x: leftFlank, y: topY + s))
        path.addArc(                                       // shoulder concave
            tangent1End: CGPoint(x: leftFlank, y: topY),
            tangent2End: CGPoint(x: rect.minX, y: topY),
            radius: s
        )

        // ── Top edge of the bounding rect ────────────────────────────
        path.addLine(to: CGPoint(x: rect.maxX, y: topY))

        // ── Right half ───────────────────────────────────────────────
        path.addArc(                                       // shoulder concave
            tangent1End: CGPoint(x: rightFlank, y: topY),
            tangent2End: CGPoint(x: rightFlank, y: topY + s),
            radius: s
        )
        path.addLine(to: CGPoint(x: rightFlank, y: baseY - k))
        path.addArc(                                       // skirt convex
            tangent1End: CGPoint(x: rightFlank, y: baseY),
            tangent2End: CGPoint(x: rightFlank - k, y: baseY),
            radius: k
        )
        path.addLine(to: CGPoint(x: rect.midX, y: baseY))

        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        BrowSilhouette(shoulderRadius: 5, skirtRadius: 12)
            .fill(Color.black)
            .frame(width: 220, height: 32)

        BrowSilhouette(shoulderRadius: 14, skirtRadius: 22)
            .fill(Color.black)
            .frame(width: 540, height: 220)
    }
    .padding(24)
    .background(Color.gray.opacity(0.25))
}
