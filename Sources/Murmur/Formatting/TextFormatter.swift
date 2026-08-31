import Foundation

/// The cleanup pass between raw transcription and injection.
protocol TextFormatter: Sendable {
    func format(_ raw: String) async -> String
}

/// Deterministic, zero-latency cleanup. Formats lists, cleans fillers, and normalizes punctuation.
struct RuleBasedFormatter: TextFormatter {
    private static let fillers = ["um", "uh", "erm", "uhm", "hmm", "mhm"]

    private struct TransitionRule {
        let word: String
        let capitalizedWord: String
        let midRegex: NSRegularExpression
        let startRegex: NSRegularExpression

        init(word: String) {
            self.word = word
            self.capitalizedWord = word.capitalized
            let midPattern = "(?<=[\\w])\\s+\(word)\\s+"
            self.midRegex = try! NSRegularExpression(pattern: midPattern)

            let startPattern = "(?i)(?:^|(?<=[.!?\\n]\\s))(\(word))\\s+(?!,)"
            self.startRegex = try! NSRegularExpression(pattern: startPattern)
        }
    }

    private static let transitionRules: [TransitionRule] = [
        "however", "therefore", "furthermore", "moreover", "meanwhile"
    ].map { TransitionRule(word: $0) }

    func format(_ raw: String) async -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = stripFillers(from: text)
        text = detectAndFormatEnumerations(in: text)
        text = formatTransitions(in: text)
        text = collapseWhitespace(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)

        return text
    }

    private func stripFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            let pattern = "(?i)(?<![\\w'])\(filler)\\b,?"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        // Repeatedly strip stacked leading filler phrases and restart markers at start of string or after sentence boundary
        var previous = ""
        while previous != result {
            previous = result
            result = result
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: "(?i)(?:^|(?<=[.!?\\n]\\s))(?:so\\s+basically|basically|like|so|um|uh|no\\s+wait|wait|make\\s+that)[,\\s]+",
                    with: "",
                    options: .regularExpression
                )
        }
        return result
    }

    private func formatTransitions(in text: String) -> String {
        var result = text
        // Format discourse transitions like "however", "therefore", "furthermore"
        for rule in Self.transitionRules {
            // If preceded by a space and not punctuation, add period and capitalize
            let midRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.midRegex.stringByReplacingMatches(
                in: result,
                range: midRange,
                withTemplate: ". \(rule.capitalizedWord), "
            )

            // If at start of sentence/string without trailing comma, add comma
            let startRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.startRegex.stringByReplacingMatches(
                in: result,
                range: startRange,
                withTemplate: "$1, "
            )
        }
        return result
    }

    /// Detects and formats spoken lists, step sequences, ordinals, and bullet items.
    private func detectAndFormatEnumerations(in text: String) -> String {
        let result = text

        // 1. Explicit Bullet Items ("intro bullet item1 bullet item2 bullet item3")
        let bulletPattern = "(?i)^(?<intro>.*?)(?::|\\s+)bullet\\s+(?<item1>.*?)\\s+bullet\\s+(?<item2>.*?)(?:\\s+(?:and\\s+)?bullet\\s+(?<item3>.*))?$"
        if let match = firstMatch(for: bulletPattern, in: result) {
            let intro = match["intro"] ?? ""
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"]
            var items = [item1, item2]
            if let item3 = item3, !item3.isEmpty { items.append(item3) }
            return formatListOutput(intro: intro, items: items, style: .bullet)
        }

        // 2. Step-based list ("Here are the steps to install step one git clone repo step two run make app step three make install")
        let stepPattern = "(?i)^(?<intro>.*?)(?::|\\s+)(?:number|step|point|item)\\s+(?:one|1)[,:\\s]+(?<item1>.*?)\\s+(?:number|step|point|item)\\s+(?:two|2)[,:\\s]+(?<item2>.*?)\\s+(?:(?:and\\s+)?(?:number|step|point|item)\\s+(?:three|3)[,:\\s]+)(?<item3>.*)$"
        if let match = firstMatch(for: stepPattern, in: result) {
            let intro = match["intro"] ?? ""
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"] ?? ""
            return formatListOutput(intro: intro, items: [item1, item2, item3], style: .numbered)
        }

        // 3. Ordinal list ("To reproduce the issue first open Settings second select Parakeet streaming and third hold the push to talk hotkey.")
        let ordinalPattern = "(?i)^(?<intro>.*?)(?::|\\s+)(?:first|1st)[,:\\s]+(?<item1>.*?)\\s+(?:second|2nd)[,:\\s]+(?<item2>.*?)\\s+(?:(?:and\\s+)?(?:third|3rd)[,:\\s]+)(?<item3>.*)$"
        if let match = firstMatch(for: ordinalPattern, in: result) {
            let intro = match["intro"] ?? ""
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"] ?? ""
            return formatListOutput(intro: intro, items: [item1, item2, item3], style: .numbered)
        }

        // 4. Prepositional / Verb Intro List ("with/includes/features one X, two Y, and three Z")
        let enum3Pattern = "(?i)^(?<intro>.*?\\b(?:with|for|about|are|include|includes|contains|contain|has|features|following|steps|points|things|questions))(?::|\\s+)(?:(?:number|step|item|point)\\s+)?(?:one|1|first)\\s+(?<item1>.*?)[,;\\s]+(?:(?:number|step|item|point)\\s+)?(?:two|2|second)\\s+(?<item2>.*?)[,;\\s]+(?:(?:and\\s+)?(?:the\\s+last\\s+one|last\\s+one|(?:(?:number|step|item|point)\\s+)?(?:three|3|third)))\\s+(?<item3>.*)$"
        if let match = firstMatch(for: enum3Pattern, in: result) {
            let intro = match["intro"] ?? ""
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"] ?? ""
            return formatListOutput(intro: intro, items: [item1, item2, item3], style: .numbered)
        }

        // 5. Standalone numbered list ("One revamp header, two optimize images, and three fix contrast")
        let standalonePattern = "(?i)^(?:(?:number|step|item|point)\\s+)?(?:one|1|first)\\s+(?<item1>.*?)[,;\\s]+(?:(?:number|step|item|point)\\s+)?(?:two|2|second)\\s+(?<item2>.*?)[,;\\s]+(?:(?:and\\s+)?(?:the\\s+last\\s+one|last\\s+one|(?:(?:number|step|item|point)\\s+)?(?:three|3|third)))\\s+(?<item3>.*)$"
        if let match = firstMatch(for: standalonePattern, in: result) {
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"] ?? ""
            return formatListOutput(intro: "", items: [item1, item2, item3], style: .numbered)
        }

        // 6. Paragraph-embedded list ("...priorities for next sprint. One revamp X, two optimize Y, and three fix Z. Outro...")
        let paragraphListPattern = "(?i)^(?:(?<pre>.*?[.!?])\\s+)?(?<intro>[A-Z][^.!?]*?\\b(?:priorities|steps|items|reasons|goals|following|points)[^.!?]*?)(?::|\\.|\\s+)\\s*(?:(?:number|step|item|point)\\s+)?(?:one|1|first)\\s+(?<item1>.*?)[,;\\s]+(?:(?:number|step|item|point)\\s+)?(?:two|2|second)\\s+(?<item2>.*?)[,;\\s]+(?:(?:and\\s+)?(?:the\\s+last\\s+one|last\\s+one|(?:(?:number|step|item|point)\\s+)?(?:three|3|third)))\\s+(?<item3>.*?(?=[.?!]|$))[.?!]?(?:\\s+(?<outro>.*))?$"
        if let match = firstMatch(for: paragraphListPattern, in: result) {
            let pre = match["pre"] ?? ""
            let intro = match["intro"] ?? ""
            let item1 = match["item1"] ?? ""
            let item2 = match["item2"] ?? ""
            let item3 = match["item3"] ?? ""
            let outro = match["outro"] ?? ""
            let formattedList = formatListOutput(intro: intro, items: [item1, item2, item3], style: .numbered)
            let trimmedPre = pre.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOutro = outro.trimmingCharacters(in: .whitespacesAndNewlines)
            var textBody = formattedList
            if !trimmedPre.isEmpty {
                textBody = "\(trimmedPre) \(formattedList)"
            }
            if !trimmedOutro.isEmpty {
                textBody = "\(textBody)\n\(trimmedOutro)"
            }
            return textBody
        }

        return result
    }

    private enum ListStyle {
        case numbered
        case bullet
    }

    private func formatListOutput(intro: String, items: [String], style: ListStyle) -> String {
        let cleanIntro = intro.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ":,;."))
        let isQuestion = cleanIntro.lowercased().hasPrefix("how") || cleanIntro.lowercased().hasPrefix("what") ||
                         cleanIntro.lowercased().hasPrefix("why") || cleanIntro.lowercased().hasPrefix("which") ||
                         cleanIntro.lowercased().hasPrefix("can") || cleanIntro.lowercased().hasPrefix("does") ||
                         cleanIntro.lowercased().hasPrefix("is")

        var formattedLines: [String] = []
        if !cleanIntro.isEmpty {
            formattedLines.append("\(cleanIntro):")
        }

        for (index, item) in items.enumerated() {
            var cleanItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanItem = cleanItem.trimmingCharacters(in: CharacterSet(charactersIn: ",;.?!"))
            if let first = cleanItem.first {
                cleanItem = first.uppercased() + cleanItem.dropFirst()
            }

            let isLast = index == items.count - 1
            let terminal = isLast ? (isQuestion ? "?" : ".") : ""

            switch style {
            case .numbered:
                formattedLines.append("\(index + 1). \(cleanItem)\(terminal)")
            case .bullet:
                formattedLines.append("• \(cleanItem)\(terminal)")
            }
        }

        return formattedLines.joined(separator: "\n")
    }

    private func firstMatch(for pattern: String, in text: String) -> [String: String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard let match = matches.first else { return nil }

        var result: [String: String] = [:]
        for name in ["pre", "intro", "item1", "item2", "item3", "outro"] {
            let range = match.range(withName: name)
            if range.location != NSNotFound {
                result[name] = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]

            if char == "•" {
                result.append(char)
                capitalizeNext = true
                index = text.index(after: index)
                continue
            }

            if char.isNumber {
                result.append(char)
                let nextIdx = text.index(after: index)
                if nextIdx < text.endIndex && text[nextIdx] == "." {
                    result.append(".")
                    capitalizeNext = true
                    index = text.index(after: nextIdx)
                    continue
                }
                index = nextIdx
                continue
            }

            if capitalizeNext && char.isLetter {
                result.append(Character(char.uppercased()))
                capitalizeNext = false
            } else {
                result.append(char)
                if ".!?\n".contains(char) {
                    capitalizeNext = true
                }
            }
            index = text.index(after: index)
        }
        return result
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard !text.contains("\n") else { return text }
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        let isQuestion = text.range(of: "(?i)^(?:what|when|where|why|how|who|which|is|can|does|do|will|could|should|would)\\b", options: .regularExpression) != nil
        return text + (isQuestion ? "?" : ".")
    }
}

/// No-op formatter, for comparing raw engine output against the cleanup pass.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
