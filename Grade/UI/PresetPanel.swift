import SwiftUI

/// Category chips, the preset strip and the strength slider.
struct PresetPanel: View {
    @Environment(EditorModel.self) private var model
    @State private var categoryID: String?

    var body: some View {
        VStack(spacing: 14) {
            categories
            strip
            strength
        }
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", id: nil)
                ForEach(model.categories) { chip($0.name, id: $0.id) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, id: String?) -> some View {
        let isSelected = categoryID == id
        return Button {
            withAnimation(.snappy) { categoryID = id }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .black : .white)
                .background(isSelected ? Color.white : Theme.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category-\(id ?? "all")")
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    PresetThumbnail(
                        name: "Original",
                        image: model.thumbnails[EditorModel.originalID],
                        isSelected: model.selectedPresetID == nil
                    ) {
                        model.selectPreset(nil)
                    }
                    .accessibilityIdentifier("preset-\(EditorModel.originalID)")

                    ForEach(model.presets(in: categoryID)) { preset in
                        PresetThumbnail(
                            name: preset.name,
                            image: model.thumbnails[preset.id],
                            isSelected: model.selectedPresetID == preset.id
                        ) {
                            withAnimation(.snappy) { proxy.scrollTo(preset.id, anchor: .center) }
                            model.selectPreset(preset.id)
                        }
                        .id(preset.id)
                        .accessibilityIdentifier("preset-\(preset.id)")
                        .contextMenu {
                            if preset.category == EditorModel.myLooksCategory.id {
                                Button("Delete Look", systemImage: "trash", role: .destructive) {
                                    model.deleteLook(id: preset.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var strength: some View {
        HStack(spacing: 12) {
            Text("Strength")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { model.intensity }, set: { model.setIntensity($0) }),
                in: 0...1
            )
            .accessibilityLabel("Strength")
            .accessibilityIdentifier("intensitySlider")
            Text("\(Int((model.intensity * 100).rounded()))")
                .font(.footnote.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        // Keep the panel's height steady when the original is selected.
        .opacity(model.selectedPresetID == nil ? 0 : 1)
        .disabled(model.selectedPresetID == nil)
    }
}

struct PresetThumbnail: View {
    let name: String
    let image: RenderedImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Theme.control
                    if let image {
                        Image(decorative: image.cgImage, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: Theme.thumbnailSize, height: Theme.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2.5)
                }
                Text(name)
                    .font(.caption2.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: Theme.thumbnailSize + 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
