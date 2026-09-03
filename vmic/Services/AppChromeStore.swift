import SwiftUI

enum FloatingDockPresentation: String, CaseIterable, Identifiable {
    case expanded
    case compact

    var id: String {
        rawValue
    }
}

@MainActor
final class AppChromeStore: ObservableObject {
    @Published var isDebugPageVisible = false
    @Published var floatingDockPresentation: FloatingDockPresentation = .expanded
    @Published var floatingDockOffset: CGSize = .zero
    @Published var isPlaybackSettingsPresented = false
}
