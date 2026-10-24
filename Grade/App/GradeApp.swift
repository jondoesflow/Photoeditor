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
/// `-GradeEmpty` (with `-GradeDemo`, starts with no photo), `-GradePreset <id>` (starts with that preset)
/// and `-GradeDemoPhoto portrait` (opens the demo portrait instead of the car).
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
              let url = Bundle.main.url(forResource: demoPhotoName(arguments), withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return }
        // Choose the preset first so the photo opens with it already applied.
        if let index = arguments.firstIndex(of: "-GradePreset"), arguments.indices.contains(index + 1) {
            model.selectPreset(arguments[index + 1])
        }
        // A stand-in library identifier, so Replace Original can be exercised; DemoSaver keeps it in memory.
        await model.load(data, assetIdentifier: "demo-asset")
    }

    private static func demoPhotoName(_ arguments: [String]) -> String {
        guard let index = arguments.firstIndex(of: "-GradeDemoPhoto"), arguments.indices.contains(index + 1),
              arguments[index + 1] == "portrait" else { return "DemoPhoto" }
        return "DemoPortrait"
    }
}
