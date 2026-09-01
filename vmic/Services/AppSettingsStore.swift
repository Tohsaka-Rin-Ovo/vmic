import Foundation

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

enum VmicText {
    case settings
    case language
    case checking
    case openAddAudioSettings
    case allowVmic
    case openSoftwareUpdate
    case callRoute
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
    private static let singlePlaybackKey = "vmic.singlePlayback"
    private static let showDurationKey = "vmic.showDuration"

    init() {
        let rawValue = UserDefaults.standard.string(forKey: Self.languageKey)
        language = rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .chinese
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
        case .language:
            return "语言"
        case .checking:
            return "正在检查 vmic"
        case .openAddAudioSettings:
            return "打开通话音频设置"
        case .allowVmic:
            return "允许 vmic"
        case .openSoftwareUpdate:
            return "打开系统更新"
        case .callRoute:
            return "通话路径"
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
        case .language:
            return "Language"
        case .checking:
            return "Checking vmic"
        case .openAddAudioSettings:
            return "Open Add Audio Settings"
        case .allowVmic:
            return "Allow vmic"
        case .openSoftwareUpdate:
            return "Open Software Update"
        case .callRoute:
            return "Call Route"
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
