import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @FocusState private var isTailNumberFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Tail number input
                TailNumberInputView(
                    tailNumber: $viewModel.tailNumber,
                    isFocused: $isTailNumberFocused,
                    isEnabled: viewModel.state == .ready
                )

                // Status indicator
                StatusView(state: viewModel.state, tailNumber: viewModel.tailNumber)

                // Audio level indicator
                if viewModel.state == .listening || viewModel.state == .recording || viewModel.state == .keywordDetected {
                    AudioLevelView(level: viewModel.audioLevel)
                        .frame(height: 8)
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                // Transcription display
                TranscriptionTextView(
                    text: viewModel.transcribedText,
                    liveText: viewModel.liveTranscription,
                    isLive: viewModel.state == .recording || viewModel.state == .keywordDetected,
                    history: viewModel.transcriptionHistory
                )

                Spacer()

                // Control buttons
                ControlButtonsView(
                    state: viewModel.state,
                    tailNumber: viewModel.tailNumber,
                    onStartListening: {
                        isTailNumberFocused = false
                        Task {
                            await viewModel.startListening()
                        }
                    },
                    onStopListening: {
                        viewModel.stopListening()
                    },
                    onToggleRecording: {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    },
                    onClear: {
                        viewModel.clearTranscription()
                        viewModel.clearHistory()
                    }
                )
            }
            .padding()
            .navigationTitle("ATC Said What")
            .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        }
    }
}

// MARK: - Tail Number Input

struct TailNumberInputView: View {
    @Binding var tailNumber: String
    var isFocused: FocusState<Bool>.Binding
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Callsign / Tail Number")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "airplane")
                    .foregroundStyle(.secondary)

                TextField("N12345", text: $tailNumber)
                    .textFieldStyle(.plain)
                    .font(.title2.monospaced())
                    .textCase(.uppercase)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .focused(isFocused)
                    .disabled(!isEnabled)

                if !tailNumber.isEmpty {
                    Button {
                        tailNumber = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!isEnabled)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.6)
        }
    }
}

// MARK: - Status View

struct StatusView: View {
    let state: TranscriptionState
    let tailNumber: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if state == .listening {
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.8)
                            .opacity(0.6)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: state)
                    } else if state == .recording || state == .keywordDetected {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.8)
                    }
                }

            Text(state.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .idle, .loadingModel:
            return .orange
        case .ready:
            return .green
        case .listening:
            return .blue
        case .keywordDetected:
            return .purple
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .error:
            return .red
        }
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))
            }
        }
    }

    private var levelColor: Color {
        if level < 0.3 {
            return .green
        } else if level < 0.7 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Transcription Text View

struct TranscriptionTextView: View {
    let text: String
    let liveText: String
    let isLive: Bool
    let history: [TranscriptionEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Live transcription (shown during recording)
                if isLive {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Live")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }

                        if liveText.isEmpty {
                            Text("Listening...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            Text(liveText)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .animation(.easeInOut(duration: 0.2), value: liveText)
                }

                if !isLive && text.isEmpty && history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)

                        Text("Enter your callsign above and tap 'Start Listening' to monitor for ATC communications.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if !isLive {
                    // Current transcription (shown after recording stops)
                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest Transcription")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // History
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("History")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(history) { entry in
                                TranscriptionHistoryRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TranscriptionHistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.tailNumber)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                Spacer()

                Text(entry.formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.transcription)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Control Buttons View

struct ControlButtonsView: View {
    let state: TranscriptionState
    let tailNumber: String
    let onStartListening: () -> Void
    let onStopListening: () -> Void
    let onToggleRecording: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Primary action button (Start/Stop Listening)
            if state == .listening || state == .keywordDetected {
                Button(action: onStopListening) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Listening")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(state == .keywordDetected)
                .opacity(state == .keywordDetected ? 0.6 : 1)
            } else if state == .ready && !tailNumber.isEmpty {
                Button(action: onStartListening) {
                    HStack {
                        Image(systemName: "ear.fill")
                        Text("Start Listening for \(tailNumber)")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Secondary controls
            HStack(spacing: 24) {
                // Clear button
                Button(action: onClear) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                        Text("Clear")
                            .font(.caption2)
                    }
                }
                .disabled(state != .ready)
                .opacity(state == .ready ? 1 : 0.5)

                // Manual record button
                Button(action: onToggleRecording) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(recordButtonColor)
                                .frame(width: 64, height: 64)

                            if state == .recording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(state == .recording ? "Stop" : "Manual")
                            .font(.caption2)
                    }
                }
                .disabled(!canManualRecord)
                .opacity(canManualRecord ? 1 : 0.5)
                .scaleEffect(state == .recording ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: state)

                // Copy button
                Button(action: copyToClipboard) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                        Text("Copy")
                            .font(.caption2)
                    }
                }
                .disabled(state != .ready)
                .opacity(state == .ready ? 1 : 0.5)
            }
            .foregroundStyle(.primary)
        }
    }

    private var canManualRecord: Bool {
        state == .ready || state == .recording
    }

    private var recordButtonColor: Color {
        switch state {
        case .recording:
            return .red
        case .ready:
            return .orange
        default:
            return .gray
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = ""
    }
}

#Preview {
    ContentView()
}
