import SwiftUI

@main
struct GradeApp: App {
    @State private var model = AppEnvironment.makeModel()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await AppEnvironment.loadDemoPhotoIfNeeded(into: model) }
        }
    }
}

/// Builds the model from bundled config, honouring launch arguments used by UI tests:
/// `-GradeDemo` (opens the bundled demo photo; saves go to memory, not Photos),
/// `-GradeEmpty` (with `-GradeDemo`, starts with no photo) and `-GradePreset <id>` (starts with that preset).
@MainActor
enum AppEnvironment {
    static func makeModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> EditorModel {
        let library: PresetLibrary
        do {
            library = try PresetLibrary.loadBundled()
        } catch {
            fatalError("Grade could not load its bundled presets: \(error)")
        }

        guard arguments.contains("-GradeDemo") else {
            return EditorModel(library: library, saver: PhotoLibrarySaver(), lookStore: LookStore())
        }
        let store = LookStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("GradeDemo", isDirectory: true))
        store.removeAll()
        return EditorModel(library: library, saver: DemoSaver(), lookStore: store)
    }

    static func loadDemoPhotoIfNeeded(into model: EditorModel, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard arguments.contains("-GradeDemo"), !arguments.contains("-GradeEmpty"),
              let url = Bundle.main.url(forResource: "DemoPhoto", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return }
        await model.load(data)
        if let index = arguments.firstIndex(of: "-GradePreset"), arguments.indices.contains(index + 1) {
            model.selectPreset(arguments[index + 1])
        }
    }
}
