import SwiftUI

extension SongFolderSetupSheet {
    enum KeyDetectionState: Equatable {
        case idle
        case detecting
        case detected(SongKeyDetector.DetectedKey)
        case failed(String)
    }

    var keySection: some View {
        Section {
            Picker("Key", selection: $keySelection) {
                Text("None").tag("")
                ForEach(SongMusicalKey.chromaticOrder, id: \.rawValue) { key in
                    Text(key.displayName).tag(key.rawValue)
                }
            }
            Picker("Mode", selection: $keyMode) {
                ForEach(SongKeyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(keySelection.isEmpty)
            if SongKeyDetector.isSupported {
                detectKeyRow
            }
        } header: {
            Text("Key")
        } footer: {
            if let keyFooter {
                Text(keyFooter)
            }
        }
    }

    private var detectKeyRow: some View {
        HStack {
            Button(action: detectKey) {
                Label("Detect Key", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(keyDetection == .detecting || currentPreview.trackURLs.isEmpty)
            Spacer()
            detectionStatus
        }
    }

    @ViewBuilder
    private var detectionStatus: some View {
        switch keyDetection {
        case .detecting:
            ProgressView()
                .controlSize(.small)
        case .detected(let detected):
            Label(detected.label, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .idle, .failed:
            EmptyView()
        }
    }

    private var keyFooter: String? {
        guard SongKeyDetector.isSupported else { return nil }
        switch keyDetection {
        case .idle:
            if currentPreview.trackURLs.isEmpty {
                return "Add audio stems to the folder to detect the key."
            }
            return "Detect Key listens to the stems on this device. Nothing is uploaded."
        case .detecting:
            return "Listening to the stems…"
        case .detected:
            return "Detected from the stems. You can still change it."
        case .failed(let message):
            return message
        }
    }

    func detectKey() {
        cancelKeyDetection()
        let preview = currentPreview
        keyDetection = .detecting
        keyDetectionTask = Task {
            do {
                let detected = try await SongKeyDetector.detectKey(
                    folderURL: preview.folderURL,
                    trackURLs: preview.trackURLs
                )
                guard !Task.isCancelled, preview.id == currentPreview.id else { return }
                keySelection = detected.key.rawValue
                keyMode = detected.mode
                keyDetection = .detected(detected)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                keyDetection = .failed(error.localizedDescription)
            }
        }
    }

    func cancelKeyDetection() {
        keyDetectionTask?.cancel()
        keyDetectionTask = nil
        keyDetection = .idle
    }
}
