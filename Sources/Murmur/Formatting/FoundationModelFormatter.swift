import Foundation
import FoundationModels

/// Cleanup via Apple's on-device LLM (macOS 26 Foundation Models).
///
/// This is the pass that separates dictation from *usable* dictation: it removes fillers,
/// restores punctuation and capitalization, formats spoken lists, and honors mid-sentence
/// corrections like "make that three, actually".
///
/// Three properties make it safe to put in the hot path:
/// - **On-device.** Nothing leaves the Mac, so it's viable for anything you'd dictate.
/// - **Bounded & Low Latency.** Compact prompt, dynamic token capping, and greedy decoding.
/// - **Guarded.** Output is rejected if it looks like the model answered the text instead
///   of cleaning it.
@available(macOS 26.0, *)
struct FoundationModelFormatter: TextFormatter {
    /// Deterministic fallback used on timeout, unavailability, or a rejected response.
    private let fallback = RuleBasedFormatter()

    /// Past this, taking the raw/rule text beats making the user wait.
    private let timeout: Duration = .seconds(2.0)

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in System Settings."
            case .modelNotReady: return "The on-device model is still downloading."
            @unknown default: return "The on-device model is unavailable."
            }
        @unknown default:
            return "The on-device model is unavailable."
        }
    }

    /// Pre-warms the foundation model subsystem so key-up cleanup is immediate.
    static func warmUp() {
        guard isAvailable else { return }
        Task.detached(priority: .utility) {
            _ = SystemLanguageModel.default
        }
    }

    func format(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Short-circuit single words or very short trivial inputs to 0ms
        let wordCount = trimmed.split(separator: " ").count
        if wordCount <= 2 && !trimmed.contains("um") && !trimmed.contains("uh") {
            return await fallback.format(trimmed)
        }

        guard Self.isAvailable else {
            Log.speech.info("Foundation model unavailable — using rule-based cleanup")
            return await fallback.format(trimmed)
        }

        let draft = await fallback.format(trimmed)

        // If deterministic rules already structured a clean multi-line list/bullet sequence and there are no self-correction markers
        if (draft.contains("\n1.") || draft.contains("\n•")) && !trimmed.contains("no wait") && !trimmed.contains("make that") {
            return draft
        }

        // Multi-sentence selective pipeline for large inputs
        let sentences = Self.splitSentences(in: draft)
        if sentences.count > 1 {
            return await formatSentences(sentences, original: trimmed, draft: draft)
        }

        return await cleanSingle(draft, original: trimmed)
    }

    private func formatSentences(_ sentences: [String], original: String, draft: String) async -> String {
        var needsCleanup: [Int: String] = [:]
        for (index, sentence) in sentences.enumerated() {
            if Self.sentenceNeedsAiCleanup(sentence) {
                needsCleanup[index] = sentence
            }
        }

        // Fast-path: if all sentences in the multi-sentence input are clean, return in <1ms!
        if needsCleanup.isEmpty {
            return joinSentences(sentences)
        }

        // Clean disfluent sentences concurrently
        var cleanedResults: [Int: String] = [:]
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, sentence) in needsCleanup {
                group.addTask {
                    let cleaned = (try? await Self.clean(sentence)) ?? sentence
                    let plausible = Self.isPlausibleCleanup(original: sentence, cleaned: cleaned) ? cleaned : sentence
                    return (index, plausible)
                }
            }
            for await (index, result) in group {
                cleanedResults[index] = result
            }
        }

        var assembled: [String] = []
        for (index, sentence) in sentences.enumerated() {
            if let cleaned = cleanedResults[index] {
                assembled.append(cleaned)
            } else {
                assembled.append(sentence)
            }
        }

        return joinSentences(assembled)
    }

    private func cleanSingle(_ text: String, original: String) async -> String {
        do {
            let cleaned = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await Self.clean(text) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw CleanupError.timedOut
                }
                guard let first = try await group.next() else { throw CleanupError.timedOut }
                group.cancelAll()
                return first
            }

            guard Self.isPlausibleCleanup(original: original, cleaned: cleaned) else {
                Log.speech.info("Foundation model output rejected — using rule-based cleanup")
                return text
            }
            return cleaned
        } catch {
            Log.speech.info("Foundation model cleanup failed (\(Self.describe(error), privacy: .public)) — falling back")
            return text
        }
    }

    private func joinSentences(_ sentences: [String]) -> String {
        var mutableSentences = sentences
        // If a sentence is immediately followed by a list, convert its trailing period to a colon
        for i in 0..<(mutableSentences.count - 1) {
            let next = mutableSentences[i + 1]
            let isNextList = next.hasPrefix("•") || next.range(of: "^\\d+\\.", options: .regularExpression) != nil || next.contains("\n1.")
            if isNextList && mutableSentences[i].hasSuffix(".") {
                mutableSentences[i] = String(mutableSentences[i].dropLast()) + ":"
            }
        }

        var result = ""
        for (index, s) in mutableSentences.enumerated() {
            if index == 0 {
                result = s
            } else {
                let prev = mutableSentences[index - 1]
                if prev.hasSuffix(":") || s.hasPrefix("•") || s.range(of: "^\\d+\\.", options: .regularExpression) != nil || prev.contains("\n") {
                    result += "\n" + s
                } else {
                    result += " " + s
                }
            }
        }
        return result
    }

    private static func splitSentences(in text: String) -> [String] {
        var sentences: [String] = []
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }

            if trimmedLine.hasPrefix("•") || trimmedLine.range(of: "^\\d+\\.", options: .regularExpression) != nil {
                sentences.append(trimmedLine)
                continue
            }

            let pattern = "(?<=[.!?])\\s+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = trimmedLine as NSString
                let matches = regex.matches(in: trimmedLine, range: NSRange(location: 0, length: nsString.length))
                var lastLocation = 0
                for match in matches {
                    let range = NSRange(location: lastLocation, length: match.range.location - lastLocation)
                    let sentence = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty {
                        sentences.append(sentence)
                    }
                    lastLocation = match.range.location + match.range.length
                }
                if lastLocation < nsString.length {
                    let sentence = nsString.substring(from: lastLocation).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty {
                        sentences.append(sentence)
                    }
                }
            } else {
                sentences.append(trimmedLine)
            }
        }
        return sentences
    }

    private static func sentenceNeedsAiCleanup(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let triggers = [
            "um", "uh", "erm", "uhm", "hmm", "mhm",
            "no wait", "make that", "scratch that", "i mean", "sorry",
            "bullet", "step one", "number one", "firstly",
            "i was thinking that we could i was thinking"
        ]
        if triggers.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }

    private static func describe(_ error: Error) -> String {
        error.localizedDescription
    }

    static func cleanDirect(_ text: String) async throws -> String {
        try await clean(text)
    }

    private static func clean(_ text: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You clean speech transcripts. Return ONLY the cleaned speech text.
            - Fix punctuation, grammar, capitalization, and sentence transitions.
            - Remove conversational fillers (um, uh, like, so basically, you know) and stutters.
            - Apply spoken self-corrections (e.g. "Let's meet Tuesday morning no wait actually Thursday at 10 AM" becomes "Let's meet Thursday at 10 AM").
            - Do NOT drop opening phrases like "Let's", "I think", "we should", or "in my opinion".
            - Do NOT change declarative statements into questions. Only use a question mark (?) if the input is an actual question.
            - Format multi-item lists on numbered (1. 2. 3.) or bulleted (•) lines with a colon after the intro clause.
            - Never turn regular multi-clause sentences or ordinary paragraphs into lists.
            - Preserve exact meaning and vocabulary. Never add preambles, explanations, or answers.
            """)

        let maxTokens = min(max(Int(Double(text.count) * 0.35) + 12, 25), 180)

        let response = try await session.respond(
            to: "Clean: \(text)",
            options: GenerationOptions(
                temperature: 0.0,
                maximumResponseTokens: maxTokens
            )
        )

        var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // If model prepended a stray "1. " but there is no multi-item list, strip the stray "1. "
        if content.hasPrefix("1. ") && !content.contains("2.") && !content.contains("\n") {
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = content.first {
                content = first.uppercased() + content.dropFirst()
            }
        }

        return content
    }

    /// Rejects output that isn't recognizably a cleaned version of the input.
    static func isPlausibleCleanup(original: String, cleaned: String) -> Bool {
        guard !cleaned.isEmpty else { return false }

        let originalTokens = contentWords(original)
        let cleanedTokens = contentWords(cleaned)
        guard !originalTokens.isEmpty else { return false }

        // 1. No invented content words. Numbers/digits and punctuation are structural, not invented content.
        let vocabulary = Set(originalTokens)
        let invented = cleanedTokens.filter { token in
            // Digits / numbers are structural markers, not invented vocabulary
            if token.allSatisfy(\.isNumber) { return false }
            if vocabulary.contains(token) { return false }
            // Check numeral / word aliases
            if let aliases = numeralAliases[token], aliases.contains(where: { vocabulary.contains($0) }) {
                return false
            }
            return true
        }
        guard invented.isEmpty else {
            Log.speech.info("cleanup rejected — invented words: \(invented.prefix(5).joined(separator: ", "), privacy: .public)")
            return false
        }

        // 2. Length sanity ratio
        let ratio = Double(cleanedTokens.count) / Double(max(1, spokenWordCount(original)))
        guard ratio >= 0.25, ratio <= 1.7 else {
            Log.speech.info("cleanup rejected — length ratio \(ratio, format: .fixed(precision: 2))")
            return false
        }

        // 3. Conversational rejection
        let lowered = cleaned.lowercased()
        let tells = [
            "here's the cleaned", "here is the cleaned", "cleaned transcript",
            "sure,", "certainly,", "i cannot", "i can't", "as an ai",
        ]
        if tells.contains(where: { lowered.hasPrefix($0) }) { return false }

        // 4. Ensure important intent markers aren't silently deleted
        let origLower = original.lowercased()
        if (origLower.contains("i think") || origLower.contains("we think")) &&
           (!lowered.contains("i think") && !lowered.contains("we think")) {
            return false
        }

        return true
    }

    private static let numeralAliases: [String: Set<String>] = [
        "1": ["1", "one", "first", "firstly"],
        "2": ["2", "two", "second", "secondly"],
        "3": ["3", "three", "third", "thirdly"],
        "4": ["4", "four", "fourth", "fourthly"],
        "5": ["5", "five", "fifth", "fifthly"],
        "6": ["6", "six", "sixth"],
        "7": ["7", "seven", "seventh"],
        "8": ["8", "eight", "eighth"],
        "9": ["9", "nine", "ninth"],
        "10": ["10", "ten", "tenth"],
        "one": ["1", "first"],
        "two": ["2", "second"],
        "three": ["3", "third"],
        "first": ["1", "one"],
        "second": ["2", "two"],
        "third": ["3", "three"]
    ]

    private static func contentWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "then", "s", "t", "re", "ll", "ve", "d", "m",
        "bullet", "point", "next", "line", "paragraph", "colon", "semicolon", "comma", "period",
        "number", "step", "item"
    ]

    private static func spokenWordCount(_ text: String) -> Int {
        contentWords(text).count { !fillerWords.contains($0) }
    }

    private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "uhm", "hmm", "mhm", "like", "basically", "actually", "literally",
        "just", "really", "okay", "ok", "well", "right", "anyway", "i", "mean", "you", "know",
        "kind", "sort", "of", "stuff", "thing", "things",
    ]

    private enum CleanupError: LocalizedError {
        case timedOut
        var errorDescription: String? { "on-device cleanup timed out" }
    }
}
