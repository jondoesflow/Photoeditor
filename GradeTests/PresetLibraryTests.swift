import Foundation
import Testing
@testable import Grade

@Suite("Presets.json")
struct PresetLibraryTests {
    private let library: PresetLibrary

    init() throws {
        library = try PresetLibrary.loadBundled()
    }

    @Test("Loads at least 20 presets in 5 categories")
    func counts() {
        #expect(library.presets.count >= 20)
        #expect(library.categories.count >= 5)
    }

    @Test("IDs and names are unique, and none clash with reserved IDs")
    func uniqueness() {
        let ids = library.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(library.presets.map(\.name)).count == library.presets.count)
        #expect(!ids.contains(EditorModel.originalID))
        #expect(!ids.contains { $0.hasPrefix("look-") })
        #expect(!library.categories.map(\.id).contains(EditorModel.myLooksCategory.id))
    }

    @Test("Every preset is in a known category and every category has presets")
    func categories() {
        let categoryIDs = Set(library.categories.map(\.id))
        for preset in library.presets {
            #expect(categoryIDs.contains(preset.category), "\(preset.id) has unknown category \(preset.category)")
        }
        for category in library.categories {
            #expect(library.presets.contains { $0.category == category.id }, "\(category.id) is empty")
        }
    }

    @Test("Every preset changes the photo and its tones are valid")
    func recipes() {
        for preset in library.presets {
            #expect(!preset.recipe.isNeutral, "\(preset.id) does nothing")
            for tone in [preset.recipe.shadowTone, preset.recipe.highlightTone].compactMap({ $0 }) {
                #expect(tone.rgb != nil, "\(preset.id) has a bad colour \(tone.color)")
                #expect((0...1).contains(tone.strength), "\(preset.id) tone strength out of range")
            }
        }
    }

    @Test("Neon Nights is a dark, cool night look with glow")
    func neonNights() throws {
        let preset = try #require(library.preset(id: "neon-nights"))
        #expect(preset.recipe[.exposure] < 0)
        #expect(preset.recipe[.warmth] < 0)
        #expect(preset.recipe[.skyDarken] > 0)
        #expect(preset.recipe[.glow] > 0)
    }

    @Test("Black & white presets remove all colour")
    func mono() {
        for preset in library.presets where preset.category == "mono" {
            #expect(preset.recipe[.saturation] == -1, "\(preset.id) isn't monochrome")
        }
    }
}
