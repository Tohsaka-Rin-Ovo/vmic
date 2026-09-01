import SwiftUI

@main
struct VmicApp: App {
    @StateObject private var injectionManager = MicrophoneInjectionManager()
    @StateObject private var libraryStore = SoundLibraryStore()
    @StateObject private var playbackManager = AudioPlaybackManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(injectionManager)
                .environmentObject(libraryStore)
                .environmentObject(playbackManager)
        }
    }
}
