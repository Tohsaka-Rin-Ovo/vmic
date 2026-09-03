import AVFoundation
import Foundation

enum SoundPlaybackState: Equatable {
    case playing
    case paused
}

@MainActor
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var activeClipIDs: Set<UUID> = []
    @Published private(set) var pausedClipIDs: Set<UUID> = []
    @Published private(set) var currentClipID: UUID?
    @Published private(set) var playbackProgressByClipID: [UUID: Double] = [:]
    @Published private(set) var elapsedTimeByClipID: [UUID: TimeInterval] = [:]
    @Published private(set) var durationByClipID: [UUID: TimeInterval] = [:]
    @Published var lastError: String?

    var playbackDidFinish: ((UUID) -> Void)?

    private var playersByClipID: [UUID: AVAudioPlayer] = [:]
    private var clipIDsByPlayerID: [ObjectIdentifier: UUID] = [:]
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
        elapsedTimeByClipID[clipID] ?? playersByClipID[clipID]?.currentTime ?? 0
    }

    func duration(for clipID: UUID) -> TimeInterval? {
        if let duration = durationByClipID[clipID], duration.isFinite, duration > 0 {
            return duration
        }

        guard let player = playersByClipID[clipID], player.duration.isFinite, player.duration > 0 else {
            return nil
        }

        return player.duration
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
        guard let player = playersByClipID[clipID] else { return }

        let duration = player.duration
        guard duration.isFinite, duration > 0 else { return }

        let targetProgress = min(max(progress, 0), 1)
        player.currentTime = duration * targetProgress
        currentClipID = clipID
        refreshPlaybackProgress()
        DiagnosticLogStore.shared.log(
            "调整播放进度",
            source: .playback,
            details: [
                "clipID=\(shortID(clipID))",
                "progress=\(formatPercent(targetProgress))",
                "time=\(formatSeconds(player.currentTime))",
                "duration=\(formatSeconds(duration))"
            ]
        )

        if player.isPlaying {
            startProgressTimerIfNeeded()
        }
    }

    func setOutputVolume(_ volume: Double) {
        outputVolume = Float(min(max(volume, 0), 1))
        playersByClipID.values.forEach { player in
            player.volume = outputVolume
        }

        let shouldLog = lastLoggedOutputVolume.map { abs($0 - outputVolume) >= 0.01 } ?? true
        if shouldLog {
            lastLoggedOutputVolume = outputVolume
            DiagnosticLogStore.shared.log(
                "设置文件音频音量",
                source: .playback,
                details: ["volume=\(formatPercent(Double(outputVolume)))", "activePlayers=\(playersByClipID.count)"]
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

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = outputVolume
            player.prepareToPlay()

            if let existingPlayer = playersByClipID[clip.id] {
                existingPlayer.stop()
                clipIDsByPlayerID[ObjectIdentifier(existingPlayer)] = nil
                playersByClipID[clip.id] = nil
            }

            let didStart = player.play()
            guard didStart else {
                throw AudioPlaybackError.playbackDidNotStart
            }

            playersByClipID[clip.id] = player
            clipIDsByPlayerID[ObjectIdentifier(player)] = clip.id
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
                "播放音频已调用",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "didStart=\(didStart)",
                    "duration=\(formatSeconds(player.duration))",
                    "sampleRate=\(Int(player.format.sampleRate.rounded()))",
                    "channels=\(player.format.channelCount)"
                ]
            )
        } catch {
            playersByClipID[clip.id] = nil
            activeClipIDs.remove(clip.id)
            pausedClipIDs.remove(clip.id)
            playbackProgressByClipID[clip.id] = nil
            elapsedTimeByClipID[clip.id] = nil
            durationByClipID[clip.id] = nil
            playbackStartedAtByClipID[clip.id] = nil
            playbackCompletionCountByClipID[clip.id] = nil
            updateCurrentClip(afterRemoving: clip.id)
            lastError = "无法播放 \(clip.title)：\(error.localizedDescription)"
            DiagnosticLogStore.shared.log(
                "播放音频失败",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "error=\(error.localizedDescription)"
                ]
            )
        }
    }

    func pause(_ clip: SoundClip) {
        guard let player = playersByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        player.pause()
        pausedClipIDs.insert(clip.id)
        currentClipID = clip.id
        refreshPlaybackProgress()
        DiagnosticLogStore.shared.log(
            "暂停音频",
            source: .playback,
            details: [
                "title=\(clip.title)",
                "clipID=\(shortID(clip.id))",
                "time=\(formatSeconds(player.currentTime))"
            ]
        )
    }

    func resume(
        _ clip: SoundClip,
        reapplyInjectionPreference: (@MainActor () throws -> Void)? = nil
    ) {
        guard let player = playersByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        do {
            try configureAudioSession(reapplyInjectionPreference: reapplyInjectionPreference)
            player.volume = outputVolume
            let didStart = player.play()
            guard didStart else {
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
                    "didStart=\(didStart)",
                    "time=\(formatSeconds(player.currentTime))"
                ]
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
        if let player = playersByClipID[clip.id] {
            DiagnosticLogStore.shared.log(
                "停止音频",
                source: .playback,
                details: [
                    "title=\(clip.title)",
                    "clipID=\(shortID(clip.id))",
                    "time=\(formatSeconds(player.currentTime))"
                ]
            )
            player.stop()
            clipIDsByPlayerID[ObjectIdentifier(player)] = nil
        }

        playersByClipID[clip.id] = nil
        activeClipIDs.remove(clip.id)
        pausedClipIDs.remove(clip.id)
        playbackProgressByClipID[clip.id] = nil
        elapsedTimeByClipID[clip.id] = nil
        durationByClipID[clip.id] = nil
        playbackStartedAtByClipID[clip.id] = nil
        playbackCompletionCountByClipID[clip.id] = nil
        updateCurrentClip(afterRemoving: clip.id)
        stopProgressTimerIfNeeded()
    }

    func stopAll() {
        DiagnosticLogStore.shared.log(
            "停止全部音频",
            source: .playback,
            details: ["activePlayers=\(playersByClipID.count)"]
        )
        playersByClipID.values.forEach { $0.stop() }
        playersByClipID.removeAll()
        clipIDsByPlayerID.removeAll()
        activeClipIDs.removeAll()
        pausedClipIDs.removeAll()
        currentClipID = nil
        playbackProgressByClipID.removeAll()
        elapsedTimeByClipID.removeAll()
        durationByClipID.removeAll()
        playbackStartedAtByClipID.removeAll()
        playbackCompletionCountByClipID.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if let clipID = clipIDsByPlayerID[ObjectIdentifier(player)] {
                DiagnosticLogStore.shared.log(
                    "音频播放完成",
                    source: .playback,
                    details: [
                        "clipID=\(shortID(clipID))",
                        "successfully=\(flag)"
                    ]
                )
                playbackCompletionCountByClipID[clipID, default: 0] += 1
                playbackDidFinish?(clipID)
            }
            clear(player, preserveSessionCounters: true)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            lastError = error?.localizedDescription
            DiagnosticLogStore.shared.log(
                "音频解码错误",
                source: .playback,
                details: ["error=\(error?.localizedDescription ?? "unknown")"]
            )
            clear(player)
        }
    }

    private func clear(_ player: AVAudioPlayer, preserveSessionCounters: Bool = false) {
        let playerID = ObjectIdentifier(player)
        guard let clipID = clipIDsByPlayerID[playerID] else { return }
        let isCurrentPlayer = playersByClipID[clipID].map { ObjectIdentifier($0) == playerID } ?? false

        if isCurrentPlayer {
            playersByClipID[clipID] = nil
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
        }

        clipIDsByPlayerID[playerID] = nil
        stopProgressTimerIfNeeded()
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
        guard playersByClipID.isEmpty else { return }
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshPlaybackProgress() {
        guard !playersByClipID.isEmpty else {
            playbackProgressByClipID.removeAll()
            elapsedTimeByClipID.removeAll()
            durationByClipID.removeAll()
            stopProgressTimerIfNeeded()
            return
        }

        var progressByClipID: [UUID: Double] = [:]
        var elapsedByClipID: [UUID: TimeInterval] = [:]
        var durationByClipID: [UUID: TimeInterval] = [:]

        for (clipID, player) in playersByClipID {
            let duration = player.duration
            let elapsed = max(player.currentTime, 0)
            elapsedByClipID[clipID] = elapsed

            guard duration.isFinite, duration > 0 else {
                progressByClipID[clipID] = 0
                continue
            }

            durationByClipID[clipID] = duration
            progressByClipID[clipID] = min(max(elapsed / duration, 0), 1)
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
            "配置播放音频会话开始",
            source: .playback,
            details: [
                "categoryBefore=\(session.category.rawValue)",
                "modeBefore=\(session.mode.rawValue)",
                "optionsBefore=\(session.categoryOptions.rawValue)",
                "sampleRateBefore=\(Int(session.sampleRate.rounded()))"
            ]
        )
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        DiagnosticLogStore.shared.log(
            "播放音频会话 setCategory 完成",
            source: .playback,
            details: [
                "category=\(session.category.rawValue)",
                "mode=\(session.mode.rawValue)",
                "options=\(session.categoryOptions.rawValue)"
            ]
        )
        try session.setActive(true)
        DiagnosticLogStore.shared.log(
            "播放音频会话 setActive 完成",
            source: .playback,
            details: [
                "sampleRate=\(Int(session.sampleRate.rounded()))",
                "inputs=\(session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ","))",
                "outputs=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
            ]
        )
        try reapplyInjectionPreference?()
        DiagnosticLogStore.shared.log(
            "播放音频会话配置完成",
            source: .playback,
            details: [
                "category=\(session.category.rawValue)",
                "mode=\(session.mode.rawValue)",
                "options=\(session.categoryOptions.rawValue)"
            ]
        )
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
}

private enum AudioPlaybackError: LocalizedError {
    case playbackDidNotStart

    var errorDescription: String? {
        switch self {
        case .playbackDidNotStart:
            return "系统没有启动音频播放。"
        }
    }
}
