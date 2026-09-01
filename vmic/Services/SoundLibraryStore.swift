import Foundation
import UniformTypeIdentifiers

@MainActor
final class SoundLibraryStore: ObservableObject {
    @Published private(set) var clips: [SoundClip] = []
    @Published var lastError: String?

    let soundsDirectory: URL

    private let indexURL: URL
    private let fileManager = FileManager.default

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        soundsDirectory = documents.appendingPathComponent("Sounds", isDirectory: true)
        indexURL = documents.appendingPathComponent("sound-library.json")

        do {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            try load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importFiles(from urls: [URL]) async {
        for sourceURL in urls {
            importFile(from: sourceURL)
        }
        save()
    }

    func delete(_ clip: SoundClip) {
        do {
            try fileManager.removeItem(at: clip.fileURL(in: soundsDirectory))
        } catch {
            lastError = error.localizedDescription
        }

        clips.removeAll { $0.id == clip.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        let selected = offsets.map { clips[$0] }
        selected.forEach(delete)
    }

    private func importFile(from sourceURL: URL) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let originalName = sourceURL.deletingPathExtension().lastPathComponent
            let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
            let destinationName = "\(UUID().uuidString).\(fileExtension)"
            let destinationURL = soundsDirectory.appendingPathComponent(destinationName)

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            clips.append(SoundClip(title: originalName, fileName: destinationName))
            sortClips()
            lastError = nil
        } catch {
            lastError = "Cannot import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            clips = []
            return
        }

        let data = try Data(contentsOf: indexURL)
        clips = try JSONDecoder.vmic.decode([SoundClip].self, from: data)
        sortClips()
    }

    private func save() {
        do {
            let data = try JSONEncoder.vmic.encode(clips)
            try data.write(to: indexURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sortClips() {
        clips.sort {
            $0.createdAt < $1.createdAt
        }
    }
}

private extension JSONDecoder {
    static var vmic: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var vmic: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
