import Foundation
import AVFoundation
import Combine

enum PlaybackState: Equatable {
    case idle
    case playing
    case paused
    case finished
}

/// Plays the last recorded WAV file using AVAudioPlayer.
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published var playbackState: PlaybackState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var currentURL: URL?

    // MARK: - Public API

    func load(url: URL) {
        stop()
        currentURL = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackState = .idle
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            currentTime = 0
            playbackState = .idle
        } catch {
            player = nil
            playbackState = .idle
            print("AudioPlayer: failed to load \(url.lastPathComponent) — \(error)")
        }
    }

    func play() {
        guard let p = player else { return }
        if playbackState == .finished {
            p.currentTime = 0
        }
        p.play()
        playbackState = .playing
        startTimer()
    }

    func pause() {
        player?.pause()
        playbackState = .paused
        stopTimer()
    }

    func restart() {
        player?.currentTime = 0
        currentTime = 0
        player?.play()
        playbackState = .playing
        startTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        stopTimer()
    }

    var canPlay: Bool { player != nil }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = self.player?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playbackState = .finished
            self.currentTime = self.duration
            self.stopTimer()
        }
    }
}
