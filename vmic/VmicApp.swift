import SwiftUI
import UIKit

@main
struct VmicApp: App {
    @StateObject private var injectionManager = MicrophoneInjectionManager()
    @StateObject private var libraryStore = SoundLibraryStore()
    @StateObject private var playbackManager = AudioPlaybackManager()
    @StateObject private var settingsStore = AppSettingsStore()

    init() {
        UINavigationBar.configureVmicAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(injectionManager)
                .environmentObject(libraryStore)
                .environmentObject(playbackManager)
                .environmentObject(settingsStore)
        }
    }
}
