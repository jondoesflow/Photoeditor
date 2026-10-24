import CoreImage
import Foundation
import Testing
@testable import Grade

@MainActor
@Suite("EditorModel: loading, editing, saving and My Looks")
struct EditorModelTests {
    private func makeModel(saver: any PhotoSaving = RecordingSaver(), store: LookStore? = nil) throws -> EditorModel {
        EditorModel(
            library: try PresetLibrary.loadBundled(),
            saver: saver,
            lookStore: store ?? LookStore(directory: temporaryDirectory())
        )
    }

    private func loadedModel(saver: any PhotoSaving = RecordingSaver(), store: LookStore? = nil) async throws -> EditorModel {
        let model = try makeModel(saver: saver, store: store)
        await model.load(try TestImages.demoPhotoData())
        return model
    }

    @Test("Starts empty with nothing to save")
    func startsEmpty() throws {
        let model = try makeModel()
        #expect(model.phase == .empty)
        #expect(!model.canSave)
        #expect(model.recipe.isNeutral)
    }

    @Test("Loading a photo renders a preview, the original and a thumbnail per preset")
    func load() async throws {
        let model = try await loadedModel()
        #expect(model.phase == .editing)
        let preview = try #require(model.edited)
        #expect(max(preview.size.width, preview.size.height) <= PhotoRenderer.previewMaxDimension)
        #expect(model.original != nil)
        #expect(model.thumbnails.count == model.allPresets.count + 1)
        #expect(model.thumbnails[EditorModel.originalID] != nil)
    }

    @Test("Data that isn't an image fails cleanly")
    func badData() async throws {
        let model = try makeModel()
        await model.load(Data("not a photo".utf8))
        guard case .failed = model.phase else {
            Issue.record("Expected failure, got \(model.phase)")
            return
        }
        #expect(model.edited == nil)
        #expect(!model.canSave)
    }

    @Test("Choosing a preset applies it at full strength and re-renders the preview")
    func selectPreset() async throws {
        let model = try await loadedModel()
        let before = try #require(model.edited)
        let preset = try #require(model.library.preset(id: "neon-nights"))
        model.selectPreset(preset.id)
        await model.waitForRender()
        #expect(model.selectedPreset == preset)
        #expect(model.recipe == preset.recipe)
        #expect(model.edited != before)
    }

    @Test("Every preset renders a full-size preview")
    func everyPresetPreviews() async throws {
        let model = try await loadedModel()
        for preset in model.library.presets {
            model.selectPreset(preset.id)
            await model.waitForRender()
            #expect(model.isPreviewCurrent, "\(preset.id) preview didn't render: \(model.renderFailure ?? "no error")")
        }
    }

    @Test("Strength scales the preset; adjustments add on top; reset clears everything")
    func strengthAndAdjustments() async throws {
        let model = try await loadedModel()
        let preset = try #require(model.library.preset(id: "golden-hour"))
        model.selectPreset(preset.id)
        model.setIntensity(0.5)
        #expect(model.recipe == preset.recipe.scaled(by: 0.5))
        model.setAdjustment(.grain, to: 0.4)
        #expect(abs(model.recipe[.grain] - 0.4) < 1e-9)
        model.selectPreset("teal-orange")
        #expect(model.intensity == 1)
        #expect(model.adjustments[.grain] == 0.4)
        model.resetAll()
        #expect(model.recipe.isNeutral)
        #expect(!model.hasEdits)
        #expect(model.selectedPresetID == nil)
    }

    @Test("Opening another photo keeps the current look")
    func lookCarriesOver() async throws {
        let model = try await loadedModel()
        model.selectPreset("noir")
        await model.load(try TestImages.demoPhotoData())
        #expect(model.selectedPresetID == "noir")
        #expect(model.phase == .editing)
    }

    @Test("Saving exports the full-resolution photo with the look applied")
    func save() async throws {
        let saver = RecordingSaver()
        let model = try await loadedModel(saver: saver)
        model.selectPreset("neon-nights")
        await model.save()
        #expect(model.saveState == .saved)
        #expect(model.saveCount == 1)
        let saved = try #require(await saver.saved.first)
        let image = try #require(CIImage(data: saved))
        let original = try #require(CIImage(data: try TestImages.demoPhotoData()))
        #expect(image.extent.size == original.extent.size)
        let software = (image.properties["{TIFF}"] as? [String: Any])?["Software"] as? String
        #expect(software == ExportMetadata.software)
    }

    @Test("A failed save reports why")
    func saveFailure() async throws {
        let model = try await loadedModel(saver: RecordingSaver(shouldFail: true))
        await model.save()
        #expect(model.saveState == .failed(SaveError.notAuthorized.localizedDescription))
        model.dismissSaveState()
        #expect(model.saveState == .idle)
    }

    @Test("Saving a look stores the combined recipe, selects it and survives a relaunch")
    func saveLook() async throws {
        let store = LookStore(directory: temporaryDirectory())
        let model = try await loadedModel(store: store)
        model.selectPreset("warm-film")
        model.setIntensity(0.6)
        model.setAdjustment(.exposure, to: 0.2)
        let expected = model.recipe
        model.saveLook(named: "  Holiday  ")

        let look = try #require(model.looks.first)
        #expect(look.name == "Holiday")
        #expect(look.recipe == expected)
        #expect(model.selectedPresetID == look.id)
        #expect(model.recipe == expected)
        #expect(model.adjustments.isNeutral)
        #expect(model.categories.last == EditorModel.myLooksCategory)
        #expect(model.presets(in: EditorModel.myLooksCategory.id) == [look])

        let relaunched = try makeModel(store: store)
        #expect(relaunched.looks == [look])

        model.deleteLook(id: look.id)
        #expect(model.looks.isEmpty)
        #expect(model.selectedPresetID == nil)
        #expect(store.load().isEmpty)
        #expect(!model.categories.contains(EditorModel.myLooksCategory))
    }

    @Test("An empty look name gets a default")
    func defaultLookName() async throws {
        let model = try await loadedModel()
        model.setAdjustment(.contrast, to: 0.3)
        model.saveLook(named: "   ")
        #expect(model.looks.first?.name == "My Look 1")
    }
}
