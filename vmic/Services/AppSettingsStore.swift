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
    case debug
    case monitorVolumeExperiment
    case monitorVolumeExperimentDetail
    case experimentAudio
    case experimentNoAudio
    case localMonitorVolume
    case bridgeSendVolume
    case baselineTest
    case mutedMonitorTest
    case stopTest
    case experimentInstruction
    case experimentReady
    case experimentBaselineRunning
    case experimentMutedMonitorRunning
    case experimentBaselineFinished
    case experimentMutedMonitorFinished
    case experimentStopped
    case experimentFailed(String)
    case themeSystem
    case themeLight
    case themeDark
    case version
    case aboutDetail
    case checking
    case openAddAudioSettings
    case allowVmic
    case openSoftwareUpdate
    case refreshStatus
    case requestPermission
    case enableInjection
    case disableInjection
    case turningOnInjection
    case turningOffInjection
    case enableInjectionHelp
    case latestInjectionResult
    case noInjectionResult
    case audioSessionDiagnostics
    case channelVerdict
    case channelVerdictAvailable
    case channelVerdictUnavailable
    case channelVerdictUnsupported
    case directChannelCheck
    case notificationChannel
    case currentCategory
    case currentMode
    case currentInputPorts
    case currentOutputPorts
    case currentInputDevices
    case currentOutputDevices
    case sampleRate
    case inputChannels
    case outputChannels
    case lastRouteChange
    case routeChangeReason
    case notSupported
    case emptyRoute
    case copyChannelDiagnostics
    case copiedChannelDiagnostics
    case audioSessionDiagnosticsNote
    case actionSucceeded
    case actionNeedsAttention
    case actionFailed
    case actionUnsupportedOS(String)
    case actionPermissionRequired
    case actionServiceDisabled
    case actionPermissionDenied
    case actionPermissionUnknown
    case actionEnableSucceeded
    case actionEnableNoChannel
    case actionDisableSucceeded
    case actionModeChangeBusy
    case actionModeChangeFailed(String)
    case openSystemSwitch
    case device
    case systemVersion
    case minimumVersion
    case permissionStateLabel
    case lastRefresh
    case lastCallEvent
    case lastInjectionChange
    case lastError
    case noError
    case never
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
    case bridgeAudioReady
    case clipPlaying(String)
    case clipPaused(String)
    case selectSoundToPlay
    case call
    case standby
    case live
    case local
    case audio
    case audioList
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
    case inputVolume
    case inputVolumeDetail
    case volumePercent(Int)
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

    @Published var inputVolume: Double {
        didSet {
            UserDefaults.standard.set(inputVolume, forKey: Self.inputVolumeKey)
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
    private static let inputVolumeKey = "vmic.inputVolume"
    private static let showDurationKey = "vmic.showDuration"

    init() {
        let rawValue = UserDefaults.standard.string(forKey: Self.languageKey)
        language = rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        themeMode = rawTheme.flatMap(AppThemeMode.init(rawValue:)) ?? .system
        singlePlayback = UserDefaults.standard.bool(forKey: Self.singlePlaybackKey)
        let savedVolume = UserDefaults.standard.object(forKey: Self.inputVolumeKey) as? Double ?? 1
        inputVolume = min(max(savedVolume, 0), 1)
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
        case .debug:
            return "调试"
        case .monitorVolumeExperiment:
            return "监听验证"
        case .monitorVolumeExperimentDetail:
            return "验证本机监听音量能否与桥接发送音量分离。"
        case .experimentAudio:
            return "测试音频"
        case .experimentNoAudio:
            return "请先在音频列表导入一个音频。"
        case .localMonitorVolume:
            return "本机监听音量"
        case .bridgeSendVolume:
            return "桥接发送音量"
        case .baselineTest:
            return "基线播放"
        case .mutedMonitorTest:
            return "静音监听"
        case .stopTest:
            return "停止测试"
        case .experimentInstruction:
            return "测试时保持通话，先运行基线播放确认对方能听到，再运行静音监听。如果本机无声但对方仍能听到，说明监听分离有机会正式接入。"
        case .experimentReady:
            return "等待开始测试。"
        case .experimentBaselineRunning:
            return "基线播放中：本机监听为 100%，用于确认当前注入链路有效。"
        case .experimentMutedMonitorRunning:
            return "静音监听中：本机监听为 0%，桥接发送按滑块输出。"
        case .experimentBaselineFinished:
            return "基线播放已结束。"
        case .experimentMutedMonitorFinished:
            return "静音监听已结束，请记录对方是否仍能听到。"
        case .experimentStopped:
            return "测试已停止。"
        case .experimentFailed(let message):
            return "测试失败：\(message)"
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
        case .refreshStatus:
            return "刷新状态"
        case .requestPermission:
            return "请求权限"
        case .enableInjection:
            return "尝试开启注入"
        case .disableInjection:
            return "关闭注入"
        case .turningOnInjection:
            return "正在开启"
        case .turningOffInjection:
            return "正在关闭"
        case .enableInjectionHelp:
            return "此按钮在系统权限已授予后可用。它只负责请求 iOS 切到麦克风注入模式；当前通话是否真的能接入，还要看通话 App 是否提供 Apple 注入通道。"
        case .latestInjectionResult:
            return "最近注入结果"
        case .noInjectionResult:
            return "暂无操作结果"
        case .audioSessionDiagnostics:
            return "通道检测"
        case .channelVerdict:
            return "检测结论"
        case .channelVerdictAvailable:
            return "当前通话已暴露 Apple 麦克风注入通道。"
        case .channelVerdictUnavailable:
            return "当前通话未暴露 Apple 麦克风注入通道。若此时 KOOK 正在通话，软件层基本无法注入。"
        case .channelVerdictUnsupported:
            return "当前系统无法直接查询麦克风注入通道。"
        case .directChannelCheck:
            return "直接查询"
        case .notificationChannel:
            return "通知状态"
        case .currentCategory:
            return "Category"
        case .currentMode:
            return "Mode"
        case .currentInputPorts:
            return "输入端口"
        case .currentOutputPorts:
            return "输出端口"
        case .currentInputDevices:
            return "输入设备"
        case .currentOutputDevices:
            return "输出设备"
        case .sampleRate:
            return "采样率"
        case .inputChannels:
            return "输入声道"
        case .outputChannels:
            return "输出声道"
        case .lastRouteChange:
            return "上次路由变化"
        case .routeChangeReason:
            return "路由原因"
        case .notSupported:
            return "不支持"
        case .emptyRoute:
            return "无"
        case .copyChannelDiagnostics:
            return "复制通道诊断"
        case .copiedChannelDiagnostics:
            return "已复制"
        case .audioSessionDiagnosticsNote:
            return "Category 和 Mode 是 vmic 当前音频会话；通话是否可注入，以直接查询和系统通知为准。"
        case .actionSucceeded:
            return "操作已完成"
        case .actionNeedsAttention:
            return "需要处理"
        case .actionFailed:
            return "操作失败"
        case .actionUnsupportedOS(let version):
            return "当前系统是 iOS \(version)，麦克风注入需要 iOS 18.2 或更高版本。"
        case .actionPermissionRequired:
            return "vmic 还没有通话音频注入权限，请先请求权限。"
        case .actionServiceDisabled:
            return "系统的“通话中添加音频”总开关未开启，请先打开系统开关。"
        case .actionPermissionDenied:
            return "权限已被拒绝，请在系统设置中重新允许 vmic。"
        case .actionPermissionUnknown:
            return "系统返回了未知权限状态，请刷新后再试。"
        case .actionEnableSucceeded:
            return "已向 iOS 请求开启麦克风注入模式。"
        case .actionEnableNoChannel:
            return "已向 iOS 请求开启麦克风注入模式，但当前通话没有暴露可用注入通道。"
        case .actionDisableSucceeded:
            return "麦克风注入模式已关闭。"
        case .actionModeChangeBusy:
            return "上一轮注入模式切换还在处理中，请等待当前操作完成。"
        case .actionModeChangeFailed(let message):
            return "系统拒绝了这次切换：\(message)"
        case .openSystemSwitch:
            return "打开系统开关"
        case .device:
            return "设备"
        case .systemVersion:
            return "系统版本"
        case .minimumVersion:
            return "最低要求"
        case .permissionStateLabel:
            return "权限状态"
        case .lastRefresh:
            return "上次刷新"
        case .lastCallEvent:
            return "上次通道事件"
        case .lastInjectionChange:
            return "上次注入变更"
        case .lastError:
            return "最近错误"
        case .noError:
            return "无"
        case .never:
            return "暂无"
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
        case .bridgeAudioReady:
            return "桥接音频已就绪"
        case .clipPlaying(let title):
            return "\(title) 播放中"
        case .clipPaused(let title):
            return "\(title) 已暂停"
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
        case .audio:
            return "音频"
        case .audioList:
            return "音频列表"
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
        case .inputVolume:
            return "输入音量"
        case .inputVolumeDetail:
            return "控制本地音频加入通话时的音量。"
        case .volumePercent(let value):
            return "\(value)%"
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
        case .debug:
            return "Debug"
        case .monitorVolumeExperiment:
            return "Monitor Check"
        case .monitorVolumeExperimentDetail:
            return "Checks whether local monitoring can be separated from bridge send volume."
        case .experimentAudio:
            return "Test Audio"
        case .experimentNoAudio:
            return "Import an audio file in the audio list first."
        case .localMonitorVolume:
            return "Local Monitor"
        case .bridgeSendVolume:
            return "Bridge Send"
        case .baselineTest:
            return "Baseline"
        case .mutedMonitorTest:
            return "Muted Monitor"
        case .stopTest:
            return "Stop Test"
        case .experimentInstruction:
            return "Stay in the call, run Baseline first to confirm the other side can hear it, then run Muted Monitor. If this iPhone is silent but the other side still hears audio, monitor separation is worth promoting to the main UI."
        case .experimentReady:
            return "Waiting to start."
        case .experimentBaselineRunning:
            return "Baseline is playing with local monitor at 100%."
        case .experimentMutedMonitorRunning:
            return "Muted Monitor is playing with local monitor at 0% and bridge send controlled by the slider."
        case .experimentBaselineFinished:
            return "Baseline finished."
        case .experimentMutedMonitorFinished:
            return "Muted Monitor finished. Record whether the other side still heard it."
        case .experimentStopped:
            return "Test stopped."
        case .experimentFailed(let message):
            return "Test failed: \(message)"
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
        case .refreshStatus:
            return "Refresh Status"
        case .requestPermission:
            return "Request Permission"
        case .enableInjection:
            return "Try Enable Injection"
        case .disableInjection:
            return "Disable Injection"
        case .turningOnInjection:
            return "Turning On"
        case .turningOffInjection:
            return "Turning Off"
        case .enableInjectionHelp:
            return "This action becomes available after system permission is granted. It only asks iOS to switch to microphone injection mode; the current call must still expose Apple's injection channel."
        case .latestInjectionResult:
            return "Latest Injection Result"
        case .noInjectionResult:
            return "No result yet"
        case .audioSessionDiagnostics:
            return "Channel Check"
        case .channelVerdict:
            return "Verdict"
        case .channelVerdictAvailable:
            return "The current call exposes Apple's microphone injection channel."
        case .channelVerdictUnavailable:
            return "The current call does not expose Apple's microphone injection channel. If KOOK is in a call now, software injection is probably unavailable."
        case .channelVerdictUnsupported:
            return "This system cannot directly query microphone injection availability."
        case .directChannelCheck:
            return "Direct Query"
        case .notificationChannel:
            return "Notification"
        case .currentCategory:
            return "Category"
        case .currentMode:
            return "Mode"
        case .currentInputPorts:
            return "Input Ports"
        case .currentOutputPorts:
            return "Output Ports"
        case .currentInputDevices:
            return "Input Devices"
        case .currentOutputDevices:
            return "Output Devices"
        case .sampleRate:
            return "Sample Rate"
        case .inputChannels:
            return "Input Channels"
        case .outputChannels:
            return "Output Channels"
        case .lastRouteChange:
            return "Last Route Change"
        case .routeChangeReason:
            return "Route Reason"
        case .notSupported:
            return "Unsupported"
        case .emptyRoute:
            return "None"
        case .copyChannelDiagnostics:
            return "Copy Channel Diagnostics"
        case .copiedChannelDiagnostics:
            return "Copied"
        case .audioSessionDiagnosticsNote:
            return "Category and mode are vmic's current audio session. Use the direct query and system notification as the call injection verdict."
        case .actionSucceeded:
            return "Done"
        case .actionNeedsAttention:
            return "Needs Attention"
        case .actionFailed:
            return "Failed"
        case .actionUnsupportedOS(let version):
            return "This iPhone is running iOS \(version). Microphone injection requires iOS 18.2 or later."
        case .actionPermissionRequired:
            return "vmic does not have call audio injection permission yet. Request permission first."
        case .actionServiceDisabled:
            return "Add Audio in Calls is off in system settings. Open the system switch first."
        case .actionPermissionDenied:
            return "Permission was denied. Allow vmic again in system settings."
        case .actionPermissionUnknown:
            return "The system returned an unknown permission state. Refresh and try again."
        case .actionEnableSucceeded:
            return "iOS accepted the request to turn on microphone injection mode."
        case .actionEnableNoChannel:
            return "iOS accepted the request, but the current call has not exposed an available injection channel."
        case .actionDisableSucceeded:
            return "Microphone injection mode is off."
        case .actionModeChangeBusy:
            return "A microphone injection mode change is already in progress. Wait for it to finish."
        case .actionModeChangeFailed(let message):
            return "The system rejected this change: \(message)"
        case .openSystemSwitch:
            return "Open System Switch"
        case .device:
            return "Device"
        case .systemVersion:
            return "System Version"
        case .minimumVersion:
            return "Minimum"
        case .permissionStateLabel:
            return "Permission"
        case .lastRefresh:
            return "Last Refresh"
        case .lastCallEvent:
            return "Last Channel Event"
        case .lastInjectionChange:
            return "Last Injection Change"
        case .lastError:
            return "Last Error"
        case .noError:
            return "None"
        case .never:
            return "Never"
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
        case .bridgeAudioReady:
            return "Bridge audio ready"
        case .clipPlaying(let title):
            return "\(title) playing"
        case .clipPaused(let title):
            return "\(title) paused"
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
        case .audio:
            return "Audio"
        case .audioList:
            return "Audio List"
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
        case .inputVolume:
            return "Input Volume"
        case .inputVolumeDetail:
            return "Controls the local audio volume added to calls."
        case .volumePercent(let value):
            return "\(value)%"
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
