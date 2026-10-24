import SwiftUI

/// A dark, photo-first palette so colours on screen aren't skewed by bright chrome.
enum Theme {
    static let accent = Color.accentColor
    static let canvas = Color.black
    static let panel = Color(white: 0.07)
    static let control = Color(white: 0.15)
    static let teal = Color(red: 0.13, green: 0.63, blue: 0.67)

    static let thumbnailSize: CGFloat = 72
}

/// A small capsule label, used for "Before" / "After".
struct CanvasBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(10)
            .allowsHitTesting(false)
    }
}
