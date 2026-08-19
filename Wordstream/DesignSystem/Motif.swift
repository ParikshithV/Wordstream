//
//  Motif.swift
//  Wordstream
//
//  The Wordstream mark, drawn as native SwiftUI shapes.
//
//  One mark, one drawing: three concentric rosette rings stroked at a single
//  medium weight. It is the same geometry in the onboarding hero, the overlay, the
//  empty states and the menu bar — only size and opacity change. Nothing here is
//  filled, so the mark survives the menu bar's monochrome template requirement and
//  small sizes, where the old layered fill closed up into a disc.
//
//  Geometry is never eyeballed: everything derives from circles repeated on a
//  shared ring. The rosette below is generated from the two ratios §1 calls out —
//  cusp 0.93, and lobe counts that share no divisors — rather than from copied
//  path data, so it stays reproducible at any size.
//

import SwiftUI
import AppKit

// MARK: - Rosette

/// The union of `lobes` circles repeated on a shared ring: broad outward lobes
/// separated by small sharp cusps.
///
/// Solving for the arc radius, given the cusp ring `rCusp = rOut * cuspRatio`:
///
///     h = rCusp·sin(π/n)          half-chord between adjacent cusps
///     m = rCusp·cos(π/n)          centre → chord midpoint
///     k = rOut - m                sagitta, how far the lobe bulges past the chord
///     r = (h² + k²) / 2k          the arc radius that hits rOut at its apex
///
/// Each arc's centre then sits at `rOut - r` from the middle, along the bisector.
/// Checked against `gateway-lotus.svg`: for 16 lobes at rOut 108.01 this yields
/// r = 24.96 against the file's 24.97.
struct RosetteShape: Shape {
    var lobes: Int
    /// Notch depth between lobes. Deeper turns the mark into a spiky star; §1 pins
    /// it at 0.93 because with few layers each ring is fully exposed and adjacent
    /// scallops otherwise collide into a berry texture.
    var cuspRatio: CGFloat = 0.93
    var rotation: Angle = .degrees(-90)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = max(3, lobes)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let rOut = min(rect.width, rect.height) / 2
        guard rOut > 0 else { return path }

        let rCusp = rOut * cuspRatio
        let step = 2 * CGFloat.pi / CGFloat(n)
        let h = rCusp * sin(step / 2)
        let m = rCusp * cos(step / 2)
        let k = rOut - m
        guard k > 0.0001 else { return path }
        let r = (h * h + k * k) / (2 * k)
        let dC = rOut - r

        func point(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }

        let base = CGFloat(rotation.radians)
        path.move(to: point(base, rCusp))

        for i in 0..<n {
            let a0 = base + step * CGFloat(i)
            let a1 = a0 + step
            let bisector = a0 + step / 2
            let arcCentre = point(bisector, dC)
            let p0 = point(a0, rCusp)
            let p1 = point(a1, rCusp)
            let start = atan2(p0.y - arcCentre.y, p0.x - arcCentre.x)
            let end = atan2(p1.y - arcCentre.y, p1.x - arcCentre.x)
            path.addArc(
                center: arcCentre,
                radius: r,
                startAngle: .radians(Double(start)),
                endAngle: .radians(Double(end)),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - The mark

/// The one Wordstream mark: three concentric rosette rings, stroked at a single
/// medium weight, used at every size on every surface.
///
/// It used to come in three forms — a filled four-ring lotus with a lit-from-above
/// gradient for the onboarding hero, a two-ring outline for empty states, and a
/// one-ring outline in the menu bar. Three drawings of the same idea read as three
/// different logos, and the filled version couldn't follow the app into the menu
/// bar at all (template images are monochrome). One stroked mark carries
/// everywhere, and a stroke stays legible at 18pt where the layered fill turned to
/// mud.
///
/// Lobe counts are pairwise coprime so the cusps of one ring never line up
/// radially with another's and snap the mark to a rigid star. Ring scales are wider
/// apart than the old filled lotus's, whose 0.787/0.574 steps were tuned for solid
/// shapes: stroked, those rings sit within a stroke width of each other and the
/// mark closes into a blob at menu-bar size.
enum MotifMark {
    static let rings: [(lobes: Int, scale: CGFloat, rotation: Double)] = [
        (11, 1.00, -90),
        (9, 0.68, -81),
        (7, 0.36, -72),
    ]

    /// The single stroke weight, in one place so the SwiftUI mark and the AppKit
    /// menu-bar image can't drift apart. Medium: heavy enough to hold at 18pt,
    /// light enough that three rings don't close up at 26pt.
    static func lineWidth(for size: CGFloat) -> CGFloat {
        max(1.25, size / 16)
    }
}

/// The mark, tinted. `opacity` is the only register that changes between states —
/// the geometry and the stroke weight never do.
struct MotifMarkView: View {
    var size: CGFloat
    var opacity: Double = 1

    var body: some View {
        ZStack {
            ForEach(Array(MotifMark.rings.enumerated()), id: \.offset) { _, ring in
                RosetteShape(lobes: ring.lobes, rotation: .degrees(ring.rotation))
                    .stroke(.tint, lineWidth: MotifMark.lineWidth(for: size))
                    .frame(width: size * ring.scale, height: size * ring.scale)
            }
        }
        .opacity(opacity)
        .frame(width: size, height: size)
    }
}

// MARK: - Assistant state

/// §7's most distinctive pattern: the motif's scale carries the machine's status,
/// so the copy doesn't have to shout it. Each state pairs a quiet mono eyebrow
/// with a plain-language headline.
enum AssistantState: Equatable {
    /// Small, static.
    case readyAndListening(eyebrow: String, headline: String)
    /// Large, pulsing on the 2s brand cadence.
    case formingAResolution(eyebrow: String, headline: String)
    /// Medium, dimmed.
    case holdingSteady(eyebrow: String, headline: String)

    var eyebrow: String {
        switch self {
        case let .readyAndListening(e, _), let .formingAResolution(e, _), let .holdingSteady(e, _): e
        }
    }

    var headline: String {
        switch self {
        case let .readyAndListening(_, h), let .formingAResolution(_, h), let .holdingSteady(_, h): h
        }
    }
}

struct AssistantStateMotif: View {
    var state: AssistantState
    var scale: CGFloat = 1

    @State private var pulsing = false

    var body: some View {
        Group {
            switch state {
            // One mark, three intensities — size and opacity carry the state,
            // never a different drawing.
            case .readyAndListening:
                MotifMarkView(size: 26 * scale, opacity: 0.55)
            case .formingAResolution:
                MotifMarkView(size: 40 * scale)
                    .scaleEffect(pulsing ? 1.06 : 0.94)
                    .opacity(pulsing ? 1.0 : 0.82)
            case .holdingSteady:
                MotifMarkView(size: 30 * scale, opacity: 0.32)
            }
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: state) { _, _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        guard case .formingAResolution = state, !Motion.reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeInOut(duration: Motion.pulse).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

// MARK: - Menu bar icon

extension NSImage {
    /// The menu-bar mark: `MotifMarkView` redrawn in AppKit, because a menu-bar
    /// item has to be a monochrome template image so macOS can tint it for light,
    /// dark and tinted menu bars.
    ///
    /// Same three rings, same coprime lobe counts, same stroke rule as every other
    /// surface — only the drawing API differs.
    static func gatewayMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let lineWidth = MotifMark.lineWidth(for: size)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()

            for ring in MotifMark.rings {
                // Inset by half the stroke so the outermost ring sits inside the
                // frame instead of being clipped by it.
                let side = (size - lineWidth) * ring.scale
                let box = NSRect(
                    x: rect.midX - side / 2,
                    y: rect.midY - side / 2,
                    width: side,
                    height: side
                )
                let path = RosetteShape(lobes: ring.lobes, rotation: .degrees(ring.rotation))
                    .path(in: box)

                let bezier = NSBezierPath()
                path.forEach { element in
                    switch element {
                    case let .move(to): bezier.move(to: to)
                    case let .line(to): bezier.line(to: to)
                    case let .quadCurve(to, control):
                        bezier.curve(to: to, controlPoint1: control, controlPoint2: control)
                    case let .curve(to, control1, control2):
                        bezier.curve(to: to, controlPoint1: control1, controlPoint2: control2)
                    case .closeSubpath: bezier.close()
                    }
                }
                bezier.lineWidth = lineWidth
                bezier.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
