//
//  HistoryView.swift
//  Wordstream
//

import SwiftUI
import SwiftData
import AppKit

struct HistoryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]

    @State private var search = ""
    @State private var showingRaw = false

    private var filtered: [Transcript] {
        guard !search.isEmpty else { return transcripts }
        return transcripts.filter {
            $0.finalText.localizedCaseInsensitiveContains(search)
                || ($0.appName ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.x3) {
                        ForEach(filtered) { transcript in
                            TranscriptRow(transcript: transcript, showingRaw: showingRaw) {
                                modelContext.delete(transcript)
                            }
                        }
                    }
                    .padding(Space.x6)
                }
            }
        }
        .background(theme.bgCanvas)
        .frame(minWidth: 620, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: Space.x4) {
            TextField("Search transcripts", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320, minHeight: Layout.tapTarget)

            Spacer()

            HStack(spacing: Space.x3) {
                Text("Show original")
                    .typeStyle(Typography.bodySm)
                    .foregroundStyle(theme.fgPrimary)
                Toggle("Show original", isOn: $showingRaw)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help("Show what the speech model produced, before cleanup")
            }
        }
        .padding(.horizontal, Space.x6)
        .padding(.vertical, Space.x4)
        .background(theme.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.x4) {
            Spacer()
            MotifMarkView(size: 96, opacity: 0.35)
                .tint(theme.fgTertiary)
            Text(search.isEmpty ? "Nothing dictated yet" : "No matches")
                .typeStyle(Typography.headingSm)
                .foregroundStyle(theme.fgSecondary)
            if search.isEmpty {
                Text("Hold your dictation key anywhere in macOS and start talking.")
                    .typeStyle(Typography.bodySm)
                    .foregroundStyle(theme.fgTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriptRow: View {
    @Environment(\.theme) private var theme
    var transcript: Transcript
    var showingRaw: Bool
    var onDelete: () -> Void

    @State private var copied = false

    var body: some View {
        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(spacing: Space.x3) {
                    Text(transcript.createdAt, format: .dateTime.hour().minute().day().month(.abbreviated))
                        .typeStyle(Typography.label)
                        .foregroundStyle(theme.fgTertiary)

                    if let app = transcript.appName {
                        GatewayBadge(text: app, tone: .neutral)
                    }

                    if transcript.wasEdited {
                        GatewayBadge(text: transcript.enhancementTier, tone: .brand)
                    }

                    Spacer()

                    Text("\(transcript.wordCount) words · \(transcript.durationSeconds, format: .number.precision(.fractionLength(1)))s")
                        .typeStyleTabular(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                }

                Text(showingRaw ? transcript.rawText : transcript.finalText)
                    .typeStyle(Typography.bodySm)
                    .foregroundStyle(showingRaw ? theme.fgSecondary : theme.fgPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Space.x2) {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            showingRaw ? transcript.rawText : transcript.finalText,
                            forType: .string
                        )
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                    .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm))

                    Button("Delete", action: onDelete)
                        .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm))

                    Spacer()
                }
            }
        }
    }
}
