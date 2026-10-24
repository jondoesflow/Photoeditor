import SwiftUI

/// Autopilot plus the repair tools: light, colour, denoise, detail, faces, dust, background and upscale.
struct EnhancePanel: View {
    @Environment(EditorModel.self) private var model
    @State private var selected = EnhanceTool.light

    var body: some View {
        VStack(spacing: 12) {
            autopilot
            tools
            control
                .frame(minHeight: 64, alignment: .top)
        }
    }

    private var autopilot: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { model.runAutopilot() }
            } label: {
                Label("Autopilot", systemImage: "wand.and.sparkles")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(.black)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("autopilotButton")

            Text(model.insights.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("insightsSummary")
            Spacer(minLength: 0)
            if !model.enhancement.isNeutral {
                Button("Reset") { model.resetEnhancement() }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("resetEnhanceButton")
            }
        }
        .padding(.horizontal, 16)
    }

    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(EnhanceTool.allCases) { tool in
                    Button {
                        selected = tool
                    } label: {
                        ToolIcon(
                            title: tool.displayName,
                            symbol: tool.symbol,
                            isSelected: tool == selected,
                            isChanged: model.enhancement.isActive(tool),
                            isAvailable: model.isAvailable(tool)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.displayName)
                    .accessibilityAddTraits(tool == selected ? .isSelected : [])
                    .accessibilityIdentifier("enhance-\(tool.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var control: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.isAvailable(selected) {
                Text(unavailableReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                switch selected {
                case .background: backgroundControl
                case .upscale: upscaleControl
                default: slider(for: selected)
                }
            }
            Text(selected.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func slider(for tool: EnhanceTool) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(tool.displayName).font(.footnote.weight(.semibold))
                Spacer()
                Text("\(Int((model.enhancement[tool] * 100).rounded()))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(model.enhancement[tool] == 0 ? Color.secondary : Theme.accent)
            }
            Slider(
                value: Binding(get: { model.enhancement[tool] }, set: { model.setEnhancement(tool, to: $0) }),
                in: 0...1
            )
            .accessibilityLabel(tool.displayName)
            .accessibilityIdentifier("enhanceSlider")
        }
    }

    private var backgroundControl: some View {
        VStack(spacing: 8) {
            Picker("Background", selection: Binding(get: { model.enhancement.background }, set: { model.setBackground($0) })) {
                Text("Keep").tag(Enhancement.Background.keep)
                Text("Blur").tag(Enhancement.Background.blur)
                Text("Remove").tag(Enhancement.Background.remove)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("backgroundPicker")
            if model.enhancement.background == .blur {
                Slider(
                    value: Binding(get: { model.enhancement.backgroundBlur }, set: { model.setEnhancement(.background, to: $0) }),
                    in: 0...1
                )
                .accessibilityLabel("Blur amount")
                .accessibilityIdentifier("backgroundBlurSlider")
            } else if model.enhancement.background == .remove {
                Text("Saves as a PNG with a transparent background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var upscaleControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Upscale", selection: Binding(get: { model.enhancement.upscale }, set: { model.setUpscale($0) })) {
                ForEach(UpscaleFactor.allCases, id: \.self) { factor in
                    Text(factor.label)
                        .tag(factor)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("upscalePicker")
            let input = model.insights.pixelSize, output = model.outputSize
            Text("\(Int(input.width)) × \(Int(input.height)) → \(Int(output.width)) × \(Int(output.height)) when saved"
                + (UpscaleFactor.quadruple.isAvailable(for: input) ? "" : " · 4× needs a smaller photo"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("upscaleSize")
        }
    }

    private var unavailableReason: String {
        switch selected {
        case .faces: "No faces found in this photo."
        case .background: "No clear subject found in this photo."
        case .upscale: "This photo is already too large to upscale."
        default: ""
        }
    }
}

/// A round tool button with a caption; a teal dot marks tools in use.
struct ToolIcon: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let isChanged: Bool
    var isAvailable = true

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .background(isSelected ? Theme.accent : Theme.control, in: Circle())
                .foregroundStyle(isSelected ? .black : .white)
                .overlay(alignment: .topTrailing) {
                    if isChanged {
                        Circle()
                            .fill(Theme.teal)
                            .frame(width: 9, height: 9)
                    }
                }
            Text(title)
                .font(.caption2)
                .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(width: 64)
        .opacity(isAvailable ? 1 : 0.4)
    }
}
