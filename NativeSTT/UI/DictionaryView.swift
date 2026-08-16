//
//  DictionaryView.swift
//  NativeSTT
//

import SwiftUI
import SwiftData

struct DictionaryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryEntry.createdAt, order: .reverse) private var entries: [DictionaryEntry]

    @State private var spoken = ""
    @State private var written = ""

    var body: some View {
        SectionHeader(
            eyebrow: "Dictionary",
            title: "Names, jargon, and spellings",
            subtitle: "Terms here are fixed up after transcription, and — more usefully — fed to the speech model as context beforehand, so it is more likely to get them right in the first place."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(spacing: Space.x2) {
                    TextField("Heard as", text: $spoken)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: Layout.tapTarget)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(theme.fgTertiary)

                    TextField("Written as", text: $written)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: Layout.tapTarget)

                    Button("Add", action: add)
                        .buttonStyle(GatewayButtonStyle(variant: .primary, size: .md))
                        .disabled(spoken.isEmpty || written.isEmpty)
                }

                Text("Example: \u{201C}kubernetes\u{201D} \u{2192} \u{201C}Kubernetes\u{201D}, or \u{201C}see sharp\u{201D} \u{2192} \u{201C}C#\u{201D}.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
            }
        }

        if entries.isEmpty {
            GatewayCard {
                HStack(spacing: Space.x4) {
                    LineMotif(size: 48, opacity: 0.35)
                        .tint(theme.fgTertiary)
                    Text("No terms yet. Add the words this app keeps getting wrong.")
                        .typeStyle(Typography.bodySm)
                        .foregroundStyle(theme.fgTertiary)
                    Spacer()
                }
            }
        } else {
            GatewayCard {
                VStack(spacing: Space.x2) {
                    ForEach(entries) { entry in
                        HStack(spacing: Space.x3) {
                            Text(entry.spoken)
                                .typeStyle(Typography.bodySm)
                                .foregroundStyle(theme.fgSecondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.fgTertiary)
                            Text(entry.written)
                                .typeStyle(Typography.bodySmMedium)
                                .foregroundStyle(theme.fgPrimary)

                            Spacer()

                            Toggle("Bias", isOn: bindingForBias(entry))
                                .toggleStyle(.checkbox)
                                .typeStyle(Typography.caption)
                                .help("Also give this term to the speech model as context before it transcribes")

                            Button {
                                modelContext.delete(entry)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(theme.fgTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(entry.written)")
                        }
                        .frame(minHeight: Layout.tapTarget)

                        if entry.id != entries.last?.id {
                            Divider().overlay(theme.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private func bindingForBias(_ entry: DictionaryEntry) -> Binding<Bool> {
        Binding(
            get: { entry.isBiasTerm },
            set: { entry.isBiasTerm = $0 }
        )
    }

    private func add() {
        let entry = DictionaryEntry(
            spoken: spoken.trimmingCharacters(in: .whitespaces),
            written: written.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(entry)
        spoken = ""
        written = ""
    }
}
