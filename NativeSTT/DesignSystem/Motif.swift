//
//  Motif.swift
//  NativeSTT
//
//  The gateway motif, redrawn as native SwiftUI shapes.
//
//  Gateway ships these as SVG, but §8 records that react-native-svg cannot render
//  SVG filters — which the mark's layer shadow depends on — and offers three lossy
//  workarounds. Xcode asset catalogs have the same limitation. SwiftUI does not, so
//  this target gets the full-fidelity version, and gets it resolution-independent
//  and animatable for free.
//
//  §1 names three specific traps, all three of which are what actually separate a
//  finished mark from construction lines:
//
//    1. Stacked opacity double-darkens every intersection. Each ring is SOLID.
//    2. One gradient across the whole mark reads flat. Each ring carries the same
//       gradient in ITS OWN bounding box, so every layer restarts light at its own
//       top edge. Here that falls out of framing each ring to its own size.
//    3. Gradient alone still looks printed on one surface. Each ring casts a soft
//       shadow onto the ring behind it, so the stack behaves like cut paper lit
//       from above. This is the single biggest contributor to the look.
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

// MARK: - Seed

/// The atomic ogee gateway: pointed apex, swollen body, settled base. Ported from
/// `gateway-seed.svg`'s single path, normalised off its 120-unit viewBox so it
/// scales to any frame.
struct SeedShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 120
        let ox = rect.midX - 60 * s
        let oy = rect.midY - 60 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()
        path.move(to: p(60, 13))
        path.addCurve(to: p(103, 76), control1: p(70, 36), control2: p(103, 50))
        path.addCurve(to: p(60, 118), control1: p(103, 101), control2: p(83, 118))
        path.addCurve(to: p(17, 76), control1: p(37, 118), control2: p(17, 101))
        path.addCurve(to: p(60, 13), control1: p(17, 50), control2: p(50, 36))
        path.closeSubpath()
        return path
    }
}

// MARK: - Line mandala

/// One ring, eight points on it, one centre — the construction logic stated in the
/// fewest possible marks. §6 notes an earlier version stacked ten overlapping
/// circles and turned to noise below 200px, which is the opposite of what a mark
/// for quiet backdrops and small chrome needs to do.
struct LineMandalaShape: Shape {
    var pointCount: Int = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let ring = side * 0.35
        let dot = side * 0.0208
        let rhombus = side * 0.0667

        path.addEllipse(in: CGRect(
            x: centre.x - ring, y: centre.y - ring,
            width: ring * 2, height: ring * 2
        ))

        for i in 0..<pointCount {
            let a = -CGFloat.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(pointCount)
            let c = CGPoint(x: centre.x + ring * cos(a), y: centre.y + ring * sin(a))
            path.addEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        }

        path.move(to: CGPoint(x: centre.x, y: centre.y - rhombus))
        path.addLine(to: CGPoint(x: centre.x + rhombus, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + rhombus))
        path.addLine(to: CGPoint(x: centre.x - rhombus, y: centre.y))
        path.closeSubpath()
        return path
    }
}

// MARK: - Material

/// The shared motif material: a ramp lit from above — light at the top edge,
/// saturated at the bottom — plus the cast shadow. Colour may change between
/// states; the material may not. A flat brand-coloured motif is a bug.
private struct MotifMaterial: ViewModifier {
    let theme: Theme
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: theme.motifStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(
                color: theme.motifStops.last?.opacity(0.32) ?? .clear,
                radius: shadowRadius,
                x: 0,
                y: shadowRadius * 0.6
            )
    }
}

// MARK: - Lotus

/// "Under load": four nested rosettes, concentric, at lobe counts that share no
/// divisors so the cusps cannot line up radially and snap the mark to a rigid star.
///
/// Ratios measured off `gateway-lotus.svg`. Every ring shares one centre — §1 notes
/// that lifting inner rings to suggest a dome just reads as a mis-registered
/// centre, because the shadows already supply the depth.
struct LotusMotif: View {
    @Environment(\.theme) private var theme
    var size: CGFloat

    private static let rings: [(lobes: Int, scale: CGFloat, rotation: Double)] = [
        (16, 1.000, -90),
        (14, 0.787, -81),
        (12, 0.574, -72),
        (10, 0.370, -63),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.rings.enumerated()), id: \.offset) { _, ring in
                RosetteShape(lobes: ring.lobes, rotation: .degrees(ring.rotation))
                    .frame(width: size * ring.scale, height: size * ring.scale)
                    .modifier(MotifMaterial(theme: theme, shadowRadius: max(1.5, size * 0.0125)))
            }
        }
        .frame(width: size, height: size)
        // The viewBox needs padding for the shadow, or the blur clips and the
        // outermost layer looks cut off.
        .padding(size * 0.07)
    }
}

/// "Ready, at rest": the single seed, small.
struct SeedMotif: View {
    @Environment(\.theme) private var theme
    var size: CGFloat

    var body: some View {
        SeedShape()
            .frame(width: size, height: size)
            .modifier(MotifMaterial(theme: theme, shadowRadius: max(1.5, size * 0.033)))
            .padding(size * 0.08)
    }
}

/// "Quiet, structural": the outline mandala, for empty states and small chrome.
struct LineMotif: View {
    var size: CGFloat
    var opacity: Double = 0.75

    var body: some View {
        LineMandalaShape()
            .fill(.tint)
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
            case .readyAndListening:
                SeedMotif(size: 24 * scale)
            case .formingAResolution:
                LotusMotif(size: 40 * scale)
                    .scaleEffect(pulsing ? 1.06 : 0.94)
                    .opacity(pulsing ? 1.0 : 0.82)
            case .holdingSteady:
                SeedMotif(size: 30 * scale)
                    .opacity(0.55)
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
    /// The menu-bar mark.
    ///
    /// Two constraints meet here and happen to agree. A menu-bar item must be a
    /// monochrome template image so macOS can tint it for light, dark and tinted
    /// menu bars — which rules out the lit-from-above material. And at 18pt we are
    /// well under §5's 32px floor, below which the mandala turns to mud. §5 already
    /// sanctions the line treatment as the "quiet, structural" state, and it is
    /// `currentColor`-based, so the line mandala is the correct form on both counts.
    static func gatewayMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = LineMandalaShape().path(in: rect)
            NSColor.black.setStroke()
            NSColor.black.setFill()

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
            bezier.lineWidth = max(1, size / 18)
            bezier.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
