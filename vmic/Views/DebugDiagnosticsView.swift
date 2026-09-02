import SwiftUI
import UIKit

enum DebugFocusTarget: Hashable {
    case permission
    case channel
    case injectionSwitch
}

struct DebugDiagnosticsView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let initialFocus: DebugFocusTarget?

    @State private var runningAction: DiagnosticAction?
    @State private var didCopyDiagnostics = false
    @State private var highlightedFocus: DebugFocusTarget?

    init(initialFocus: DebugFocusTarget? = nil) {
        self.initialFocus = initialFocus
    }

    private var diagnosticText: String {
        if injectionManager.isInjectionAvailableInCurrentCall && injectionManager.isInjectionEnabled {
            return settingsStore.text(.diagnosticReady)
        }

        if injectionManager.isInjectionAvailableInCurrentCall {
            return settingsStore.text(.diagnosticEnableSwitch)
        }

        if injectionManager.isInjectionEnabled {
            return settingsStore.text(.diagnosticNotCompatible)
        }

        return settingsStore.text(.diagnosticWaitingForCall)
    }

    private var overviewTint: Color {
        if injectionManager.isInjectionAvailableInCurrentCall && injectionManager.isInjectionEnabled {
            return VmicTheme.mint
        }

        if injectionManager.isInjectionAvailableInCurrentCall || injectionManager.isInjectionEnabled {
            return VmicTheme.blue
        }

        return VmicTheme.mutedInk
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    DebugOverviewCard(diagnosticText: diagnosticText, tint: overviewTint)

                    DebugPermissionCard(
                        isHighlighted: highlightedFocus == .permission,
                        runningAction: runningAction,
                        run: { action, operation in
                            run(action, operation: operation)
                        }
                    )
                    .id(DebugFocusTarget.permission)

                    DebugChannelCard(
                        isHighlighted: highlightedFocus == .channel,
                        runningAction: runningAction,
                        didCopyDiagnostics: didCopyDiagnostics,
                        run: { action, operation in
                            run(action, operation: operation)
                        },
                        copyDiagnostics: copyDiagnostics
                    )
                    .id(DebugFocusTarget.channel)

                    DebugSwitchCard(
                        isHighlighted: highlightedFocus == .injectionSwitch,
                        runningAction: runningAction,
                        run: { action, operation in
                            run(action, operation: operation)
                        }
                    )
                    .id(DebugFocusTarget.injectionSwitch)

                    DebugResultCard()

                    DebugSessionDetailsCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(VmicTheme.appBackground)
            .onAppear {
                scrollToInitialFocus(with: proxy)
            }
        }
        .navigationTitle(settingsStore.text(.debug))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }

    private func scrollToInitialFocus(with proxy: ScrollViewProxy) {
        guard let initialFocus else { return }

        highlightedFocus = initialFocus

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(initialFocus, anchor: .top)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            guard highlightedFocus == initialFocus else { return }

            withAnimation(.easeInOut(duration: 0.22)) {
                highlightedFocus = nil
            }
        }
    }

    private func copyDiagnostics() {
        injectionManager.copyAudioSessionDiagnosticsToPasteboard()
        didCopyDiagnostics = true

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopyDiagnostics = false
            }
        }
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

private struct DebugOverviewCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let diagnosticText: String
    let tint: Color

    var body: some View {
        DebugCard(
            title: settingsStore.text(.debug),
            subtitle: diagnosticText,
            systemImage: "stethoscope",
            tint: tint
        ) {
            HStack(spacing: 0) {
                DebugMetric(
                    title: settingsStore.text(.systemPermission),
                    value: injectionManager.permissionState.canEnableInjection ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                    tint: injectionManager.permissionState.canEnableInjection ? VmicTheme.mint : VmicTheme.mutedInk
                )

                DebugMetricDivider()

                DebugMetric(
                    title: settingsStore.text(.injectionChannel),
                    value: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                    tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                )

                DebugMetricDivider()

                DebugMetric(
                    title: settingsStore.text(.injectionSwitch),
                    value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled),
                    tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
                )
            }
            .padding(.top, 2)
        }
    }
}

private struct DebugPermissionCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let isHighlighted: Bool
    let runningAction: DiagnosticAction?
    let run: (DiagnosticAction, @escaping () async -> Void) -> Void

    private var tint: Color {
        injectionManager.permissionState.canEnableInjection ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.systemPermission),
            subtitle: injectionManager.permissionState.detail(using: settingsStore),
            systemImage: injectionManager.permissionState.canEnableInjection ? "checkmark.circle.fill" : "hand.raised",
            tint: tint,
            isHighlighted: isHighlighted
        ) {
            DebugInfoRow(
                title: settingsStore.text(.permissionStateLabel),
                value: injectionManager.permissionState.title(using: settingsStore)
            )

            HStack(spacing: 10) {
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
                .buttonStyle(DebugActionButtonStyle())
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
                .buttonStyle(DebugActionButtonStyle())
                .disabled(runningAction != nil)
            }
            .padding(.top, 4)
        }
    }
}

private struct DebugChannelCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let isHighlighted: Bool
    let runningAction: DiagnosticAction?
    let didCopyDiagnostics: Bool
    let run: (DiagnosticAction, @escaping () async -> Void) -> Void
    let copyDiagnostics: () -> Void

    private var tint: Color {
        switch injectionManager.audioSessionDiagnostics.microphoneInjectionAvailable {
        case .some(true):
            return VmicTheme.mint
        case .some(false):
            return Color(red: 0.88, green: 0.58, blue: 0.12)
        case nil:
            return VmicTheme.mutedInk
        }
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.injectionChannel),
            subtitle: settingsStore.text(.audioSessionDiagnosticsNote),
            systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
            tint: tint,
            isHighlighted: isHighlighted
        ) {
            ChannelVerdictBanner(diagnostics: injectionManager.audioSessionDiagnostics)

            DebugInfoGrid {
                DebugCompactValue(
                    title: settingsStore.text(.directChannelCheck),
                    value: boolValue(injectionManager.audioSessionDiagnostics.microphoneInjectionAvailable)
                )
                DebugCompactValue(
                    title: settingsStore.text(.notificationChannel),
                    value: boolValue(injectionManager.lastNotifiedInjectionAvailability)
                )
                DebugCompactValue(
                    title: settingsStore.text(.lastCallEvent),
                    value: format(injectionManager.lastCapabilitiesChangeAt)
                )
                DebugCompactValue(
                    title: settingsStore.text(.lastRouteChange),
                    value: format(injectionManager.audioSessionDiagnostics.lastRouteChangeAt)
                )
            }

            HStack(spacing: 10) {
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
                .buttonStyle(DebugActionButtonStyle())
                .disabled(runningAction != nil)

                Button {
                    copyDiagnostics()
                } label: {
                    DiagnosticActionLabel(
                        title: didCopyDiagnostics ? settingsStore.text(.copiedChannelDiagnostics) : settingsStore.text(.copyChannelDiagnostics),
                        systemImage: didCopyDiagnostics ? "checkmark" : "doc.on.doc",
                        isRunning: false
                    )
                }
                .buttonStyle(DebugActionButtonStyle())
                .disabled(runningAction != nil)
            }
            .padding(.top, 4)
        }
    }

    private func boolValue(_ value: Bool?) -> String {
        guard let value else {
            return settingsStore.text(.notSupported)
        }

        return value ? settingsStore.text(.available) : settingsStore.text(.unavailable)
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return settingsStore.text(.never)
        }

        return date.formatted(date: .omitted, time: .standard)
    }
}

private struct DebugSwitchCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let isHighlighted: Bool
    let runningAction: DiagnosticAction?
    let run: (DiagnosticAction, @escaping () async -> Void) -> Void

    private var isBusy: Bool {
        runningAction != nil || injectionManager.isChangingInjectionMode
    }

    private var isRunningSwitchAction: Bool {
        runningAction == targetAction || injectionManager.isChangingInjectionMode
    }

    private var targetAction: DiagnosticAction {
        injectionManager.isInjectionEnabled ? .disableInjection : .enableInjection
    }

    private var actionTitle: String {
        if injectionManager.isChangingInjectionMode {
            return settingsStore.text(injectionManager.pendingInjectionMode == false ? .turningOffInjection : .turningOnInjection)
        }

        return injectionManager.isInjectionEnabled ? settingsStore.text(.disableInjection) : settingsStore.text(.enableInjection)
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.injectionSwitch),
            subtitle: settingsStore.text(.enableInjectionHelp),
            systemImage: injectionManager.isInjectionEnabled ? "waveform.badge.plus" : "waveform",
            tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk,
            isHighlighted: isHighlighted
        ) {
            DebugInfoRow(
                title: settingsStore.text(.injectionSwitch),
                value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled)
            )

            Button {
                run(targetAction) {
                    await injectionManager.setInjectionEnabled(!injectionManager.isInjectionEnabled)
                }
            } label: {
                DiagnosticActionLabel(
                    title: actionTitle,
                    systemImage: injectionManager.isInjectionEnabled ? "waveform" : "waveform.badge.plus",
                    isRunning: isRunningSwitchAction
                )
            }
            .buttonStyle(DebugActionButtonStyle(tint: injectionManager.isInjectionEnabled ? VmicTheme.mutedInk : VmicTheme.blue))
            .disabled(isBusy)
            .padding(.top, 4)
        }
    }
}

private struct DebugResultCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        DebugCard(
            title: settingsStore.text(.latestInjectionResult),
            subtitle: injectionManager.lastError ?? settingsStore.text(.noError),
            systemImage: "waveform.path.ecg",
            tint: resultTint
        ) {
            if let result = injectionManager.lastModeChangeResult {
                InjectionModeResultBanner(result: result, timestamp: injectionManager.lastModeChangeResultAt)
            } else {
                Text(settingsStore.text(.noInjectionResult))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
    }

    private var resultTint: Color {
        guard let result = injectionManager.lastModeChangeResult else {
            return VmicTheme.mutedInk
        }

        switch result {
        case .enabled(let channelAvailable):
            return channelAvailable ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
        case .disabled:
            return VmicTheme.blue
        case .failed:
            return Color(red: 0.82, green: 0.20, blue: 0.18)
        case .unsupportedOS, .permissionRequired, .busy:
            return Color(red: 0.88, green: 0.58, blue: 0.12)
        }
    }
}

private struct DebugSessionDetailsCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        DebugCard(
            title: settingsStore.text(.audioSessionDiagnostics),
            subtitle: "\(settingsStore.text(.device)) \(UIDevice.current.model) / \(settingsStore.text(.systemVersion)) \(UIDevice.current.systemVersion)",
            systemImage: "slider.horizontal.3",
            tint: VmicTheme.blue
        ) {
            DebugInfoGrid {
                DebugCompactValue(title: settingsStore.text(.minimumVersion), value: "iOS 18.2")
                DebugCompactValue(title: settingsStore.text(.sampleRate), value: formatSampleRate(injectionManager.audioSessionDiagnostics.sampleRate))
                DebugCompactValue(title: settingsStore.text(.inputChannels), value: "\(injectionManager.audioSessionDiagnostics.inputChannelCount)")
                DebugCompactValue(title: settingsStore.text(.outputChannels), value: "\(injectionManager.audioSessionDiagnostics.outputChannelCount)")
            }

            DebugInfoRow(title: settingsStore.text(.currentCategory), value: injectionManager.audioSessionDiagnostics.category)
            DebugInfoRow(title: settingsStore.text(.currentMode), value: injectionManager.audioSessionDiagnostics.mode)
            DebugInfoRow(title: settingsStore.text(.currentInputPorts), value: listValue(injectionManager.audioSessionDiagnostics.inputPortTypes))
            DebugInfoRow(title: settingsStore.text(.currentOutputPorts), value: listValue(injectionManager.audioSessionDiagnostics.outputPortTypes))
            DebugInfoRow(title: settingsStore.text(.currentInputDevices), value: listValue(injectionManager.audioSessionDiagnostics.inputPortNames))
            DebugInfoRow(title: settingsStore.text(.currentOutputDevices), value: listValue(injectionManager.audioSessionDiagnostics.outputPortNames))
            DebugInfoRow(title: settingsStore.text(.routeChangeReason), value: injectionManager.audioSessionDiagnostics.lastRouteChangeReason ?? settingsStore.text(.emptyRoute))

            HStack(spacing: 10) {
                DebugInfoRow(title: settingsStore.text(.lastRefresh), value: format(injectionManager.lastRefreshAt))
                DebugInfoRow(title: settingsStore.text(.lastInjectionChange), value: format(injectionManager.lastInjectionModeChangeAt))
            }
        }
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

    private func format(_ date: Date?) -> String {
        guard let date else {
            return settingsStore.text(.never)
        }

        return date.formatted(date: .omitted, time: .standard)
    }
}

private struct DebugCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isHighlighted: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(VmicTheme.ink)

                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(15)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHighlighted ? tint.opacity(0.82) : Color.white.opacity(0.70), lineWidth: isHighlighted ? 1.6 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
}

private struct DebugMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DebugMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(VmicTheme.separator.opacity(0.62))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 10)
    }
}

private struct DebugInfoGrid<Content: View>: View {
    let content: Content

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 10)
    ]

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            content
        }
    }
}

private struct DebugCompactValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VmicTheme.mutedInk)
                .lineLimit(1)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(VmicTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DebugInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
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
        HStack(spacing: 9) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .frame(width: 16, height: 16)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DebugActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color

    init(tint: Color = VmicTheme.blue) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.46)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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
