import Foundation
import Testing
@testable import Murmur

@MainActor
struct LiveTranscriptModelTests {
    private func update(_ speaker: Speaker, _ text: String, final: Bool = false) -> LiveUpdate {
        LiveUpdate(speaker: speaker, text: text, isFinal: final)
    }

    @Test func partialTextIsReplacedAsRecognitionRefinesIt() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "we should"))
        model.apply(update(.others, "we should move the"))
        #expect(model.blocks.count == 1)
        #expect(model.blocks[0].volatileText == "we should move the")
        #expect(model.blocks[0].finalText.isEmpty)
    }

    @Test func finalTextIsKeptAndPartialCleared() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "we should move"))
        model.apply(update(.others, "We should move the launch.", final: true))
        #expect(model.blocks == [LiveBlock(id: 0, speaker: .others, finalText: "We should move the launch.", volatileText: "")])
    }

    @Test func consecutiveSentencesFromTheSameSpeakerShareABlock() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "First.", final: true))
        model.apply(update(.you, "Second.", final: true))
        #expect(model.blocks.count == 1)
        #expect(model.blocks[0].finalText == "First. Second.")
    }

    @Test func turnChangesStartANewBlock() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "Ready?", final: true))
        model.apply(update(.you, "Yes.", final: true))
        model.apply(update(.others, "Great.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others, .you, .others])
    }

    @Test func overlappingSpeechUpdatesEachSpeakersOwnBlock() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "so the budget"))
        model.apply(update(.you, "sorry"))
        model.apply(update(.others, "So the budget is approved.", final: true))
        model.apply(update(.you, "Sorry, go on.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others, .you])
        #expect(model.blocks.map(\.finalText) == ["So the budget is approved.", "Sorry, go on."])
        #expect(model.blocks.allSatisfy { $0.volatileText.isEmpty })
    }

    @Test func emptyResultsLeaveNoEmptyBlocks() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "hmm"))
        model.apply(update(.you, "", final: true))
        #expect(model.blocks.isEmpty)
    }

    @Test func hidesMicrophoneEchoOfWhatOthersJustSaid() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "We should move the launch to November.", final: true))
        model.apply(update(.you, "we should move the"))
        model.apply(update(.you, "We should move the lunch to November.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others])
    }

    @Test func sameSentenceRecognizedOnBothTracksAtOnceShowsOnlyAsOthers() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "we should"))
        model.apply(update(.others, "we should move"))
        model.apply(update(.you, "we should move the"))
        model.apply(update(.others, "we should move the launch"))
        model.apply(update(.you, "We should move the lunch to November.", final: true))
        model.apply(update(.others, "We should move the launch to November.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others])
        #expect(model.blocks[0].finalText == "We should move the launch to November.")
    }

    @Test func removesEchoThatArrivedBeforeTheOthersText() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "We should move the lunch to November.", final: true))
        model.apply(update(.others, "We should move the launch to November.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others])
    }

    @Test func othersKeepTheirOpenBlockWhenAnEarlierEchoIsRemoved() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "We should move the lunch to November.", final: true))
        model.apply(update(.others, "we should move the launch"))
        model.apply(update(.others, "We should move the launch to November.", final: true))
        #expect(model.blocks == [LiveBlock(id: 1, speaker: .others, finalText: "We should move the launch to November.", volatileText: "")])
    }

    @Test func keepsYourOwnAnswerWhileOthersTalk() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "Can you take the release notes?", final: true))
        model.apply(update(.you, "Sure, I'll draft them tonight.", final: true))
        model.apply(update(.others, "Great, thanks.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others, .you, .others])
    }

    @Test func oldOthersTextDoesNotHideWhatYouSayLater() {
        var clock = Date(timeIntervalSince1970: 0)
        let model = LiveTranscriptModel(now: { clock })
        model.apply(update(.others, "We should move the launch to November.", final: true))
        clock += LiveTranscriptModel.echoWindow + 1
        model.apply(update(.you, "Let's move the launch to November.", final: true))
        #expect(model.blocks.map(\.speaker) == [.others, .you])
    }

    @Test func mutedMicrophoneShowsNothingNewFromYouButKeepsOthers() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "Let me check", final: true))
        model.setMuted(true)
        model.apply(update(.you, "private comment", final: true))
        model.apply(update(.others, "Any updates?", final: true))
        #expect(model.blocks.map(\.speaker) == [.you, .others])
        #expect(model.blocks.map(\.finalText) == ["Let me check", "Any updates?"])
    }

    @Test func mutingDropsWhatYouWereHalfwayThroughSaying() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "half a sente"))
        model.setMuted(true)
        #expect(model.blocks.isEmpty)
    }

    @Test func unmutingShowsYouAgain() {
        let model = LiveTranscriptModel()
        model.setMuted(true, warning: "This microphone can't be muted by other apps.")
        #expect(model.muteWarning != nil)
        model.setMuted(false)
        #expect(model.muteWarning == nil)
        model.apply(update(.you, "I'm back.", final: true))
        #expect(model.blocks.map(\.finalText) == ["I'm back."])
    }

    @Test func transcriptTextListsEachTurnWithItsSpeaker() {
        let model = LiveTranscriptModel()
        model.apply(update(.others, "Ready?", final: true))
        model.apply(update(.you, "Yes.", final: true))
        model.apply(update(.you, "Let's go"))
        #expect(model.transcriptText == "Others: Ready?\nYou: Yes. Let's go")
    }

    @Test func punctuationOnlyResultsAreNotShown() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, ".", final: true))
        model.apply(update(.others, "Ready?", final: true))
        model.apply(update(.others, " . ", final: true))
        #expect(model.blocks == [LiveBlock(id: 1, speaker: .others, finalText: "Ready?", volatileText: "")])
    }

    @Test func resetClearsEverything() {
        let model = LiveTranscriptModel()
        model.apply(update(.you, "Hi.", final: true))
        model.setStatus("Preparing…")
        model.setCanMute(true)
        model.setMuted(true)
        model.reset()
        #expect(model.blocks.isEmpty)
        #expect(model.status == nil)
        #expect(!model.canMute)
        #expect(!model.isMuted)
        model.apply(update(.others, "New meeting.", final: true))
        #expect(model.blocks.first?.id == 0)
    }
}
