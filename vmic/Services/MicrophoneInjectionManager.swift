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

        if #available(iOS 18.2, *) {
            microphoneInjectionAvailable = session.isMicrophoneInjectionAvailable
        } else {
            microphoneInjectionAvailable = nil
        }

        return AudioSessionDiagnostics(
            capturedAt: Date(),
            category: session.category.rawValue,
            mode: session.mode.rawValue,
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
    @Published private(set) var lastRouteChangeAt: Date?
    @Published private(set) var lastRouteChangeReason: String?
    @Published var lastError: String?

    var channelDiagnosticsReport: String {
        [
            "当前 AVAudioSession Category: \(audioSessionDiagnostics.category)",
            "当前 Mode: \(audioSessionDiagnostics.mode)",
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
            "上次路由变化: \(debugValue(lastRouteChangeAt))",
            "路由变化原因: \(lastRouteChangeReason ?? "none")"
        ].joined(separator: "\n")
    }

    private var capabilitiesObserverTask: Task<Void, Never>?
    private var routeObserverTask: Task<Void, Never>?

    init() {
        capabilitiesObserverTask = Task { [weak self] in
            await self?.observeCapabilities()
        }
        routeObserverTask = Task { [weak self] in
            await self?.observeRouteChanges()
        }
    }

    deinit {
        capabilitiesObserverTask?.cancel()
        routeObserverTask?.cancel()
    }

    func refresh(printDiagnostics: Bool = false) async {
        lastRefreshAt = Date()
        refreshAudioSessionDiagnostics(printToConsole: printDiagnostics)

        guard #available(iOS 18.2, *) else {
            permissionState = .unsupportedOS(version: UIDevice.current.systemVersion)
            isInjectionEnabled = false
            isInjectionAvailableInCurrentCall = false
            return
        }

        permissionState = Self.map(AVAudioApplication.shared.microphoneInjectionPermission)
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
    }

    func copyAudioSessionDiagnosticsToPasteboard() {
        refreshAudioSessionDiagnostics(printToConsole: true)
        UIPasteboard.general.string = channelDiagnosticsReport
    }

    func requestPermission() async {
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
    }

    @discardableResult
    func setInjectionEnabled(_ enabled: Bool) async -> InjectionModeChangeResult {
        guard #available(iOS 18.2, *) else {
            await refresh()
            return publishModeChangeResult(.unsupportedOS(version: UIDevice.current.systemVersion))
        }

        guard !enabled || permissionState.canEnableInjection else {
            isInjectionEnabled = false
            return publishModeChangeResult(.permissionRequired(state: permissionState))
        }

        guard !isChangingInjectionMode else {
            return publishModeChangeResult(.busy)
        }

        isChangingInjectionMode = true
        pendingInjectionMode = enabled

        do {
            let session = AVAudioSession.sharedInstance()

            if enabled {
                try configureAudioSessionForInjection()
            }

            try session.setPreferredMicrophoneInjectionMode(enabled ? .spokenAudio : .none)
            isInjectionEnabled = enabled
            lastInjectionModeChangeAt = Date()
            lastError = nil
            refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)
            isChangingInjectionMode = false
            pendingInjectionMode = nil
            return publishModeChangeResult(enabled ? .enabled(channelAvailable: isInjectionAvailableInCurrentCall) : .disabled)
        } catch {
            isInjectionEnabled = false
            lastInjectionModeChangeAt = Date()
            lastError = error.localizedDescription
            isChangingInjectionMode = false
            pendingInjectionMode = nil
            return publishModeChangeResult(.failed(message: error.localizedDescription))
        }
    }

    func reapplyInjectionPreferenceIfNeeded() throws {
        guard isInjectionEnabled else { return }

        if #available(iOS 18.2, *) {
            do {
                try AVAudioSession.sharedInstance().setPreferredMicrophoneInjectionMode(.spokenAudio)
                lastInjectionModeChangeAt = Date()
                lastError = nil
                refreshAudioSessionDiagnostics(printToConsole: true, updatesModeResult: false)
                _ = publishModeChangeResult(.enabled(channelAvailable: isInjectionAvailableInCurrentCall))
            } catch {
                lastInjectionModeChangeAt = Date()
                lastError = error.localizedDescription
                _ = publishModeChangeResult(.failed(message: error.localizedDescription))
                throw error
            }
        }
    }

    func openAddAudioInCallsSettings() async {
        guard #available(iOS 18.2, *) else {
            openAppSettings()
            return
        }

        do {
            try await AccessibilitySettings.openSettings(for: .allowAppsToAddAudioToCalls)
        } catch {
            lastError = error.localizedDescription
            openAppSettings()
        }
    }

    func openSoftwareUpdateSettings() {
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
        }
    }

    private func observeRouteChanges() async {
        for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
            lastRouteChangeAt = Date()
            lastRouteChangeReason = Self.routeChangeReason(from: notification)
            refreshAudioSessionDiagnostics(printToConsole: true)
        }
    }

    private func publishModeChangeResult(_ result: InjectionModeChangeResult) -> InjectionModeChangeResult {
        lastModeChangeResult = result
        lastModeChangeResultAt = Date()
        return result
    }

    @available(iOS 18.2, *)
    private func configureAudioSessionForInjection() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
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
