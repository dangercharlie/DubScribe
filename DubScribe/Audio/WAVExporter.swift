import Foundation
import AVFoundation

/// Handles WAV file creation from AVAudioFile recordings.
/// AVAudioFile with kAudioFormatLinearPCM writes a valid WAV automatically.
enum WAVExporter {

    /// The audio format used for all recordings.
    static var recordingFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        )!
    }

    /// Settings dictionary for AVAudioRecorder (used as fallback).
    static var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
