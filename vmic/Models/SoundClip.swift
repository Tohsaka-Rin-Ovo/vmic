import Foundation

struct SoundClip: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, fileName: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.createdAt = createdAt
    }

    func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
