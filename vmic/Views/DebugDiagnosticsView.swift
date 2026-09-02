import SwiftUI
import UIKit

struct DebugDiagnosticsView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var runningAction: DiagnosticAction?
    @State private var didCopyDiagnostics = false

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
                Text(settingsStore.text(.audioSessionDiagnostics))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)

                ChannelVerdictBanner(diagnostics: injectionManager.audioSessionDiagnostics)
                    .padding(.vertical, 5)

                DebugStatusRow(
                    title: settingsStore.text(.directChannelCheck),
                    value: boolValue(injectionManager.audioSessionDiagnostics.microphoneInjectionAvailable)
                )
                DebugStatusRow(
                    title: settingsStore.text(.notificationChannel),
                    value: boolValue(injectionManager.lastNotifiedInjectionAvailability)
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentCategory),
                    value: injectionManager.audioSessionDiagnostics.category
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentMode),
                    value: injectionManager.audioSessionDiagnostics.mode
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentInputPorts),
                    value: listValue(injectionManager.audioSessionDiagnostics.inputPortTypes)
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentOutputPorts),
                    value: listValue(injectionManager.audioSessionDiagnostics.outputPortTypes)
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentInputDevices),
                    value: listValue(injectionManager.audioSessionDiagnostics.inputPortNames)
                )
                DebugStatusRow(
                    title: settingsStore.text(.currentOutputDevices),
                    value: listValue(injectionManager.audioSessionDiagnostics.outputPortNames)
                )
                DebugStatusRow(
                    title: settingsStore.text(.sampleRate),
                    value: formatSampleRate(injectionManager.audioSessionDiagnostics.sampleRate)
                )
                DebugStatusRow(
                    title: settingsStore.text(.inputChannels),
                    value: "\(injectionManager.audioSessionDiagnostics.inputChannelCount)"
                )
                DebugStatusRow(
                    title: settingsStore.text(.outputChannels),
                    value: "\(injectionManager.audioSessionDiagnostics.outputChannelCount)"
                )
                DebugStatusRow(
                    title: settingsStore.text(.lastRouteChange),
                    value: format(injectionManager.audioSessionDiagnostics.lastRouteChangeAt)
                )
                DebugStatusRow(
                    title: settingsStore.text(.routeChangeReason),
                    value: injectionManager.audioSessionDiagnostics.lastRouteChangeReason ?? settingsStore.text(.emptyRoute)
                )

                Text(settingsStore.text(.audioSessionDiagnosticsNote))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(settingsStore.text(.latestInjectionResult))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk)

                    if let result = injectionManager.lastModeChangeResult {
                        InjectionModeResultBanner(result: result, timestamp: injectionManager.lastModeChangeResultAt)
                    } else {
                        Text(settingsStore.text(.noInjectionResult))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VmicTheme.ink)
                    }
                }
                .padding(.vertical, 5)
            }
            .listRowBackground(Color.clear)

            Section {
                Text(settingsStore.text(.enableInjectionHelp))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    run(.refresh) {
                        await injectionManager.refresh(printDiagnostics: true)
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.refreshStatus),
                        systemImage: "arrow.clockwise",
                        isRunning: runningAction == .refresh
                    )
                }
                .disabled(runningAction != nil)

                Button {
                    injectionManager.copyAudioSessionDiagnosticsToPasteboard()
                    didCopyDiagnostics = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await MainActor.run {
                            didCopyDiagnostics = false
                        }
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: didCopyDiagnostics ? settingsStore.text(.copiedChannelDiagnostics) : settingsStore.text(.copyChannelDiagnostics),
                        systemImage: didCopyDiagnostics ? "checkmark" : "doc.on.doc",
                        isRunning: false
                    )
                }
                .disabled(runningAction != nil)

                Button {
                    run(.requestPermission) {
                        await injectionManager.requestPermission()
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.requestPermission),
                        systemImage: "hand.raised",
                        isRunning: runningAction == .requestPermission
                    )
                }
                .disabled(runningAction != nil || !injectionManager.permissionState.canRequestPermission)

                Button {
                    run(.openSettings) {
                        await injectionManager.openAddAudioInCallsSettings()
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.openSystemSwitch),
                        systemImage: "switch.2",
                        isRunning: runningAction == .openSettings
                    )
                }
                .disabled(runningAction != nil)

                Button {
                    run(.enableInjection) {
                        await injectionManager.setInjectionEnabled(true)
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: runningAction == .enableInjection ? settingsStore.text(.turningOnInjection) : settingsStore.text(.enableInjection),
                        systemImage: "waveform.badge.plus",
                        isRunning: runningAction == .enableInjection
                    )
                }
                .disabled(runningAction != nil || injectionManager.isChangingInjectionMode || !injectionManager.permissionState.canEnableInjection)

                Button(role: .destructive) {
                    run(.disableInjection) {
                        await injectionManager.setInjectionEnabled(false)
                    }
                } label: {
                    DiagnosticActionLabel(
                        title: runningAction == .disableInjection ? settingsStore.text(.turningOffInjection) : settingsStore.text(.disableInjection),
                        systemImage: "waveform",
                        isRunning: runningAction == .disableInjection
                    )
                }
                .disabled(runningAction != nil || injectionManager.isChangingInjectionMode || !injectionManager.isInjectionEnabled)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VmicTheme.appBackground)
        .navigationTitle(settingsStore.text(.debug))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return settingsStore.text(.never)
        }

        return date.formatted(date: .omitted, time: .standard)
    }

    private func boolValue(_ value: Bool?) -> String {
        guard let value else {
            return settingsStore.text(.notSupported)
        }

        return value ? settingsStore.text(.available) : settingsStore.text(.unavailable)
    }

    private func listValue(_ values: [String]) -> String {
        values.isEmpty ? settingsStore.text(.emptyRoute) : values.joined(separator: ", ")
    }

    private func formatSampleRate(_ value: Double) -> String {
        guard value.isFinite, value > 0 else {
            return settingsStore.text(.emptyRoute)
        }

        return "\(Int(value.rounded())) Hz"
    }

    private func run(_ action: DiagnosticAction, operation: @escaping () async -> Void) {
        guard runningAction == nil else { return }

        runningAction = action
        Task {
            await operation()
            await MainActor.run {
                runningAction = nil
            }
        }
    }
}

private struct ChannelVerdictBanner: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let diagnostics: AudioSessionDiagnostics

    private var tint: Color {
        switch diagnostics.microphoneInjectionAvailable {
        case .some(true):
            return VmicTheme.mint
        case .some(false):
            return Color(red: 0.88, green: 0.58, blue: 0.12)
        case nil:
            return VmicTheme.mutedInk
        }
    }

    private var systemImage: String {
        switch diagnostics.microphoneInjectionAvailable {
        case .some(true):
            return "checkmark.circle.fill"
        case .some(false):
            return "exclamationmark.circle.fill"
        case nil:
            return "questionmark.circle"
        }
    }

    private var detail: String {
        switch diagnostics.microphoneInjectionAvailable {
        case .some(true):
            return settingsStore.text(.channelVerdictAvailable)
        case .some(false):
            return settingsStore.text(.channelVerdictUnavailable)
        case nil:
            return settingsStore.text(.channelVerdictUnsupported)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(settingsStore.text(.channelVerdict))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(diagnostics.capturedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk.opacity(0.82))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum DiagnosticAction: Equatable {
    case refresh
    case requestPermission
    case openSettings
    case enableInjection
    case disableInjection
}

private struct DiagnosticActionLabel: View {
    let title: String
    let systemImage: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)

            Spacer(minLength: 8)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(VmicTheme.ink)
        .padding(.vertical, 4)
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

struct InjectionModeResultBanner: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let result: InjectionModeChangeResult
    let timestamp: Date?

    private var tint: Color {
        switch result {
        case .enabled(let channelAvailable):
            return channelAvailable ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
        case .disabled:
            return VmicTheme.blue
        case .unsupportedOS, .permissionRequired, .busy:
            return Color(red: 0.88, green: 0.58, blue: 0.12)
        case .failed:
            return Color(red: 0.82, green: 0.20, blue: 0.18)
        }
    }

    private var systemImage: String {
        switch result {
        case .enabled(let channelAvailable):
            return channelAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        case .disabled:
            return "waveform"
        case .unsupportedOS, .permissionRequired, .busy:
            return "exclamationmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let timestamp {
                    Text(timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk.opacity(0.82))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        switch result {
        case .enabled(let channelAvailable):
            return settingsStore.text(channelAvailable ? .actionSucceeded : .actionNeedsAttention)
        case .disabled:
            return settingsStore.text(.actionSucceeded)
        case .unsupportedOS, .permissionRequired, .busy:
            return settingsStore.text(.actionNeedsAttention)
        case .failed:
            return settingsStore.text(.actionFailed)
        }
    }

    private var detail: String {
        switch result {
        case .unsupportedOS(let version):
            return settingsStore.text(.actionUnsupportedOS(version))
        case .permissionRequired(let state):
            return settingsStore.text(permissionDetail(for: state))
        case .enabled(let channelAvailable):
            return settingsStore.text(channelAvailable ? .actionEnableSucceeded : .actionEnableNoChannel)
        case .disabled:
            return settingsStore.text(.actionDisableSucceeded)
        case .busy:
            return settingsStore.text(.actionModeChangeBusy)
        case .failed(let message):
            return settingsStore.text(.actionModeChangeFailed(message))
        }
    }

    private func permissionDetail(for state: InjectionPermissionState) -> VmicText {
        switch state {
        case .unsupportedOS(let version):
            return .actionUnsupportedOS(version)
        case .serviceDisabled:
            return .actionServiceDisabled
        case .denied:
            return .actionPermissionDenied
        case .unknown:
            return .actionPermissionUnknown
        case .checking, .undetermined, .granted:
            return .actionPermissionRequired
        }
    }
}
