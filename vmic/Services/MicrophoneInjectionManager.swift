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

@MainActor
final class MicrophoneInjectionManager: ObservableObject {
    @Published private(set) var permissionState: InjectionPermissionState = .checking
    @Published private(set) var isInjectionEnabled = false
    @Published private(set) var isInjectionAvailableInCurrentCall = false
    @Published var lastError: String?

    private var observerTask: Task<Void, Never>?

    init() {
        observerTask = Task { [weak self] in
            await self?.observeCapabilities()
        }
    }

    deinit {
        observerTask?.cancel()
    }

    func refresh() async {
        guard #available(iOS 18.2, *) else {
            permissionState = .unsupportedOS(version: UIDevice.current.systemVersion)
            isInjectionEnabled = false
            isInjectionAvailableInCurrentCall = false
            return
        }

        permissionState = Self.map(AVAudioApplication.shared.microphoneInjectionPermission)
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

    func setInjectionEnabled(_ enabled: Bool) async {
        guard #available(iOS 18.2, *) else {
            await refresh()
            return
        }

        guard permissionState.canEnableInjection else {
            isInjectionEnabled = false
            return
        }

        do {
            try AVAudioSession.sharedInstance().setPreferredMicrophoneInjectionMode(enabled ? .spokenAudio : .none)
            isInjectionEnabled = enabled
            lastError = nil
        } catch {
            isInjectionEnabled = false
            lastError = error.localizedDescription
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
            isInjectionAvailableInCurrentCall = available
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
