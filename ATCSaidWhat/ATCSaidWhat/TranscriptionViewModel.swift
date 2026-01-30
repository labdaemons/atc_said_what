import Foundation
import SwiftUI
import Combine

enum TranscriptionState: Equatable {
    case idle
    case loadingModel
    case ready
    case recording
    case transcribing
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Initializing..."
        case .loadingModel:
            return "Loading Whisper model..."
        case .ready:
            return "Ready to record"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loadingModel, .loadingModel), (.ready, .ready),
             (.recording, .recording), (.transcribing, .transcribing):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

@MainActor
final class TranscriptionViewModel: ObservableObject {

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var segments: [TranscriptionSegment] = []
    @Published private(set) var audioLevel: Float = 0.0

    private let audioService = AudioCaptureService()
    private let whisperService = WhisperTranscriptionService()

    private var audioLevelTimer: Timer?

    init() {
        Task {
            await loadModel()
        }
    }

    func loadModel() async {
        state = .loadingModel

        do {
            // Try to load model - user needs to add the model file to the bundle
            try await whisperService.loadModel(named: "ggml-base")
            state = .ready
        } catch WhisperError.modelNotFound {
            // Model not found - show instructions
            state = .error("Model not found. Please add ggml-base.bin to the app bundle.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func toggleRecording() async {
        switch state {
        case .ready:
            await startRecording()
        case .recording:
            await stopRecordingAndTranscribe()
        default:
            break
        }
    }

    private func startRecording() async {
        do {
            try await audioService.startRecording()
            state = .recording
            startAudioLevelMonitoring()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() async {
        stopAudioLevelMonitoring()
        let samples = audioService.stopRecording()

        guard !samples.isEmpty else {
            state = .ready
            return
        }

        state = .transcribing

        do {
            let text = try await whisperService.transcribe(samples: samples)
            transcribedText = text
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func transcribeWithTimestamps() async {
        stopAudioLevelMonitoring()
        let samples = audioService.stopRecording()

        guard !samples.isEmpty else {
            state = .ready
            return
        }

        state = .transcribing

        do {
            let newSegments = try await whisperService.transcribeWithTimestamps(samples: samples)
            segments = newSegments
            transcribedText = newSegments.map { $0.text }.joined(separator: " ")
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func clearTranscription() {
        transcribedText = ""
        segments = []
    }

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let buffer = self.audioService.getCurrentBuffer()
                if !buffer.isEmpty {
                    // Calculate RMS for audio level
                    let rms = sqrt(buffer.suffix(1600).map { $0 * $0 }.reduce(0, +) / Float(min(buffer.count, 1600)))
                    self.audioLevel = min(1.0, rms * 10)
                }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0
    }
}
