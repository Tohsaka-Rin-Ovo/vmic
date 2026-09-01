import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                Group {
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
                .disabled(isSettingsPresented)
                .blur(radius: isSettingsPresented ? 2 : 0)

                if isSettingsPresented {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSettingsPresented = false
                            }
                        }

                    GeometryReader { proxy in
                        SettingsDrawer {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSettingsPresented = false
                            }
                        }
                        .frame(width: max(260, proxy.size.width * 0.52))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .vertical)
                }
            }
            .background(VmicTheme.appBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSettingsPresented = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(QuietIconButtonStyle())
                    .accessibilityLabel(settingsStore.text(.settings))
                }
            }
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
        .preferredColorScheme(settingsStore.themeMode.colorScheme)
    }
}
