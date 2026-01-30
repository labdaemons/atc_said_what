import AVFoundation
import Foundation

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case audioSessionSetupFailed(Error)
    case engineStartFailed(Error)
    case noInputNode

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied"
        case .audioSessionSetupFailed(let error):
            return "Failed to setup audio session: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            return "No audio input available"
        }
    }
}

protocol AudioCaptureServiceDelegate: AnyObject {
    func audioCaptureService(_ service: AudioCaptureService, didCaptureBuffer buffer: [Float])
    func audioCaptureService(_ service: AudioCaptureService, didEncounterError error: AudioCaptureError)
}

final class AudioCaptureService {

    // Whisper requires 16kHz sample rate
    static let sampleRate: Double = 16000

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    weak var delegate: AudioCaptureServiceDelegate?

    private(set) var isRecording = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        let granted = await requestPermission()
        guard granted else {
            throw AudioCaptureError.permissionDenied
        }

        try setupAudioSession()
        try setupAudioEngine()

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            throw AudioCaptureError.engineStartFailed(error)
        }
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        bufferLock.lock()
        let capturedAudio = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return capturedAudio
    }

    func getCurrentBuffer() -> [Float] {
        bufferLock.lock()
        let currentBuffer = audioBuffer
        bufferLock.unlock()
        return currentBuffer
    }

    func clearBuffer() {
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
    }

    private func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredSampleRate(Self.sampleRate)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.audioSessionSetupFailed(error)
        }
    }

    private func setupAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputNode
        }

        // Create format for Whisper (16kHz, mono, float)
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.noInputNode
        }

        // Create converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let converter = converter {
                self.processBufferWithConversion(buffer, converter: converter, outputFormat: whisperFormat)
            } else {
                self.processBuffer(buffer)
            }
        }
    }

    private func processBufferWithConversion(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * Self.sampleRate / inputBuffer.format.sampleRate)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, let floatChannelData = outputBuffer.floatChannelData else {
            return
        }

        let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: Int(outputBuffer.frameLength)))

        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()

        delegate?.audioCaptureService(self, didCaptureBuffer: samples)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: Int(buffer.frameLength)))

        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()

        delegate?.audioCaptureService(self, didCaptureBuffer: samples)
    }
}
