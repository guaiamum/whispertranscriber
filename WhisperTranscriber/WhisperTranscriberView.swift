import SwiftUI

struct WhisperTranscriberView: View {
    @StateObject private var vm = RecorderViewModel.shared
    @ObservedObject private var settings = SettingsManager.shared

    var showRecords: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            if vm.isPrewarming {
                PrewarmingView(isDownloading: vm.isDownloading, downloadProgress: vm.downloadProgress)
            } else {
                IdleRecordingView(
                    settings: settings,
                    isRecording: vm.isRecording,
                    activity: vm.activity,
                    livePreview: vm.livePreview,
                    showRecords: showRecords
                )
            }
        }
        .frame(width: 300)
        .fontDesign(.rounded)
        .tint(.orange)
        .alert(isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Alert(
                title: Text("Error"),
                message: Text(vm.errorMessage ?? "An unexpected error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct PrewarmingView: View {
    var isDownloading: Bool
    var downloadProgress: Double

    private var activity: RecorderActivity { isDownloading ? .downloading : .preparing }

    var body: some View {
        VStack(spacing: 12) {
            PanelHeader()

            VStack(spacing: 10) {
                ActivityBadge(activity: activity)

                VStack(spacing: 3) {
                    Text(isDownloading ? "Downloading Parakeet…" : "Warming up Parakeet…")
                        .font(.headline)
                    Text(isDownloading ? "This only happens once per install." : "About a second on the Neural Engine.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if isDownloading {
                    ProgressView(value: downloadProgress, total: 1.0)
                        .tint(activity.tint)
                    Text("The non-Lite version ships with the model, so it skips this step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .cardBackground()

            PanelFooter(showRecords: nil)
        }
        .padding(14)
    }
}

struct IdleRecordingView: View {
    @ObservedObject var settings: SettingsManager
    var isRecording: Bool
    var activity: RecorderActivity
    var livePreview: String
    var showRecords: () -> Void

    @AppStorage("showAdvancedSettings") private var showAdvanced = false

    var body: some View {
        VStack(spacing: 12) {
            PanelHeader()

            StatusCard(
                activity: activity,
                hotkey: settings.hotkey,
                holdToTalk: settings.holdToTalkEnabled,
                autoPaste: settings.autoPasteEnabled,
                livePreview: livePreview
            )

            VStack(spacing: 0) {
                SettingRow(title: "Shortcut", systemImage: "command") {
                    HotkeyRecorderView(chord: $settings.hotkey) { newChord in
                        let old = settings.hotkey
                        settings.hotkey = newChord
                        if !RecorderViewModel.registerHotkey(newChord) {
                            settings.hotkey = old
                            RecorderViewModel.registerHotkey(old)
                        }
                    }
                    .frame(width: 96, height: 24)
                }
                .help("Click, then press the new shortcut, e.g. ⌥Space.")

                RowDivider()

                ToggleRow(title: "Hold to Talk", systemImage: "hand.tap", isOn: $settings.holdToTalkEnabled)
                    .disabled(isRecording)
                    .help("On: hold the shortcut while you speak, release to transcribe. Off: press once to start, again to stop.")

                RowDivider()

                ToggleRow(title: "Paste Automatically", systemImage: "doc.on.clipboard", isOn: $settings.autoPasteEnabled)
                    .onChange(of: settings.autoPasteEnabled) { _, enabled in
                        if enabled { requestPasteAccess() }
                    }
                    .help("Pastes the transcript into the app you're typing in. Needs Accessibility access, asked for the first time.")

                RowDivider()

                ToggleRow(title: "Live Transcription", systemImage: "captions.bubble", isOn: $settings.liveTranscriptionEnabled)
                    .disabled(isRecording)
                    .help("Locked in when a recording starts. Off records silently and transcribes once at the end.")

                RowDivider()

                ToggleRow(title: "Detect Speakers", systemImage: "person.2", isOn: $settings.speakerDetectionEnabled)
                    .disabled(isRecording)
                    .help("Labels each turn in the final transcript. For conversations, not dictation. Downloads ~130MB the first time.")

                RowDivider()

                SettingRow(title: "Suffix", systemImage: "text.append") {
                    TextField("None", text: $settings.suffix)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 96)
                }
                .help("Added to the end of every transcript.")
            }
            .cardBackground()

            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) { showAdvanced.toggle() }
                } label: {
                    SettingRow(title: "Advanced", systemImage: "slider.horizontal.3") {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    RowDivider()

                    ToggleRow(title: "Fade Volume", systemImage: "speaker.wave.2", isOn: $settings.fadeVolumeEnabled)

                    if settings.fadeVolumeEnabled {
                        RowDivider()

                        SettingRow(title: "Fade Duration", systemImage: "timer") {
                            HStack(spacing: 4) {
                                TextField("Fade Milliseconds", value: $settings.fadeMilliseconds, format: .number)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("ms")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    RowDivider()

                    SettingRow(title: "Delete Recordings", systemImage: "trash") {
                        Picker("Delete Recordings", selection: $settings.recordingRetentionDays) {
                            Text("Never").tag(0)
                            Text("After 1 day").tag(1)
                            Text("After 7 days").tag(7)
                            Text("After 30 days").tag(30)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .help("Recordings are stored unencrypted on this Mac. Older ones are deleted automatically.")

                    RowDivider()

                    ToggleRow(title: "Clean Up Text", systemImage: "wand.and.stars", isOn: $settings.cleanupEnabled)

                    if settings.cleanupEnabled {
                        RowDivider()

                        ToggleRow(title: "Also Remove \"um\"", systemImage: "text.badge.minus", isOn: $settings.removeUm)
                    }
                }
            }
            .cardBackground()

            PanelFooter(showRecords: showRecords)
        }
        .padding(14)
    }
}

// MARK: - Building blocks

struct PanelHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("WhisperTranscriber")
                    .font(.headline)
                Text("Homemade · transcribed right on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

struct StatusCard: View {
    var activity: RecorderActivity
    var hotkey: String
    var holdToTalk: Bool
    var autoPaste: Bool
    var livePreview: String

    private var title: String {
        switch activity {
        case .transcribing:
            return "Writing it down…"
        case .recordingLive:
            return "Listening, writing as you go"
        case .recording:
            return "Listening…"
        case .downloading, .preparing:
            return "Getting ready…"
        case .idle:
            return "Ready when you are"
        }
    }

    private var hint: Text {
        let key = Text(hotkey).fontWeight(.semibold).foregroundStyle(.primary)
        switch activity {
        case .idle:
            return holdToTalk
                ? Text("Hold \(key) and talk.")
                : Text("Press \(key) to start talking.")
        case .recording, .recordingLive:
            return holdToTalk
                ? Text("Let go of \(key) when you're done.")
                : Text("Press \(key) again to finish.")
        case .transcribing:
            return Text(autoPaste ? "It'll paste where you were typing." : "It'll land on your clipboard.")
        case .downloading, .preparing:
            return Text("Parakeet is loading.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ActivityBadge(activity: activity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    hint
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !livePreview.isEmpty {
                LivePreviewView(text: livePreview)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((activity.tint ?? .clear).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .cardBackground()
        .animation(.smooth, value: activity)
    }
}

/// The state's symbol in a soft circle, pulsing while something is happening
struct ActivityBadge: View {
    var activity: RecorderActivity

    var body: some View {
        Image(systemName: activity.symbolName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(activity.tint ?? .primary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: activity != .idle)
            .frame(width: 40, height: 40)
            .background((activity.tint ?? .secondary).opacity(0.15), in: Circle())
    }
}

struct LivePreviewView: View {
    var text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 76)
        .padding(8)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingRow<Accessory: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var accessory: Accessory

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct ToggleRow: View {
    var title: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, systemImage: systemImage) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// A divider inset to line up with the row titles, like System Settings
struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 40)
    }
}

struct PanelFooter: View {
    var showRecords: (() -> Void)?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "v\($0)" } ?? ""
    }

    var body: some View {
        HStack {
            if let showRecords {
                Button(action: showRecords) {
                    Label("Records", systemImage: "clock.arrow.circlepath")
                }
            }

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("Q")
        }
        .overlay {
            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private extension View {
    func cardBackground() -> some View {
        background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}


struct WhisperTranscriberView_Previews: PreviewProvider {
    static var previews: some View {

        Group {
            PrewarmingView(isDownloading: true, downloadProgress: 0.4)
                .previewDisplayName("Downloading")
                .frame(width: 300)

            PrewarmingView(isDownloading: false, downloadProgress: 0)
                .previewDisplayName("Prewarming")
                .frame(width: 300)

            IdleRecordingView(
                settings: SettingsManager.shared,
                isRecording: false,
                activity: .idle,
                livePreview: "",
                showRecords: {}
            )
            .previewDisplayName("Idle/Recording")
            .frame(width: 300)

            IdleRecordingView(
                settings: SettingsManager.shared,
                isRecording: true,
                activity: .recordingLive,
                livePreview: "This is what a live transcript looks like as it streams in.",
                showRecords: {}
            )
            .previewDisplayName("Live Preview")
            .frame(width: 300)
        }
        .fontDesign(.rounded)
        .tint(.orange)
    }
}
