import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            rootContent
                .background(VmicTheme.appBackground)
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
            await injectionManager.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await injectionManager.refresh()
            }
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
}
