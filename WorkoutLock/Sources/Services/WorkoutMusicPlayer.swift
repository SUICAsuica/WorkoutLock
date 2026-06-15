import AVFoundation
import Foundation

@MainActor
final class WorkoutMusicPlayer: ObservableObject {
    @Published private(set) var statusText = "停止中"

    private var player: AVAudioPlayer?

    func start(track: WorkoutMusicTrack, volume: Double, isEnabled: Bool) {
        stop()
        guard isEnabled else {
            statusText = "オフ"
            return
        }

        let bundledURL = Bundle.main.url(
            forResource: track.resourceName,
            withExtension: track.resourceExtension,
            subdirectory: "Music"
        ) ?? Bundle.main.url(
            forResource: track.resourceName,
            withExtension: track.resourceExtension
        )

        guard let url = bundledURL else {
            statusText = "音源未追加"
            return
        }

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
            statusText = track.title
        } catch {
            statusText = "再生失敗"
        }
    }

    func updateVolume(_ volume: Double) {
        player?.volume = Float(min(1, max(0, volume)))
    }

    func stop() {
        player?.stop()
        player = nil
        statusText = "停止中"
    }
}
