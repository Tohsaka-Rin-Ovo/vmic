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

    private var playersByClipID: [UUID: AVAudioPlayer] = [:]
    private var clipIDsByPlayerID: [ObjectIdentifier: UUID] = [:]
    private var outputVolume: Float = 1
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

    func setOutputVolume(_ volume: Double) {
        outputVolume = Float(min(max(volume, 0), 1))
        playersByClipID.values.forEach { player in
            player.volume = outputVolume
        }
    }

    func toggle(_ clip: SoundClip, from directory: URL, volume: Double) {
        setOutputVolume(volume)

        switch playbackState(for: clip.id) {
        case .playing:
            pause(clip)
        case .paused:
            resume(clip)
        case nil:
            play(clip, from: directory)
        }
    }

    func play(_ clip: SoundClip, from directory: URL) {
        let url = clip.fileURL(in: directory)

        do {
            try configureAudioSession()

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = outputVolume
            player.prepareToPlay()

            if let existingPlayer = playersByClipID[clip.id] {
                existingPlayer.stop()
                clipIDsByPlayerID[ObjectIdentifier(existingPlayer)] = nil
            }

            playersByClipID[clip.id] = player
            clipIDsByPlayerID[ObjectIdentifier(player)] = clip.id
            activeClipIDs.insert(clip.id)
            pausedClipIDs.remove(clip.id)
            currentClipID = clip.id

            player.play()
            refreshPlaybackProgress()
            startProgressTimerIfNeeded()
            lastError = nil
        } catch {
            activeClipIDs.remove(clip.id)
            pausedClipIDs.remove(clip.id)
            playbackProgressByClipID[clip.id] = nil
            elapsedTimeByClipID[clip.id] = nil
            durationByClipID[clip.id] = nil
            lastError = "无法播放 \(clip.title)：\(error.localizedDescription)"
        }
    }

    func pause(_ clip: SoundClip) {
        guard let player = playersByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        player.pause()
        pausedClipIDs.insert(clip.id)
        currentClipID = clip.id
        refreshPlaybackProgress()
    }

    func resume(_ clip: SoundClip) {
        guard let player = playersByClipID[clip.id], activeClipIDs.contains(clip.id) else { return }

        do {
            try configureAudioSession()
            player.volume = outputVolume
            player.play()
            pausedClipIDs.remove(clip.id)
            currentClipID = clip.id
            refreshPlaybackProgress()
            startProgressTimerIfNeeded()
            lastError = nil
        } catch {
            lastError = "无法继续播放 \(clip.title)：\(error.localizedDescription)"
        }
    }

    func stop(_ clip: SoundClip) {
        if let player = playersByClipID[clip.id] {
            player.stop()
            clipIDsByPlayerID[ObjectIdentifier(player)] = nil
        }

        playersByClipID[clip.id] = nil
        activeClipIDs.remove(clip.id)
        pausedClipIDs.remove(clip.id)
        playbackProgressByClipID[clip.id] = nil
        elapsedTimeByClipID[clip.id] = nil
        durationByClipID[clip.id] = nil
        updateCurrentClip(afterRemoving: clip.id)
        stopProgressTimerIfNeeded()
    }

    func stopAll() {
        playersByClipID.values.forEach { $0.stop() }
        playersByClipID.removeAll()
        clipIDsByPlayerID.removeAll()
        activeClipIDs.removeAll()
        pausedClipIDs.removeAll()
        currentClipID = nil
        playbackProgressByClipID.removeAll()
        elapsedTimeByClipID.removeAll()
        durationByClipID.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            clear(player)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            lastError = error?.localizedDescription
            clear(player)
        }
    }

    private func clear(_ player: AVAudioPlayer) {
        let playerID = ObjectIdentifier(player)
        guard let clipID = clipIDsByPlayerID[playerID] else { return }

        playersByClipID[clipID] = nil
        clipIDsByPlayerID[playerID] = nil
        activeClipIDs.remove(clipID)
        pausedClipIDs.remove(clipID)
        playbackProgressByClipID[clipID] = nil
        elapsedTimeByClipID[clipID] = nil
        durationByClipID[clipID] = nil
        updateCurrentClip(afterRemoving: clipID)
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

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
    }
}
