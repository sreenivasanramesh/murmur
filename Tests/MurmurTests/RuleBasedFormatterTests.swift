import Testing
@testable import Murmur

struct RuleBasedFormatterTests {

    @Test("Handles empty and whitespace-only strings")
    func handlesEmptyAndWhitespaceStrings() async {
        let formatter = RuleBasedFormatter()

        let empty = await formatter.format("")
        #expect(empty == "")

        let spaces = await formatter.format("   ")
        #expect(spaces == "")

        let collapse = await formatter.format("word1     word2")
        #expect(collapse == "Word1 word2.")
    }

    @Test("Strips standalone filler words like um and uh")
    func stripsFillers() async {
        let formatter = RuleBasedFormatter()

        let result1 = await formatter.format("um test")
        #expect(result1 == "Test.")

        let result2 = await formatter.format("uh, hello")
        #expect(result2 == "Hello.")

        let result3 = await formatter.format("this is erm good")
        #expect(result3 == "This is good.")

        let result4 = await formatter.format("so basically, we need to go")
        #expect(result4 == "We need to go.")

        let result5 = await formatter.format("wait, no wait, let me think")
        #expect(result5 == "Let me think.")
    }

    @Test("Capitalizes and punctuates transition words")
    func formatTransitions() async {
        let formatter = RuleBasedFormatter()

        let result1 = await formatter.format("I think this is good however it needs work")
        #expect(result1 == "I think this is good. However, it needs work.")

        let result2 = await formatter.format("meanwhile we should wait")
        #expect(result2 == "Meanwhile, we should wait.")

        let result3 = await formatter.format("therefore I am")
        #expect(result3 == "Therefore, I am.")
    }

    @Test("Detects and formats bullet lists")
    func bulletLists() async {
        let formatter = RuleBasedFormatter()

        let result = await formatter.format("intro bullet one bullet two bullet three")
        #expect(result == "Intro:\n• One\n• Two\n• Three.")
    }

    @Test("Detects and formats step lists")
    func stepLists() async {
        let formatter = RuleBasedFormatter()

        let result = await formatter.format("Here are the steps step one git clone step two build step three run")
        #expect(result == "Here are the steps:\n1. Git clone\n2. Build\n3. Run.")
    }

    @Test("Detects and formats ordinal lists")
    func ordinalLists() async {
        let formatter = RuleBasedFormatter()

        let result = await formatter.format("first we go second we eat third we sleep")
        #expect(result == "1. We go\n2. We eat\n3. We sleep.")
    }

    @Test("Capitalizes sentences and terminal punctuation")
    func capitalizationAndPunctuation() async {
        let formatter = RuleBasedFormatter()

        let sentence = await formatter.format("word , word")
        #expect(sentence == "Word, word.")

        let question1 = await formatter.format("what is this")
        #expect(question1 == "What is this?")

        let question2 = await formatter.format("how does it work")
        #expect(question2 == "How does it work?")

        let question3 = await formatter.format("is this real")
        #expect(question3 == "Is this real?")
    }
}
