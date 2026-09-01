import Foundation

struct SoundClip: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String?
    var fileName: String
    var artworkFileName: String?
    var durationSeconds: Double?
    var createdAt: Date
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        fileName: String,
        artworkFileName: String? = nil,
        durationSeconds: Double? = nil,
        createdAt: Date = Date(),
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileName = fileName
        self.artworkFileName = artworkFileName
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func artworkURL(in directory: URL) -> URL? {
        artworkFileName.map {
            directory.appendingPathComponent($0)
        }
    }
}
