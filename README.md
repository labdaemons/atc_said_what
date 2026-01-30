# ATC Said What

An iOS app that transcribes audio from the microphone to text using the Whisper AI model, running entirely offline on-device.

## Features

- **Callsign/Tail Number Detection**: Enter your aircraft tail number (e.g., "N12345") and the app will continuously listen for ATC communications mentioning your callsign
- **Automatic Transcription**: When your callsign is detected, the app automatically captures and transcribes the full transmission
- **Real-Time Transcription**: See live transcription as you speak - text appears and updates every second during recording
- **Silence Detection**: Recording automatically stops after 1 second of silence, capturing complete transmissions without manual intervention
- **Phonetic Alphabet Support**: Recognizes both standard callsigns and NATO phonetic alphabet variations (e.g., "November One Two Three Four Five")
- **Manual Recording Mode**: Also supports traditional push-to-record transcription
- **Transcription History**: Keeps a log of all detected communications
- Real-time audio capture from the device microphone
- On-device speech-to-text transcription using Whisper
- No internet connection required after initial setup
- Clean SwiftUI interface with recording status and audio level visualization
- Copy transcription results to clipboard

## Requirements

- iOS 17.0+
- Xcode 15.0+
- A Whisper model file (see setup instructions)

## Setup

### 1. Clone and Open Project

```bash
git clone <repository-url>
cd atc_said_what
open ATCSaidWhat/ATCSaidWhat.xcodeproj
```

### 2. Download Whisper Model

Download a Whisper model file from the [whisper.cpp releases](https://huggingface.co/ggerganov/whisper.cpp/tree/main) or convert one yourself.

Recommended models for iOS:
- `ggml-tiny.bin` (~75MB) - Fastest, lower accuracy
- `ggml-base.bin` (~142MB) - Good balance (recommended)
- `ggml-small.bin` (~466MB) - Better accuracy, slower

### 3. Add Model to Xcode Project

1. Download your chosen model (e.g., `ggml-base.bin`)
2. Drag the model file into the Xcode project navigator
3. Ensure "Copy items if needed" is checked
4. Ensure the file is added to the "ATCSaidWhat" target

### 4. Build and Run

1. Select your target device (iPhone or iPad)
2. Build and run (Cmd+R)
3. Grant microphone permission when prompted

## Usage

### Automatic Callsign Detection Mode (Recommended)

1. **Enter Your Callsign**: Type your aircraft tail number in the input field (e.g., "N12345")
2. **Start Listening**: Tap "Start Listening for [callsign]" to begin monitoring
3. **Wait for Detection**: The app continuously analyzes audio for your callsign
4. **Automatic Capture**: When detected, the app continues recording until 1 second of silence, then transcribes
5. **View Results**: Transcriptions appear in the main area and are saved to history
6. **Stop**: Tap "Stop Listening" when done

### Manual Recording Mode

1. **Start Recording**: Tap the orange microphone button to begin recording
2. **Speak**: Speak clearly into the device microphone
3. **Auto-Stop**: Recording automatically stops after 1 second of silence (or tap stop manually)
4. **View Results**: The transcribed text will appear in the main text area

### Other Controls

- **Copy**: Use the copy button to copy the transcription to clipboard
- **Clear**: Use the trash button to clear the current transcription and history

## Architecture

```
ATCSaidWhat/
├── ATCSaidWhatApp.swift          # App entry point
├── ContentView.swift             # Main SwiftUI interface
├── TranscriptionViewModel.swift  # Business logic & state management
├── AudioCaptureService.swift     # Microphone audio capture (AVFoundation)
├── WhisperTranscriptionService.swift  # Whisper model wrapper
├── Info.plist                    # App configuration & permissions
└── Assets.xcassets/              # App icons & colors
```

## Dependencies

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C/C++ port of OpenAI's Whisper model with Swift bindings

## Privacy

- All audio processing happens entirely on-device
- No audio data is sent to any server
- No network connection required for transcription

## License

MIT License
