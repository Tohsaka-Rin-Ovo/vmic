import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum VmicText {
    case settings
    case theme
    case language
    case about
    case themeSystem
    case themeLight
    case themeDark
    case version
    case aboutDetail
    case checking
    case openAddAudioSettings
    case allowVmic
    case openSoftwareUpdate
    case callRoute
    case diagnosticReady
    case diagnosticWaitingForCall
    case diagnosticEnableSwitch
    case diagnosticNotCompatible
    case systemPermission
    case injectionChannel
    case injectionSwitch
    case available
    case unavailable
    case enabled
    case disabled
    case callDetected
    case noSupportedCall
    case injecting
    case injectionOff
    case readyToBridgeAudio
    case soundsPlaying(Int)
    case injectionEnabled
    case selectSoundToPlay
    case call
    case standby
    case live
    case local
    case noSounds
    case importAudio
    case importShort
    case importHint
    case localAudio
    case unknownArtist
    case rename
    case renameAudio
    case audioName
    case save
    case done
    case cancel
    case removeFromLibrary
    case sortingEnabled
    case playback
    case singlePlayback
    case singlePlaybackDetail
    case list
    case showDuration
    case showDurationDetail
    case delete
    case playSound(String)
    case permissionChecking
    case permissionUnsupportedOS
    case permissionServiceDisabled
    case permissionUndetermined
    case permissionDenied
    case permissionGranted
    case permissionUnknown
    case detailChecking
    case detailUnsupportedOS(String)
    case detailServiceDisabled
    case detailUndetermined
    case detailDenied
    case detailGranted
    case detailUnknown
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    @Published var themeMode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: Self.themeKey)
        }
    }

    @Published var singlePlayback: Bool {
        didSet {
            UserDefaults.standard.set(singlePlayback, forKey: Self.singlePlaybackKey)
        }
    }

    @Published var showDuration: Bool {
        didSet {
            UserDefaults.standard.set(showDuration, forKey: Self.showDurationKey)
        }
    }

    private static let languageKey = "vmic.language"
    private static let themeKey = "vmic.theme"
    private static let singlePlaybackKey = "vmic.singlePlayback"
    private static let showDurationKey = "vmic.showDuration"

    init() {
        let rawValue = UserDefaults.standard.string(forKey: Self.languageKey)
        language = rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        themeMode = rawTheme.flatMap(AppThemeMode.init(rawValue:)) ?? .system
        singlePlayback = UserDefaults.standard.bool(forKey: Self.singlePlaybackKey)
        showDuration = UserDefaults.standard.object(forKey: Self.showDurationKey) as? Bool ?? true
    }

    func text(_ key: VmicText) -> String {
        switch language {
        case .chinese:
            return chineseText(key)
        case .english:
            return englishText(key)
        }
    }

    private func chineseText(_ key: VmicText) -> String {
        switch key {
        case .settings:
            return "设置"
        case .theme:
            return "主题"
        case .language:
            return "语言"
        case .about:
            return "关于"
        case .themeSystem:
            return "跟随系统"
        case .themeLight:
            return "浅色"
        case .themeDark:
            return "深色"
        case .version:
            return "版本"
        case .aboutDetail:
            return "vmic 使用 iOS 18.2+ 的通话音频注入能力，将本地播放的音频加入支持的通话输入流。它不是系统级虚拟麦克风。"
        case .checking:
            return "正在检查 vmic"
        case .openAddAudioSettings:
            return "打开通话音频设置"
        case .allowVmic:
            return "允许 vmic"
        case .openSoftwareUpdate:
            return "打开系统更新"
        case .callRoute:
            return "注入通道"
        case .diagnosticReady:
            return "当前通话可用，可以播放音频测试对方是否能听到。"
        case .diagnosticWaitingForCall:
            return "请先进入电话、FaceTime 或支持的 VoIP 通话。"
        case .diagnosticEnableSwitch:
            return "已检测到注入通道，开启右侧开关后再播放音频。"
        case .diagnosticNotCompatible:
            return "iOS 检测到通话不等于注入通道可用。当前通话没有提供 Apple 麦克风注入通道，KOOK/微信需要实测兼容。"
        case .systemPermission:
            return "系统权限"
        case .injectionChannel:
            return "通道"
        case .injectionSwitch:
            return "开关"
        case .available:
            return "可用"
        case .unavailable:
            return "不可用"
        case .enabled:
            return "已开启"
        case .disabled:
            return "未开启"
        case .callDetected:
            return "检测到通话"
        case .noSupportedCall:
            return "未检测到支持的通话"
        case .injecting:
            return "注入中"
        case .injectionOff:
            return "注入关闭"
        case .readyToBridgeAudio:
            return "准备桥接音频"
        case .soundsPlaying(let count):
            return "\(count) 个音频播放中"
        case .injectionEnabled:
            return "通话注入已开启"
        case .selectSoundToPlay:
            return "选择一个音频播放"
        case .call:
            return "通话"
        case .standby:
            return "待机"
        case .live:
            return "实时"
        case .local:
            return "本地"
        case .noSounds:
            return "暂无音频"
        case .importAudio:
            return "导入音频"
        case .importShort:
            return "导入"
        case .importHint:
            return "导入音频文件后会生成列表项。"
        case .localAudio:
            return "本地"
        case .unknownArtist:
            return "未知作者"
        case .rename:
            return "重命名"
        case .renameAudio:
            return "重命名音频"
        case .audioName:
            return "音频名称"
        case .save:
            return "保存"
        case .done:
            return "完成"
        case .cancel:
            return "取消"
        case .removeFromLibrary:
            return "从列表移除"
        case .sortingEnabled:
            return "排序模式已开启"
        case .playback:
            return "播放"
        case .singlePlayback:
            return "单音频播放"
        case .singlePlaybackDetail:
            return "播放新音频时停止其他音频。"
        case .list:
            return "列表"
        case .showDuration:
            return "显示时长"
        case .showDurationDetail:
            return "在音频列表右侧显示时长。"
        case .delete:
            return "删除"
        case .playSound(let title):
            return "播放 \(title)"
        case .permissionChecking:
            return "正在检查"
        case .permissionUnsupportedOS:
            return "需要 iOS 18.2"
        case .permissionServiceDisabled:
            return "通话中添加音频未开启"
        case .permissionUndetermined:
            return "需要权限"
        case .permissionDenied:
            return "权限已拒绝"
        case .permissionGranted:
            return "已就绪"
        case .permissionUnknown:
            return "未知状态"
        case .detailChecking:
            return "vmic 正在检查系统支持状态。"
        case .detailUnsupportedOS(let version):
            return "当前设备运行 iOS \(version)。麦克风注入需要 iOS 18.2 或更高版本。"
        case .detailServiceDisabled:
            return "请在辅助功能设置中开启“通话中添加音频”。"
        case .detailUndetermined:
            return "允许 vmic 将本 App 音频添加到通话。"
        case .detailDenied:
            return "权限已被拒绝，请在“通话中添加音频”设置中修改。"
        case .detailGranted:
            return "vmic 可以将音频添加到支持的通话。"
        case .detailUnknown:
            return "系统返回了未知的权限状态。"
        }
    }

    private func englishText(_ key: VmicText) -> String {
        switch key {
        case .settings:
            return "Settings"
        case .theme:
            return "Theme"
        case .language:
            return "Language"
        case .about:
            return "About"
        case .themeSystem:
            return "System"
        case .themeLight:
            return "Light"
        case .themeDark:
            return "Dark"
        case .version:
            return "Version"
        case .aboutDetail:
            return "vmic uses iOS 18.2+ call audio injection to add local app audio to supported call input streams. It is not a system-wide virtual microphone."
        case .checking:
            return "Checking vmic"
        case .openAddAudioSettings:
            return "Open Add Audio Settings"
        case .allowVmic:
            return "Allow vmic"
        case .openSoftwareUpdate:
            return "Open Software Update"
        case .callRoute:
            return "Injection Channel"
        case .diagnosticReady:
            return "This call is available. Play an audio file to check whether the other side can hear it."
        case .diagnosticWaitingForCall:
            return "Join a Phone, FaceTime, or supported VoIP call first."
        case .diagnosticEnableSwitch:
            return "The injection channel is available. Turn on the switch before playing audio."
        case .diagnosticNotCompatible:
            return "The iOS call indicator does not guarantee an injection channel. This call has not exposed Apple's microphone injection channel; KOOK and WeChat need device testing."
        case .systemPermission:
            return "Permission"
        case .injectionChannel:
            return "Channel"
        case .injectionSwitch:
            return "Switch"
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .callDetected:
            return "Call Detected"
        case .noSupportedCall:
            return "No Supported Call"
        case .injecting:
            return "Injecting"
        case .injectionOff:
            return "Injection Off"
        case .readyToBridgeAudio:
            return "Ready to bridge audio"
        case .soundsPlaying(let count):
            return "\(count) sounds playing"
        case .injectionEnabled:
            return "Injection enabled"
        case .selectSoundToPlay:
            return "Select a sound to play"
        case .call:
            return "Call"
        case .standby:
            return "Standby"
        case .live:
            return "Live"
        case .local:
            return "Local"
        case .noSounds:
            return "No Sounds"
        case .importAudio:
            return "Import Audio"
        case .importShort:
            return "Import"
        case .importHint:
            return "Import audio files to create list items."
        case .localAudio:
            return "Local"
        case .unknownArtist:
            return "Unknown Artist"
        case .rename:
            return "Rename"
        case .renameAudio:
            return "Rename Audio"
        case .audioName:
            return "Audio Name"
        case .save:
            return "Save"
        case .done:
            return "Done"
        case .cancel:
            return "Cancel"
        case .removeFromLibrary:
            return "Remove from Library"
        case .sortingEnabled:
            return "Sorting enabled"
        case .playback:
            return "Playback"
        case .singlePlayback:
            return "Single Playback"
        case .singlePlaybackDetail:
            return "Stop other sounds when a new sound plays."
        case .list:
            return "List"
        case .showDuration:
            return "Show Duration"
        case .showDurationDetail:
            return "Show durations on the right side of the audio list."
        case .delete:
            return "Delete"
        case .playSound(let title):
            return "Play \(title)"
        case .permissionChecking:
            return "Checking"
        case .permissionUnsupportedOS:
            return "iOS 18.2 Required"
        case .permissionServiceDisabled:
            return "Add Audio in Calls Off"
        case .permissionUndetermined:
            return "Permission Needed"
        case .permissionDenied:
            return "Permission Denied"
        case .permissionGranted:
            return "Ready"
        case .permissionUnknown:
            return "Unknown"
        case .detailChecking:
            return "vmic is checking system support."
        case .detailUnsupportedOS(let version):
            return "This iPhone is running iOS \(version). Microphone injection requires iOS 18.2 or later."
        case .detailServiceDisabled:
            return "Turn on Add Audio in Calls in Accessibility settings."
        case .detailUndetermined:
            return "Allow vmic to add app audio to calls."
        case .detailDenied:
            return "Permission was denied. Change it in Add Audio in Calls settings."
        case .detailGranted:
            return "vmic can add its audio to supported calls."
        case .detailUnknown:
            return "The system returned an unknown permission state."
        }
    }
}
