import AVFAudio
import SwiftUI
import UIKit

enum DebugFocusTarget: Hashable, Identifiable {
    case overview
    case permission
    case channel
    case injectionSwitch

    var id: String {
        switch self {
        case .overview:
            return "overview"
        case .permission:
            return "permission"
        case .channel:
            return "channel"
        case .injectionSwitch:
            return "injectionSwitch"
        }
    }

    var initialFocus: DebugFocusTarget? {
        switch self {
        case .overview:
            return nil
        case .permission, .channel, .injectionSwitch:
            return self
        }
    }
}

struct DebugDiagnosticsView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var diagnosticLogStore: DiagnosticLogStore

    let initialFocus: DebugFocusTarget?

    @StateObject private var monitorExperiment = MonitorVolumeExperimentManager()
    @StateObject private var speechProbe = OfficialSpeechProbeManager()

    @State private var runningAction: DiagnosticAction?
    @State private var didCopyDiagnostics = false
    @State private var didCopyLogs = false
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

    private var experimentClip: SoundClip? {
        if let currentClipID = playbackManager.currentClipID,
           let clip = libraryStore.clips.first(where: { $0.id == currentClipID }) {
            return clip
        }

        return libraryStore.clips.first
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

                    OfficialSpeechProbeCard(
                        probeManager: speechProbe,
                        prepareForProbe: prepareForOfficialSpeechProbe
                    )

                    MonitorVolumeExperimentCard(
                        clip: experimentClip,
                        soundsDirectory: libraryStore.soundsDirectory,
                        experimentManager: monitorExperiment,
                        prepareForExperiment: prepareForMonitorExperiment
                    )

                    DebugResultCard()

                    DebugLogCard(
                        logStore: diagnosticLogStore,
                        didCopyLogs: didCopyLogs,
                        copyLogs: copyDiagnosticLogs,
                        clearLogs: clearDiagnosticLogs
                    )

                    DebugSessionDetailsCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(VmicTheme.appBackground)
            .onAppear {
                DiagnosticLogStore.shared.log(
                    "进入调试页",
                    source: .app,
                    details: ["initialFocus=\(initialFocus?.id ?? "overview")"]
                )
                scrollToInitialFocus(with: proxy)
            }
        }
        .navigationTitle(settingsStore.text(.debug))
        .navigationBarTitleDisplayMode(.inline)
        .vmicOpaqueNavigationBar()
    }

    private func scrollToInitialFocus(with proxy: ScrollViewProxy) {
        guard let initialFocus, initialFocus != .overview else { return }

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

    private func prepareForMonitorExperiment() async {
        DiagnosticLogStore.shared.log("准备监听验证", source: .monitorExperiment)
        playbackManager.stopAll()
        speechProbe.stop()

        if !injectionManager.isInjectionEnabled, injectionManager.permissionState.canEnableInjection {
            _ = await injectionManager.setInjectionEnabled(true)
        }

        injectionManager.refreshAudioSessionDiagnostics(printToConsole: true)
    }

    private func prepareForOfficialSpeechProbe() async {
        DiagnosticLogStore.shared.log("准备官方语音对照", source: .speechProbe)
        playbackManager.stopAll()
        monitorExperiment.stop()

        if !injectionManager.isInjectionEnabled, injectionManager.permissionState.canEnableInjection {
            _ = await injectionManager.setInjectionEnabled(true)
        }

        do {
            try injectionManager.reapplyInjectionPreferenceIfNeeded()
        } catch {
            injectionManager.refreshAudioSessionDiagnostics(printToConsole: true)
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

    private func copyDiagnosticLogs() {
        DiagnosticLogStore.shared.log("已复制运行日志", source: .app)
        UIPasteboard.general.string = diagnosticLogStore.exportText()
        didCopyLogs = true

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopyLogs = false
            }
        }
    }

    private func clearDiagnosticLogs() {
        diagnosticLogStore.clear()
    }

    private func run(_ action: DiagnosticAction, operation: @escaping () async -> Void) {
        guard runningAction == nil else { return }

        DiagnosticLogStore.shared.log(
            "开始调试动作",
            source: .app,
            details: ["action=\(action.logName)"]
        )
        runningAction = action
        Task {
            await operation()
            await MainActor.run {
                DiagnosticLogStore.shared.log(
                    "结束调试动作",
                    source: .app,
                    details: ["action=\(action.logName)"]
                )
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

private struct OfficialSpeechProbeCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @ObservedObject var probeManager: OfficialSpeechProbeManager
    let prepareForProbe: () async -> Void

    private var channelTint: Color {
        injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
    }

    private var switchTint: Color {
        injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
    }

    private var canStartProbe: Bool {
        let canUseSwitch = injectionManager.isInjectionEnabled || injectionManager.permissionState.canEnableInjection

        return injectionManager.isInjectionAvailableInCurrentCall
            && canUseSwitch
            && probeManager.status != .running
            && !injectionManager.isChangingInjectionMode
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.officialSpeechProbe),
            subtitle: settingsStore.text(.officialSpeechProbeDetail),
            systemImage: "text.bubble",
            tint: VmicTheme.blue
        ) {
            DebugInfoRow(
                title: settingsStore.text(.speechProbePhraseLabel),
                value: settingsStore.text(.speechProbePhrase)
            )

            HStack(spacing: 0) {
                DebugMetric(
                    title: settingsStore.text(.injectionChannel),
                    value: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                    tint: channelTint
                )

                DebugMetricDivider()

                DebugMetric(
                    title: settingsStore.text(.injectionSwitch),
                    value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled),
                    tint: switchTint
                )
            }

            HStack(spacing: 10) {
                Button {
                    startProbe()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.playSpeechProbe),
                        systemImage: "play.fill",
                        isRunning: probeManager.status == .running
                    )
                }
                .buttonStyle(DebugActionButtonStyle())
                .disabled(!canStartProbe)

                Button {
                    probeManager.stop()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.stopSpeechProbe),
                        systemImage: "stop.fill",
                        isRunning: false
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.mutedInk))
                .disabled(probeManager.status != .running)
            }
            .padding(.top, 4)

            SpeechProbeStatusBanner(status: probeManager.status)

            Text(settingsStore.text(.speechProbeInstruction))
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startProbe() {
        Task {
            await prepareForProbe()
            await MainActor.run {
                probeManager.speak(
                    settingsStore.text(.speechProbePhrase),
                    reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
                )
            }
        }
    }
}

private struct MonitorVolumeExperimentCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip?
    let soundsDirectory: URL
    @ObservedObject var experimentManager: MonitorVolumeExperimentManager
    let prepareForExperiment: () async -> Void

    private var channelTint: Color {
        injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
    }

    private var switchTint: Color {
        injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.monitorVolumeExperiment),
            subtitle: settingsStore.text(.monitorVolumeExperimentDetail),
            systemImage: "ear",
            tint: VmicTheme.cyan
        ) {
            if let clip {
                DebugInfoRow(title: settingsStore.text(.experimentAudio), value: clip.title)
            } else {
                DebugInfoRow(title: settingsStore.text(.experimentAudio), value: settingsStore.text(.experimentNoAudio))
            }

            HStack(spacing: 0) {
                DebugMetric(
                    title: settingsStore.text(.injectionChannel),
                    value: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                    tint: channelTint
                )

                DebugMetricDivider()

                DebugMetric(
                    title: settingsStore.text(.injectionSwitch),
                    value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled),
                    tint: switchTint
                )
            }

            ExperimentVolumeSlider(
                title: settingsStore.text(.localMonitorVolume),
                systemImage: "headphones",
                value: $experimentManager.localMonitorVolume,
                isDisabled: experimentManager.status == .running(.mutedMonitor)
            )

            ExperimentVolumeSlider(
                title: settingsStore.text(.bridgeSendVolume),
                systemImage: "waveform.badge.plus",
                value: $experimentManager.bridgeSendVolume
            )

            HStack(spacing: 10) {
                Button {
                    startBaseline()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.baselineTest),
                        systemImage: "speaker.wave.2",
                        isRunning: experimentManager.status == .running(.baseline)
                    )
                }
                .buttonStyle(DebugActionButtonStyle())
                .disabled(clip == nil || experimentManager.isRunning || injectionManager.isChangingInjectionMode)

                Button {
                    startMutedMonitor()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.mutedMonitorTest),
                        systemImage: "speaker.slash",
                        isRunning: experimentManager.status == .running(.mutedMonitor)
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.cyan))
                .disabled(clip == nil || experimentManager.isRunning || injectionManager.isChangingInjectionMode)
            }
            .padding(.top, 4)

            Button {
                experimentManager.stop()
            } label: {
                DiagnosticActionLabel(
                    title: settingsStore.text(.stopTest),
                    systemImage: "stop.fill",
                    isRunning: false
                )
            }
            .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.mutedInk))
            .disabled(!experimentManager.isRunning)

            ExperimentStatusBanner(status: experimentManager.status)

            Text(settingsStore.text(.experimentInstruction))
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startBaseline() {
        guard let clip else { return }

        Task {
            await prepareForExperiment()
            await MainActor.run {
                experimentManager.playBaseline(
                    clip,
                    from: soundsDirectory,
                    reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
                )
            }
        }
    }

    private func startMutedMonitor() {
        guard let clip else { return }

        Task {
            await prepareForExperiment()
            await MainActor.run {
                experimentManager.playMutedMonitor(
                    clip,
                    from: soundsDirectory,
                    reapplyInjectionPreference: injectionManager.reapplyInjectionPreferenceIfNeeded
                )
            }
        }
    }
}

private struct ExperimentVolumeSlider: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let systemImage: String
    @Binding var value: Double
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Spacer()

                Text(settingsStore.text(.volumePercent(Int((value * 100).rounded()))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
            }

            Slider(value: $value, in: 0...1)
                .tint(VmicTheme.blue)
                .disabled(isDisabled)
        }
        .padding(12)
        .background(VmicTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isDisabled ? 0.62 : 1)
    }
}

private struct ExperimentStatusBanner: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let status: MonitorVolumeExperimentStatus

    private var tint: Color {
        switch status {
        case .idle, .stopped:
            return VmicTheme.mutedInk
        case .running:
            return VmicTheme.blue
        case .finished:
            return VmicTheme.mint
        case .failed:
            return Color(red: 0.82, green: 0.20, blue: 0.18)
        }
    }

    private var systemImage: String {
        switch status {
        case .idle:
            return "checkmark.circle"
        case .running:
            return "waveform"
        case .finished:
            return "checkmark.circle.fill"
        case .stopped:
            return "stop.circle"
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

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        switch status {
        case .idle:
            return settingsStore.text(.experimentReady)
        case .running(.baseline):
            return settingsStore.text(.experimentBaselineRunning)
        case .running(.mutedMonitor):
            return settingsStore.text(.experimentMutedMonitorRunning)
        case .finished(.baseline):
            return settingsStore.text(.experimentBaselineFinished)
        case .finished(.mutedMonitor):
            return settingsStore.text(.experimentMutedMonitorFinished)
        case .stopped:
            return settingsStore.text(.experimentStopped)
        case .failed(let message):
            return settingsStore.text(.experimentFailed(message))
        }
    }
}

private struct SpeechProbeStatusBanner: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let status: OfficialSpeechProbeStatus

    private var tint: Color {
        switch status {
        case .idle, .stopped:
            return VmicTheme.mutedInk
        case .running:
            return VmicTheme.blue
        case .finished:
            return VmicTheme.mint
        case .failed:
            return Color(red: 0.82, green: 0.20, blue: 0.18)
        }
    }

    private var systemImage: String {
        switch status {
        case .idle:
            return "text.bubble"
        case .running:
            return "waveform"
        case .finished:
            return "checkmark.circle.fill"
        case .stopped:
            return "stop.circle"
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

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        switch status {
        case .idle:
            return settingsStore.text(.speechProbeReady)
        case .running:
            return settingsStore.text(.speechProbeRunning)
        case .finished:
            return settingsStore.text(.speechProbeFinished)
        case .stopped:
            return settingsStore.text(.speechProbeStopped)
        case .failed(let message):
            return settingsStore.text(.speechProbeFailed(message))
        }
    }
}

private enum OfficialSpeechProbeStatus: Equatable {
    case idle
    case running
    case finished
    case stopped
    case failed(String)
}

@MainActor
private final class OfficialSpeechProbeManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var status: OfficialSpeechProbeStatus = .idle

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ text: String,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        do {
            DiagnosticLogStore.shared.log(
                "官方语音对照开始",
                source: .speechProbe,
                details: ["textLength=\(text.count)"]
            )
            try reapplyInjectionPreference?()

            if synthesizer.isSpeaking {
                DiagnosticLogStore.shared.log("停止上一段官方语音", source: .speechProbe)
                synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)
            let enhancedVoice = AVSpeechSynthesisVoice.speechVoices().first(where: {
                $0.language == AVSpeechSynthesisVoice.currentLanguageCode() && $0.quality == .enhanced
            })
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") ?? enhancedVoice
            utterance.volume = 1
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            status = .running
            synthesizer.speak(utterance)
            DiagnosticLogStore.shared.log(
                "官方语音已提交给 AVSpeechSynthesizer",
                source: .speechProbe,
                details: [
                    "voice=\(utterance.voice?.identifier ?? "default")",
                    "volume=\(utterance.volume)"
                ]
            )
        } catch {
            status = .failed(error.localizedDescription)
            DiagnosticLogStore.shared.log(
                "官方语音对照失败",
                source: .speechProbe,
                details: ["error=\(error.localizedDescription)"]
            )
        }
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            status = .stopped
            DiagnosticLogStore.shared.log("官方语音对照停止：当前未朗读", source: .speechProbe)
            return
        }

        DiagnosticLogStore.shared.log("官方语音对照停止", source: .speechProbe)
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.status = .finished
            DiagnosticLogStore.shared.log("官方语音对照播放完成", source: .speechProbe)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.status = .stopped
            DiagnosticLogStore.shared.log("官方语音对照已取消", source: .speechProbe)
        }
    }
}

private enum MonitorVolumeExperimentKind: Equatable {
    case baseline
    case mutedMonitor

    var logName: String {
        switch self {
        case .baseline:
            return "baseline"
        case .mutedMonitor:
            return "mutedMonitor"
        }
    }
}

private enum MonitorVolumeExperimentStatus: Equatable {
    case idle
    case running(MonitorVolumeExperimentKind)
    case finished(MonitorVolumeExperimentKind)
    case stopped
    case failed(String)

    var logName: String {
        switch self {
        case .idle:
            return "idle"
        case .running(let kind):
            return "running(\(kind.logName))"
        case .finished(let kind):
            return "finished(\(kind.logName))"
        case .stopped:
            return "stopped"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

@MainActor
private final class MonitorVolumeExperimentManager: NSObject, ObservableObject {
    private static let maximumTestDuration: TimeInterval = 12

    @Published var localMonitorVolume: Double = 1 {
        didSet {
            updateVolumes()
        }
    }
    @Published var bridgeSendVolume: Double = 1 {
        didSet {
            updateVolumes()
        }
    }
    @Published private(set) var status: MonitorVolumeExperimentStatus = .idle

    private var engine: AVAudioEngine?
    private var localPlayerNode: AVAudioPlayerNode?
    private var bridgePlayerNode: AVAudioPlayerNode?
    private var silentBridgeMixer: AVAudioMixerNode?
    private var localAudioFile: AVAudioFile?
    private var bridgeAudioFile: AVAudioFile?
    private var finishTask: Task<Void, Never>?
    private var lastLoggedVolumeSignature: String?

    var isRunning: Bool {
        if case .running = status {
            return true
        }

        return false
    }

    func playBaseline(
        _ clip: SoundClip,
        from directory: URL,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        DiagnosticLogStore.shared.log(
            "请求基线播放",
            source: .monitorExperiment,
            details: ["title=\(clip.title)"]
        )
        localMonitorVolume = 1
        bridgeSendVolume = 1
        play(
            clip,
            from: directory,
            kind: .baseline,
            reapplyInjectionPreference: reapplyInjectionPreference
        )
    }

    func playMutedMonitor(
        _ clip: SoundClip,
        from directory: URL,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        DiagnosticLogStore.shared.log(
            "请求静音监听",
            source: .monitorExperiment,
            details: ["title=\(clip.title)"]
        )
        localMonitorVolume = 0
        bridgeSendVolume = 1
        play(
            clip,
            from: directory,
            kind: .mutedMonitor,
            reapplyInjectionPreference: reapplyInjectionPreference
        )
    }

    func stop() {
        DiagnosticLogStore.shared.log(
            "停止监听验证",
            source: .monitorExperiment,
            details: ["status=\(status.logName)"]
        )
        stopEngineOnly()
        status = .stopped
    }

    private func play(
        _ clip: SoundClip,
        from directory: URL,
        kind: MonitorVolumeExperimentKind,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        let url = clip.fileURL(in: directory)
        DiagnosticLogStore.shared.log(
            "监听验证准备播放",
            source: .monitorExperiment,
            details: [
                "kind=\(kind.logName)",
                "title=\(clip.title)",
                "file=\(url.lastPathComponent)",
                "exists=\(FileManager.default.fileExists(atPath: url.path))"
            ]
        )

        do {
            stopEngineOnly()

            let localAudioFile = try AVAudioFile(forReading: url)
            let bridgeAudioFile = try AVAudioFile(forReading: url)
            let engine = AVAudioEngine()
            let localPlayerNode = AVAudioPlayerNode()
            let bridgePlayerNode = AVAudioPlayerNode()
            let silentBridgeMixer = AVAudioMixerNode()
            let format = localAudioFile.processingFormat
            DiagnosticLogStore.shared.log(
                "监听验证音频文件已打开",
                source: .monitorExperiment,
                details: [
                    "kind=\(kind.logName)",
                    "sampleRate=\(Int(format.sampleRate.rounded()))",
                    "channels=\(format.channelCount)",
                    "frames=\(localAudioFile.length)"
                ]
            )

            engine.attach(localPlayerNode)
            engine.attach(bridgePlayerNode)
            engine.attach(silentBridgeMixer)
            engine.connect(localPlayerNode, to: engine.mainMixerNode, format: format)
            engine.connect(bridgePlayerNode, to: silentBridgeMixer, format: format)
            engine.connect(silentBridgeMixer, to: engine.mainMixerNode, format: format)

            localPlayerNode.volume = Float(clamped(localMonitorVolume))
            bridgePlayerNode.volume = Float(clamped(bridgeSendVolume))
            silentBridgeMixer.outputVolume = 0

            let frameCount = frameCount(for: localAudioFile)
            localPlayerNode.scheduleSegment(localAudioFile, startingFrame: 0, frameCount: frameCount, at: nil)
            bridgePlayerNode.scheduleSegment(bridgeAudioFile, startingFrame: 0, frameCount: frameCount, at: nil)

            try configureAudioSession(reapplyInjectionPreference: reapplyInjectionPreference)
            try engine.start()
            DiagnosticLogStore.shared.log(
                "监听验证引擎已启动",
                source: .monitorExperiment,
                details: [
                    "kind=\(kind.logName)",
                    "localVolume=\(localMonitorVolume)",
                    "bridgeVolume=\(bridgeSendVolume)"
                ]
            )

            self.engine = engine
            self.localPlayerNode = localPlayerNode
            self.bridgePlayerNode = bridgePlayerNode
            self.silentBridgeMixer = silentBridgeMixer
            self.localAudioFile = localAudioFile
            self.bridgeAudioFile = bridgeAudioFile
            status = .running(kind)

            localPlayerNode.play()
            bridgePlayerNode.play()
            scheduleFinish(frameCount: frameCount, sampleRate: format.sampleRate, kind: kind)
        } catch {
            stopEngineOnly()
            status = .failed(error.localizedDescription)
            DiagnosticLogStore.shared.log(
                "监听验证失败",
                source: .monitorExperiment,
                details: [
                    "kind=\(kind.logName)",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    private func updateVolumes() {
        guard isRunning else { return }

        if case .running(.mutedMonitor) = status {
            localPlayerNode?.volume = 0
        } else {
            localPlayerNode?.volume = Float(clamped(localMonitorVolume))
        }

        bridgePlayerNode?.volume = Float(clamped(bridgeSendVolume))

        let localPercent = Int((Double(localPlayerNode?.volume ?? -1) * 100).rounded())
        let bridgePercent = Int((Double(bridgePlayerNode?.volume ?? -1) * 100).rounded())
        let signature = "\(status.logName)|\(localPercent / 5)|\(bridgePercent / 5)"

        guard signature != lastLoggedVolumeSignature else { return }

        lastLoggedVolumeSignature = signature
        DiagnosticLogStore.shared.log(
            "监听验证音量更新",
            source: .monitorExperiment,
            details: [
                "status=\(status.logName)",
                "local=\(localPercent)%",
                "bridge=\(bridgePercent)%"
            ]
        )
    }

    private func frameCount(for audioFile: AVAudioFile) -> AVAudioFrameCount {
        let maximumFrames = AVAudioFramePosition(audioFile.processingFormat.sampleRate * Self.maximumTestDuration)
        let selectedFrames = max(1, min(audioFile.length, maximumFrames))

        return AVAudioFrameCount(selectedFrames)
    }

    private func scheduleFinish(frameCount: AVAudioFrameCount, sampleRate: Double, kind: MonitorVolumeExperimentKind) {
        finishTask?.cancel()

        let duration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        let wait = UInt64(max(duration + 0.2, 0.5) * 1_000_000_000)

        finishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)

            await MainActor.run {
                guard let self, self.status == .running(kind) else { return }

                self.stopEngineOnly()
                self.status = .finished(kind)
                DiagnosticLogStore.shared.log(
                    "监听验证自然结束",
                    source: .monitorExperiment,
                    details: ["kind=\(kind.logName)"]
                )
            }
        }
    }

    private func stopEngineOnly() {
        finishTask?.cancel()
        finishTask = nil
        localPlayerNode?.stop()
        bridgePlayerNode?.stop()
        engine?.stop()
        engine = nil
        localPlayerNode = nil
        bridgePlayerNode = nil
        silentBridgeMixer = nil
        localAudioFile = nil
        bridgeAudioFile = nil
        lastLoggedVolumeSignature = nil
    }

    private func configureAudioSession(reapplyInjectionPreference: (@MainActor () throws -> Void)?) throws {
        let session = AVAudioSession.sharedInstance()
        DiagnosticLogStore.shared.log(
            "监听验证配置音频会话开始",
            source: .monitorExperiment,
            details: [
                "categoryBefore=\(session.category.rawValue)",
                "modeBefore=\(session.mode.rawValue)"
            ]
        )
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
        try reapplyInjectionPreference?()
        DiagnosticLogStore.shared.log(
            "监听验证配置音频会话完成",
            source: .monitorExperiment,
            details: [
                "category=\(session.category.rawValue)",
                "mode=\(session.mode.rawValue)",
                "outputs=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
            ]
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
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

private struct DebugLogCard: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @ObservedObject var logStore: DiagnosticLogStore

    let didCopyLogs: Bool
    let copyLogs: () -> Void
    let clearLogs: () -> Void

    private var visibleEntries: [DiagnosticLogEntry] {
        Array(logStore.entries.suffix(18).reversed())
    }

    var body: some View {
        DebugCard(
            title: settingsStore.text(.debugLog),
            subtitle: settingsStore.text(.debugLogDetail),
            systemImage: "doc.text.magnifyingglass",
            tint: VmicTheme.blue
        ) {
            HStack(spacing: 10) {
                Button(action: copyLogs) {
                    DiagnosticActionLabel(
                        title: didCopyLogs ? settingsStore.text(.copiedDebugLog) : settingsStore.text(.copyDebugLog),
                        systemImage: didCopyLogs ? "checkmark" : "doc.on.doc",
                        isRunning: false
                    )
                }
                .buttonStyle(DebugActionButtonStyle())

                Button(action: clearLogs) {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.clearDebugLog),
                        systemImage: "trash",
                        isRunning: false
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.mutedInk))
                .disabled(logStore.entries.isEmpty)
            }

            if visibleEntries.isEmpty {
                Text(settingsStore.text(.noDebugLog))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleEntries) { entry in
                        DebugLogRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct DebugLogRow: View {
    let entry: DiagnosticLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(entry.timeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()

                Text(entry.source.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VmicTheme.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(VmicTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Spacer(minLength: 0)
            }

            Text(entry.message)
                .font(.caption.weight(.medium))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VmicTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            DebugInfoRow(title: settingsStore.text(.preferredInjectionMode), value: injectionManager.audioSessionDiagnostics.preferredMicrophoneInjectionMode ?? settingsStore.text(.notSupported))
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

    var logName: String {
        switch self {
        case .refresh:
            return "refresh"
        case .requestPermission:
            return "requestPermission"
        case .openSettings:
            return "openSettings"
        case .enableInjection:
            return "enableInjection"
        case .disableInjection:
            return "disableInjection"
        }
    }
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
