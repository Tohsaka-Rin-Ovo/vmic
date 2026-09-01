import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var activeClipIDs: Set<UUID> = []
    @Published var lastError: String?

    private var playersByClipID: [UUID: AVAudioPlayer] = [:]
    private var clipIDsByPlayerID: [ObjectIdentifier: UUID] = [:]

    func play(_ clip: SoundClip, from directory: URL) {
        let url = clip.fileURL(in: directory)

        do {
            try configureAudioSession()

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            playersByClipID[clip.id]?.stop()
            playersByClipID[clip.id] = player
            clipIDsByPlayerID[ObjectIdentifier(player)] = clip.id
            activeClipIDs.insert(clip.id)

            player.play()
            lastError = nil
        } catch {
            activeClipIDs.remove(clip.id)
            lastError = "Cannot play \(clip.title): \(error.localizedDescription)"
        }
    }

    func stop(_ clip: SoundClip) {
        playersByClipID[clip.id]?.stop()
        playersByClipID[clip.id] = nil
        activeClipIDs.remove(clip.id)
    }

    func stopAll() {
        playersByClipID.values.forEach { $0.stop() }
        playersByClipID.removeAll()
        clipIDsByPlayerID.removeAll()
        activeClipIDs.removeAll()
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
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
    }
}
