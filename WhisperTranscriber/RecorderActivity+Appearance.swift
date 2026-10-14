import SwiftUI

extension Color {
    static let darkOrange = Color(red: 0.72, green: 0.28, blue: 0.0)
}

extension RecorderActivity {
    /// SF Symbol for this state, shared by the menu bar icon and the panel
    var symbolName: String {
        switch self {
        case .downloading:
            return "arrow.down.circle"
        case .preparing:
            return "hourglass"
        case .transcribing:
            return "text.bubble"
        case .recordingLive:
            return "waveform.and.mic"
        case .recording:
            return "mic.fill"
        case .idle:
            return "waveform"
        }
    }

    /// nil when idle, so the symbol follows the menu bar's light or dark appearance
    var tint: Color? {
        switch self {
        case .downloading:
            return .purple
        case .preparing:
            return .red
        case .transcribing:
            return .blue
        case .recordingLive:
            return .darkOrange
        case .recording:
            return .orange
        case .idle:
            return nil
        }
    }
}
