import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SoundLibraryStore: ObservableObject {
    @Published private(set) var clips: [SoundClip] = []
    @Published var lastError: String?

    let soundsDirectory: URL
    let artworkDirectory: URL

    private let indexURL: URL
    private let fileManager = FileManager.default

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        soundsDirectory = documents.appendingPathComponent("Sounds", isDirectory: true)
        artworkDirectory = documents.appendingPathComponent("Artwork", isDirectory: true)
        indexURL = documents.appendingPathComponent("sound-library.json")

        do {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
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
        clips.removeAll { $0.id == clip.id }
        updateSortOrder()
        save()
    }

    func rename(_ clip: SoundClip, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }

        clips[index].title = trimmed
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
        updateSortOrder()
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
            let clipID = UUID()
            let destinationName = "\(clipID.uuidString).\(fileExtension)"
            let destinationURL = soundsDirectory.appendingPathComponent(destinationName)

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let metadata = try readMetadata(from: destinationURL)
            clips.append(
                SoundClip(
                    id: clipID,
                    title: metadata.title ?? originalName,
                    artist: metadata.artist,
                    fileName: destinationName,
                    artworkFileName: metadata.artworkFileName,
                    durationSeconds: metadata.durationSeconds,
                    sortOrder: clips.count
                )
            )
            updateSortOrder()
            lastError = nil
        } catch {
            lastError = "无法导入 \(sourceURL.lastPathComponent)：\(error.localizedDescription)"
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
        updateSortOrder()
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
            if let left = $0.sortOrder, let right = $1.sortOrder {
                return left < right
            }

            if $0.sortOrder != nil {
                return true
            }

            if $1.sortOrder != nil {
                return false
            }

            return $0.createdAt < $1.createdAt
        }
    }

    private func updateSortOrder() {
        for index in clips.indices {
            clips[index].sortOrder = index
        }
    }

    private func readMetadata(from url: URL) throws -> ImportedAudioMetadata {
        let asset = AVURLAsset(url: url)
        let commonMetadata = asset.commonMetadata
        let duration = CMTimeGetSeconds(asset.duration)
        let title = firstString(in: commonMetadata, identifier: .commonIdentifierTitle)
        let artist = firstString(in: commonMetadata, identifier: .commonIdentifierArtist)
        let artworkFileName = try saveArtworkIfPresent(from: commonMetadata)

        return ImportedAudioMetadata(
            title: title,
            artist: artist,
            artworkFileName: artworkFileName,
            durationSeconds: duration.isFinite && duration > 0 ? duration : nil
        )
    }

    private func firstString(in metadata: [AVMetadataItem], identifier: AVMetadataIdentifier) -> String? {
        AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
            .compactMap(\.stringValue)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveArtworkIfPresent(from metadata: [AVMetadataItem]) throws -> String? {
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let data = items.compactMap(\.dataValue).first else { return nil }

        let fileExtension = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: artworkDirectory.appendingPathComponent(fileName), options: [.atomic])
        return fileName
    }
}

private struct ImportedAudioMetadata {
    var title: String?
    var artist: String?
    var artworkFileName: String?
    var durationSeconds: Double?
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
