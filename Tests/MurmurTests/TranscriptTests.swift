import Foundation
import Testing
@testable import Murmur

struct TranscriptTests {
    @Test(arguments: [
        (0.0, "00:00"),
        (59.9, "00:59"),
        (65.0, "01:05"),
        (3599.0, "59:59"),
        (3725.0, "1:02:05"),
        (-3.0, "00:00"),
    ])
    func formatsTimestamps(seconds: Double, expected: String) {
        #expect(Transcript.timestamp(seconds) == expected)
    }

    @Test(arguments: [("Hello.", true), ("42", true), ("Olá, você", true), (".", false), (" . . ", false), ("", false), ("...?", false)])
    func onlyTextWithWordsCountsAsSpeech(text: String, expected: Bool) {
        #expect(Transcript.hasWords(text) == expected)
    }

    @Test func unlabeledSegmentsRenderOneParagraphEach() {
        let transcript = Transcript(
            segments: [TranscriptSegment(start: 0, text: "Hello."), TranscriptSegment(start: 61, text: "Next topic.")],
            engine: "test"
        )
        #expect(transcript.markdown == "**[00:00]** Hello.\n\n**[01:01]** Next topic.")
    }

    @Test func labeledSegmentsShowTheSpeakerAndMergeConsecutiveTurns() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, text: "Let's start.", speaker: .others),
            TranscriptSegment(start: 2, text: "First topic is the launch.", speaker: .others),
            TranscriptSegment(start: 5, text: "I'll take that.", speaker: .you),
            TranscriptSegment(start: 8, text: "Great.", speaker: .others),
        ], engine: "test")
        #expect(transcript.markdown == """
        **[00:00] Others:** Let's start. First topic is the launch.

        **[00:05] You:** I'll take that.

        **[00:08] Others:** Great.
        """)
    }

    @Test func longTurnsAreSplitIntoReadableParagraphs() {
        let sentence = String(repeating: "word ", count: 70).trimmingCharacters(in: .whitespaces)
        let segments = (0..<3).map { TranscriptSegment(start: Double($0 * 20), text: sentence, speaker: .others) }
        #expect(Transcript.paragraphs(segments).count == 3)
    }
}

struct TranscriptMergerTests {
    private func seg(_ start: Double, _ text: String, end: Double? = nil) -> TranscriptSegment {
        TranscriptSegment(start: start, text: text, end: end)
    }

    @Test func labelsMicAsYouAndSystemAsOthersInTimeOrder() {
        let merged = TranscriptMerger.merge(
            you: [seg(4, "I'll send the deck tomorrow.")],
            others: [seg(0, "Can someone send the deck?"), seg(9, "Thanks!")]
        )
        #expect(merged.map(\.speaker) == [.others, .you, .others])
        #expect(merged.map(\.start) == [0, 4, 9])
    }

    @Test func dropsMicrophoneEchoOfTheOtherParticipants() {
        let merged = TranscriptMerger.merge(
            you: [seg(10.4, "we should move the launch to November"), seg(20, "Sounds good to me.")],
            others: [seg(10, "We should move the launch to November 12.")]
        )
        #expect(merged == [
            TranscriptSegment(start: 10, text: "We should move the launch to November 12.", speaker: .others),
            TranscriptSegment(start: 20, text: "Sounds good to me.", speaker: .you),
        ])
    }

    @Test func dropsAnEchoTheRecognizerHeardBadly() {
        let others = [seg(103, "And then I'll just ask, can anyone help out here with 488. I think I can help.", end: 112)]
        #expect(TranscriptMerger.isEcho(seg(105, "And then I'll just ask, did you hear what I brought here?", end: 108), against: others))
    }

    @Test func dropsAnEchoInTheMiddleOfALongerSegment() {
        let others = [seg(44, "Sean. Yesterday it was just code reviews. Yeah, I think you had mentioned that 48 was already down the road.", end: 90)]
        #expect(TranscriptMerger.isEcho(seg(88, "Yeah, I think you hadn't mentioned... Yeah.", end: 91), against: others))
    }

    @Test func keepsWhatYouSayWhileOthersAreSilent() {
        let others = [seg(590, "Victor, how are you doing?", end: 593)]
        #expect(!TranscriptMerger.isEcho(seg(606, "Yeah, so I finished the code reviews and opened a draft PR.", end: 615), against: others))
    }

    @Test func keepsSimilarWordsSaidFarApartInTime() {
        let original = seg(10, "Let's move the launch to November.")
        #expect(!TranscriptMerger.isEcho(seg(40, "Let's move the launch to November."), against: [original]))
    }

    @Test func keepsDifferentSentencesSaidAtTheSameTime() {
        #expect(!TranscriptMerger.isEcho(seg(10, "Yes, I agree with that."), against: [seg(10, "The budget is not approved yet.")]))
    }

    @Test func emptyTextIsNeverAnEcho() {
        #expect(!TranscriptMerger.isEcho(seg(10, "..."), against: [seg(10, "...")]))
    }

    @Test func otherSpeakerComesFirstOnExactTies() {
        let merged = TranscriptMerger.merge(you: [seg(5, "Okay.")], others: [seg(5, "Ready?")])
        #expect(merged.map(\.speaker) == [.others, .you])
    }
}
