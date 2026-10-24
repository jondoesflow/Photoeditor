import SwiftUI

/// Manual sliders, applied on top of the chosen preset. The current look can be saved to My Looks.
struct AdjustPanel: View {
    @Environment(EditorModel.self) private var model
    @State private var selected = Parameter.exposure
    @State private var isNamingLook = false
    @State private var lookName = ""

    var body: some View {
        VStack(spacing: 12) {
            parameters
            slider
            actions
        }
        .alert("Save look", isPresented: $isNamingLook) {
            TextField("Name", text: $lookName)
            Button("Save") {
                model.saveLook(named: lookName)
                lookName = ""
            }
            Button("Cancel", role: .cancel) { lookName = "" }
        } message: {
            Text("Keep this preset, strength and adjustments to use on other photos.")
        }
    }

    private var parameters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Parameter.allCases) { parameter in
                    Button {
                        selected = parameter
                    } label: {
                        ParameterIcon(
                            parameter: parameter,
                            isSelected: parameter == selected,
                            isChanged: model.adjustments[parameter] != 0
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(parameter.displayName)
                    .accessibilityAddTraits(parameter == selected ? .isSelected : [])
                    .accessibilityIdentifier("adjust-\(parameter.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var slider: some View {
        let value = model.adjustments[selected]
        return VStack(spacing: 4) {
            HStack {
                Text(selected.displayName)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(value == 0 ? "0" : String(format: "%+d", Int((value * 100).rounded())))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(value == 0 ? Color.secondary : Theme.accent)
            }
            Slider(
                value: Binding(
                    get: { model.adjustments[selected] },
                    set: { model.setAdjustment(selected, to: $0) }
                ),
                in: selected.range
            )
            .accessibilityLabel(selected.displayName)
            .accessibilityIdentifier("adjustSlider")
        }
        .padding(.horizontal, 16)
    }

    private var actions: some View {
        HStack {
            Button("Reset", systemImage: "arrow.counterclockwise") {
                model.resetAdjustments()
            }
            .disabled(model.adjustments.isNeutral)
            .accessibilityIdentifier("resetAdjustmentsButton")
            Spacer()
            Button("Save Look", systemImage: "star") {
                isNamingLook = true
            }
            .disabled(!model.hasEdits)
            .accessibilityIdentifier("saveLookButton")
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 16)
    }
}

private struct ParameterIcon: View {
    let parameter: Parameter
    let isSelected: Bool
    let isChanged: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: parameter.symbol)
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
            Text(parameter.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(width: 64)
    }
}
