import Foundation
import Combine

enum DiagnosticLogSource: String, Equatable {
    case app = "app"
    case injection = "injection"
    case playback = "playback"
    case speechProbe = "speech-probe"
    case monitorExperiment = "monitor-experiment"
    case floatingWindow = "floating-window"
    case library = "library"
}

struct DiagnosticLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let source: DiagnosticLogSource
    let message: String

    var timeText: String {
        timestamp.formatted(date: .omitted, time: .standard)
    }

    var exportLine: String {
        "[\(timestamp.formatted(date: .numeric, time: .standard))][\(source.rawValue)] \(message)"
    }
}

@MainActor
final class DiagnosticLogStore: ObservableObject {
    static let shared = DiagnosticLogStore()

    @Published private(set) var entries: [DiagnosticLogEntry] = []

    private let maximumEntries = 120

    private init() {}

    func log(
        _ message: String,
        source: DiagnosticLogSource,
        details: [String] = []
    ) {
        let detailText = details.isEmpty ? "" : " | \(details.joined(separator: " | "))"
        let entry = DiagnosticLogEntry(
            timestamp: Date(),
            source: source,
            message: "\(message)\(detailText)"
        )

        entries.append(entry)

        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }

        print("[vmic][\(entry.source.rawValue)] \(entry.message)")
    }

    func exportText() -> String {
        guard !entries.isEmpty else {
            return "vmic diagnostic log: empty"
        }

        return entries
            .map(\.exportLine)
            .joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
        print("[vmic][log] cleared")
    }
}
