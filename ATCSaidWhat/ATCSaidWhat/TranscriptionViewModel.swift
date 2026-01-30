import Foundation
import SwiftUI
import Combine

enum TranscriptionState: Equatable {
    case idle
    case loadingModel
    case ready
    case listening          // Continuously listening for keyword
    case keywordDetected    // Keyword found, capturing full transmission
    case recording          // Manual recording mode
    case transcribing
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Initializing..."
        case .loadingModel:
            return "Loading Whisper model..."
        case .ready:
            return "Ready"
        case .listening:
            return "Listening for callsign..."
        case .keywordDetected:
            return "Callsign detected! Recording..."
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
             (.listening, .listening), (.keywordDetected, .keywordDetected),
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
    @Published private(set) var liveTranscription: String = ""  // Real-time transcription during recording
    @Published private(set) var segments: [TranscriptionSegment] = []
    @Published private(set) var audioLevel: Float = 0.0
    @Published var tailNumber: String = "" {
        didSet {
            // Normalize tail number (uppercase, no spaces)
            let normalized = tailNumber.uppercased().replacingOccurrences(of: " ", with: "")
            if normalized != tailNumber {
                tailNumber = normalized
            }
        }
    }

    // History of transcriptions when keyword is detected
    @Published private(set) var transcriptionHistory: [TranscriptionEntry] = []

    private let audioService = AudioCaptureService()
    private let whisperService = WhisperTranscriptionService()

    private var audioLevelTimer: Timer?
    private var keywordDetectionTimer: Timer?
    private var silenceDetectionTimer: Timer?
    private var liveTranscriptionTimer: Timer?
    private var recordingStartTime: Date?
    private var isTranscribing = false  // Prevent overlapping transcription calls

    // Configuration for keyword detection
    private let keywordCheckInterval: TimeInterval = 2.0  // Check every 2 seconds
    private let keywordAudioWindow: Double = 4.0          // Analyze last 4 seconds for keyword

    // Configuration for silence detection
    private let silenceDuration: Double = 1.0             // Stop after 1 second of silence
    private let silenceThreshold: Float = 0.01            // Audio level threshold for silence
    private let silenceCheckInterval: UInt64 = 100_000_000 // Check every 0.1 seconds (in nanoseconds)
    private let maxRecordingDuration: Double = 30.0       // Maximum recording time as safety limit

    // Configuration for live transcription
    private let liveTranscriptionInterval: TimeInterval = 1.0  // Transcribe every 1 second

    private var keywordDetectionTime: Date?

    init() {
        Task {
            await loadModel()
        }
    }

    func loadModel() async {
        state = .loadingModel

        do {
            try await whisperService.loadModel(named: "ggml-base")
            state = .ready
        } catch WhisperError.modelNotFound {
            state = .error("Model not found. Please add ggml-base.bin to the app bundle.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Keyword Listening Mode

    func startListening() async {
        guard state == .ready, !tailNumber.isEmpty else { return }

        do {
            try await audioService.startRecording()
            state = .listening
            startKeywordDetection()
            startAudioLevelMonitoring()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stopListening() {
        stopKeywordDetection()
        stopAudioLevelMonitoring()
        _ = audioService.stopRecording()
        state = .ready
    }

    private func startKeywordDetection() {
        keywordDetectionTimer = Timer.scheduledTimer(withTimeInterval: keywordCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForKeyword()
            }
        }
    }

    private func stopKeywordDetection() {
        keywordDetectionTimer?.invalidate()
        keywordDetectionTimer = nil
    }

    private func checkForKeyword() async {
        guard state == .listening else { return }

        // Get recent audio for keyword detection
        let recentAudio = audioService.getRecentAudio(seconds: keywordAudioWindow)
        guard recentAudio.count > Int(AudioCaptureService.sampleRate) else { return } // Need at least 1 second

        do {
            let text = try await whisperService.transcribe(samples: recentAudio)
            let normalizedText = normalizeForComparison(text)
            let normalizedKeyword = normalizeForComparison(tailNumber)

            if normalizedText.contains(normalizedKeyword) {
                // Keyword detected!
                await onKeywordDetected()
            } else {
                // Trim buffer to prevent unbounded growth, keep enough for context
                audioService.trimBuffer(keepingLast: keywordAudioWindow + 2.0)
            }
        } catch {
            // Silently continue listening on transcription errors
        }
    }

    private func onKeywordDetected() async {
        state = .keywordDetected
        keywordDetectionTime = Date()
        liveTranscription = ""
        stopKeywordDetection()

        // Start live transcription while waiting for silence
        startLiveTranscription()

        // Wait for silence to indicate end of transmission
        await waitForSilence()

        // Stop live transcription before final transcription
        stopLiveTranscription()

        // Now transcribe the full captured audio
        await transcribeFullCapture()
    }

    private func waitForSilence() async {
        let startTime = Date()

        // Poll for silence
        while true {
            // Safety check: don't record forever
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= maxRecordingDuration {
                break
            }

            // Check if we have silence for the required duration
            if audioService.isSilent(forLast: silenceDuration, threshold: silenceThreshold) {
                // Ensure we have at least some audio (the keyword + some speech)
                let buffer = audioService.getCurrentBuffer()
                let minSamples = Int(AudioCaptureService.sampleRate * 2.0) // At least 2 seconds
                if buffer.count >= minSamples {
                    break
                }
            }

            // Wait before checking again
            try? await Task.sleep(nanoseconds: silenceCheckInterval)
        }
    }

    private func transcribeFullCapture() async {
        state = .transcribing

        let samples = audioService.stopRecording()

        guard !samples.isEmpty else {
            liveTranscription = ""
            state = .ready
            return
        }

        do {
            // Final transcription pass for accuracy
            let text = try await whisperService.transcribe(samples: samples)
            transcribedText = text
            liveTranscription = ""

            // Add to history
            let entry = TranscriptionEntry(
                timestamp: Date(),
                tailNumber: tailNumber,
                transcription: text
            )
            transcriptionHistory.insert(entry, at: 0)

            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Normalize text for keyword comparison (handles phonetic variations)
    private func normalizeForComparison(_ text: String) -> String {
        var normalized = text.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        // Handle common phonetic alphabet substitutions
        let phoneticNumbers: [String: String] = [
            "ZERO": "0", "ONE": "1", "TWO": "2", "THREE": "3",
            "FOUR": "4", "FIVE": "5", "SIX": "6", "SEVEN": "7",
            "EIGHT": "8", "NINER": "9", "NINE": "9"
        ]

        for (word, digit) in phoneticNumbers {
            normalized = normalized.replacingOccurrences(of: word, with: digit)
        }

        // Handle phonetic letters (NATO alphabet)
        let phoneticLetters: [String: String] = [
            "ALPHA": "A", "BRAVO": "B", "CHARLIE": "C", "DELTA": "D",
            "ECHO": "E", "FOXTROT": "F", "GOLF": "G", "HOTEL": "H",
            "INDIA": "I", "JULIET": "J", "JULIETT": "J", "KILO": "K",
            "LIMA": "L", "MIKE": "M", "NOVEMBER": "N", "OSCAR": "O",
            "PAPA": "P", "QUEBEC": "Q", "ROMEO": "R", "SIERRA": "S",
            "TANGO": "T", "UNIFORM": "U", "VICTOR": "V", "WHISKEY": "W",
            "XRAY": "X", "X-RAY": "X", "YANKEE": "Y", "ZULU": "Z"
        ]

        for (word, letter) in phoneticLetters {
            normalized = normalized.replacingOccurrences(of: word, with: letter)
        }

        return normalized
    }

    // MARK: - Manual Recording Mode

    func toggleRecording() async {
        switch state {
        case .ready:
            await startRecording()
        case .recording:
            await stopRecordingAndTranscribe()
        case .listening:
            stopListening()
        default:
            break
        }
    }

    private func startRecording() async {
        do {
            try await audioService.startRecording()
            state = .recording
            recordingStartTime = Date()
            liveTranscription = ""
            startAudioLevelMonitoring()
            startSilenceDetection()
            startLiveTranscription()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() async {
        stopSilenceDetection()
        stopLiveTranscription()
        stopAudioLevelMonitoring()
        let samples = audioService.stopRecording()

        guard !samples.isEmpty else {
            liveTranscription = ""
            state = .ready
            return
        }

        state = .transcribing

        do {
            // Final transcription pass for accuracy
            let text = try await whisperService.transcribe(samples: samples)
            transcribedText = text
            liveTranscription = ""
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func startSilenceDetection() {
        silenceDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .recording else { return }

                // Need at least 2 seconds of audio before checking for silence
                guard let startTime = self.recordingStartTime,
                      Date().timeIntervalSince(startTime) >= 2.0 else { return }

                // Check for silence
                if self.audioService.isSilent(forLast: self.silenceDuration, threshold: self.silenceThreshold) {
                    await self.stopRecordingAndTranscribe()
                }

                // Safety: stop after max duration
                if Date().timeIntervalSince(startTime) >= self.maxRecordingDuration {
                    await self.stopRecordingAndTranscribe()
                }
            }
        }
    }

    private func stopSilenceDetection() {
        silenceDetectionTimer?.invalidate()
        silenceDetectionTimer = nil
        recordingStartTime = nil
    }

    // MARK: - Live Transcription

    private func startLiveTranscription() {
        liveTranscriptionTimer = Timer.scheduledTimer(withTimeInterval: liveTranscriptionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performLiveTranscription()
            }
        }
    }

    private func stopLiveTranscription() {
        liveTranscriptionTimer?.invalidate()
        liveTranscriptionTimer = nil
        isTranscribing = false
    }

    private func performLiveTranscription() async {
        // Prevent overlapping transcription calls
        guard !isTranscribing else { return }
        guard state == .recording || state == .keywordDetected else { return }

        let samples = audioService.getCurrentBuffer()
        guard samples.count > Int(AudioCaptureService.sampleRate * 0.5) else { return } // Need at least 0.5 seconds

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let text = try await whisperService.transcribe(samples: samples)
            // Only update if we're still recording
            if state == .recording || state == .keywordDetected {
                liveTranscription = text
            }
        } catch {
            // Silently continue on transcription errors during live mode
        }
    }

    func clearTranscription() {
        transcribedText = ""
        segments = []
    }

    func clearHistory() {
        transcriptionHistory = []
    }

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let buffer = self.audioService.getCurrentBuffer()
                if !buffer.isEmpty {
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

// MARK: - Models

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let tailNumber: String
    let transcription: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}
