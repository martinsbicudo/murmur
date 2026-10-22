import AppKit
import SwiftUI

enum Brand {
    static let sky = NSColor(srgbRed: 134 / 255, green: 211 / 255, blue: 255 / 255, alpha: 1)
    static let pool = NSColor(srgbRed: 52 / 255, green: 217 / 255, blue: 184 / 255, alpha: 1)

    static let gradient = AnyShapeStyle(LinearGradient(
        colors: [Color(nsColor: sky), Color(nsColor: pool)],
        startPoint: .leading,
        endPoint: .trailing
    ))
}
