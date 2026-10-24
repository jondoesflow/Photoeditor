import Foundation
import Observation

/// Editor state: the loaded photo, the chosen look, manual adjustments and saving.
/// The current look is always `preset × intensity + adjustments`; the original is never changed.
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

    nonisolated static let myLooksCategory = PresetCategory(id: "mine", name: "My Looks")
    /// Thumbnail key for the unedited photo.
    nonisolated static let originalID = "original"

    let library: PresetLibrary
    private(set) var looks: [Preset]
    private(set) var phase: Phase = .empty
    private(set) var original: RenderedImage?
    private(set) var edited: RenderedImage?
    private(set) var thumbnails: [String: RenderedImage] = [:]
    private(set) var selectedPresetID: String?
    private(set) var intensity: Double = 1
    private(set) var adjustments = Recipe.neutral
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

    var hasEdits: Bool { !recipe.isNeutral }

    var canSave: Bool { phase == .editing && saveState != .saving }

    // MARK: - Loading

    /// Opens a new photo, keeping the current look so it can be applied to a series of shots.
    func load(_ data: Data) async {
        renderTask?.cancel()
        phase = .loading
        saveState = .idle
        do {
            try await renderer.load(data)
            original = try await renderer.renderPreview(.neutral)
            edited = try await renderer.renderPreview(recipe)
            phase = .editing
            await refreshThumbnails()
        } catch {
            original = nil
            edited = nil
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
        scheduleRender()
    }

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

    /// Renders the full-resolution photo and adds it to the camera roll as a new photo.
    func save() async {
        guard canSave else { return }
        saveState = .saving
        do {
            let data = try await renderer.export(recipe)
            try await saver.save(data)
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
        renderTask = Task {
            guard let image = try? await renderer.renderPreview(recipe),
                  !Task.isCancelled, generation == renderGeneration else { return }
            edited = image
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
