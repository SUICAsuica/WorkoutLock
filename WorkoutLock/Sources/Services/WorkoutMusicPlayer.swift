import AVFoundation
import Foundation

@MainActor
final class WorkoutMusicPlayer: ObservableObject {
    @Published private(set) var statusText = "停止中"

    private var player: AVAudioPlayer?

    @discardableResult
    func start(
        track: WorkoutMusicTrack,
        volume: Double,
        isEnabled: Bool,
        fallbackTracks: [WorkoutMusicTrack] = []
    ) -> WorkoutMusicTrack? {
        stop()
        guard isEnabled else {
            statusText = "オフ"
            return nil
        }

        let candidates = uniqueTracks([track] + fallbackTracks)

        var foundBundledAudio = false

        for candidate in candidates {
            guard let url = candidate.bundledURL() else { continue }
            foundBundledAudio = true

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)

                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = Float(min(1, max(0, volume)))
                audioPlayer.prepareToPlay()
                audioPlayer.play()
                player = audioPlayer
                statusText = candidate.title
                return candidate
            } catch {
                continue
            }
        }

        statusText = foundBundledAudio ? "再生失敗" : "音源未追加"
        return nil
    }

    func updateVolume(_ volume: Double) {
        player?.volume = Float(min(1, max(0, volume)))
    }

    func stop() {
        player?.stop()
        player = nil
        statusText = "停止中"
    }

    private func uniqueTracks(_ tracks: [WorkoutMusicTrack]) -> [WorkoutMusicTrack] {
        var seen = Set<WorkoutMusicTrack>()
        return tracks.filter { seen.insert($0).inserted }
    }
}
