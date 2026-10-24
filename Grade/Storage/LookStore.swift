import Foundation

/// The looks the user has saved, as JSON in Application Support. Nothing is synced or sent anywhere.
struct LookStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Grade", isDirectory: true)
        }
    }

    private var looksURL: URL { directory.appendingPathComponent("looks.json") }

    func load() -> [Preset] {
        guard let data = try? Data(contentsOf: looksURL) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }

    func save(_ looks: [Preset]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(looks).write(to: looksURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Storage is best-effort; the app still works without saved looks.
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
