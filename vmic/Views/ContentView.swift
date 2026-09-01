import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager

    var body: some View {
        NavigationStack {
            Group {
                switch injectionManager.permissionState {
                case .checking:
                    CheckingView()
                case .unsupportedOS:
                    UnsupportedOSView()
                case .serviceDisabled:
                    SetupGateView(
                        systemImage: "switch.2",
                        title: injectionManager.permissionState.title,
                        message: injectionManager.permissionState.detail,
                        primaryTitle: "Open Add Audio Settings",
                        action: {
                            Task {
                                await injectionManager.openAddAudioInCallsSettings()
                            }
                        }
                    )
                case .undetermined:
                    SetupGateView(
                        systemImage: "mic.badge.plus",
                        title: injectionManager.permissionState.title,
                        message: injectionManager.permissionState.detail,
                        primaryTitle: "Allow vmic",
                        action: {
                            Task {
                                await injectionManager.requestPermission()
                            }
                        }
                    )
                case .denied:
                    SetupGateView(
                        systemImage: "hand.raised",
                        title: injectionManager.permissionState.title,
                        message: injectionManager.permissionState.detail,
                        primaryTitle: "Open Add Audio Settings",
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
            .background(VmicTheme.appBackground)
            .toolbarBackground(.hidden, for: .navigationBar)
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
    }
}
