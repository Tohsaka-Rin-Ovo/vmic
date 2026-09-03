import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @StateObject private var floatingWindowManager = FloatingNowPlayingWindowManager()
    @State private var isSettingsPresented = false

    private var currentClip: SoundClip? {
        if let currentClipID = playbackManager.currentClipID,
           let clip = libraryStore.clips.first(where: { $0.id == currentClipID }) {
            return clip
        }

        return libraryStore.clips.first {
            playbackManager.activeClipIDs.contains($0.id)
        }
    }

    private var currentPlaybackState: SoundPlaybackState? {
        guard let currentClip else { return nil }
        return playbackManager.playbackState(for: currentClip.id)
    }

    var body: some View {
        NavigationStack {
            rootContent
                .background(VmicTheme.appBackground)
                .overlay(alignment: .topLeading) {
                    FloatingNowPlayingHostView(manager: floatingWindowManager)
                        .frame(width: 96, height: 96)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(QuietIconButtonStyle())
                        .accessibilityLabel(settingsStore.text(.settings))
                    }
                }
                .vmicOpaqueNavigationBar()
        }
        .task {
            await MainActor.run {
                DiagnosticLogStore.shared.log("根视图首次刷新注入状态", source: .app)
            }
            await injectionManager.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                DiagnosticLogStore.shared.log(
                    "场景状态变化",
                    source: .app,
                    details: ["phase=\(scenePhaseDescription(newPhase))"]
                )
                guard newPhase == .active else { return }

                DiagnosticLogStore.shared.log("App 回到前台，刷新注入状态", source: .app)
                await injectionManager.refresh()
            }
            syncFloatingWindow(for: newPhase)
        }
        .onChange(of: settingsStore.floatingWindowEnabled) { _, _ in
            syncFloatingWindow(for: scenePhase)
        }
        .onChange(of: playbackManager.currentClipID) { _, _ in
            syncFloatingWindow(for: scenePhase)
        }
        .onChange(of: playbackManager.activeClipIDs) { _, _ in
            syncFloatingWindow(for: scenePhase)
        }
        .onChange(of: playbackManager.pausedClipIDs) { _, _ in
            syncFloatingWindow(for: scenePhase)
        }
        .onChange(of: libraryStore.clips) { _, _ in
            syncFloatingWindow(for: scenePhase)
        }
        .preferredColorScheme(settingsStore.themeMode.colorScheme)
        .fullScreenCover(isPresented: $isSettingsPresented) {
            SettingsDrawer(close: closeSettings)
                .preferredColorScheme(settingsStore.themeMode.colorScheme)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch injectionManager.permissionState {
        case .checking:
            CheckingView()
        case .unsupportedOS:
            UnsupportedOSView()
        case .serviceDisabled:
            SetupGateView(
                systemImage: "switch.2",
                title: injectionManager.permissionState.title(using: settingsStore),
                message: injectionManager.permissionState.detail(using: settingsStore),
                primaryTitle: settingsStore.text(.openAddAudioSettings),
                action: {
                    Task {
                        await injectionManager.openAddAudioInCallsSettings()
                    }
                }
            )
        case .undetermined:
            SetupGateView(
                systemImage: "mic.badge.plus",
                title: injectionManager.permissionState.title(using: settingsStore),
                message: injectionManager.permissionState.detail(using: settingsStore),
                primaryTitle: settingsStore.text(.allowVmic),
                action: {
                    Task {
                        await injectionManager.requestPermission()
                    }
                }
            )
        case .denied:
            SetupGateView(
                systemImage: "hand.raised",
                title: injectionManager.permissionState.title(using: settingsStore),
                message: injectionManager.permissionState.detail(using: settingsStore),
                primaryTitle: settingsStore.text(.openAddAudioSettings),
                action: {
                    Task {
                        await injectionManager.openAddAudioInCallsSettings()
                    }
                }
            )
        case .granted, .unknown:
            SoundboardView()
        }
    }

    private func closeSettings() {
        isSettingsPresented = false
    }

    private func syncFloatingWindow(for phase: ScenePhase) {
        floatingWindowManager.sync(
            isForeground: phase == .active,
            isEnabled: settingsStore.floatingWindowEnabled,
            clip: currentClip,
            artworkDirectory: libraryStore.artworkDirectory,
            playbackState: currentPlaybackState
        )
    }

    private func scenePhaseDescription(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
