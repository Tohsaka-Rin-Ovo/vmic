import AVFoundation
import Foundation
import SwiftUI
import UIKit
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
            refreshMissingMetadataIfNeeded()
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

    private func readMetadata(from url: URL, saveArtwork: Bool = true) throws -> ImportedAudioMetadata {
        let asset = AVURLAsset(url: url)
        let metadata = allMetadata(from: asset)
        let duration = durationSeconds(from: asset, url: url)
        let title = firstString(
            in: metadata,
            identifier: .commonIdentifierTitle,
            fallbackTokens: ["title", "tit2", "©nam", "name"]
        )
        let artist = firstString(
            in: metadata,
            identifier: .commonIdentifierArtist,
            fallbackTokens: ["artist", "tpe1", "©art", "performer", "author"]
        )
        let artworkFileName = saveArtwork ? try saveArtworkIfPresent(from: metadata) : nil

        return ImportedAudioMetadata(
            title: title,
            artist: artist,
            artworkFileName: artworkFileName,
            durationSeconds: duration
        )
    }

    private func refreshMissingMetadataIfNeeded() {
        var didUpdate = false

        for index in clips.indices {
            let clip = clips[index]
            let needsDuration = clip.durationSeconds == nil
            let needsArtwork = clip.artworkFileName == nil
            let needsArtist = clip.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false

            guard needsDuration || needsArtwork || needsArtist else { continue }

            do {
                let metadata = try readMetadata(from: clip.fileURL(in: soundsDirectory), saveArtwork: needsArtwork)

                if needsDuration, let durationSeconds = metadata.durationSeconds {
                    clips[index].durationSeconds = durationSeconds
                    didUpdate = true
                }

                if needsArtwork, let artworkFileName = metadata.artworkFileName {
                    clips[index].artworkFileName = artworkFileName
                    didUpdate = true
                }

                if needsArtist, let artist = metadata.artist {
                    clips[index].artist = artist
                    didUpdate = true
                }
            } catch {}
        }

        if didUpdate {
            save()
        }
    }

    private func allMetadata(from asset: AVURLAsset) -> [AVMetadataItem] {
        var metadata = asset.commonMetadata

        for format in asset.availableMetadataFormats {
            metadata.append(contentsOf: asset.metadata(forFormat: format))
        }

        return metadata
    }

    private func durationSeconds(from asset: AVURLAsset, url: URL) -> Double? {
        let assetDuration = CMTimeGetSeconds(asset.duration)
        if assetDuration.isFinite, assetDuration > 0 {
            return assetDuration
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let processingSampleRate = audioFile.processingFormat.sampleRate
            let fileSampleRate = audioFile.fileFormat.sampleRate
            let sampleRate = processingSampleRate > 0 ? processingSampleRate : fileSampleRate
            guard sampleRate > 0 else { return nil }
            return Double(audioFile.length) / sampleRate
        } catch {
            return nil
        }
    }

    private func firstString(
        in metadata: [AVMetadataItem],
        identifier: AVMetadataIdentifier,
        fallbackTokens: [String]
    ) -> String? {
        let directMatch = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
            .compactMap { normalizedString($0.stringValue) }
            .first

        if let directMatch {
            return directMatch
        }

        return metadata
            .filter { metadataItem($0, matchesAny: fallbackTokens) }
            .compactMap { normalizedString($0.stringValue) }
            .first
    }

    private func saveArtworkIfPresent(from metadata: [AVMetadataItem]) throws -> String? {
        for item in metadata where isArtworkItem(item) {
            if let data = artworkData(from: item) {
                return try saveArtworkData(data)
            }
        }

        return nil
    }

    private func isArtworkItem(_ item: AVMetadataItem) -> Bool {
        item.identifier == .commonIdentifierArtwork
            || metadataItem(item, matchesAny: ["artwork", "cover", "covr", "apic", "pic"])
    }

    private func artworkData(from item: AVMetadataItem) -> Data? {
        if let data = item.dataValue {
            return data
        }

        if let data = item.value as? Data {
            return data
        }

        if let values = item.value as? NSDictionary {
            return values.allValues.compactMap { $0 as? Data }.first
        }

        if let image = item.value as? UIImage {
            return image.pngData()
        }

        return nil
    }

    private func saveArtworkData(_ data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }
        let fileExtension = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: artworkDirectory.appendingPathComponent(fileName), options: [.atomic])
        return fileName
    }

    private func metadataItem(_ item: AVMetadataItem, matchesAny tokens: [String]) -> Bool {
        let descriptor = metadataDescriptor(for: item)
        return tokens.contains { descriptor.contains($0.lowercased()) }
    }

    private func metadataDescriptor(for item: AVMetadataItem) -> String {
        [
            item.identifier?.rawValue,
            item.commonKey?.rawValue,
            item.keySpace?.rawValue,
            item.key.map { "\($0)" }
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func normalizedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
