import Foundation
import Testing
@testable import Murmur

struct NoteTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let transcript = Transcript(segments: [TranscriptSegment(start: 0, text: "Hi all.")], engine: "Apple on-device speech")

    @Test func freshNoteShowsTranscribingPlaceholder() {
        let text = Note(date: date, duration: 30, audioName: "a.m4a").render()
        #expect(text.hasPrefix("# Meeting notes\n"))
        #expect(text.contains("_Transcribing…_"))
        #expect(text.contains("## Transcript\n\n_Pending._"))
        #expect(text.contains("[audio](a.m4a)"))
    }

    @Test func transcribedNoteShowsSummarizingAndTranscript() {
        let note = Note(date: date, duration: 30, audioName: "a.m4a", transcript: transcript)
        let text = note.render()
        #expect(text.contains("_Summarizing…_"))
        #expect(text.contains("transcribed with Apple on-device speech"))
        #expect(text.contains("**[00:00]** Hi all."))
    }

    @Test func finishedNotePutsSummaryAboveDividerAndTranscriptBelow() throws {
        let summary = Summary(title: "Launch sync", body: "## Summary\n- One", engine: "Claude Code")
        let text = Note(date: date, duration: 30, audioName: "a.m4a", transcript: transcript, summary: summary).render()
        #expect(text.hasPrefix("# Launch sync\n"))
        let divider = try #require(text.range(of: "\n---\n"))
        let summaryRange = try #require(text.range(of: "## Summary"))
        let transcriptRange = try #require(text.range(of: "## Transcript"))
        #expect(summaryRange.lowerBound < divider.lowerBound)
        #expect(divider.upperBound <= transcriptRange.lowerBound)
        #expect(!text.contains("_Summarizing…_"))
        #expect(text.contains("summarized with Claude Code"))
    }

    @Test func failedSummaryKeepsTranscriptAndExplainsWhy() {
        let note = Note(date: date, duration: 30, audioName: "a.m4a", transcript: transcript, problem: "Summary failed: offline\nretry")
        let text = note.render()
        #expect(text.contains("> **Note:** Summary failed: offline\n> retry"))
        #expect(!text.contains("_Summarizing…_"))
        #expect(text.contains("**[00:00]** Hi all."))
    }

    @Test func emptyTranscriptSaysNoSpeech() {
        let silent = Transcript(segments: [], engine: "x")
        #expect(Note(date: date, duration: 5, audioName: "a.m4a", transcript: silent).render().contains("_No speech detected._"))
    }

    @Test(arguments: [(0.0, "0 s"), (19.4, "19 s"), (59.4, "59 s"), (60.0, "1 min"), (3540.0, "59 min"), (3600.0, "1 h 0 min"), (5430.0, "1 h 31 min")])
    func formatsDuration(seconds: Double, expected: String) {
        #expect(Note.format(seconds) == expected)
    }
}
