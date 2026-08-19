//
//  RuleCleaner.swift
//  Wordstream
//

import Foundation

/// Deterministic cleanup. Always runs, LLM or not.
///
/// This is the floor of the enhancement chain, so it is deliberately conservative:
/// every rule here fires on every dictation with no model to sanity-check it, which
/// means a rule that is right 90% of the time is a bad rule. Anything ambiguous is
/// left for the LLM tiers, which can at least read the sentence around it.
struct RuleCleaner {

    /// Only ever removed when standing alone as a whole word.
    ///
    /// Note what is absent: "like", "so", "right", "well", "I mean". They are
    /// filler often enough to be tempting, and load-bearing often enough that
    /// stripping them changes meaning — "it works like this", "so the total is
    /// twelve". The LLM tiers can make that call in context; a regex cannot.
    ///
    /// An array rather than a `Set` because these are joined into a regex
    /// alternation, and `Set` iteration order is not stable between runs. The
    /// `\b` anchors make the result correct either way, but a pattern that is
    /// spelled differently on each launch is not something to leave to
    /// backtracking.
    private static let fillers = [
        "um", "uh", "erm", "uhh", "umm", "hmm", "mmm", "mhm", "ah", "eh",
    ]

    /// Spoken punctuation, applied in listed order.
    ///
    /// Multi-word phrases come first so that a shorter entry added later —
    /// "mark", "point", "line" — cannot consume part of a longer one before it
    /// has had its turn. No current pair actually overlaps; the ordering is a
    /// standing guard for the next entry rather than a fix for a live collision.
    private static let punctuation: [(phrase: String, replacement: String, attaches: Bool)] = [
        ("new paragraph", "\n\n", false),
        ("new line", "\n", false),
        ("exclamation point", "!", true),
        ("exclamation mark", "!", true),
        ("question mark", "?", true),
        ("open parenthesis", "(", false),
        ("close parenthesis", ")", true),
        ("semicolon", ";", true),
        ("full stop", ".", true),
        ("ellipsis", "…", true),
        ("comma", ",", true),
        ("period", ".", true),
        ("colon", ":", true),
    ]

    func clean(
        _ input: String,
        dictionary: [(spoken: String, written: String)],
        removeFillers: Bool,
        spokenPunctuation: Bool
    ) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if removeFillers { text = stripFillers(from: text) }
        if spokenPunctuation { text = applySpokenPunctuation(to: text) }
        text = applyDictionary(to: text, entries: dictionary)
        text = normaliseWhitespace(text)
        text = capitaliseSentences(text)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Steps

    private func stripFillers(from text: String) -> String {
        let pattern = "\\b(" + Self.fillers.joined(separator: "|") + ")\\b[,]?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func applySpokenPunctuation(to text: String) -> String {
        var result = text
        for (phrase, replacement, attaches) in Self.punctuation {
            let pattern = "\\s*\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let template = NSRegularExpression.escapedTemplate(for: attaches ? replacement : " \(replacement)")
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result
    }

    /// Word-boundary replacement that keeps the speaker's capitalisation.
    ///
    /// If they started a sentence with the term, the replacement should still be
    /// capitalised — otherwise the dictionary quietly introduces a new error while
    /// fixing another one.
    private func applyDictionary(to text: String, entries: [(spoken: String, written: String)]) -> String {
        var result = text
        for entry in entries {
            let spoken = entry.spoken.trimmingCharacters(in: .whitespaces)
            guard !spoken.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: spoken) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            var output = ""
            var last = result.startIndex
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches {
                guard let range = Range(match.range, in: result) else { continue }
                output += result[last..<range.lowerBound]
                let matched = String(result[range])
                let startsUpper = matched.first?.isUppercase == true
                output += startsUpper ? entry.written.capitalisedFirst : entry.written
                last = range.upperBound
            }
            output += result[last...]
            result = output
        }
        return result
    }

    private func normaliseWhitespace(_ text: String) -> String {
        var result = text

        // Collapse runs of spaces and tabs, but leave newlines alone — "new
        // paragraph" has to survive this step.
        result = result.replacingOccurrences(
            of: "[ \\t]+", with: " ", options: .regularExpression
        )
        // No space before punctuation.
        result = result.replacingOccurrences(
            of: " +([,.;:!?…])", with: "$1", options: .regularExpression
        )
        // Exactly one space after it, when a word follows.
        result = result.replacingOccurrences(
            of: "([,.;:!?…])([A-Za-z0-9])", with: "$1 $2", options: .regularExpression
        )
        // Collapse duplicates left behind by filler removal ("um, so" → ", so").
        result = result.replacingOccurrences(
            of: "([,.;:!?])\\s*\\1+", with: "$1", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: " *\\n *", with: "\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\n{3,}", with: "\n\n", options: .regularExpression
        )
        return result
    }

    /// Capitalises the first letter of the text and of anything following
    /// sentence-ending punctuation or a newline.
    ///
    /// Note it never *lowercases* anything — a word the speaker capitalised, or
    /// that the dictionary fixed, is left as it is.
    private func capitaliseSentences(_ text: String) -> String {
        var characters = Array(text)
        var capitaliseNext = true

        for index in characters.indices {
            let character = characters[index]
            if capitaliseNext, character.isLetter {
                characters[index] = Character(character.uppercased())
                capitaliseNext = false
            } else if character == "." || character == "!" || character == "?" || character == "\n" {
                capitaliseNext = true
            } else if !character.isWhitespace, character != "\"", character != "'" {
                capitaliseNext = false
            }
        }
        return String(characters)
    }
}

private extension String {
    var capitalisedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
