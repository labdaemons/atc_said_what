import Foundation
import whisper

enum WhisperError: Error, LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case transcriptionFailed
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Whisper model file not found in app bundle"
        case .modelLoadFailed:
            return "Failed to load Whisper model"
        case .transcriptionFailed:
            return "Transcription failed"
        case .contextCreationFailed:
            return "Failed to create Whisper context"
        }
    }
}

struct TranscriptionSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

final class WhisperTranscriptionService {

    private var whisperContext: OpaquePointer?
    private let processingQueue = DispatchQueue(label: "com.atcsaidwhat.whisper", qos: .userInitiated)

    private(set) var isModelLoaded = false

    deinit {
        if let context = whisperContext {
            whisper_free(context)
        }
    }

    /// Load Whisper model from the app bundle
    /// - Parameter modelName: Name of the model file (without extension), e.g., "ggml-tiny", "ggml-base", "ggml-small"
    func loadModel(named modelName: String = "ggml-base") async throws {
        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: WhisperError.contextCreationFailed)
                    return
                }

                // Look for model in bundle
                guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "bin") else {
                    continuation.resume(throwing: WhisperError.modelNotFound)
                    return
                }

                // Free existing context if any
                if let existingContext = self.whisperContext {
                    whisper_free(existingContext)
                    self.whisperContext = nil
                }

                // Initialize Whisper context with default parameters
                var params = whisper_context_default_params()
                params.use_gpu = true

                guard let context = whisper_init_from_file_with_params(modelPath, params) else {
                    continuation.resume(throwing: WhisperError.modelLoadFailed)
                    return
                }

                self.whisperContext = context
                self.isModelLoaded = true
                continuation.resume()
            }
        }
    }

    /// Transcribe audio samples
    /// - Parameter samples: Audio samples in Float format at 16kHz sample rate
    /// - Returns: Transcribed text
    func transcribe(samples: [Float]) async throws -> String {
        guard let context = whisperContext else {
            throw WhisperError.modelLoadFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                // Configure transcription parameters
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.print_realtime = false
                params.print_progress = false
                params.print_timestamps = false
                params.print_special = false
                params.single_segment = false
                params.max_tokens = 0
                params.language = "en".withCString { strdup($0) }
                params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))

                // Run transcription
                let result = samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(context, params, samplesPtr.baseAddress, Int32(samples.count))
                }

                if result != 0 {
                    continuation.resume(throwing: WhisperError.transcriptionFailed)
                    return
                }

                // Extract transcribed text
                var transcription = ""
                let numSegments = whisper_full_n_segments(context)

                for i in 0..<numSegments {
                    if let segmentText = whisper_full_get_segment_text(context, i) {
                        transcription += String(cString: segmentText)
                    }
                }

                continuation.resume(returning: transcription.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Transcribe audio samples and return segments with timestamps
    /// - Parameter samples: Audio samples in Float format at 16kHz sample rate
    /// - Returns: Array of transcription segments with timing information
    func transcribeWithTimestamps(samples: [Float]) async throws -> [TranscriptionSegment] {
        guard let context = whisperContext else {
            throw WhisperError.modelLoadFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                // Configure transcription parameters
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.print_realtime = false
                params.print_progress = false
                params.print_timestamps = true
                params.print_special = false
                params.single_segment = false
                params.max_tokens = 0
                params.language = "en".withCString { strdup($0) }
                params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))

                // Run transcription
                let result = samples.withUnsafeBufferPointer { samplesPtr in
                    whisper_full(context, params, samplesPtr.baseAddress, Int32(samples.count))
                }

                if result != 0 {
                    continuation.resume(throwing: WhisperError.transcriptionFailed)
                    return
                }

                // Extract segments with timestamps
                var segments: [TranscriptionSegment] = []
                let numSegments = whisper_full_n_segments(context)

                for i in 0..<numSegments {
                    if let segmentText = whisper_full_get_segment_text(context, i) {
                        let text = String(cString: segmentText)
                        let startTime = TimeInterval(whisper_full_get_segment_t0(context, i)) / 100.0
                        let endTime = TimeInterval(whisper_full_get_segment_t1(context, i)) / 100.0

                        let segment = TranscriptionSegment(
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            startTime: startTime,
                            endTime: endTime
                        )
                        segments.append(segment)
                    }
                }

                continuation.resume(returning: segments)
            }
        }
    }
}
