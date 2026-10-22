import AppKit

/// The menu bar mark while recording: the brand gradient flowing through it, left to right.
@MainActor
final class RecordingIcon {
    nonisolated static let period: TimeInterval = 3
    static let framesPerSecond = 15.0
    nonisolated static let size = NSSize(width: 22, height: 18)

    private let mask: NSImage
    private var timer: Timer?
    private var startedAt = Date()

    init(mask: NSImage) {
        self.mask = mask
    }

    func start(in button: NSStatusBarButton) {
        guard timer == nil else { return }
        startedAt = Date()
        button.image = Self.frame(mask: mask, phase: 0)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                button.image = Self.frame(mask: self.mask, phase: Self.phase(elapsed: Date().timeIntervalSince(self.startedAt)))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated static func phase(elapsed: TimeInterval) -> Double {
        (elapsed / period).truncatingRemainder(dividingBy: 1)
    }

    nonisolated static func frame(mask: NSImage, phase: Double) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext,
                  let gradient = CGGradient(
                      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [Brand.sky.cgColor, Brand.pool.cgColor, Brand.sky.cgColor] as CFArray,
                      locations: [0, 0.5, 1]
                  ) else { return false }
            mask.draw(in: rect)
            context.setBlendMode(.sourceIn)
            for tile in 0..<2 {
                let x = rect.minX + (Double(tile) - phase) * rect.width
                context.drawLinearGradient(gradient, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + rect.width, y: 0), options: [])
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
