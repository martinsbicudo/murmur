import AppKit
import Testing
@testable import Murmur

struct RecordingIconTests {
    private let mask = NSImage(size: RecordingIcon.size, flipped: false) { rect in
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
        return true
    }

    private func pixel(_ image: NSImage, x: Double, y: Double) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let color = bitmap.colorAt(x: Int(x * Double(bitmap.pixelsWide)), y: Int(y * Double(bitmap.pixelsHigh)))
        return color?.usingColorSpace(.sRGB)
    }

    @Test(arguments: [(0.0, 0.0), (1.5, 0.5), (3.0, 0.0), (4.5, 0.5), (7.5, 0.5)])
    func gradientLoopsEveryPeriod(elapsed: Double, expected: Double) {
        #expect(abs(RecordingIcon.phase(elapsed: elapsed) - expected) < 1e-9)
    }

    @Test func paintsTheGradientOnlyInsideTheMark() throws {
        let frame = RecordingIcon.frame(mask: mask, phase: 0)
        let inside = try #require(pixel(frame, x: 0.02, y: 0.5))
        let outside = try #require(pixel(frame, x: 0.9, y: 0.5))
        #expect(inside.alphaComponent > 0.9)
        #expect(inside.blueComponent > 0.6)
        #expect(outside.alphaComponent < 0.01)
    }

    @Test func gradientMovesAsThePhaseAdvances() throws {
        let start = try #require(pixel(RecordingIcon.frame(mask: mask, phase: 0), x: 0.02, y: 0.5))
        let later = try #require(pixel(RecordingIcon.frame(mask: mask, phase: 0.5), x: 0.02, y: 0.5))
        #expect(start.blueComponent - later.blueComponent > 0.1)
    }
}
