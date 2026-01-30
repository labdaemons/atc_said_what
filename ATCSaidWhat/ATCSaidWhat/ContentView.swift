import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status indicator
                StatusView(state: viewModel.state)

                // Audio level indicator (shown when recording)
                if viewModel.state == .recording {
                    AudioLevelView(level: viewModel.audioLevel)
                        .frame(height: 8)
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                // Transcription display
                TranscriptionTextView(text: viewModel.transcribedText)

                Spacer()

                // Control buttons
                ControlButtonsView(
                    state: viewModel.state,
                    onToggleRecording: {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    },
                    onClear: {
                        viewModel.clearTranscription()
                    }
                )
            }
            .padding()
            .navigationTitle("ATC Said What")
            .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        }
    }
}

struct StatusView: View {
    let state: TranscriptionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if state == .recording {
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
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .error:
            return .red
        }
    }
}

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

struct TranscriptionTextView: View {
    let text: String

    var body: some View {
        ScrollView {
            if text.isEmpty {
                Text("Tap the microphone button to start recording.\nSpeak clearly and tap again to transcribe.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ControlButtonsView: View {
    let state: TranscriptionState
    let onToggleRecording: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 32) {
            // Clear button
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .disabled(state != .ready)
            .opacity(state == .ready ? 1 : 0.5)

            // Record button
            Button(action: onToggleRecording) {
                ZStack {
                    Circle()
                        .fill(recordButtonColor)
                        .frame(width: 80, height: 80)

                    if state == .recording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(!canRecord)
            .opacity(canRecord ? 1 : 0.5)
            .scaleEffect(state == .recording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: state)

            // Copy button
            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .disabled(state != .ready)
            .opacity(state == .ready ? 1 : 0.5)
        }
    }

    private var canRecord: Bool {
        state == .ready || state == .recording
    }

    private var recordButtonColor: Color {
        switch state {
        case .recording:
            return .red
        case .ready:
            return .blue
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
