import SwiftUI
import UIKit

struct DebugDiagnosticsView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        List {
            Section {
                DebugStatusRow(title: settingsStore.text(.device), value: UIDevice.current.model)
                DebugStatusRow(title: settingsStore.text(.systemVersion), value: UIDevice.current.systemVersion)
                DebugStatusRow(title: settingsStore.text(.minimumVersion), value: "iOS 18.2")
                DebugStatusRow(
                    title: settingsStore.text(.permissionStateLabel),
                    value: injectionManager.permissionState.title(using: settingsStore)
                )
                DebugStatusRow(
                    title: settingsStore.text(.systemPermission),
                    value: injectionManager.permissionState.canEnableInjection ? settingsStore.text(.available) : settingsStore.text(.unavailable)
                )
                DebugStatusRow(
                    title: settingsStore.text(.injectionChannel),
                    value: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.available) : settingsStore.text(.unavailable)
                )
                DebugStatusRow(
                    title: settingsStore.text(.injectionSwitch),
                    value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled)
                )
                DebugStatusRow(title: settingsStore.text(.lastRefresh), value: format(injectionManager.lastRefreshAt))
                DebugStatusRow(title: settingsStore.text(.lastCallEvent), value: format(injectionManager.lastCapabilitiesChangeAt))
                DebugStatusRow(title: settingsStore.text(.lastInjectionChange), value: format(injectionManager.lastInjectionModeChangeAt))
                DebugStatusRow(title: settingsStore.text(.lastError), value: injectionManager.lastError ?? settingsStore.text(.noError))
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    Task {
                        await injectionManager.refresh()
                    }
                } label: {
                    Label(settingsStore.text(.refreshStatus), systemImage: "arrow.clockwise")
                }

                Button {
                    Task {
                        await injectionManager.requestPermission()
                    }
                } label: {
                    Label(settingsStore.text(.requestPermission), systemImage: "hand.raised")
                }
                .disabled(!injectionManager.permissionState.canRequestPermission)

                Button {
                    Task {
                        await injectionManager.openAddAudioInCallsSettings()
                    }
                } label: {
                    Label(settingsStore.text(.openSystemSwitch), systemImage: "switch.2")
                }

                Button {
                    Task {
                        await injectionManager.setInjectionEnabled(true)
                    }
                } label: {
                    Label(settingsStore.text(.enableInjection), systemImage: "waveform.badge.plus")
                }
                .disabled(!injectionManager.permissionState.canEnableInjection)

                Button(role: .destructive) {
                    Task {
                        await injectionManager.setInjectionEnabled(false)
                    }
                } label: {
                    Label(settingsStore.text(.disableInjection), systemImage: "waveform")
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.appBackground)
        .navigationTitle(settingsStore.text(.debug))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return settingsStore.text(.never)
        }

        return date.formatted(date: .omitted, time: .standard)
    }
}

private struct DebugStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }
}
