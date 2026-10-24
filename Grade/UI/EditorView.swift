import PhotosUI
import SwiftUI

struct EditorView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case adjust = "Adjust"
        case enhance = "Enhance"

        var id: String { rawValue }
    }

    @Environment(EditorModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var tool = Tool.presets
    @State private var isComparing = false
    @State private var isChoosingSave = false

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas.ignoresSafeArea())
                .navigationTitle("Grade")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .overlay(alignment: .top) { savedToast }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .confirmationDialog("Save photo", isPresented: $isChoosingSave, titleVisibility: .visible) {
            Button("Save as New Photo") {
                Task { await model.save(to: .newPhoto) }
            }
            if model.canReplaceOriginal {
                Button("Replace Original") {
                    Task { await model.save(to: .replaceOriginal) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.replaceUnavailableReason
                ?? "Replace Original saves your edit onto the photo in your library. Photos keeps the original, so you can always go back with Edit → Revert.")
        }
        .alert("Couldn't save", isPresented: saveFailedBinding) {
            Button("OK") { model.dismissSaveState() }
        } message: {
            if case .failed(let message) = model.saveState { Text(message) }
        }
        .sensoryFeedback(.selection, trigger: model.selectedPresetID)
        .sensoryFeedback(.success, trigger: model.saveCount)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            EmptyStateView(pickerItem: $pickerItem)
        case .loading:
            ProgressView("Opening photo…")
                .tint(.white)
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't open photo", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                PhotosPicker("Choose another photo", selection: $pickerItem, matching: .images, photoLibrary: .shared())
                    .buttonStyle(.borderedProminent)
            }
        case .editing:
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            CompareCanvas(
                original: model.original,
                edited: model.edited,
                lookName: model.selectedPreset?.name ?? "Original",
                isCurrent: model.isPreviewCurrent,
                failure: model.renderFailure,
                isComparing: $isComparing
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { canvasButtons }

            VStack(spacing: 14) {
                Picker("Tool", selection: $tool) {
                    ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch tool {
                case .presets: PresetPanel()
                case .adjust: AdjustPanel()
                case .enhance: EnhancePanel()
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Theme.panel.ignoresSafeArea(edges: .bottom))
        }
    }

    private var canvasButtons: some View {
        HStack(spacing: 10) {
            if model.hasEdits {
                Button {
                    withAnimation(.snappy) { isComparing.toggle() }
                } label: {
                    Image(systemName: isComparing ? "rectangle" : "rectangle.split.2x1")
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel(isComparing ? "Hide before and after" : "Compare before and after")
                .accessibilityIdentifier("compareButton")
            }
        }
        .foregroundStyle(.white)
        .padding(20)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose photo", systemImage: "photo.on.rectangle.angled")
            }
            .accessibilityIdentifier("pickPhotoButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isChoosingSave = true
            } label: {
                if model.saveState == .saving {
                    if let progress = model.exportProgress {
                        // Upscaling takes a while; show how far along it is.
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                    } else {
                        ProgressView()
                    }
                } else {
                    Text("Save").fontWeight(.semibold)
                }
            }
            .disabled(!model.canSave)
            .accessibilityLabel("Save to Photos")
            .accessibilityIdentifier("saveButton")
        }
    }

    @ViewBuilder
    private var savedToast: some View {
        if model.saveState == .saved {
            Label(savedMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("savedToast")
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { model.dismissSaveState() }
                }
        }
    }

    private var savedMessage: String {
        let action = model.lastSaveDestination == .replaceOriginal ? "Original replaced" : "Saved as new photo"
        guard let size = model.lastSavedSize else { return action }
        return "\(action) · \(Int(size.width)) × \(Int(size.height))"
    }

    private var saveFailedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = model.saveState { return true }
                return false
            },
            set: { if !$0 { model.dismissSaveState() } }
        )
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                isComparing = false
                // Known when the picker is given the shared library; lets the edit replace the original.
                await model.load(data, assetIdentifier: item.itemIdentifier)
            } else {
                model.showLoadFailure()
            }
        } catch {
            model.showLoadFailure()
        }
        // Clear the selection so picking the same photo again still opens it.
        pickerItem = nil
    }
}
