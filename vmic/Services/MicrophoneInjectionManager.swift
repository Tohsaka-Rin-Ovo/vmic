import AVFAudio
import Accessibility
import Foundation
import UIKit

enum InjectionPermissionState: Equatable {
    case checking
    case unsupportedOS(version: String)
    case serviceDisabled
    case undetermined
    case denied
    case granted
    case unknown

    @MainActor
    func title(using settings: AppSettingsStore) -> String {
        switch self {
        case .checking:
            return settings.text(.permissionChecking)
        case .unsupportedOS:
            return settings.text(.permissionUnsupportedOS)
        case .serviceDisabled:
            return settings.text(.permissionServiceDisabled)
        case .undetermined:
            return settings.text(.permissionUndetermined)
        case .denied:
            return settings.text(.permissionDenied)
        case .granted:
            return settings.text(.permissionGranted)
        case .unknown:
            return settings.text(.permissionUnknown)
        }
    }

    @MainActor
    func detail(using settings: AppSettingsStore) -> String {
        switch self {
        case .checking:
            return settings.text(.detailChecking)
        case .unsupportedOS(let version):
            return settings.text(.detailUnsupportedOS(version))
        case .serviceDisabled:
            return settings.text(.detailServiceDisabled)
        case .undetermined:
            return settings.text(.detailUndetermined)
        case .denied:
            return settings.text(.detailDenied)
        case .granted:
            return settings.text(.detailGranted)
        case .unknown:
            return settings.text(.detailUnknown)
        }
    }

    var canRequestPermission: Bool {
        self == .undetermined
    }

    var canEnableInjection: Bool {
        self == .granted
    }
}

enum InjectionModeChangeResult: Equatable {
    case unsupportedOS(version: String)
    case permissionRequired(state: InjectionPermissionState)
    case enabled(channelAvailable: Bool)
    case disabled
    case busy
    case failed(message: String)
}

struct AudioSessionDiagnostics: Equatable {
    let capturedAt: Date
    let category: String
    let mode: String
    let preferredMicrophoneInjectionMode: String?
    let microphoneInjectionAvailable: Bool?
    let inputPortTypes: [String]
    let outputPortTypes: [String]
    let inputPortNames: [String]
    let outputPortNames: [String]
    let sampleRate: Double
    let inputChannelCount: Int
    let outputChannelCount: Int
    let lastRouteChangeReason: String?
    let lastRouteChangeAt: Date?

    static func capture(lastRouteChangeReason: String? = nil, lastRouteChangeAt: Date? = nil) -> AudioSessionDiagnostics {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute
        let microphoneInjectionAvailable: Bool?
        let preferredMicrophoneInjectionMode: String?

        if #available(iOS 18.2, *) {
            microphoneInjectionAvailable = session.isMicrophoneInjectionAvailable
            preferredMicrophoneInjectionMode = Self.microphoneInjectionModeDescription(session.preferredMicrophoneInjectionMode)
        } else {
            microphoneInjectionAvailable = nil
            preferredMicrophoneInjectionMode = nil
        }

        return AudioSessionDiagnostics(
            capturedAt: Date(),
            category: session.category.rawValue,
            mode: session.mode.rawValue,
            preferredMicrophoneInjectionMode: preferredMicrophoneInjectionMode,
            microphoneInjectionAvailable: microphoneInjectionAvailable,
            inputPortTypes: currentRoute.inputs.map { $0.portType.rawValue },
            outputPortTypes: currentRoute.outputs.map { $0.portType.rawValue },
            inputPortNames: currentRoute.inputs.map { $0.portName },
            outputPortNames: currentRoute.outputs.map { $0.portName },
            sampleRate: session.sampleRate,
            inputChannelCount: session.inputNumberOfChannels,
            outputChannelCount: session.outputNumberOfChannels,
            lastRouteChangeReason: lastRouteChangeReason,
            lastRouteChangeAt: lastRouteChangeAt
        )
    }

    @available(iOS 18.2, *)
    private static func microphoneInjectionModeDescription(_ mode: AVAudioSession.MicrophoneInjectionMode) -> String {
        switch mode {
        case .none:
            return "none"
        case .spokenAudio:
            return "spokenAudio"
        @unknown default:
            return "unknown(\(mode.rawValue))"
        }
    }
}

@MainActor
final class MicrophoneInjectionManager: ObservableObject {
    @Published private(set) var permissionState: InjectionPermissionState = .checking
    @Published private(set) var isInjectionEnabled = false
    @Published private(set) var isInjectionAvailableInCurrentCall = false
    @Published private(set) var lastNotifiedInjectionAvailability: Bool?
    @Published private(set) var audioSessionDiagnostics = AudioSessionDiagnostics.capture()
    @Published private(set) var isChangingInjectionMode = false
    @Published private(set) var pendingInjectionMode: Bool?
    @Published private(set) var lastModeChangeResult: InjectionModeChangeResult?
    @Published private(set) var lastModeChangeResultAt: Date?
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastCapabilitiesChangeAt: Date?
    @Published private(set) var lastInjectionModeChangeAt: Date?
    @Published private(set) var lastMediaServicesResetAt: Date?
    @Published private(set) var lastRouteChangeAt: Date?
    @Published private(set) var lastRouteChangeReason: String?
    @Published var lastError: String?

    var channelDiagnosticsReport: String {
        [
            "当前 AVAudioSession Category: \(audioSessionDiagnostics.category)",
            "当前 Mode: \(audioSessionDiagnostics.mode)",
            "期望注入模式: \(audioSessionDiagnostics.preferredMicrophoneInjectionMode ?? "unsupported")",
            "麦克风注入是否可用: \(debugValue(audioSessionDiagnostics.microphoneInjectionAvailable))",
            "通知通道状态: \(debugValue(lastNotifiedInjectionAvailability))",
            "当前输入端口: \(audioSessionDiagnostics.inputPortTypes)",
            "当前输出端口: \(audioSessionDiagnostics.outputPortTypes)",
            "当前输入设备: \(audioSessionDiagnostics.inputPortNames)",
            "当前输出设备: \(audioSessionDiagnostics.outputPortNames)",
            "采样率: \(audioSessionDiagnostics.sampleRate)",
            "输入声道: \(audioSessionDiagnostics.inputChannelCount)",
            "输出声道: \(audioSessionDiagnostics.outputChannelCount)",
            "权限状态: \(debugValue(permissionState))",
            "注入开关: \(isInjectionEnabled)",
            "上次通道事件: \(debugValue(lastCapabilitiesChangeAt))",
            "上次媒体服务重置: \(debugValue(lastMediaServicesResetAt))",
            "上次路由变化: \(debugValue(lastRouteChangeAt))",
            "路由变化原因: \(lastRouteChangeReason ?? "none")"
        ].joined(separator: "\n")
    }

    private var capabilitiesObserverTask: Task<Void, Never>?
    private var routeObserverTask: Task<Void, Never>?
    private var mediaServicesObserverTask: Task<Void, Never>?

    init() {
        capabilitiesObserverTask = Task { [weak self] in
            await self?.observeCapabilities()
        }
        routeObserverTask = Task { [weak self] in
            await self?.observeRouteChanges()
        }
        mediaServicesObserverTask = Task { [weak self] in
            await self?.observeMediaServicesReset()
        }
    }

    deinit {
        capabilitiesObserverTask?.cancel()
        routeObserverTask?.cancel()
        mediaServicesObserverTask?.cancel()
    }

    func refresh(printDiagnostics: Bool = false) async {
        DiagnosticLogStore.shared.log(
            "刷新注入状态开始",
            source: .injection,
            details: [
                "system=iOS \(UIDevice.current.systemVersion)",
                "printDiagnostics=\(printDiagnostics)"
            ]
        )
        lastRefreshAt = Date()
        refreshAudioSessionDiagnostics(printToConsole: printDiagnostics)

        guard #available(iOS 18.2, *) else {
            permissionState = .unsupportedOS(version: UIDevice.current.systemVersion)
            isInjectionEnabled = false
            isInjectionAvailableInCurrentCall = false
            DiagnosticLogStore.shared.log(
                "刷新注入状态结束：系统版本不支持",
                source: .injection,
                details: ["permission=\(debugValue(permissionState))"]
            )
            return
        }

        permissionState = Self.map(AVAudioApplication.shared.microphoneInjectionPermission)
        DiagnosticLogStore.shared.log(
            "刷新注入状态结束",
            source: .injection,
            details: [
                "permission=\(debugValue(permissionState))",
                "available=\(debugValue(audioSessionDiagnostics.microphoneInjectionAvailable))",
                "preferred=\(audioSessionDiagnostics.preferredMicrophoneInjectionMode ?? "unsupported")",
                "enabled=\(isInjectionEnabled)"
            ]
        )
    }

    func refreshAudioSessionDiagnostics(printToConsole: Bool = false, updatesModeResult: Bool = true) {
        let diagnostics = AudioSessionDiagnostics.capture(
            lastRouteChangeReason: lastRouteChangeReason,
            lastRouteChangeAt: lastRouteChangeAt
        )
        audioSessionDiagnostics = diagnostics

        if let microphoneInjectionAvailable = diagnostics.microphoneInjectionAvailable {
            isInjectionAvailableInCurrentCall = microphoneInjectionAvailable
        }

        if updatesModeResult, isInjectionEnabled, let microphoneInjectionAvailable = diagnostics.microphoneInjectionAvailable {
            _ = publishModeChangeResult(.enabled(channelAvailable: microphoneInjectionAvailable))
        }

        if printToConsole {
            print(channelDiagnosticsReport)
        }

        DiagnosticLogStore.shared.log(
            "采集音频会话",
            source: .injection,
            details: [
                "category=\(diagnostics.category)",
                "mode=\(diagnostics.mode)",
                "preferred=\(diagnostics.preferredMicrophoneInjectionMode ?? "unsupported")",
                "available=\(debugValue(diagnostics.microphoneInjectionAvailable))",
                "inputs=\(diagnostics.inputPortTypes.joined(separator: ","))",
                "outputs=\(diagnostics.outputPortTypes.joined(separator: ","))"
            ]
        )
    }

    func copyAudioSessionDiagnosticsToPasteboard() {
        refreshAudioSessionDiagnostics(printToConsole: true)
        UIPasteboard.general.string = channelDiagnosticsReport
        DiagnosticLogStore.shared.log("已复制通道诊断", source: .injection)
    }

    func requestPermission() async {
        DiagnosticLogStore.shared.log("请求麦克风注入权限开始", source: .injection)

        guard #available(iOS 18.2, *) else {
            await refresh()
            return
        }

        let result = await withCheckedContinuation { continuation in
            AVAudioApplication.requestMicrophoneInjectionPermission { permission in
                continuation.resume(returning: permission)
            }
        }

        permissionState = Self.map(result)
        DiagnosticLogStore.shared.log(
            "请求麦克风注入权限结束",
            source: .injection,
            details: ["permission=\(debugValue(permissionState))"]
        )
    }

    @discardableResult
    func setInjectionEnabled(_ enabled: Bool) async -> InjectionModeChangeResult {
        DiagnosticLogStore.shared.log(
            "请求切换注入开关",
            source: .injection,
            details: ["target=\(enabled)", "current=\(isInjectionEnabled)"]
        )

        guard #available(iOS 18.2, *) else {
            await refresh()
            DiagnosticLogStore.shared.log(
                "切换注入开关失败：系统版本不支持",
                source: .injection,
                details: ["system=iOS \(UIDevice.current.systemVersion)"]
            )
            return publishModeChangeResult(.unsupportedOS(version: UIDevice.current.systemVersion))
        }

        guard !enabled || permissionState.canEnableInjection else {
            isInjectionEnabled = false
            DiagnosticLogStore.shared.log(
                "切换注入开关失败：权限未就绪",
                source: .injection,
                details: ["permission=\(debugValue(permissionState))"]
            )
            return publishModeChangeResult(.permissionRequired(state: permissionState))
        }

        guard !isChangingInjectionMode else {
            DiagnosticLogStore.shared.log("切换注入开关被跳过：已有操作进行中", source: .injection)
            return publishModeChangeResult(.busy)
        }

        isChangingInjectionMode = true
        pendingInjectionMode = enabled

        do {
            if enabled {
                prepareAppAudioSessionForInjection(reason: "enableInjection")
            }
            try AVAudioSession.sharedInstance().setPreferredMicrophoneInjectionMode(enabled ? .spokenAudio : .none)
            isInjectionEnabled = enabled
            lastInjectionModeChangeAt = Date()
            lastError = nil
            refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)
            isChangingInjectionMode = false
            pendingInjectionMode = nil
            DiagnosticLogStore.shared.log(
                "切换注入开关成功",
                source: .injection,
                details: [
                    "enabled=\(isInjectionEnabled)",
                    "available=\(isInjectionAvailableInCurrentCall)",
                    "preferred=\(audioSessionDiagnostics.preferredMicrophoneInjectionMode ?? "unsupported")"
                ]
            )
            return publishModeChangeResult(enabled ? .enabled(channelAvailable: isInjectionAvailableInCurrentCall) : .disabled)
        } catch {
            isInjectionEnabled = false
            lastInjectionModeChangeAt = Date()
            lastError = error.localizedDescription
            isChangingInjectionMode = false
            pendingInjectionMode = nil
            DiagnosticLogStore.shared.log(
                "切换注入开关失败：系统拒绝",
                source: .injection,
                details: ["error=\(error.localizedDescription)"]
            )
            return publishModeChangeResult(.failed(message: error.localizedDescription))
        }
    }

    func reapplyInjectionPreferenceIfNeeded() throws {
        guard isInjectionEnabled else {
            DiagnosticLogStore.shared.log("跳过重申注入偏好：开关未开启", source: .injection)
            return
        }

        if #available(iOS 18.2, *) {
            do {
                DiagnosticLogStore.shared.log("重申注入偏好开始", source: .injection)
                prepareAppAudioSessionForInjection(reason: "reapplyInjectionPreference")
                try AVAudioSession.sharedInstance().setPreferredMicrophoneInjectionMode(.spokenAudio)
                lastInjectionModeChangeAt = Date()
                lastError = nil
                refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)
                _ = publishModeChangeResult(.enabled(channelAvailable: isInjectionAvailableInCurrentCall))
                DiagnosticLogStore.shared.log(
                    "重申注入偏好成功",
                    source: .injection,
                    details: [
                        "available=\(isInjectionAvailableInCurrentCall)",
                        "preferred=\(audioSessionDiagnostics.preferredMicrophoneInjectionMode ?? "unsupported")"
                    ]
                )
            } catch {
                lastInjectionModeChangeAt = Date()
                lastError = error.localizedDescription
                _ = publishModeChangeResult(.failed(message: error.localizedDescription))
                DiagnosticLogStore.shared.log(
                    "重申注入偏好失败",
                    source: .injection,
                    details: ["error=\(error.localizedDescription)"]
                )
                throw error
            }
        }
    }

    private func prepareAppAudioSessionForInjection(reason: String) {
        let session = AVAudioSession.sharedInstance()
        DiagnosticLogStore.shared.log(
            "准备通话注入音频会话",
            source: .injection,
            details: [
                "reason=\(reason)",
                "categoryBefore=\(session.category.rawValue)",
                "modeBefore=\(session.mode.rawValue)",
                "optionsBefore=\(session.categoryOptions.rawValue)"
            ]
        )

        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
            refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)
            DiagnosticLogStore.shared.log(
                "通话注入音频会话已准备",
                source: .injection,
                details: [
                    "reason=\(reason)",
                    "category=\(session.category.rawValue)",
                    "mode=\(session.mode.rawValue)",
                    "options=\(session.categoryOptions.rawValue)"
                ]
            )
        } catch {
            DiagnosticLogStore.shared.log(
                "通话注入音频会话准备失败，继续尝试注入偏好",
                source: .injection,
                details: [
                    "reason=\(reason)",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    func openAddAudioInCallsSettings() async {
        DiagnosticLogStore.shared.log("打开系统通话音频设置", source: .injection)

        guard #available(iOS 18.2, *) else {
            openAppSettings()
            return
        }

        do {
            try await AccessibilitySettings.openSettings(for: .allowAppsToAddAudioToCalls)
        } catch {
            lastError = error.localizedDescription
            DiagnosticLogStore.shared.log(
                "打开系统通话音频设置失败，回退到 App 设置",
                source: .injection,
                details: ["error=\(error.localizedDescription)"]
            )
            openAppSettings()
        }
    }

    func openSoftwareUpdateSettings() {
        DiagnosticLogStore.shared.log("打开系统更新设置", source: .app)
        // This deep link is intended for personal builds. Apple does not provide
        // a fully stable public URL for the Software Update screen.
        if let url = URL(string: "App-prefs:General&path=SOFTWARE_UPDATE_LINK") {
            UIApplication.shared.open(url)
        } else {
            openAppSettings()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func observeCapabilities() async {
        guard #available(iOS 18.2, *) else { return }

        for await notification in NotificationCenter.default.notifications(named: AVAudioSession.microphoneInjectionCapabilitiesChangeNotification) {
            let available = notification.userInfo?[AVAudioSessionMicrophoneInjectionIsAvailableKey] as? Bool ?? false
            lastNotifiedInjectionAvailability = available
            isInjectionAvailableInCurrentCall = available
            lastCapabilitiesChangeAt = Date()
            refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)

            if isInjectionEnabled {
                _ = publishModeChangeResult(.enabled(channelAvailable: isInjectionAvailableInCurrentCall))
            }

            DiagnosticLogStore.shared.log(
                "收到注入通道能力通知",
                source: .injection,
                details: [
                    "available=\(available)",
                    "enabled=\(isInjectionEnabled)"
                ]
            )
        }
    }

    private func observeRouteChanges() async {
        for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
            lastRouteChangeAt = Date()
            lastRouteChangeReason = Self.routeChangeReason(from: notification)
            refreshAudioSessionDiagnostics(printToConsole: true)
            DiagnosticLogStore.shared.log(
                "收到音频路由变化通知",
                source: .injection,
                details: [
                    "reason=\(lastRouteChangeReason ?? "unknown")",
                    "inputs=\(audioSessionDiagnostics.inputPortTypes.joined(separator: ","))",
                    "outputs=\(audioSessionDiagnostics.outputPortTypes.joined(separator: ","))"
                ]
            )
        }
    }

    private func observeMediaServicesReset() async {
        for await notification in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
            lastMediaServicesResetAt = Date()
            DiagnosticLogStore.shared.log(
                "媒体服务已重置",
                source: .injection,
                details: [
                    "notification=\(notification.name.rawValue)",
                    "enabled=\(isInjectionEnabled)"
                ]
            )

            if isInjectionEnabled {
                do {
                    try reapplyInjectionPreferenceIfNeeded()
                } catch {
                    lastError = error.localizedDescription
                    DiagnosticLogStore.shared.log(
                        "媒体服务重置后恢复注入失败",
                        source: .injection,
                        details: ["error=\(error.localizedDescription)"]
                    )
                }
            } else {
                refreshAudioSessionDiagnostics(printToConsole: true)
            }
        }
    }

    private func publishModeChangeResult(_ result: InjectionModeChangeResult) -> InjectionModeChangeResult {
        lastModeChangeResult = result
        lastModeChangeResultAt = Date()
        return result
    }

    private func debugValue(_ value: Bool?) -> String {
        guard let value else {
            return "unsupported"
        }

        return value ? "true" : "false"
    }

    private func debugValue(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }

        return date.formatted(date: .numeric, time: .standard)
    }

    private func debugValue(_ state: InjectionPermissionState) -> String {
        switch state {
        case .checking:
            return "checking"
        case .unsupportedOS(let version):
            return "unsupportedOS(\(version))"
        case .serviceDisabled:
            return "serviceDisabled"
        case .undetermined:
            return "undetermined"
        case .denied:
            return "denied"
        case .granted:
            return "granted"
        case .unknown:
            return "unknown"
        }
    }

    private static func routeChangeReason(from notification: Notification) -> String? {
        guard
            let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue.uintValue)
        else {
            return nil
        }

        switch reason {
        case .unknown:
            return "unknown"
        case .newDeviceAvailable:
            return "newDeviceAvailable"
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .categoryChange:
            return "categoryChange"
        case .override:
            return "override"
        case .wakeFromSleep:
            return "wakeFromSleep"
        case .noSuitableRouteForCategory:
            return "noSuitableRouteForCategory"
        case .routeConfigurationChange:
            return "routeConfigurationChange"
        @unknown default:
            return "unknown"
        }
    }

    @available(iOS 18.2, *)
    private static func map(_ permission: AVAudioApplication.MicrophoneInjectionPermission) -> InjectionPermissionState {
        switch permission {
        case .serviceDisabled:
            return .serviceDisabled
        case .undetermined:
            return .undetermined
        case .denied:
            return .denied
        case .granted:
            return .granted
        @unknown default:
            return .unknown
        }
    }
}
