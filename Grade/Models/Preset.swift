import Foundation

struct PresetCategory: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A named look. Bundled presets come from `Presets.json`; looks the user saves live in `LookStore`.
struct Preset: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var category: String
    var recipe: Recipe
}

/// The bundled presets and their categories.
struct PresetLibrary: Sendable {
    let categories: [PresetCategory]
    let presets: [Preset]

    enum LoadError: Error, CustomStringConvertible {
        case missingResource

        var description: String { "Missing bundled Presets.json" }
    }

    private struct File: Decodable {
        let categories: [PresetCategory]
        let presets: [Preset]
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> PresetLibrary {
        guard let url = bundle.url(forResource: "Presets", withExtension: "json") else { throw LoadError.missingResource }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> PresetLibrary {
        let file = try JSONDecoder().decode(File.self, from: data)
        return PresetLibrary(categories: file.categories, presets: file.presets)
    }

    func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }
}
