import Foundation
import Testing
@testable import Murmur

struct PipelineTests {
    @Test func stampRoundTripsThroughFileNames() throws {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 10, 21, 9, 5)
        let date = try #require(Calendar.current.date(from: components))
        #expect(NotePipeline.stamp(for: date) == "2026-10-21-0905")
        #expect(NotePipeline.date(fromStamp: "2026-10-21-0905") == date)
        #expect(NotePipeline.date(fromStamp: "2026-10-21-0905-2") == date)
    }

    @Test func nonStampFileNamesHaveNoDate() {
        #expect(NotePipeline.date(fromStamp: "standup recording") == nil)
    }

    @Test func secondRecordingInTheSameMinuteGetsASuffix() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(NotePipeline.uniqueBase(in: dir, stamp: "2026-10-21-0905").lastPathComponent == "2026-10-21-0905")
        FileManager.default.createFile(atPath: dir.appendingPathComponent("2026-10-21-0905.md").path, contents: nil)
        #expect(NotePipeline.uniqueBase(in: dir, stamp: "2026-10-21-0905").lastPathComponent == "2026-10-21-0905-2")
        FileManager.default.createFile(atPath: dir.appendingPathComponent("2026-10-21-0905-2.m4a").path, contents: nil)
        #expect(NotePipeline.uniqueBase(in: dir, stamp: "2026-10-21-0905").lastPathComponent == "2026-10-21-0905-3")
    }

    @Test func singleTrackIsEncodedWithoutMixing() {
        let args = NotePipeline.mixArguments(inputs: [URL(fileURLWithPath: "/t/system.caf")], output: URL(fileURLWithPath: "/n/a.m4a"))
        #expect(args == ["-hide_banner", "-loglevel", "error", "-y", "-i", "/t/system.caf", "-c:a", "aac", "-b:a", "128k", "/n/a.m4a"])
    }

    @Test func twoTracksAreNormalizedAndMixedWithoutAttenuation() throws {
        let args = NotePipeline.mixArguments(
            inputs: [URL(fileURLWithPath: "/t/system.caf"), URL(fileURLWithPath: "/t/mic.caf")],
            output: URL(fileURLWithPath: "/n/a.m4a")
        )
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.contains("[0:a]aformat=sample_rates=48000:channel_layouts=stereo[a0]"))
        #expect(graph.contains("[1:a]aformat=sample_rates=48000:channel_layouts=stereo[a1]"))
        #expect(graph.contains("[a0][a1]amix=inputs=2:duration=longest:normalize=0"))
        #expect(args.suffix(1) == ["/n/a.m4a"])
        #expect(args.contains("[out]"))
    }

    @Test func workDirectoryIsHiddenInsideNotesFolder() {
        let config = Config(values: ["NOTES_DIR": "/tmp/notes"])
        #expect(NotePipeline.workDirectory(for: "2026-10-21-0905", config: config).path == "/tmp/notes/.recording-2026-10-21-0905")
    }

    @Test func leftoverRecordingKeepsItsOriginalStartTime() throws {
        let config = Config(values: ["NOTES_DIR": "/tmp/notes"])
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 10, 21, 9, 5)
        let date = try #require(Calendar.current.date(from: components))
        let dir = NotePipeline.workDirectory(for: NotePipeline.stamp(for: date), config: config)
        #expect(NotePipeline.recordingDate(ofWorkDirectory: dir) == date)
        #expect(NotePipeline.recordingDate(ofWorkDirectory: URL(fileURLWithPath: "/tmp/2026-10-21-0905")) == nil)
    }
}

struct TrackAlignmentTests {
    @Test func padsSilenceWhenASourceStartsLate() {
        #expect(TrackWriter.silenceFrames(offsetSeconds: 0.5, sampleRate: 48_000, framesWritten: 0) == 24_000)
    }

    @Test func padsOnlyTheMissingPartOfAGap() {
        #expect(TrackWriter.silenceFrames(offsetSeconds: 2, sampleRate: 48_000, framesWritten: 48_000) == 48_000)
    }

    @Test func ignoresJitterBelowTwentyMilliseconds() {
        #expect(TrackWriter.silenceFrames(offsetSeconds: 1.019, sampleRate: 48_000, framesWritten: 48_000) == 0)
    }

    @Test func padsJustAboveTheTolerance() {
        #expect(TrackWriter.silenceFrames(offsetSeconds: 1.021, sampleRate: 48_000, framesWritten: 48_000) == 1_008)
    }

    @Test func neverPadsWhenAheadOfTheClockOrGivenInvalidTime() {
        #expect(TrackWriter.silenceFrames(offsetSeconds: 0.5, sampleRate: 48_000, framesWritten: 96_000) == 0)
        #expect(TrackWriter.silenceFrames(offsetSeconds: .nan, sampleRate: 48_000, framesWritten: 0) == 0)
    }
}

struct RecordedTracksTests {
    @Test func leftoverRecordingFolderIsRecognizedWithSpeakerLabels() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(RecordedTracks.load(from: dir) == nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("system.caf").path, contents: nil)
        #expect(RecordedTracks.load(from: dir)?.tracks.map(\.speaker) == [.others])
        FileManager.default.createFile(atPath: dir.appendingPathComponent("mic.caf").path, contents: nil)
        #expect(RecordedTracks.load(from: dir)?.tracks.map(\.speaker) == [.you, .others])
    }

    @Test func plainAudioFileIsNotATrackFolder() {
        #expect(RecordedTracks.load(from: URL(fileURLWithPath: "/tmp/meeting.m4a")) == nil)
    }
}
