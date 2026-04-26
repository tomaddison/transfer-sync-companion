import Foundation

struct FileExtensionWhitelist: Codable {
    var extensions: Set<String>

    static let defaultExtensions: Set<String> = [
        "wav", "aiff", "aif", "mp3", "flac", "m4a", "ogg", "opus", "caf"
    ]

    init(extensions: Set<String> = Self.defaultExtensions) {
        self.extensions = extensions
    }

    func matches(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }

    // MARK: - UserDefaults Persistence

    private static let userDefaultsKey = "fileExtensionWhitelist"

    static func load() -> FileExtensionWhitelist {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let whitelist = try? JSONDecoder().decode(FileExtensionWhitelist.self, from: data) else {
            return FileExtensionWhitelist()
        }
        return whitelist
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    mutating func reset() {
        extensions = Self.defaultExtensions
        save()
    }

    mutating func addExtension(_ ext: String) {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return }
        extensions.insert(normalized)
        save()
    }

    mutating func removeExtension(_ ext: String) {
        extensions.remove(ext.lowercased())
        save()
    }
}
