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

    // MARK: - Enhance

    private func portraitData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "DemoPortrait", withExtension: "jpg"))
        return try Data(contentsOf: url)
    }

    @Test("Opening a portrait analyses it; Autopilot turns on face enhancement")
    func autopilotOnPortrait() async throws {
        let model = try makeModel()
        await model.load(try portraitData())
        #expect(model.insights.faceCount >= 1)
        #expect(model.isAvailable(.faces))
        model.runAutopilot()
        await model.waitForRender()
        #expect(model.enhancement.faces > 0)
        #expect(model.enhancement.light > 0)
        #expect(model.hasEdits)
        #expect(model.isPreviewCurrent, "\(model.renderFailure ?? "no error")")
    }

    @Test("Enhancements re-render the preview and reset for the next photo")
    func enhancementLifecycle() async throws {
        let model = try await loadedModel()
        let before = try #require(model.edited)
        model.setEnhancement(.detail, to: 0.8)
        await model.waitForRender()
        #expect(model.isPreviewCurrent)
        #expect(model.edited != before)
        #expect(model.enhancement.isActive(.detail))
        await model.load(try TestImages.demoPhotoData())
        #expect(model.enhancement == .none)
    }

    @Test("Faces and background are unavailable without a face or subject")
    func availability() async throws {
        let model = try makeModel()
        await model.load(TestImages.jpegData())
        #expect(!model.isAvailable(.faces))
        #expect(!model.isAvailable(.background))
        model.setBackground(.remove)
        #expect(model.enhancement.background == .keep)
    }

    @Test("Upscaling 2× saves a photo twice the size, with progress along the way")
    func upscaledSave() async throws {
        let saver = RecordingSaver()
        let model = try makeModel(saver: saver)
        await model.load(TestImages.jpegData(size: CGSize(width: 120, height: 80)))
        model.setUpscale(.double)
        #expect(model.outputSize == CGSize(width: 240, height: 160))
        await model.save()
        #expect(model.saveState == .saved, "\(model.saveState)")
        #expect(model.lastSavedSize == CGSize(width: 240, height: 160))
        #expect(model.exportProgress == nil)
        let saved = try #require(await saver.saved.first)
        #expect(try #require(CIImage(data: saved)).extent.size == CGSize(width: 240, height: 160))
    }

    @Test("Upscaling is refused when the result would be too large")
    func upscaleRefused() async throws {
        let model = try await loadedModel()
        // The demo photo is 2000 × 1333: 2× fits in 48 MP, 4× doesn't.
        model.setUpscale(.quadruple)
        #expect(model.enhancement.upscale == .none)
        model.setUpscale(.double)
        #expect(model.enhancement.upscale == .double)
    }

    @Test("Removing the background saves a transparent PNG")
    func transparentSave() async throws {
        let saver = RecordingSaver()
        let model = try makeModel(saver: saver)
        await model.load(try portraitData())
        withKnownIssue("Subject masks may be unavailable on the simulator", isIntermittent: true) {
            try #require(model.insights.hasSubject)
        }
        guard model.insights.hasSubject else { return }
        model.setBackground(.remove)
        await model.waitForRender()
        #expect(model.isPreviewCurrent, "\(model.renderFailure ?? "no error")")
        await model.save()
        let saved = try #require(await saver.saved.first)
        // PNG signature.
        #expect(Array(saved.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        let bitmap = TestImages.bitmap(try #require(CIImage(data: saved)).transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1)))
        #expect(bitmap.alpha(x: 2, y: 2) < 0.5, "a corner of the portrait should be background")
    }
}
