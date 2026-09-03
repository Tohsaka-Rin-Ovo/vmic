import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var appChromeStore: AppChromeStore

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

    private var shouldShowFloatingDock: Bool {
        guard currentClip != nil else { return false }
        if appChromeStore.isDebugPageVisible {
            return settingsStore.showFloatingDockInDebug
        }

        return true
    }

    var body: some View {
        ZStack(alignment: .leading) {
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
                                withAnimation(.easeInOut(duration: 0.26)) {
                                    isSettingsPresented = true
                                }
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(QuietIconButtonStyle())
                            .accessibilityLabel(settingsStore.text(.settings))
                        }
                    }
                    .vmicOpaqueNavigationBar()
            }

            if isSettingsPresented {
                SettingsDrawer(close: closeSettings)
                    .preferredColorScheme(settingsStore.themeMode.colorScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VmicTheme.drawerBackground.ignoresSafeArea())
                    .transition(.move(edge: .leading))
                    .zIndex(10)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowFloatingDock, let currentClip {
                BottomNowPlayingBar(
                    clip: currentClip,
                    artworkDirectory: libraryStore.artworkDirectory,
                    playbackState: playbackManager.playbackState(for: currentClip.id),
                    progress: playbackManager.playbackProgress(for: currentClip.id),
                    elapsedTime: playbackManager.elapsedTime(for: currentClip.id),
                    duration: playbackManager.duration(for: currentClip.id) ?? currentClip.durationSeconds,
                    togglePlayback: {
                        togglePlayback(currentClip)
                    },
                    stopAction: {
                        playbackManager.stop(currentClip)
                    },
                    previousAction: {
                        skipPlayback(from: currentClip, direction: .previous)
                    },
                    nextAction: {
                        skipPlayback(from: currentClip, direction: .next)
                    },
                    seekAction: { progress in
                        playbackManager.seek(currentClip, toProgress: progress)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .padding(.top, 4)
                .zIndex(20)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { appChromeStore.isPlaybackSettingsPresented },
            set: { appChromeStore.isPlaybackSettingsPresented = $0 }
        )) {
            PlaybackSessionSettingsView(close: {
                appChromeStore.isPlaybackSettingsPresented = false
            })
            .preferredColorScheme(settingsStore.themeMode.colorScheme)
        }
        .task {
            await MainActor.run {
                DiagnosticLogStore.shared.log("根视图首次刷新注入状态", source: .app)
            }
            configurePlaybackFinishHandler()
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
        withAnimation(.easeInOut(duration: 0.24)) {
            isSettingsPresented = false
        }
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

    private func togglePlayback(_ clip: SoundClip) {
        if settingsStore.singlePlayback && playbackManager.playbackState(for: clip.id) == nil {
            playbackManager.stopAll()
        }

        playbackManager.toggle(
            clip,
            from: libraryStore.soundsDirectory,
            volume: settingsStore.inputVolume,
            reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
        )
    }

    private func skipPlayback(from clip: SoundClip, direction: PlaybackSkipDirection) {
        guard let targetClip = adjacentClip(to: clip, direction: direction) else { return }

        if settingsStore.singlePlayback {
            playbackManager.stopAll()
        } else {
            playbackManager.stop(clip)
        }

        playbackManager.setOutputVolume(settingsStore.inputVolume)
        playbackManager.play(
            targetClip,
            from: libraryStore.soundsDirectory,
            reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
        )
    }

    private func adjacentClip(to clip: SoundClip, direction: PlaybackSkipDirection) -> SoundClip? {
        let clips = libraryStore.clips
        guard clips.count > 1, let index = clips.firstIndex(where: { $0.id == clip.id }) else {
            return nil
        }

        switch direction {
        case .previous:
            return clips[index == clips.startIndex ? clips.index(before: clips.endIndex) : clips.index(before: index)]
        case .next:
            let nextIndex = clips.index(after: index)
            return clips[nextIndex == clips.endIndex ? clips.startIndex : nextIndex]
        }
    }

    private func configurePlaybackFinishHandler() {
        playbackManager.playbackDidFinish = { [weak playbackManager, weak libraryStore, weak settingsStore, weak injectionManager] clipID in
            guard
                let playbackManager,
                let libraryStore,
                let settingsStore,
                let injectionManager,
                let finishedClip = libraryStore.clips.first(where: { $0.id == clipID })
            else {
                return
            }

            let completionCount = playbackManager.playbackCompletionCount(for: clipID)
            if settingsStore.playbackLimitMode == .playCount,
               completionCount >= max(settingsStore.playbackLimitCount, 1) {
                DiagnosticLogStore.shared.log(
                    "播放限制达到次数上限",
                    source: .playback,
                    details: [
                        "clipID=\(String(clipID.uuidString.prefix(8)))",
                        "count=\(completionCount)",
                        "limit=\(settingsStore.playbackLimitCount)"
                    ]
                )
                return
            }

            if settingsStore.playbackLimitMode == .minutes,
               let startedAt = playbackManager.playbackStartedAt(for: clipID) {
                let elapsedMinutes = Date().timeIntervalSince(startedAt) / 60
                if elapsedMinutes >= Double(max(settingsStore.playbackLimitMinutes, 1)) {
                    DiagnosticLogStore.shared.log(
                        "播放限制达到时长上限",
                        source: .playback,
                        details: [
                            "clipID=\(String(clipID.uuidString.prefix(8)))",
                            "elapsedMinutes=\(String(format: "%.2f", elapsedMinutes))",
                            "limit=\(settingsStore.playbackLimitMinutes)"
                        ]
                    )
                    return
                }
            }

            let nextClip: SoundClip?
            switch settingsStore.playbackMode {
            case .repeatOne:
                nextClip = finishedClip
            case .ordered:
                nextClip = nextOrderedClip(after: finishedClip, in: libraryStore.clips)
            case .shuffle:
                nextClip = nextShuffledClip(excluding: finishedClip, in: libraryStore.clips)
            }

            guard let nextClip else { return }

            playbackManager.play(
                nextClip,
                from: libraryStore.soundsDirectory,
                reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded,
                resetPlaybackSession: false
            )
        }
    }

    private func nextOrderedClip(after clip: SoundClip, in clips: [SoundClip]) -> SoundClip? {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return nil }
        let nextIndex = clips.index(after: index)
        guard nextIndex < clips.endIndex else { return nil }
        return clips[nextIndex]
    }

    private func nextShuffledClip(excluding clip: SoundClip, in clips: [SoundClip]) -> SoundClip? {
        let candidates = clips.filter { $0.id != clip.id }
        return candidates.randomElement()
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

private enum PlaybackSkipDirection {
    case previous
    case next
}
