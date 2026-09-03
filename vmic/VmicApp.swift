import SwiftUI
import UIKit

@main
struct VmicApp: App {
    @StateObject private var injectionManager = MicrophoneInjectionManager()
    @StateObject private var libraryStore = SoundLibraryStore()
    @StateObject private var playbackManager = AudioPlaybackManager()
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var appChromeStore = AppChromeStore()
    @StateObject private var diagnosticLogStore = DiagnosticLogStore.shared

    init() {
        UINavigationBar.configureVmicAppearance()
        Task { @MainActor in
            DiagnosticLogStore.shared.log("应用初始化", source: .app)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(injectionManager)
                .environmentObject(libraryStore)
                .environmentObject(playbackManager)
                .environmentObject(settingsStore)
                .environmentObject(appChromeStore)
                .environmentObject(diagnosticLogStore)
        }
    }
}
