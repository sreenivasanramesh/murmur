import Foundation

struct CleanupBenchmark {
    struct TestCase {
        let name: String
        let raw: String
        let expected: String
    }

    static let testCases: [TestCase] = [
        TestCase(
            name: "1. Embedded Question List",
            raw: "How well does this model work with one self-correction natural list, two output cards, and three latency profiles?",
            expected: "How well does this model work with:\n1. Self-correction natural list\n2. Output cards\n3. Latency profiles?"
        ),
        TestCase(
            name: "2. Embedded Statement List",
            raw: "The release includes one streaming transcription two faster cleanup passes and three multi line UI.",
            expected: "The release includes:\n1. Streaming transcription\n2. Faster cleanup passes\n3. Multi line UI."
        ),
        TestCase(
            name: "3. Ordinal List",
            raw: "To reproduce the issue first open Settings second select Parakeet streaming and third hold the push to talk hotkey.",
            expected: "To reproduce the issue:\n1. Open Settings\n2. Select Parakeet streaming\n3. Hold the push to talk hotkey."
        ),
        TestCase(
            name: "4. Step-Based List",
            raw: "Here are the steps to install step one git clone repo step two run make app step three make install",
            expected: "Here are the steps to install:\n1. Git clone repo\n2. Run make app\n3. Make install."
        ),
        TestCase(
            name: "5. Explicit Bullet Items",
            raw: "Please pick up grocery items bullet oat milk bullet organic eggs bullet sourdough bread",
            expected: "Please pick up grocery items:\n• Oat milk\n• Organic eggs\n• Sourdough bread."
        ),
        TestCase(
            name: "6. Self-Correction",
            raw: "Let's schedule the standup for Tuesday morning no wait actually Thursday at 10 AM.",
            expected: "Let's schedule the standup for Thursday at 10 AM."
        ),
        TestCase(
            name: "7. False Starts & Stutters",
            raw: "I was thinking that we could um I was thinking we should revise the prompt design.",
            expected: "I was thinking that we could revise the prompt design."
        ),
        TestCase(
            name: "8. Heavy Filler Pruning",
            raw: "Um so basically like I think we should start deploying at five.",
            expected: "I think we should start deploying at five."
        ),
        TestCase(
            name: "9. Question Preservation",
            raw: "What time is the team sync scheduled for tomorrow morning",
            expected: "What time is the team sync scheduled for tomorrow morning?"
        ),
        TestCase(
            name: "10. Multi-Sentence Dialogue",
            raw: "the package arrived this morning it was left by the side door did you bring it inside",
            expected: "The package arrived this morning. It was left by the side door. Did you bring it inside?"
        ),
        TestCase(
            name: "11. Multi-Clause Sentence",
            raw: "We finished the benchmarks yesterday and everyone agreed with the results however we need to run more tests on battery impact before signing off",
            expected: "We finished the benchmarks yesterday, and everyone agreed with the results. However, we need to run more tests on battery impact before signing off."
        ),
        TestCase(
            name: "12. Short Fast Path",
            raw: "Sounds good",
            expected: "Sounds good."
        ),
        TestCase(
            name: "13. Large Multi-Sentence (80 words)",
            raw: "Um so basically we started the migration yesterday morning and everything went smoothly with the database setup. No wait actually we had a small issue with the Redis cache configuration but Sarah resolved it quickly. Please make sure to test the login flow on staging before we merge the pull request.",
            expected: "We started the migration yesterday morning and everything went smoothly with the database setup. Actually we had a small issue with the Redis cache configuration but Sarah resolved it quickly. Please make sure to test the login flow on staging before we merge the pull request."
        ),
        TestCase(
            name: "14. Large Embedded List (95 words)",
            raw: "I had a quick discussion with the design team regarding the upcoming release schedule. They suggested three main priorities for next sprint. One revamp the navigation header, two optimize image loading speeds, and three fix the dark mode contrast issues. We should aim to complete these items by next Friday.",
            expected: "I had a quick discussion with the design team regarding the upcoming release schedule. They suggested three main priorities for next sprint:\n1. Revamp the navigation header\n2. Optimize image loading speeds\n3. Fix the dark mode contrast issues.\nWe should aim to complete these items by next Friday."
        ),
        TestCase(
            name: "15. Large Technical Report (85 words)",
            raw: "The benchmark results on the latest M3 Max chip show a significant throughput increase across all test suites. The memory footprint remained stable under continuous load. However we noticed a slight degradation in latency when processing concurrent streaming requests. Therefore we recommend optimizing the thread pool allocation before going live.",
            expected: "The benchmark results on the latest M3 Max chip show a significant throughput increase across all test suites. The memory footprint remained stable under continuous load. However, we noticed a slight degradation in latency when processing concurrent streaming requests. Therefore, we recommend optimizing the thread pool allocation before going live."
        )
    ]

    static func run() async {
        print("\n=======================================================")
        print("          MURMUR SMART CLEANUP BENCHMARK               ")
        print("=======================================================\n")

        print("Foundation Model Available: \(FoundationModelFormatter.isAvailable)")
        if let reason = FoundationModelFormatter.unavailableReason {
            print("Reason: \(reason)")
        }

        let aiFormatter = FoundationModelFormatter()
        let ruleFormatter = RuleBasedFormatter()

        // 1. Warm-up pass
        FoundationModelFormatter.warmUp()
        _ = await aiFormatter.format("warmup test utterance")

        print("\n-------------------------------------------------------")
        print("                 BENCHMARK RESULTS                     ")
        print("-------------------------------------------------------\n")

        var aiLatencies: [Double] = []
        var ruleLatencies: [Double] = []
        var passedCount = 0

        for (index, testCase) in testCases.enumerated() {
            print("[\(index + 1)/\(testCases.count)] \(testCase.name)")
            print("  RAW:      \"\(testCase.raw)\"")
            print("  EXPECTED: \"\(testCase.expected.replacingOccurrences(of: "\n", with: " \\n "))\"")

            // Rule-based test
            let ruleStart = Date()
            let ruleCleaned = await ruleFormatter.format(testCase.raw)
            let ruleMs = Date().timeIntervalSince(ruleStart) * 1000.0
            ruleLatencies.append(ruleMs)

            // AI test
            let aiStart = Date()
            var rawAi = ""
            var wasRejected = false
            do {
                rawAi = try await FoundationModelFormatter.cleanDirect(testCase.raw)
                wasRejected = !FoundationModelFormatter.isPlausibleCleanup(original: testCase.raw, cleaned: rawAi)
            } catch {
                rawAi = "ERROR: \(error.localizedDescription)"
            }
            let aiCleaned = await aiFormatter.format(testCase.raw)
            let aiMs = Date().timeIntervalSince(aiStart) * 1000.0
            aiLatencies.append(aiMs)

            print("  RULE [\(String(format: "%.2f", ruleMs))ms]:  \"\(ruleCleaned.replacingOccurrences(of: "\n", with: " \\n "))\"")
            print("  RAW AI:          \"\(rawAi.replacingOccurrences(of: "\n", with: " \\n "))\"")
            if wasRejected {
                print("  GUARD STATUS:    REJECTED (fallback applied)")
            } else {
                print("  GUARD STATUS:    ACCEPTED")
            }
            print("  FINAL [\(String(format: "%.1f", aiMs))ms]: \"\(aiCleaned.replacingOccurrences(of: "\n", with: " \\n "))\"")

            let nAi = normalize(aiCleaned)
            let nExp = normalize(testCase.expected)
            let isPassed = nAi == nExp
            if isPassed {
                passedCount += 1
                print("  STATUS:   ✅ PASSED")
            } else {
                print("  STATUS:   ❌ DIFF DETECTED")
                print("  NORM AI:  \"\(nAi)\"")
                print("  NORM EXP: \"\(nExp)\"")
                if nAi.count != nExp.count {
                    print("  COUNT DIFF: AI length \(nAi.count) vs EXP length \(nExp.count)")
                }
                for (i, (c1, c2)) in zip(nAi, nExp).enumerated() {
                    if c1 != c2 {
                        print("  DIFF AT [\(i)]: AI '\(c1)' (\(c1.unicodeScalars.first!.value)) vs EXP '\(c2)' (\(c2.unicodeScalars.first!.value))")
                        break
                    }
                }
            }
            print("")
        }

        let avgAi = aiLatencies.reduce(0, +) / Double(aiLatencies.count)
        let avgRule = ruleLatencies.reduce(0, +) / Double(ruleLatencies.count)

        print("=======================================================")
        print("  SUMMARY:")
        print("  Pass Rate: \(passedCount)/\(testCases.count) (\(Int(Double(passedCount) / Double(testCases.count) * 100))%)")
        print("  Average Rule-Based Latency: \(String(format: "%.3f", avgRule)) ms")
        print("  Average Smart AI Latency:   \(String(format: "%.1f", avgAi)) ms")
        print("=======================================================\n")
    }

    private static func normalize(_ str: String) -> String {
        str
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: ", and ", with: " and ")
            .replacingOccurrences(of: ", however,", with: ". However,")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
