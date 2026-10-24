import CoreGraphics
import Foundation
import Observation

/// Editor state: the loaded photo, its enhancements, the chosen look, manual adjustments and saving.
/// The photo is enhanced first, then the look (`preset × intensity + adjustments`) is applied on top;
/// the original is never changed.
@MainActor
@Observable
final class EditorModel {
    enum Phase: Equatable {
        case empty
        case loading
        case editing
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    enum SaveDestination: Equatable, Sendable {
        /// Adds a separate copy; the original is untouched.
        case newPhoto
        /// Saves the edit onto the original library photo. Photos keeps the original for Revert.
        case replaceOriginal
    }

    nonisolated static let myLooksCategory = PresetCategory(id: "mine", name: "My Looks")
    /// Thumbnail key for the unedited photo.
    nonisolated static let originalID = "original"

    let library: PresetLibrary
    private(set) var looks: [Preset]
    private(set) var phase: Phase = .empty
    private(set) var original: RenderedImage?
    private(set) var edited: RenderedImage?
    /// The recipe `edited` was rendered with.
    private(set) var editedRecipe: Recipe?
    /// The enhancement `edited` was rendered with (upscaling excluded: it only happens when saving).
    private(set) var editedEnhancement: Enhancement?
    /// Why the latest preview render failed, if it did.
    private(set) var renderFailure: String?
    private(set) var thumbnails: [String: RenderedImage] = [:]
    private(set) var selectedPresetID: String?
    private(set) var intensity: Double = 1
    private(set) var adjustments = Recipe.neutral
    /// Repairs and improvements for this photo. Reset when another photo opens.
    private(set) var enhancement = Enhancement.none
    /// What the analysis found in the current photo.
    private(set) var insights = PhotoInsights.empty
    /// 0…1 while an upscaled photo is being saved.
    private(set) var exportProgress: Double?
    /// The size of the last saved photo, shown in the confirmation.
    private(set) var lastSavedSize: CGSize?
    /// Where the last photo was saved, for the confirmation.
    private(set) var lastSaveDestination = SaveDestination.newPhoto
    /// The photo library identifier of the open photo, when it came from the library.
    private(set) var sourceAssetID: String?
    private(set) var saveState: SaveState = .idle
    /// Increments on every successful save; drives the haptic.
    private(set) var saveCount = 0

    private let renderer: PhotoRenderer
    private let saver: any PhotoSaving
    private let lookStore: LookStore
    private var renderTask: Task<Void, Never>?
    private var renderGeneration = 0

    init(library: PresetLibrary, renderer: PhotoRenderer = PhotoRenderer(), saver: any PhotoSaving, lookStore: LookStore) {
        self.library = library
        self.renderer = renderer
        self.saver = saver
        self.lookStore = lookStore
        looks = lookStore.load()
    }

    // MARK: - Derived state

    var categories: [PresetCategory] {
        looks.isEmpty ? library.categories : library.categories + [Self.myLooksCategory]
    }

    var allPresets: [Preset] { library.presets + looks }

    /// All presets, or those in one category.
    func presets(in categoryID: String?) -> [Preset] {
        guard let categoryID else { return allPresets }
        return allPresets.filter { $0.category == categoryID }
    }

    var selectedPreset: Preset? {
        selectedPresetID.flatMap { id in allPresets.first { $0.id == id } }
    }

    /// What will be rendered and saved.
    var recipe: Recipe {
        (selectedPreset?.recipe.scaled(by: intensity) ?? .neutral).adding(adjustments)
    }

    var hasEdits: Bool { !recipe.isNeutral || !enhancement.isNeutral }

    /// False while a newer preview is still rendering.
    var isPreviewCurrent: Bool {
        edited != nil && editedRecipe == recipe && editedEnhancement == previewEnhancement
    }

    /// Whether a tool can do anything for this photo (faces need a face, background needs a subject).
    func isAvailable(_ tool: EnhanceTool) -> Bool {
        switch tool {
        case .faces: insights.faceCount > 0
        case .background: insights.hasSubject
        case .upscale: UpscaleFactor.double.isAvailable(for: insights.pixelSize)
        default: true
        }
    }

    /// The enhancement as the preview shows it: everything except upscaling.
    private var previewEnhancement: Enhancement {
        var preview = enhancement
        preview.upscale = .none
        return preview
    }

    var canSave: Bool { phase == .editing && saveState != .saving }

    /// Why the original can't be replaced, or nil when it can.
    var replaceUnavailableReason: String? {
        if sourceAssetID == nil { return "This photo isn't from your photo library, so it can only be saved as new." }
        if enhancement.background == .remove { return "Photos with a transparent background are always saved as new." }
        return nil
    }

    var canReplaceOriginal: Bool { replaceUnavailableReason == nil }

    // MARK: - Loading

    /// Opens and analyses a new photo, keeping the current look so it can be applied to a series of
    /// shots. Enhancements are specific to a photo, so they start again.
    /// - Parameter assetIdentifier: the photo's library identifier, so the edit can replace the original.
    func load(_ data: Data, assetIdentifier: String? = nil) async {
        renderTask?.cancel()
        phase = .loading
        saveState = .idle
        enhancement = .none
        sourceAssetID = assetIdentifier
        do {
            insights = try await renderer.load(data)
            original = try await renderer.renderPreview(.neutral)
            let recipe = recipe
            edited = try await renderer.renderPreview(recipe)
            editedRecipe = recipe
            editedEnhancement = previewEnhancement
            phase = .editing
            await refreshThumbnails()
        } catch {
            original = nil
            edited = nil
            editedRecipe = nil
            editedEnhancement = nil
            sourceAssetID = nil
            insights = .empty
            thumbnails = [:]
            phase = .failed(RenderError.unreadableImage.localizedDescription)
        }
    }

    func showLoadFailure() {
        phase = .failed(RenderError.unreadableImage.localizedDescription)
    }

    // MARK: - Editing

    /// Selects a preset at full strength, or the original when `nil`.
    func selectPreset(_ id: String?) {
        guard id != selectedPresetID else { return }
        selectedPresetID = id
        intensity = 1
        scheduleRender()
    }

    func setIntensity(_ value: Double) {
        intensity = value.clamped(to: 0...1)
        scheduleRender()
    }

    func setAdjustment(_ parameter: Parameter, to value: Double) {
        adjustments[parameter] = value
        scheduleRender()
    }

    func resetAdjustments() {
        adjustments = .neutral
        scheduleRender()
    }

    /// Back to the unedited photo.
    func resetAll() {
        selectedPresetID = nil
        intensity = 1
        adjustments = .neutral
        enhancement = .none
        scheduleRender()
    }

    // MARK: - Enhance

    func setEnhancement(_ tool: EnhanceTool, to value: Double) {
        enhancement[tool] = value
        scheduleRender()
    }

    func setBackground(_ mode: Enhancement.Background) {
        guard mode == .keep || insights.hasSubject else { return }
        enhancement.background = mode
        scheduleRender()
    }

    func setUpscale(_ factor: UpscaleFactor) {
        guard factor.isAvailable(for: insights.pixelSize) else { return }
        enhancement.upscale = factor
    }

    /// Sets every tool to what the analysis suggests, leaving the background choice alone.
    func runAutopilot() {
        enhancement = Autopilot.recommend(for: insights, keeping: enhancement)
        scheduleRender()
    }

    func resetEnhancement() {
        enhancement = .none
        scheduleRender()
    }

    /// The size the saved photo will be.
    var outputSize: CGSize { enhancement.upscale.outputSize(for: insights.pixelSize) }

    // MARK: - My Looks

    /// Saves the current look (preset, strength and adjustments combined) as a new preset and selects it.
    func saveLook(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = Preset(
            id: "look-\(UUID().uuidString)",
            name: trimmed.isEmpty ? "My Look \(looks.count + 1)" : trimmed,
            category: Self.myLooksCategory.id,
            recipe: recipe
        )
        looks.append(look)
        lookStore.save(looks)
        selectedPresetID = look.id
        intensity = 1
        adjustments = .neutral
        scheduleRender()
        Task { await refreshThumbnails() }
    }

    func deleteLook(id: String) {
        looks.removeAll { $0.id == id }
        lookStore.save(looks)
        thumbnails[id] = nil
        if selectedPresetID == id {
            selectedPresetID = nil
            intensity = 1
            scheduleRender()
        }
    }

    // MARK: - Saving

    /// Renders the full-resolution photo and adds it to the library as a new photo, or saves it as an
    /// edit of the original.
    func save(to destination: SaveDestination = .newPhoto) async {
        guard canSave, destination == .newPhoto || canReplaceOriginal else { return }
        saveState = .saving
        exportProgress = enhancement.upscale == .none ? nil : 0
        defer { exportProgress = nil }
        do {
            let export = try await renderer.export(recipe, enhancement: enhancement) { progress in
                Task { @MainActor [weak self] in
                    if self?.saveState == .saving { self?.exportProgress = progress }
                }
            }
            if destination == .replaceOriginal, let assetID = sourceAssetID {
                try await saver.replace(assetIdentifier: assetID, with: export.data, uniformType: export.uniformType)
            } else {
                try await saver.save(export.data)
            }
            lastSavedSize = export.pixelSize
            lastSaveDestination = destination
            saveState = .saved
            saveCount += 1
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    func dismissSaveState() {
        if saveState != .saving { saveState = .idle }
    }

    // MARK: - Rendering

    /// Waits for the latest preview render (used by tests).
    func waitForRender() async {
        await renderTask?.value
    }

    /// Renders the latest settings. Any render still waiting is cancelled, and a stale result
    /// that finishes late is ignored, so the preview always matches the controls.
    private func scheduleRender() {
        guard phase == .editing else { return }
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let recipe = recipe
        let enhancement = previewEnhancement
        renderTask = Task {
            do {
                let image = try await renderer.renderPreview(recipe, enhancement: enhancement)
                guard !Task.isCancelled, generation == renderGeneration else { return }
                edited = image
                editedRecipe = recipe
                editedEnhancement = enhancement
                renderFailure = nil
            } catch is CancellationError {
                // A newer render replaced this one.
            } catch {
                guard generation == renderGeneration else { return }
                renderFailure = String(describing: error)
            }
        }
    }

    private func refreshThumbnails() async {
        var recipes = Dictionary(uniqueKeysWithValues: allPresets.map { ($0.id, $0.recipe) })
        recipes[Self.originalID] = .neutral
        if let rendered = try? await renderer.renderThumbnails(recipes) {
            thumbnails = rendered
        }
    }
}
