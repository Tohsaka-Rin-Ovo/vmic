import AVFAudio
import AVFoundation
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
    @EnvironmentObject private var appChromeStore: AppChromeStore
    @EnvironmentObject private var diagnosticLogStore: DiagnosticLogStore

    let initialFocus: DebugFocusTarget?

    @StateObject private var playbackSelfCheck = PlaybackSelfCheckManager()
    @StateObject private var speechProbe = OfficialSpeechProbeManager()
    @StateObject private var audioFileProbe = AudioFileProbeManager()

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

                    AudioFileProbeCard(
                        clip: experimentClip,
                        soundsDirectory: libraryStore.soundsDirectory,
                        probeManager: audioFileProbe,
                        prepareForProbe: prepareForAudioFileProbe
                    )

                    PlaybackSelfCheckCard(
                        clip: experimentClip,
                        soundsDirectory: libraryStore.soundsDirectory,
                        selfCheckManager: playbackSelfCheck,
                        prepareForSelfCheck: prepareForPlaybackSelfCheck
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
                appChromeStore.isDebugPageVisible = true
                DiagnosticLogStore.shared.log(
                    "进入调试页",
                    source: .app,
                    details: ["initialFocus=\(initialFocus?.id ?? "overview")"]
                )
                scrollToInitialFocus(with: proxy)
            }
            .onDisappear {
                appChromeStore.isDebugPageVisible = false
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

    private func prepareForPlaybackSelfCheck() async {
        DiagnosticLogStore.shared.log("准备播放链路自检", source: .playbackSelfCheck)
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
        playbackSelfCheck.stop()

        if !injectionManager.isInjectionEnabled, injectionManager.permissionState.canEnableInjection {
            _ = await injectionManager.setInjectionEnabled(true)
        }

        do {
            try injectionManager.reapplyInjectionPreferenceIfNeeded()
        } catch {
            injectionManager.refreshAudioSessionDiagnostics(printToConsole: true)
        }
    }

    private func prepareForAudioFileProbe() async {
        DiagnosticLogStore.shared.log("准备音频文件排除工具", source: .audioFileProbe)
        playbackManager.stopAll()
        playbackSelfCheck.stop()
        speechProbe.stop()

        if !injectionManager.isInjectionEnabled, injectionManager.permissionState.canEnableInjection {
            _ = await injectionManager.setInjectionEnabled(true)
        }

        injectionManager.refreshAudioSessionDiagnostics(printToConsole: true)
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

private struct PlaybackSelfCheckCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip?
    let soundsDirectory: URL
    @ObservedObject var selfCheckManager: PlaybackSelfCheckManager
    let prepareForSelfCheck: () async -> Void

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
            systemImage: "speaker.wave.2",
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
                title: settingsStore.text(.localPlaybackVolume),
                systemImage: "speaker.wave.2",
                value: $selfCheckManager.localPlaybackVolume,
                isDisabled: selfCheckManager.status == .running(.mutedPlayback)
            )

            HStack(spacing: 10) {
                Button {
                    startNormalPlayback()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.normalPlaybackTest),
                        systemImage: "speaker.wave.2",
                        isRunning: selfCheckManager.status == .running(.normalPlayback)
                    )
                }
                .buttonStyle(DebugActionButtonStyle())
                .disabled(clip == nil || selfCheckManager.isRunning || injectionManager.isChangingInjectionMode)

                Button {
                    startMutedPlayback()
                } label: {
                    DiagnosticActionLabel(
                        title: settingsStore.text(.mutedPlaybackTest),
                        systemImage: "speaker.slash",
                        isRunning: selfCheckManager.status == .running(.mutedPlayback)
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.cyan))
                .disabled(clip == nil || selfCheckManager.isRunning || injectionManager.isChangingInjectionMode)
            }
            .padding(.top, 4)

            Button {
                selfCheckManager.stop()
            } label: {
                DiagnosticActionLabel(
                    title: settingsStore.text(.stopTest),
                    systemImage: "stop.fill",
                    isRunning: false
                )
            }
            .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.mutedInk))
            .disabled(!selfCheckManager.isRunning)

            ExperimentStatusBanner(status: selfCheckManager.status)

            Text(settingsStore.text(.experimentInstruction))
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startNormalPlayback() {
        guard let clip else { return }

        Task {
            await prepareForSelfCheck()
            await MainActor.run {
                selfCheckManager.playNormalPlayback(
                    clip,
                    from: soundsDirectory,
                    reapplyInjectionPreference: injectionManager.reapplyOfficialSampleInjectionPreferenceIfNeeded
                )
            }
        }
    }

    private func startMutedPlayback() {
        guard let clip else { return }

        Task {
            await prepareForSelfCheck()
            await MainActor.run {
                selfCheckManager.playMutedPlayback(
                    clip,
                    from: soundsDirectory,
                    reapplyInjectionPreference: injectionManager.reapplyOfficialSampleInjectionPreferenceIfNeeded
                )
            }
        }
    }
}

private struct AudioFileProbeCard: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip?
    let soundsDirectory: URL
    @ObservedObject var probeManager: AudioFileProbeManager
    let prepareForProbe: () async -> Void

    private var copy: AudioFileProbeCopy {
        AudioFileProbeCopy.make(language: settingsStore.language)
    }

    private var referencePlaybackState: SoundPlaybackState? {
        guard let referenceClip = probeManager.referenceClip else { return nil }
        return playbackManager.playbackState(for: referenceClip.id)
    }

    var body: some View {
        DebugCard(
            title: copy.title,
            subtitle: copy.detail,
            systemImage: "waveform.path.badge.magnifyingglass",
            tint: VmicTheme.blue
        ) {
            if let clip {
                DebugInfoRow(title: copy.currentAudio, value: clip.title)
            } else {
                DebugInfoRow(title: copy.currentAudio, value: copy.noAudio)
            }

            HStack(spacing: 10) {
                Button {
                    inspectCurrentClip()
                } label: {
                    DiagnosticActionLabel(
                        title: copy.inspectCurrentAudio,
                        systemImage: "checklist",
                        isRunning: probeManager.status == .checking
                    )
                }
                .buttonStyle(DebugActionButtonStyle())
                .disabled(clip == nil || probeManager.isBusy)

                Button {
                    generateAndPlayReferenceFile()
                } label: {
                    DiagnosticActionLabel(
                        title: copy.playReferenceAudioFile,
                        systemImage: "text.bubble.fill",
                        isRunning: probeManager.status == .renderingReference
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.cyan))
                .disabled(probeManager.isBusy || injectionManager.isChangingInjectionMode)
            }

            if probeManager.referenceClip != nil {
                Button {
                    stopReferencePlayback()
                } label: {
                    DiagnosticActionLabel(
                        title: copy.stopReferenceAudioFile,
                        systemImage: "stop.fill",
                        isRunning: false
                    )
                }
                .buttonStyle(DebugActionButtonStyle(tint: VmicTheme.mutedInk))
                .disabled(referencePlaybackState == nil)
            }

            AudioFileProbeStatusBanner(status: probeManager.status, copy: copy)

            if let report = probeManager.status.report {
                AudioFileProbeReportView(report: report, copy: copy)
            }

            Text(copy.instruction)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inspectCurrentClip() {
        guard let clip else { return }

        Task {
            await probeManager.inspect(clip, from: soundsDirectory)
        }
    }

    private func generateAndPlayReferenceFile() {
        Task {
            await prepareForProbe()

            guard let referenceClip = await probeManager.generateReferenceClip(
                in: soundsDirectory,
                phrase: copy.referencePhrase,
                title: copy.referenceTitle,
                artist: copy.referenceArtist
            ) else {
                return
            }

            playbackManager.play(
                referenceClip,
                from: soundsDirectory,
                reapplyInjectionPreference: injectionManager.reapplyOfficialSampleInjectionPreferenceIfNeeded
            )

            if playbackManager.playbackState(for: referenceClip.id) == nil {
                probeManager.markReferencePlaybackFailed(playbackManager.lastError ?? copy.referencePlaybackDidNotStart)
            } else {
                probeManager.markReferencePlaybackStarted()
            }
        }
    }

    private func stopReferencePlayback() {
        guard let referenceClip = probeManager.referenceClip else { return }
        playbackManager.stop(referenceClip)
        probeManager.markReferencePlaybackStopped()
    }
}

private struct AudioFileProbeStatusBanner: View {
    let status: AudioFileProbeStatus
    let copy: AudioFileProbeCopy

    private var tint: Color {
        switch status {
        case .idle:
            return VmicTheme.mutedInk
        case .checking, .renderingReference, .referencePlaybackStarted(_):
            return VmicTheme.blue
        case .checked(let report), .referenceReady(let report):
            return report.isHealthy ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)
        case .referencePlaybackStopped:
            return VmicTheme.mutedInk
        case .failed:
            return Color(red: 0.82, green: 0.20, blue: 0.18)
        }
    }

    private var systemImage: String {
        switch status {
        case .idle:
            return "waveform.path.badge.magnifyingglass"
        case .checking, .renderingReference:
            return "waveform"
        case .checked(let report), .referenceReady(let report):
            return report.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .referencePlaybackStarted(_):
            return "play.circle.fill"
        case .referencePlaybackStopped:
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
            return copy.ready
        case .checking:
            return copy.checking
        case .checked(let report):
            return report.isHealthy ? copy.checkedHealthy : copy.checkedNeedsAttention
        case .renderingReference:
            return copy.renderingReference
        case .referenceReady(let report):
            return report.isHealthy ? copy.referenceReady : copy.referenceNeedsAttention
        case .referencePlaybackStarted(_):
            return copy.referencePlaybackStarted
        case .referencePlaybackStopped:
            return copy.referencePlaybackStopped
        case .failed(let message):
            return copy.failed(message)
        }
    }
}

private struct AudioFileProbeReportView: View {
    let report: AudioFileProbeReport
    let copy: AudioFileProbeCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebugInfoGrid {
                DebugCompactValue(title: copy.fileSize, value: report.fileSizeText)
                DebugCompactValue(title: copy.assetDuration, value: report.assetDurationText)
                DebugCompactValue(title: copy.audioTracks, value: "\(report.audioTrackCount)")
                DebugCompactValue(title: copy.codec, value: report.codecText)
                DebugCompactValue(title: copy.decodedFormat, value: report.decodedFormat)
                DebugCompactValue(title: copy.playerFormat, value: report.playerFormat)
                DebugCompactValue(title: copy.peakLevel, value: report.peakLevelText)
                DebugCompactValue(title: copy.rmsLevel, value: report.rmsLevelText)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(copy.verdict)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)

                if report.warnings.isEmpty {
                    Label(copy.noWarnings, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VmicTheme.mint)
                } else {
                    ForEach(report.warnings) { warning in
                        Label(copy.warningText(warning), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 0.82, green: 0.46, blue: 0.10))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((report.isHealthy ? VmicTheme.mint : Color(red: 0.88, green: 0.58, blue: 0.12)).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private enum AudioFileProbeStatus: Equatable {
    case idle
    case checking
    case checked(AudioFileProbeReport)
    case renderingReference
    case referenceReady(AudioFileProbeReport)
    case referencePlaybackStarted(AudioFileProbeReport)
    case referencePlaybackStopped
    case failed(String)

    var report: AudioFileProbeReport? {
        switch self {
        case .checked(let report), .referenceReady(let report), .referencePlaybackStarted(let report):
            return report
        case .idle, .checking, .renderingReference, .referencePlaybackStopped, .failed:
            return nil
        }
    }
}

private struct AudioFileProbeReport: Equatable {
    let fileName: String
    let fileSizeBytes: Int64
    let assetDuration: TimeInterval?
    let audioTrackCount: Int
    let codecs: [String]
    let decodedFormat: String
    let decodedDuration: TimeInterval?
    let playerFormat: String
    let playerDuration: TimeInterval?
    let peakLevel: Double?
    let rmsLevel: Double?
    let warnings: [AudioFileProbeWarning]

    var isHealthy: Bool {
        warnings.isEmpty
    }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var assetDurationText: String {
        formatDuration(assetDuration ?? decodedDuration ?? playerDuration)
    }

    var codecText: String {
        codecs.isEmpty ? "unknown" : codecs.joined(separator: ", ")
    }

    var peakLevelText: String {
        formatLevel(peakLevel)
    }

    var rmsLevelText: String {
        formatLevel(rmsLevel)
    }

    var logDetails: [String] {
        [
            "file=\(fileName)",
            "size=\(fileSizeText)",
            "assetDuration=\(assetDurationText)",
            "audioTracks=\(audioTrackCount)",
            "codec=\(codecText)",
            "decodedFormat=\(decodedFormat)",
            "decodedDuration=\(formatDuration(decodedDuration))",
            "playerFormat=\(playerFormat)",
            "playerDuration=\(formatDuration(playerDuration))",
            "peak=\(peakLevelText)",
            "rms=\(rmsLevelText)",
            "warnings=\(warnings.map(\.rawValue).joined(separator: \",\"))"
        ]
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "unknown" }
        return String(format: "%.2fs", seconds)
    }

    private func formatLevel(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "-inf dBFS" }
        let decibels = 20 * log10(value)
        return String(format: "%.1f dBFS", decibels)
    }
}

private enum AudioFileProbeWarning: String, Identifiable, Equatable {
    case noAudioTrack
    case unreadableDuration
    case silentOrVeryLowPeak
    case lowAverageLevel
    case unusualChannelCount
    case unusualSampleRate

    var id: String {
        rawValue
    }
}

@MainActor
private final class AudioFileProbeManager: ObservableObject {
    private static let referenceFileName = "vmic-official-speech-reference.caf"
    private static let maximumAnalyzedSeconds: TimeInterval = 12
    private static let maximumFramesPerRead: AVAudioFramePosition = 16_384

    @Published private(set) var status: AudioFileProbeStatus = .idle
    @Published private(set) var referenceClip: SoundClip?

    private let speechSynthesizer = AVSpeechSynthesizer()

    var isBusy: Bool {
        status == .checking || status == .renderingReference
    }

    func inspect(_ clip: SoundClip, from directory: URL) async {
        status = .checking
        let url = clip.fileURL(in: directory)
        DiagnosticLogStore.shared.log(
            "开始音频文件体检",
            source: .audioFileProbe,
            details: [
                "title=\(clip.title)",
                "file=\(url.lastPathComponent)",
                "exists=\(FileManager.default.fileExists(atPath: url.path))"
            ]
        )

        do {
            let report = try makeReport(for: url)
            status = .checked(report)
            DiagnosticLogStore.shared.log(
                "音频文件体检完成",
                source: .audioFileProbe,
                details: report.logDetails
            )
        } catch {
            status = .failed(error.localizedDescription)
            DiagnosticLogStore.shared.log(
                "音频文件体检失败",
                source: .audioFileProbe,
                details: [
                    "file=\(url.lastPathComponent)",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    func generateReferenceClip(
        in directory: URL,
        phrase: String,
        title: String,
        artist: String
    ) async -> SoundClip? {
        status = .renderingReference
        let url = directory.appendingPathComponent(Self.referenceFileName)
        DiagnosticLogStore.shared.log(
            "开始生成官方语音文件基线",
            source: .audioFileProbe,
            details: ["file=\(url.lastPathComponent)", "textLength=\(phrase.count)"]
        )

        do {
            try await renderSpeechFile(to: url, text: phrase)
            let report = try makeReport(for: url)
            let clip = SoundClip(
                title: title,
                artist: artist,
                fileName: url.lastPathComponent,
                durationSeconds: report.decodedDuration ?? report.playerDuration ?? report.assetDuration
            )
            referenceClip = clip
            status = .referenceReady(report)
            DiagnosticLogStore.shared.log(
                "官方语音文件基线已生成",
                source: .audioFileProbe,
                details: report.logDetails
            )
            return clip
        } catch {
            status = .failed(error.localizedDescription)
            DiagnosticLogStore.shared.log(
                "官方语音文件基线生成失败",
                source: .audioFileProbe,
                details: ["error=\(error.localizedDescription)"]
            )
            return nil
        }
    }

    func markReferencePlaybackStarted() {
        if let report = status.report {
            status = .referencePlaybackStarted(report)
        }

        DiagnosticLogStore.shared.log("官方语音文件基线已交给文件播放路径", source: .audioFileProbe)
    }

    func markReferencePlaybackStopped() {
        status = .referencePlaybackStopped
        DiagnosticLogStore.shared.log("官方语音文件基线播放已停止", source: .audioFileProbe)
    }

    func markReferencePlaybackFailed(_ message: String) {
        status = .failed(message)
        DiagnosticLogStore.shared.log(
            "官方语音文件基线播放启动失败",
            source: .audioFileProbe,
            details: ["error=\(message)"]
        )
    }

    private func renderSpeechFile(to url: URL, text: String) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language == AVSpeechSynthesisVoice.currentLanguageCode() && $0.quality == .enhanced
        }
        utterance.volume = 1
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            var outputFile: AVAudioFile?

            speechSynthesizer.write(utterance) { buffer in
                guard !didResume else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    didResume = true
                    continuation.resume(throwing: AudioFileProbeError.nonPCMBuffer)
                    return
                }

                guard pcmBuffer.frameLength > 0 else {
                    didResume = true
                    outputFile = nil
                    continuation.resume(returning: ())
                    return
                }

                do {
                    if outputFile == nil {
                        outputFile = try AVAudioFile(forWriting: url, settings: pcmBuffer.format.settings)
                    }

                    try outputFile?.write(from: pcmBuffer)
                } catch {
                    didResume = true
                    outputFile = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeReport(for url: URL) throws -> AudioFileProbeReport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileProbeError.fileMissing
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        let tracks = asset.tracks(withMediaType: .audio)
        let assetDuration = validDuration(asset.duration.seconds)
        let audioFile = try AVAudioFile(forReading: url)
        let codecs = codecHints(from: url, fileFormat: audioFile.fileFormat)
        let decodedFormat = formatDescription(audioFile.processingFormat)
        let decodedDuration = duration(frameCount: audioFile.length, sampleRate: audioFile.processingFormat.sampleRate)
        let levels = try? measureLevels(in: audioFile)
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        let playerFormat = formatDescription(player.format)
        let playerDuration = validDuration(player.duration)
        let warnings = warnings(
            tracks: tracks,
            decodedFormat: audioFile.processingFormat,
            assetDuration: assetDuration,
            decodedDuration: decodedDuration,
            playerDuration: playerDuration,
            peak: levels?.peak,
            rms: levels?.rms
        )

        return AudioFileProbeReport(
            fileName: url.lastPathComponent,
            fileSizeBytes: fileSize,
            assetDuration: assetDuration,
            audioTrackCount: tracks.count,
            codecs: codecs,
            decodedFormat: decodedFormat,
            decodedDuration: decodedDuration,
            playerFormat: playerFormat,
            playerDuration: playerDuration,
            peakLevel: levels?.peak,
            rmsLevel: levels?.rms,
            warnings: warnings
        )
    }

    private func measureLevels(in audioFile: AVAudioFile) throws -> AudioFileLevels {
        let format = audioFile.processingFormat
        let maxFramesToRead = min(
            audioFile.length,
            AVAudioFramePosition(format.sampleRate * Self.maximumAnalyzedSeconds)
        )
        guard maxFramesToRead > 0 else {
            return AudioFileLevels(peak: nil, rms: nil)
        }

        audioFile.framePosition = 0
        var remainingFrames = maxFramesToRead
        var accumulator = AudioLevelAccumulator()

        while remainingFrames > 0 {
            let frameCount = AVAudioFrameCount(min(remainingFrames, Self.maximumFramesPerRead))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw AudioFileProbeError.cannotAnalyzeLevels
            }

            try audioFile.read(into: buffer, frameCount: frameCount)
            guard buffer.frameLength > 0 else { break }

            try accumulator.add(buffer)
            remainingFrames -= AVAudioFramePosition(buffer.frameLength)
        }

        return AudioFileLevels(
            peak: accumulator.sampleCount > 0 ? accumulator.peak : nil,
            rms: accumulator.sampleCount > 0 ? sqrt(accumulator.sumSquares / Double(accumulator.sampleCount)) : nil
        )
    }

    private func warnings(
        tracks: [AVAssetTrack],
        decodedFormat: AVAudioFormat,
        assetDuration: TimeInterval?,
        decodedDuration: TimeInterval?,
        playerDuration: TimeInterval?,
        peak: Double?,
        rms: Double?
    ) -> [AudioFileProbeWarning] {
        var warnings: [AudioFileProbeWarning] = []

        if tracks.isEmpty {
            warnings.append(.noAudioTrack)
        }

        if assetDuration == nil && decodedDuration == nil && playerDuration == nil {
            warnings.append(.unreadableDuration)
        }

        if let peak, peak < 0.01 {
            warnings.append(.silentOrVeryLowPeak)
        }

        if let rms, rms < 0.003 {
            warnings.append(.lowAverageLevel)
        }

        if decodedFormat.channelCount == 0 || decodedFormat.channelCount > 2 {
            warnings.append(.unusualChannelCount)
        }

        if decodedFormat.sampleRate < 8_000 || decodedFormat.sampleRate > 96_000 {
            warnings.append(.unusualSampleRate)
        }

        return warnings
    }

    private func formatDescription(_ format: AVAudioFormat) -> String {
        let layout = format.isInterleaved ? "interleaved" : "non-interleaved"
        return "\(Int(format.sampleRate.rounded())) Hz / \(format.channelCount) ch / \(commonFormatDescription(format.commonFormat)) / \(layout)"
    }

    private func codecHints(from url: URL, fileFormat: AVAudioFormat) -> [String] {
        var values: [String] = []

        let fileExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileExtension.isEmpty {
            values.append(fileExtension.uppercased())
        }

        if let formatID = (fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value {
            values.append(audioFormatIDDescription(formatID))
        }

        return Array(Set(values)).sorted()
    }

    private func commonFormatDescription(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .otherFormat:
            return "other"
        case .pcmFormatFloat32:
            return "float32"
        case .pcmFormatFloat64:
            return "float64"
        case .pcmFormatInt16:
            return "int16"
        case .pcmFormatInt32:
            return "int32"
        @unknown default:
            return "unknown"
        }
    }

    private func duration(frameCount: AVAudioFramePosition, sampleRate: Double) -> TimeInterval? {
        guard frameCount > 0, sampleRate > 0 else { return nil }
        return Double(frameCount) / sampleRate
    }

    private func validDuration(_ seconds: TimeInterval) -> TimeInterval? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func audioFormatIDDescription(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let text = String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "formatID:\(value)" : trimmed
    }
}

private struct AudioFileLevels: Equatable {
    let peak: Double?
    let rms: Double?
}

private struct AudioLevelAccumulator {
    var peak: Double = 0
    var sumSquares: Double = 0
    var sampleCount: Int = 0

    mutating func add(_ buffer: AVAudioPCMBuffer) throws {
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return }

        let pointerCount = buffer.format.isInterleaved ? 1 : channelCount
        let sampleCountPerPointer = frameCount * (buffer.format.isInterleaved ? channelCount : 1)

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else {
                throw AudioFileProbeError.cannotAnalyzeLevels
            }

            for pointerIndex in 0..<pointerCount {
                let pointer = data[pointerIndex]
                for sampleIndex in 0..<sampleCountPerPointer {
                    add(Double(pointer[sampleIndex]))
                }
            }
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else {
                throw AudioFileProbeError.cannotAnalyzeLevels
            }

            for pointerIndex in 0..<pointerCount {
                let pointer = data[pointerIndex]
                for sampleIndex in 0..<sampleCountPerPointer {
                    add(Double(pointer[sampleIndex]) / Double(Int16.max))
                }
            }
        case .pcmFormatInt32:
            guard let data = buffer.int32ChannelData else {
                throw AudioFileProbeError.cannotAnalyzeLevels
            }

            for pointerIndex in 0..<pointerCount {
                let pointer = data[pointerIndex]
                for sampleIndex in 0..<sampleCountPerPointer {
                    add(Double(pointer[sampleIndex]) / Double(Int32.max))
                }
            }
        case .otherFormat, .pcmFormatFloat64:
            throw AudioFileProbeError.cannotAnalyzeLevels
        @unknown default:
            throw AudioFileProbeError.cannotAnalyzeLevels
        }
    }

    private mutating func add(_ sample: Double) {
        let absoluteValue = abs(sample)
        peak = max(peak, absoluteValue)
        sumSquares += absoluteValue * absoluteValue
        sampleCount += 1
    }
}

private enum AudioFileProbeError: LocalizedError {
    case fileMissing
    case nonPCMBuffer
    case cannotAnalyzeLevels

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "音频文件不存在。"
        case .nonPCMBuffer:
            return "官方语音渲染没有返回 PCM 音频缓冲。"
        case .cannotAnalyzeLevels:
            return "无法分析当前音频文件的电平。"
        }
    }
}

private struct AudioFileProbeCopy {
    let title: String
    let detail: String
    let currentAudio: String
    let noAudio: String
    let inspectCurrentAudio: String
    let playReferenceAudioFile: String
    let stopReferenceAudioFile: String
    let ready: String
    let checking: String
    let checkedHealthy: String
    let checkedNeedsAttention: String
    let renderingReference: String
    let referenceReady: String
    let referenceNeedsAttention: String
    let referencePlaybackStarted: String
    let referencePlaybackStopped: String
    let instruction: String
    let fileSize: String
    let assetDuration: String
    let audioTracks: String
    let codec: String
    let decodedFormat: String
    let playerFormat: String
    let peakLevel: String
    let rmsLevel: String
    let verdict: String
    let noWarnings: String
    let referencePhrase: String
    let referenceTitle: String
    let referenceArtist: String
    let referencePlaybackDidNotStart: String

    func failed(_ message: String) -> String {
        switch title {
        case "音频文件排除工具":
            return "音频文件排除失败：\(message)"
        default:
            return "Audio file probe failed: \(message)"
        }
    }

    func warningText(_ warning: AudioFileProbeWarning) -> String {
        switch title {
        case "音频文件排除工具":
            switch warning {
            case .noAudioTrack:
                return "AVAsset 没有识别到音频轨道。"
            case .unreadableDuration:
                return "无法稳定读取时长。"
            case .silentOrVeryLowPeak:
                return "峰值电平很低，可能几乎没有有效声音。"
            case .lowAverageLevel:
                return "平均电平偏低，通话降噪可能会进一步压低。"
            case .unusualChannelCount:
                return "声道数不是常见的单声道/双声道。"
            case .unusualSampleRate:
                return "采样率不在常见范围内。"
            }
        default:
            switch warning {
            case .noAudioTrack:
                return "AVAsset did not find an audio track."
            case .unreadableDuration:
                return "The duration could not be read reliably."
            case .silentOrVeryLowPeak:
                return "Peak level is very low; the file may be nearly silent."
            case .lowAverageLevel:
                return "Average level is low; call processing may suppress it further."
            case .unusualChannelCount:
                return "The channel count is not common mono/stereo."
            case .unusualSampleRate:
                return "The sample rate is outside the common range."
            }
        }
    }

    static func make(language: AppLanguage) -> AudioFileProbeCopy {
        switch language {
        case .chinese:
            return AudioFileProbeCopy(
                title: "音频文件排除工具",
                detail: "检查当前文件是否正常，并把官方语音先渲染成文件再走文件播放链路。",
                currentAudio: "当前音频",
                noAudio: "请先在音频列表导入一个音频。",
                inspectCurrentAudio: "体检当前音频",
                playReferenceAudioFile: "播放基线文件",
                stopReferenceAudioFile: "停止基线文件",
                ready: "等待体检音频文件，或播放官方语音生成的基线文件。",
                checking: "正在读取文件、解码格式和电平。",
                checkedHealthy: "当前音频文件读写、解码和电平看起来正常。",
                checkedNeedsAttention: "当前音频文件可以读取，但有一些可能影响通话注入的风险。",
                renderingReference: "正在把官方语音渲染为音频文件。",
                referenceReady: "官方语音文件已生成，文件本身看起来正常。",
                referenceNeedsAttention: "官方语音文件已生成，但体检发现异常。",
                referencePlaybackStarted: "基线文件已交给文件播放链路；请让通话另一端确认是否能听到。",
                referencePlaybackStopped: "基线文件播放已停止。",
                instruction: "判断方法：如果官方实时语音能听到，但这个基线文件听不到，基本可以排除你的 MP3 文件，问题更可能在 iOS 对文件播放来源的注入限制。",
                fileSize: "文件大小",
                assetDuration: "时长",
                audioTracks: "音频轨",
                codec: "编码",
                decodedFormat: "解码格式",
                playerFormat: "播放器格式",
                peakLevel: "峰值",
                rmsLevel: "平均电平",
                verdict: "结论",
                noWarnings: "未发现明显文件问题。",
                referencePhrase: "这是 vmic 生成的官方语音文件基线，请确认通话另一端是否能清楚听到。",
                referenceTitle: "官方语音文件基线",
                referenceArtist: "vmic 调试",
                referencePlaybackDidNotStart: "文件播放器没有启动基线文件。"
            )
        case .english:
            return AudioFileProbeCopy(
                title: "Audio File Probe",
                detail: "Checks the current file, then renders official speech into a file and plays it through the file path.",
                currentAudio: "Current Audio",
                noAudio: "Import an audio file in the audio list first.",
                inspectCurrentAudio: "Inspect File",
                playReferenceAudioFile: "Play Reference File",
                stopReferenceAudioFile: "Stop Reference File",
                ready: "Waiting to inspect a file or play the official-speech reference file.",
                checking: "Reading file metadata, decode format, and levels.",
                checkedHealthy: "The current audio file looks readable, decodable, and loud enough.",
                checkedNeedsAttention: "The current audio file is readable, but has risks that may affect call injection.",
                renderingReference: "Rendering official speech into an audio file.",
                referenceReady: "The official-speech reference file was generated and looks healthy.",
                referenceNeedsAttention: "The reference file was generated, but the probe found warnings.",
                referencePlaybackStarted: "The reference file is now using the file playback path. Ask the remote side whether they hear it.",
                referencePlaybackStopped: "Reference file playback stopped.",
                instruction: "How to read this: if live official speech works but this reference file does not, your MP3 is probably not the cause; the issue is more likely iOS injection behavior for file playback sources.",
                fileSize: "File Size",
                assetDuration: "Duration",
                audioTracks: "Audio Tracks",
                codec: "Codec",
                decodedFormat: "Decode Format",
                playerFormat: "Player Format",
                peakLevel: "Peak",
                rmsLevel: "RMS",
                verdict: "Verdict",
                noWarnings: "No obvious file issue found.",
                referencePhrase: "This is a vmic official speech file reference. Please confirm whether the remote side can hear it clearly.",
                referenceTitle: "Official Speech File Reference",
                referenceArtist: "vmic debug",
                referencePlaybackDidNotStart: "The file player did not start the reference file."
            )
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

    let status: PlaybackSelfCheckStatus

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
        case .running(.normalPlayback):
            return settingsStore.text(.experimentNormalPlaybackRunning)
        case .running(.mutedPlayback):
            return settingsStore.text(.experimentMutedPlaybackRunning)
        case .finished(.normalPlayback):
            return settingsStore.text(.experimentNormalPlaybackFinished)
        case .finished(.mutedPlayback):
            return settingsStore.text(.experimentMutedPlaybackFinished)
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
            let session = AVAudioSession.sharedInstance()
            DiagnosticLogStore.shared.log(
                "官方语音对照开始",
                source: .speechProbe,
                details: ["textLength=\(text.count)"] + Self.audioSessionDetails(session)
            )
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
                try session.setActive(true)
                DiagnosticLogStore.shared.log(
                    "官方语音音频会话已激活",
                    source: .speechProbe,
                    details: Self.audioSessionDetails(session)
                )
            } catch {
                DiagnosticLogStore.shared.log(
                    "官方语音音频会话激活失败，继续尝试",
                    source: .speechProbe,
                    details: ["error=\(error.localizedDescription)"] + Self.audioSessionDetails(session)
                )
            }
            try reapplyInjectionPreference?()
            DiagnosticLogStore.shared.log(
                "官方语音注入偏好已重申",
                source: .speechProbe,
                details: Self.audioSessionDetails(session)
            )

            if synthesizer.isSpeaking {
                DiagnosticLogStore.shared.log("停止上一段官方语音", source: .speechProbe)
                synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)
            let enhancedVoice = AVSpeechSynthesisVoice.speechVoices().first {
                $0.language == AVSpeechSynthesisVoice.currentLanguageCode() && $0.quality == .enhanced
            }
            utterance.voice = enhancedVoice
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
                ] + Self.audioSessionDetails(session)
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

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            DiagnosticLogStore.shared.log(
                "官方语音对照开始朗读",
                source: .speechProbe,
                details: [
                    "voice=\(utterance.voice?.identifier ?? "default")",
                    "language=\(utterance.voice?.language ?? "unknown")"
                ]
            )
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.status = .stopped
            DiagnosticLogStore.shared.log("官方语音对照已取消", source: .speechProbe)
        }
    }

    private static func audioSessionDetails(_ session: AVAudioSession) -> [String] {
        var details = [
            "category=\(session.category.rawValue)",
            "mode=\(session.mode.rawValue)",
            "options=\(session.categoryOptions.rawValue)",
            "sampleRate=\(Int(session.sampleRate.rounded()))",
            "inputs=\(session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ","))",
            "outputs=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
        ]

        if #available(iOS 18.2, *) {
            details.append("preferred=\(microphoneInjectionModeDescription(session.preferredMicrophoneInjectionMode))")
            details.append("available=\(session.isMicrophoneInjectionAvailable)")
        }

        return details
    }

    private static func microphoneInjectionModeDescription(_ mode: AVAudioSession.MicrophoneInjectionMode) -> String {
        switch mode {
        case .none:
            return "none"
        case .spokenAudio:
            return "spokenAudio"
        @unknown default:
            return "unknown"
        }
    }
}

private enum PlaybackSelfCheckKind: Equatable {
    case normalPlayback
    case mutedPlayback

    var logName: String {
        switch self {
        case .normalPlayback:
            return "normalPlayback"
        case .mutedPlayback:
            return "mutedPlayback"
        }
    }
}

private enum PlaybackSelfCheckStatus: Equatable {
    case idle
    case running(PlaybackSelfCheckKind)
    case finished(PlaybackSelfCheckKind)
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
private final class PlaybackSelfCheckManager: NSObject, ObservableObject {
    private static let maximumTestDuration: TimeInterval = 12

    @Published var localPlaybackVolume: Double = 1 {
        didSet {
            updateVolume()
        }
    }
    @Published private(set) var status: PlaybackSelfCheckStatus = .idle

    private var player: AVAudioPlayer?
    private var finishTask: Task<Void, Never>?
    private var lastLoggedVolumeBucket: Int?

    var isRunning: Bool {
        if case .running = status {
            return true
        }

        return false
    }

    func playNormalPlayback(
        _ clip: SoundClip,
        from directory: URL,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        DiagnosticLogStore.shared.log(
            "请求正常播放自检",
            source: .playbackSelfCheck,
            details: ["title=\(clip.title)"]
        )
        localPlaybackVolume = 1
        play(
            clip,
            from: directory,
            kind: .normalPlayback,
            reapplyInjectionPreference: reapplyInjectionPreference
        )
    }

    func playMutedPlayback(
        _ clip: SoundClip,
        from directory: URL,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        DiagnosticLogStore.shared.log(
            "请求静音播放自检",
            source: .playbackSelfCheck,
            details: ["title=\(clip.title)"]
        )
        localPlaybackVolume = 0
        play(
            clip,
            from: directory,
            kind: .mutedPlayback,
            reapplyInjectionPreference: reapplyInjectionPreference
        )
    }

    func stop() {
        DiagnosticLogStore.shared.log(
            "停止播放链路自检",
            source: .playbackSelfCheck,
            details: ["status=\(status.logName)"]
        )
        stopPlayerOnly()
        status = .stopped
    }

    private func play(
        _ clip: SoundClip,
        from directory: URL,
        kind: PlaybackSelfCheckKind,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        let url = clip.fileURL(in: directory)
        DiagnosticLogStore.shared.log(
            "播放链路自检准备播放",
            source: .playbackSelfCheck,
            details: [
                "kind=\(kind.logName)",
                "title=\(clip.title)",
                "file=\(url.lastPathComponent)",
                "exists=\(FileManager.default.fileExists(atPath: url.path))"
            ]
        )

        do {
            stopPlayerOnly()

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = currentVolume(for: kind)
            player.prepareToPlay()
            try configureAudioSession(reapplyInjectionPreference: reapplyInjectionPreference)

            guard player.play() else {
                throw PlaybackSelfCheckError.playbackDidNotStart
            }

            try reapplyInjectionPreference?()
            DiagnosticLogStore.shared.log(
                "播放链路自检发声后已按官方式路径重申注入偏好",
                source: .playbackSelfCheck,
                details: Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )

            self.player = player
            status = .running(kind)
            DiagnosticLogStore.shared.log(
                "播放链路自检已启动",
                source: .playbackSelfCheck,
                details: [
                    "kind=\(kind.logName)",
                    "volume=\(formatPercent(Double(player.volume)))",
                    "duration=\(formatSeconds(player.duration))",
                    "sampleRate=\(Int(player.format.sampleRate.rounded()))",
                    "channels=\(player.format.channelCount)"
                ]
            )
            scheduleFinish(duration: testDuration(for: player), kind: kind)
        } catch {
            stopPlayerOnly()
            status = .failed(error.localizedDescription)
            DiagnosticLogStore.shared.log(
                "播放链路自检失败",
                source: .playbackSelfCheck,
                details: [
                    "kind=\(kind.logName)",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    private func updateVolume() {
        guard isRunning, let player else { return }

        if case .running(let kind) = status {
            player.volume = currentVolume(for: kind)
        }

        let percent = Int((Double(player.volume) * 100).rounded())
        let bucket = percent / 5

        guard bucket != lastLoggedVolumeBucket else { return }

        lastLoggedVolumeBucket = bucket
        DiagnosticLogStore.shared.log(
            "播放链路自检音量更新",
            source: .playbackSelfCheck,
            details: [
                "status=\(status.logName)",
                "volume=\(percent)%"
            ]
        )
    }

    private func currentVolume(for kind: PlaybackSelfCheckKind) -> Float {
        switch kind {
        case .normalPlayback:
            return Float(clamped(localPlaybackVolume))
        case .mutedPlayback:
            return 0
        }
    }

    private func testDuration(for player: AVAudioPlayer) -> TimeInterval {
        guard player.duration.isFinite, player.duration > 0 else {
            return Self.maximumTestDuration
        }

        return min(player.duration, Self.maximumTestDuration)
    }

    private func scheduleFinish(duration: TimeInterval, kind: PlaybackSelfCheckKind) {
        finishTask?.cancel()

        let wait = UInt64(max(duration + 0.2, 0.5) * 1_000_000_000)

        finishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)

            await MainActor.run {
                guard let self, self.status == .running(kind) else { return }

                self.stopPlayerOnly()
                self.status = .finished(kind)
                DiagnosticLogStore.shared.log(
                    "播放链路自检自然结束",
                    source: .playbackSelfCheck,
                    details: ["kind=\(kind.logName)"]
                )
            }
        }
    }

    private func stopPlayerOnly() {
        finishTask?.cancel()
        finishTask = nil
        player?.stop()
        player = nil
        lastLoggedVolumeBucket = nil
    }

    private func configureAudioSession(reapplyInjectionPreference: (@MainActor () throws -> Void)?) throws {
        let session = AVAudioSession.sharedInstance()
        DiagnosticLogStore.shared.log(
            "播放链路自检配置官方式会话开始",
            source: .playbackSelfCheck,
            details: Self.audioSessionDetails(session)
        )
        try reapplyInjectionPreference?()
        DiagnosticLogStore.shared.log(
            "播放链路自检配置官方式会话完成",
            source: .playbackSelfCheck,
            details: [
                "policy=preferredInjectionOnly",
                "categoryChangedByVmic=false",
                "activeChangedByVmic=false"
            ] + Self.audioSessionDetails(session)
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "unknown" }
        return String(format: "%.2fs", seconds)
    }

    private static func audioSessionDetails(_ session: AVAudioSession) -> [String] {
        var details = [
            "category=\(session.category.rawValue)",
            "mode=\(session.mode.rawValue)",
            "options=\(session.categoryOptions.rawValue)",
            "sampleRate=\(Int(session.sampleRate.rounded()))",
            "inputs=\(session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ","))",
            "outputs=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
        ]

        if #available(iOS 18.2, *) {
            details.append("preferred=\(microphoneInjectionModeDescription(session.preferredMicrophoneInjectionMode))")
            details.append("available=\(session.isMicrophoneInjectionAvailable)")
        }

        return details
    }

    private static func microphoneInjectionModeDescription(_ mode: AVAudioSession.MicrophoneInjectionMode) -> String {
        switch mode {
        case .none:
            return "none"
        case .spokenAudio:
            return "spokenAudio"
        @unknown default:
            return "unknown"
        }
    }
}

private enum PlaybackSelfCheckError: LocalizedError {
    case playbackDidNotStart

    var errorDescription: String? {
        switch self {
        case .playbackDidNotStart:
            return "系统没有启动本机音频播放。"
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
