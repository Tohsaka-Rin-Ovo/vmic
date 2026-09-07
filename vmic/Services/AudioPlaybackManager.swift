import AVFoundation
import Foundation

enum SoundPlaybackState: Equatable {
    case playing
    case paused
}

@MainActor
final class AudioPlaybackManager: ObservableObject {
    @Published private(set) var activeClipIDs: Set<UUID> = []
    @Published private(set) var pausedClipIDs: Set<UUID> = []
    @Published private(set) var currentClipID: UUID?
    @Published private(set) var playbackProgressByClipID: [UUID: Double] = [:]
    @Published private(set) var elapsedTimeByClipID: [UUID: TimeInterval] = [:]
    @Published private(set) var durationByClipID: [UUID: TimeInterval] = [:]
    @Published var lastError: String?

    var playbackDidFinish: ((UUID) -> Void)?

    private let engine = AVAudioEngine()
    private var sessionsByClipID: [UUID: EnginePlaybackSession] = [:]
    private var playbackStartedAtByClipID: [UUID: Date] = [:]
    private var playbackCompletionCountByClipID: [UUID: Int] = [:]
    private var outputVolume: Float = 1
    private var lastLoggedOutputVolume: Float?
    private var progressTimer: Timer?

    func playbackState(for clipID: UUID) -> SoundPlaybackState? {
        guard activeClipIDs.contains(clipID) else { return nil }
        return pausedClipIDs.contains(clipID) ? .paused : .playing
    }

    func playbackProgress(for clipID: UUID) -> Double {
        playbackProgressByClipID[clipID] ?? 0
    }

    func elapsedTime(for clipID: UUID) -> TimeInterval {
        if let session = sessionsByClipID[clipID] {
            return seconds(for: currentFrame(in: session), sampleRate: session.sampleRate)
        }

        return elapsedTimeByClipID[clipID] ?? 0
    }

    func duration(for clipID: UUID) -> TimeInterval? {
        if let duration = durationByClipID[clipID], duration.isFinite, duration > 0 {
            return duration
        }

        return sessionsByClipID[clipID]?.duration
    }

    func playbackStartedAt(for clipID: UUID) -> Date? {
        playbackStartedAtByClipID[clipID]
    }

    func playbackElapsedSinceStart(for clipID: UUID) -> TimeInterval? {
        guard let startedAt = playbackStartedAtByClipID[clipID] else { return nil }
        return Date().timeIntervalSince(startedAt)
    }

    func playbackCompletionCount(for clipID: UUID) -> Int {
        playbackCompletionCountByClipID[clipID] ?? 0
    }

    func seek(_ clip: SoundClip, toProgress progress: Double) {
        seek(clipID: clip.id, toProgress: progress)
    }

    func seek(clipID: UUID, toProgress progress: Double) {
        guard let session = sessionsByClipID[clipID], session.durationFrames > 0 else { return }

        let targetProgress = min(max(progress, 0), 1)
        let targetFrame = frame(for: targetProgress, in: session)
        let wasPlaying = playbackState(for: clipID) == .playing

        do {
            try reschedule(session, from: targetFrame, shouldPlay: wasPlaying)
            currentClipID = clipID
            refreshPlaybackProgress()
            DiagnosticLogStore.shared.log(
                "调整播放进度",
                source: .playback,
                details: [
                    "clipID=\(shortID(clipID))",
                    "progress=\(formatPercent(targetProgress))",
                    "time=\(formatSeconds(seconds(for: targetFrame, sampleRate: session.sampleRate)))",
                    "duration=\(formatSeconds(session.duration))",
                    "engineRunning=\(engine.isRunning)"
                ]
            )

            if wasPlaying {
                startProgressTimerIfNeeded()
            }
        } catch {
            lastError = "无法调整播放进度：\(error.localizedDescription)"
            DiagnosticLogStore.shared.log(
                "调整播放进度失败",
                source: .playback,
                details: [
                    "clipID=\(shortID(clipID))",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    func setOutputVolume(_ volume: Double) {
        outputVolume = Float(min(max(volume, 0), 1))
        sessionsByClipID.values.forEach { session in
            session.node.volume = outputVolume
        }

        let shouldLog = lastLoggedOutputVolume.map { abs($0 - outputVolume) >= 0.01 } ?? true
        if shouldLog {
            lastLoggedOutputVolume = outputVolume
            DiagnosticLogStore.shared.log(
                "设置文件音频音量",
                source: .playback,
                details: [
                    "volume=\(formatPercent(Double(outputVolume)))",
                    "activePlayers=\(sessionsByClipID.count)",
                    "engineRunning=\(engine.isRunning)"
                ]
            )
        }
    }

    func toggle(
        _ clip: SoundClip,
        from directory: URL,
        volume: Double,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        DiagnosticLogStore.shared.log(
            "切换播放状态",
            source: .playback,
            details: [
                "title=\(clip.title)",
                "clipID=\(shortID(clip.id))",
                "state=\(playbackStateDescription(for: clip.id))"
            ]
        )
        setOutputVolume(volume)

        switch playbackState(for: clip.id) {
        case .playing:
            pause(clip)
        case .paused:
            resume(clip, reapplyInjectionPreference: reapplyInjectionPreference)
        case nil:
            play(clip, from: directory, reapplyInjectionPreference: reapplyInjectionPreference)
        }
    }

    func play(
        _ clip: SoundClip,
        from directory: URL,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil,
        resetPlaybackSession: Bool = true
    ) {
        let url = clip.fileURL(in: directory)
        DiagnosticLogStore.shared.log(
            "准备播放音频",
            source: .playback,
            details: [
                "title=\(clip.title)",
                "clipID=\(shortID(clip.id))",
                "file=\(url.lastPathComponent)",
                "exists=\(FileManager.default.fileExists(atPath: url.path))",
                "volume=\(formatPercent(Double(outputVolume)))"
            ]
        )

        do {
            try configureAudioSession(reapplyInjectionPreference: reapplyInjectionPreference)

            let audioFile = try AVAudioFile(forReading: url)
            guard audioFile.length > 0 else {
                throw AudioPlaybackError.emptyAudioFile
            }

            removeSession(for: clip.id, preserveSessionCounters: true)

            let session = EnginePlaybackSession(clipID: clip.id, audioFile: audioFile, url: url)
            session.node.volume = outputVolume
            engine.attach(session.node)
            engine.connect(session.node, to: engine.mainMixerNode, format: audioFile.processingFormat)
            sessionsByClipID[clip.id] = session

            try schedule(session, from: 0)
            try startEngineIfNeeded()
            session.node.play()
            try reapplyInjectionPreference?()
            DiagnosticLogStore.shared.log(
                "AudioEngine 发声后已按官方式路径重申注入偏好",
                source: .playback,
                details: Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )

            guard session.node.isPlaying else {
                throw AudioPlaybackError.playbackDidNotStart
            }

            activeClipIDs.insert(clip.id)
            pausedClipIDs.remove(clip.id)
            currentClipID = clip.id
            if resetPlaybackSession || playbackStartedAtByClipID[clip.id] == nil {
                playbackStartedAtByClipID[clip.id] = Date()
            }

            if resetPlaybackSession || playbackCompletionCountByClipID[clip.id] == nil {
                playbackCompletionCountByClipID[clip.id] = 0
            }

            refreshPlaybackProgress()
            startProgressTimerIfNeeded()
            lastError = nil
            DiagnosticLogStore.shared.log(
                "播放音频已进入 AudioEngine",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "duration=\(formatSeconds(session.duration))",
                    "fileSampleRate=\(Int(session.sampleRate.rounded()))",
                    "channels=\(audioFile.processingFormat.channelCount)",
                    "nodeVolume=\(formatPercent(Double(session.node.volume)))",
                    "engineRunning=\(engine.isRunning)"
                ] + Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )
        } catch {
            removeSession(for: clip.id)
            playbackStartedAtByClipID[clip.id] = nil
            playbackCompletionCountByClipID[clip.id] = nil
            lastError = "无法播放 \(clip.title)：\(error.localizedDescription)"
            DiagnosticLogStore.shared.log(
                "播放音频失败",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "error=\(error.localizedDescription)"
                ] + Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )
        }
    }

    func pause(_ clip: SoundClip) {
        guard let session = sessionsByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        let frame = currentFrame(in: session)
        session.pausedFrame = frame
        session.node.pause()
        pausedClipIDs.insert(clip.id)
        currentClipID = clip.id
        refreshPlaybackProgress()
        DiagnosticLogStore.shared.log(
            "暂停音频",
            source: .playback,
            details: [
                "title=\(clip.title)",
                "clipID=\(shortID(clip.id))",
                "time=\(formatSeconds(seconds(for: frame, sampleRate: session.sampleRate)))",
                "engineRunning=\(engine.isRunning)"
            ]
        )
    }

    func resume(
        _ clip: SoundClip,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        guard let session = sessionsByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        do {
            try configureAudioSession(reapplyInjectionPreference: reapplyInjectionPreference)
            try startEngineIfNeeded()
            session.node.volume = outputVolume
            session.pausedFrame = nil
            session.node.play()
            try reapplyInjectionPreference?()
            DiagnosticLogStore.shared.log(
                "AudioEngine 恢复发声后已按官方式路径重申注入偏好",
                source: .playback,
                details: Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )

            guard session.node.isPlaying else {
                throw AudioPlaybackError.playbackDidNotStart
            }

            pausedClipIDs.remove(clip.id)
            currentClipID = clip.id
            refreshPlaybackProgress()
            startProgressTimerIfNeeded()
            lastError = nil
            DiagnosticLogStore.shared.log(
                "恢复播放音频",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "time=\(formatSeconds(elapsedTime(for: clip.id)))",
                    "nodeVolume=\(formatPercent(Double(session.node.volume)))",
                    "engineRunning=\(engine.isRunning)"
                ] + Self.audioSessionDetails(AVAudioSession.sharedInstance())
            )
        } catch {
            lastError = "无法继续播放 \(clip.title)：\(error.localizedDescription)"
            DiagnosticLogStore.shared.log(
                "恢复播放失败",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    func stop(_ clip: SoundClip) {
        if let session = sessionsByClipID[clip.id] {
            DiagnosticLogStore.shared.log(
                "停止音频",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "time=\(formatSeconds(seconds(for: currentFrame(in: session), sampleRate: session.sampleRate)))",
                    "engineRunning=\(engine.isRunning)"
                ]
            )
        }

        removeSession(for: clip.id)
    }

    func stopAll() {
        DiagnosticLogStore.shared.log(
            "停止全部音频",
            source: .playback,
            details: [
                "activePlayers=\(sessionsByClipID.count)",
                "engineRunning=\(engine.isRunning)"
            ]
        )

        Array(sessionsByClipID.keys).forEach { clipID in
            removeSession(for: clipID)
        }
        playbackStartedAtByClipID.removeAll()
        playbackCompletionCountByClipID.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil

        if engine.isRunning {
            engine.pause()
        }
    }

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaybackProgress()
            }
        }
    }

    private func stopProgressTimerIfNeeded() {
        guard sessionsByClipID.isEmpty else { return }
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshPlaybackProgress() {
        guard !sessionsByClipID.isEmpty else {
            playbackProgressByClipID.removeAll()
            elapsedTimeByClipID.removeAll()
            durationByClipID.removeAll()
            stopProgressTimerIfNeeded()
            return
        }

        var progressByClipID: [UUID: Double] = [:]
        var elapsedByClipID: [UUID: TimeInterval] = [:]
        var durationByClipID: [UUID: TimeInterval] = [:]

        for (clipID, session) in sessionsByClipID {
            let elapsedFrame = currentFrame(in: session)
            let elapsed = seconds(for: elapsedFrame, sampleRate: session.sampleRate)
            elapsedByClipID[clipID] = elapsed
            durationByClipID[clipID] = session.duration

            guard session.duration > 0 else {
                progressByClipID[clipID] = 0
                continue
            }

            progressByClipID[clipID] = min(max(elapsed / session.duration, 0), 1)
        }

        playbackProgressByClipID = progressByClipID
        elapsedTimeByClipID = elapsedByClipID
        self.durationByClipID = durationByClipID
    }

    private func updateCurrentClip(afterRemoving clipID: UUID) {
        guard currentClipID == clipID else { return }
        currentClipID = activeClipIDs.first
    }

    private func configureAudioSession(reapplyInjectionPreference: (@MainActor () throws -> Void)?) throws {
        let session = AVAudioSession.sharedInstance()
        DiagnosticLogStore.shared.log(
            "配置文件播放官方式会话开始",
            source: .playback,
            details: Self.audioSessionDetails(session)
        )
        try reapplyInjectionPreference?()
        DiagnosticLogStore.shared.log(
            "文件播放官方式会话配置完成",
            source: .playback,
            details: [
                "policy=preferredInjectionOnly",
                "categoryChangedByVmic=false",
                "activeChangedByVmic=false"
            ] + Self.audioSessionDetails(session)
        )
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }

        engine.prepare()
        try engine.start()
        DiagnosticLogStore.shared.log(
            "AudioEngine 已启动",
            source: .playback,
            details: [
                "engineRunning=\(engine.isRunning)",
                "outputSampleRate=\(Int(engine.outputNode.outputFormat(forBus: 0).sampleRate.rounded()))",
                "mainMixerSampleRate=\(Int(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate.rounded()))"
            ]
        )
    }

    private func schedule(_ session: EnginePlaybackSession, from frame: AVAudioFramePosition) throws {
        let startFrame = min(max(frame, 0), max(session.durationFrames - 1, 0))
        let remainingFrames = max(session.durationFrames - startFrame, 0)
        guard remainingFrames > 0 else {
            throw AudioPlaybackError.emptyAudioFile
        }

        session.generation += 1
        session.startFrame = startFrame
        session.pausedFrame = nil
        let generation = session.generation
        let token = session.token
        let clipID = session.clipID
        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))

        session.node.scheduleSegment(
            session.audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self, clipID, token, generation] _ in
            Task { @MainActor in
                self?.handlePlaybackCompletion(
                    clipID: clipID,
                    token: token,
                    generation: generation
                )
            }
        }

        DiagnosticLogStore.shared.log(
            "AudioEngine 已调度文件片段",
            source: .playback,
            details: [
                "clipID=\(shortID(clipID))",
                "startFrame=\(startFrame)",
                "frameCount=\(frameCount)",
                "duration=\(formatSeconds(session.duration))"
            ]
        )
    }

    private func reschedule(
        _ session: EnginePlaybackSession,
        from frame: AVAudioFramePosition,
        shouldPlay: Bool
    ) throws {
        session.generation += 1
        session.node.stop()
        try schedule(session, from: frame)
        session.pausedFrame = shouldPlay ? nil : session.startFrame

        if shouldPlay {
            try startEngineIfNeeded()
            session.node.play()
            pausedClipIDs.remove(session.clipID)
        } else {
            pausedClipIDs.insert(session.clipID)
        }
    }

    private func removeSession(for clipID: UUID, preserveSessionCounters: Bool = false) {
        guard let session = sessionsByClipID.removeValue(forKey: clipID) else {
            activeClipIDs.remove(clipID)
            pausedClipIDs.remove(clipID)
            playbackProgressByClipID[clipID] = nil
            elapsedTimeByClipID[clipID] = nil
            durationByClipID[clipID] = nil
            updateCurrentClip(afterRemoving: clipID)
            stopProgressTimerIfNeeded()
            return
        }

        session.generation += 1
        session.node.stop()
        engine.detach(session.node)

        activeClipIDs.remove(clipID)
        pausedClipIDs.remove(clipID)
        playbackProgressByClipID[clipID] = nil
        elapsedTimeByClipID[clipID] = nil
        durationByClipID[clipID] = nil
        if !preserveSessionCounters {
            playbackStartedAtByClipID[clipID] = nil
            playbackCompletionCountByClipID[clipID] = nil
        }
        updateCurrentClip(afterRemoving: clipID)
        stopProgressTimerIfNeeded()

        if sessionsByClipID.isEmpty, engine.isRunning {
            engine.pause()
        }
    }

    private func handlePlaybackCompletion(clipID: UUID, token: UUID, generation: Int) {
        guard let session = sessionsByClipID[clipID],
              session.token == token,
              session.generation == generation,
              !pausedClipIDs.contains(clipID) else {
            return
        }

        DiagnosticLogStore.shared.log(
            "音频播放完成",
            source: .playback,
            details: [
                "clipID=\(shortID(clipID))",
                "engineRunning=\(engine.isRunning)"
            ]
        )
        playbackCompletionCountByClipID[clipID, default: 0] += 1
        removeSession(for: clipID, preserveSessionCounters: true)
        playbackDidFinish?(clipID)
    }

    private func currentFrame(in session: EnginePlaybackSession) -> AVAudioFramePosition {
        if let pausedFrame = session.pausedFrame {
            return pausedFrame
        }

        guard session.node.isPlaying,
              let nodeTime = session.node.lastRenderTime,
              let playerTime = session.node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return session.startFrame
        }

        let playedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        let playedFrames = AVAudioFramePosition((playedSeconds * session.sampleRate).rounded())
        return min(max(session.startFrame + playedFrames, 0), session.durationFrames)
    }

    private func frame(for progress: Double, in session: EnginePlaybackSession) -> AVAudioFramePosition {
        guard session.durationFrames > 1 else { return 0 }
        let maxFrame = session.durationFrames - 1
        return AVAudioFramePosition((Double(maxFrame) * progress).rounded())
    }

    private func seconds(for frame: AVAudioFramePosition, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(max(frame, 0)) / sampleRate
    }

    private func playbackStateDescription(for clipID: UUID) -> String {
        switch playbackState(for: clipID) {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case nil:
            return "idle"
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "unknown" }
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

private final class EnginePlaybackSession {
    let token = UUID()
    let clipID: UUID
    let node = AVAudioPlayerNode()
    let audioFile: AVAudioFile
    let url: URL
    let sampleRate: Double
    let durationFrames: AVAudioFramePosition

    var startFrame: AVAudioFramePosition = 0
    var pausedFrame: AVAudioFramePosition?
    var generation = 0

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(durationFrames) / sampleRate
    }

    init(clipID: UUID, audioFile: AVAudioFile, url: URL) {
        self.clipID = clipID
        self.audioFile = audioFile
        self.url = url
        sampleRate = audioFile.processingFormat.sampleRate
        durationFrames = audioFile.length
    }
}

private enum AudioPlaybackError: LocalizedError {
    case emptyAudioFile
    case playbackDidNotStart

    var errorDescription: String? {
        switch self {
        case .emptyAudioFile:
            return "音频文件没有可播放的采样帧。"
        case .playbackDidNotStart:
            return "系统没有启动音频播放。"
        }
    }
}
