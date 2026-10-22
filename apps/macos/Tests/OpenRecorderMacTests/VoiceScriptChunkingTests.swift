import XCTest
@testable import OpenRecorderMac

final class VoiceScriptChunkingTests: XCTestCase {
    func testShortScriptIsOneChunk() {
        XCTAssertEqual(VoiceGeneratorController.splitScript("Hello there. How are you?"), ["Hello there. How are you?"])
    }

    func testLongScriptSplitsOnSentencesWithinLimit() {
        let sentence = "This is a reasonably long sentence about recording your screen."
        let script = Array(repeating: sentence, count: 10).joined(separator: " ")
        let chunks = VoiceGeneratorController.splitScript(script, maxLength: 140)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 140 })
        XCTAssertEqual(chunks.joined(separator: " "), script)
    }

    func testOversizedSentenceSplitsOnWords() {
        let script = Array(repeating: "word", count: 200).joined(separator: " ")
        let chunks = VoiceGeneratorController.splitScript(script, maxLength: 100)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 100 })
        XCTAssertEqual(chunks.joined(separator: " "), script)
    }
}
