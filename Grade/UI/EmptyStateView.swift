import PhotosUI
import SwiftUI

/// First screen: pick a photo to start.
struct EmptyStateView: View {
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "camera.filters")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.teal, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Make your photos feel")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("CINEMATIC")
                    .font(.system(size: 44, weight: .heavy, design: .default))
                    .tracking(1)
            }
            .accessibilityElement(children: .combine)
            Text("Pick a photo, try a look, then save it to your camera roll. Your original is never changed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityIdentifier("choosePhotoButton")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
