import SwiftUI

/// The photo. Hold it to see the original; in compare mode, drag the divider to wipe
/// between before (left) and after (right).
struct CompareCanvas: View {
    let original: RenderedImage?
    let edited: RenderedImage?
    let lookName: String
    /// False while a newer preview is rendering; exposed to UI tests as the canvas value.
    let isCurrent: Bool
    @Binding var isComparing: Bool

    @State private var split: CGFloat = 0.5
    @State private var isPeeking = false

    var body: some View {
        if let original, let edited {
            Color.clear
                .aspectRatio(edited.size.width / max(edited.size.height, 1), contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        if isComparing {
                            comparison(original: original, edited: edited, size: geometry.size)
                        } else {
                            peekable(original: original, edited: edited)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isPeeking ? "Original photo" : "Photo with \(lookName)")
                .accessibilityValue(isCurrent ? "ready" : "rendering")
                .accessibilityIdentifier("canvas")
        }
    }

    private func photo(_ image: RenderedImage) -> some View {
        Image(decorative: image.cgImage, scale: 1)
            .resizable()
            .interpolation(.high)
    }

    private func peekable(original: RenderedImage, edited: RenderedImage) -> some View {
        ZStack(alignment: .topLeading) {
            photo(isPeeking ? original : edited)
            if isPeeking {
                CanvasBadge(text: "Before")
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
            isPeeking = pressing
        })
    }

    private func comparison(original: RenderedImage, edited: RenderedImage, size: CGSize) -> some View {
        let dividerX = size.width * split
        return ZStack(alignment: .topLeading) {
            photo(edited)
            photo(original)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: dividerX)
                }
            CanvasBadge(text: "Before")
            CanvasBadge(text: "After")
                .frame(maxWidth: .infinity, alignment: .trailing)
            divider(height: size.height)
                .offset(x: dividerX - 22)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    split = (value.location.x / max(size.width, 1)).clamped(to: 0...1)
                }
        )
        .accessibilityIdentifier("compareSplit")
    }

    private func divider(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.4), radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .frame(width: 44, height: height)
        .allowsHitTesting(false)
    }
}
