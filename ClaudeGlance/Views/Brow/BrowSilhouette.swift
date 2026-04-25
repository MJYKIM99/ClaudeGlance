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

    init(shoulderRadius: CGFloat = 6, skirtRadius: CGFloat = 14) {
        self.shoulderRadius = shoulderRadius
        self.skirtRadius = skirtRadius
    }

    func path(in rect: CGRect) -> Path {
        // Clamp radii so they cannot collectively exceed half the width;
        // protects against degenerate paths at narrow sizes.
        let halfWidth = rect.width / 2
        let s = min(shoulderRadius, halfWidth)
        let k = min(skirtRadius, max(0, halfWidth - s))

        var path = Path()

        // Anchor at the top-left flush with the screen edge.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left shoulder: concave arc tucking inward toward the body.
        // Expressed as the arc tangent to the segment moving right along
        // the screen edge and then down into the body.
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + s, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + s, y: rect.minY + s),
            radius: s
        )

        // Left flank descends straight to where the skirt flare begins.
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - k))

        // Lower-left skirt: convex arc rolling outward to the base.
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + s, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + s + k, y: rect.maxY),
            radius: k
        )

        // Base segment connecting the two skirts.
        path.addLine(to: CGPoint(x: rect.maxX - s - k, y: rect.maxY))

        // Lower-right skirt: convex arc mirroring the left side.
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - s, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - s, y: rect.maxY - k),
            radius: k
        )

        // Right flank ascends to the right shoulder.
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))

        // Top-right shoulder: concave arc returning to the screen edge.
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - s, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: s
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        BrowSilhouette(shoulderRadius: 6, skirtRadius: 12)
            .fill(Color.black)
            .frame(width: 220, height: 32)

        BrowSilhouette(shoulderRadius: 14, skirtRadius: 22)
            .fill(Color.black)
            .frame(width: 540, height: 220)
    }
    .padding(24)
    .background(Color.gray.opacity(0.25))
}
