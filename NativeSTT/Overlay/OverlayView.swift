//
//  OverlayView.swift
//  NativeSTT
//

import SwiftUI

/// The §7 voice waveform: 2pt bars on a 4pt pitch, centre-anchored, driven by the
/// amplitude buffer at ~30fps.
///
/// Drawn in a `Canvas` rather than as a stack of `Rectangle`s because this
/// redraws 30 times a second — 48 animatable views per frame would cost far more
/// than the drawing itself.
struct WaveformView: View {
    @Environment(\.theme) private var theme
    var levels: [Float]
    var barCount: Int = 48

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 4
            let width: CGFloat = 2
            let midY = size.height / 2
            let maxHeight = size.height

            for index in 0..<barCount {
                let level = level(at: index)
                // A floor of 2pt keeps the idle waveform as a visible flat line
                // rather than nothing at all.
                let height = max(2, CGFloat(level) * maxHeight)
                let x = CGFloat(index) * pitch
                guard x + width <= size.width else { break }

                let rect = CGRect(
                    x: x,
                    y: midY - height / 2,
                    width: width,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(theme.fgBrand.opacity(0.85))
                )
            }
        }
        .frame(width: CGFloat(barCount) * 4, height: 28)
        .accessibilityHidden(true) // the timer is the accessible signal
    }

    private func level(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        // Newest sample on the right.
        let offset = barCount - index
        guard offset <= levels.count else { return 0 }
        let value = levels[levels.count - offset]
        return min(1, max(0, value * 2.2))
    }
}

/// The floating pill.
struct OverlayView: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator

    var body: some View {
        HStack(spacing: Space.x4) {
            AssistantStateMotif(state: coordinator.assistantState)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: Space.x1) {
                Text(coordinator.assistantState.eyebrow)
                    .typeStyle(Typography.label)
                    .foregroundStyle(theme.fgTertiary)

                if coordinator.state == .recording {
                    if coordinator.previewText.isEmpty {
                        Text(coordinator.assistantState.headline)
                            .typeStyle(Typography.bodySm)
                            .foregroundStyle(theme.fgSecondary)
                    } else {
                        Text(coordinator.previewText)
                            .typeStyle(Typography.bodySm)
                            .foregroundStyle(theme.fgPrimary)
                            .lineLimit(3)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(coordinator.assistantState.headline)
                        .typeStyle(Typography.bodySm)
                        .foregroundStyle(theme.fgSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if coordinator.state == .recording {
                VStack(alignment: .trailing, spacing: Space.x1) {
                    WaveformView(levels: coordinator.levels, barCount: 32)
                    // §7 requires this: the waveform is decorative to a screen
                    // reader, so the elapsed time is the real state readout.
                    Text(timeString)
                        .typeStyleTabular(Typography.mono13)
                        .foregroundStyle(theme.fgTertiary)
                        .accessibilityLabel("Recording, \(Int(coordinator.elapsed)) seconds")
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, Space.x5)
        .padding(.vertical, Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(theme.bgSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
        .elevation(.lg, theme)
        .padding(Space.x3)
        .animation(Motion.standard(), value: coordinator.state)
    }

    private var timeString: String {
        let total = Int(coordinator.elapsed)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }
}
