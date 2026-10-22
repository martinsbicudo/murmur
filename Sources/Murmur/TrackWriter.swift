import AVFoundation
import CoreMedia

/// Writes one audio source to disk, padding with silence when the source pauses
/// so every track stays aligned to the shared recording clock.
final class TrackWriter {
    let url: URL
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private var skippedBuffers = 0

    init(url: URL) {
        self.url = url
    }

    var hasAudio: Bool { framesWritten > 0 }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    func append(_ buffer: AVAudioPCMBuffer, presentationTime: CMTime, clockStart: CMTime) {
        let format = buffer.format
        let frameCount = buffer.frameLength
        do {
            let file = try openFile(for: format)
            guard file.processingFormat == format else {
                skippedBuffers += 1
                if skippedBuffers == 1 { Log.write("\(url.lastPathComponent): format changed mid-recording, skipping buffers") }
                return
            }
            let offset = CMTimeGetSeconds(CMTimeSubtract(presentationTime, clockStart))
            let gap = Self.silenceFrames(offsetSeconds: offset, sampleRate: format.sampleRate, framesWritten: framesWritten)
            if gap > 0 {
                try writeSilence(frames: gap, format: format, to: file)
            }
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(frameCount)
        } catch {
            Log.write("\(url.lastPathComponent): write failed: \(error)")
        }
    }

    static let gapTolerance = 0.02

    static func silenceFrames(offsetSeconds: Double, sampleRate: Double, framesWritten: AVAudioFramePosition) -> AVAudioFramePosition {
        guard offsetSeconds.isFinite else { return 0 }
        let gap = AVAudioFramePosition((offsetSeconds * sampleRate).rounded()) - framesWritten
        return gap > AVAudioFramePosition(sampleRate * gapTolerance) ? gap : 0
    }

    func close() {
        file = nil
    }

    private func openFile(for format: AVAudioFormat) throws -> AVAudioFile {
        if let file { return file }
        let created = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        file = created
        return created
    }

    private func writeSilence(frames: AVAudioFramePosition, format: AVAudioFormat, to file: AVAudioFile) throws {
        let chunk = AVAudioFrameCount(format.sampleRate)
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
        var remaining = frames
        while remaining > 0 {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
            silence.frameLength = count
            for audioBuffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
            }
            try file.write(from: silence)
            framesWritten += AVAudioFramePosition(count)
            remaining -= AVAudioFramePosition(count)
        }
    }
}
