import AVFoundation
import Foundation
import Dispatch
import AppKit
import SwiftUI
import Carbon

var getAudioAuthStatus: () -> AVAuthorizationStatus = {
    AVCaptureDevice.authorizationStatus(for: .audio)
}

var requestAudioAccess: (@escaping (Bool) -> Void) -> Void = { cb in
    AVCaptureDevice.requestAccess(for: .audio, completionHandler: cb)
}

func requestMicPermission(_ cb: @escaping (Bool) -> Void) {
    switch getAudioAuthStatus() {
    case .authorized:
        cb(true)
    case .notDetermined:
        requestAudioAccess(cb)
    default:
        cb(false)
    }
}

/// Auto-paste posts a ⌘V keystroke, which macOS gates behind Accessibility access.
/// Asks for it (once, via the system prompt) when it hasn't been granted yet.
@discardableResult
func requestPasteAccess() -> Bool {
    CGPreflightPostEventAccess() || CGRequestPostEventAccess()
}

enum PasteOutcome: Equatable {
    case pasted
    case skippedOwnApp
    case accessibilityDenied
}

/// True when WhisperTranscriber's own popover or window has keyboard focus,
/// where a ⌘V would drop the transcript into a settings field.
func isOwnAppFocused(
    frontmostPID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
    ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
    hasKeyWindow: Bool = NSApp.keyWindow != nil
) -> Bool {
    hasKeyWindow || frontmostPID == ownPID
}

/// Presses ⌘V in whichever app has focus, unless that app is WhisperTranscriber itself.
@MainActor
func pasteIntoFrontmostApp(ownAppFocused: Bool = isOwnAppFocused()) -> PasteOutcome {
    guard !ownAppFocused else { return .skippedOwnApp }
    guard requestPasteAccess() else { return .accessibilityDenied }

    let source = CGEventSource(stateID: .combinedSessionState)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }
    return .pasted
}

func getRecordingsDirectory() -> URL? {
    guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    let recordingsDirectory = applicationSupport
        .appendingPathComponent("WhisperTranscriber")
        .appendingPathComponent("Recordings")

    if !FileManager.default.fileExists(atPath: recordingsDirectory.path) {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.general.error("Error creating recordings directory: \(error.localizedDescription))")
            return nil
        }
    }
    return recordingsDirectory
}

func getAppSupportDirectory() -> URL? {
    guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return applicationSupport.appendingPathComponent("WhisperTranscriber")
}

func getModelsDirectory() -> URL? {
    guard let appSupport = getAppSupportDirectory() else {
        return nil
    }
    let modelsDirectory = appSupport.appendingPathComponent("Models")

    if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.general.error("Error creating models directory: \(error.localizedDescription))")
            return nil
        }
    }
    return modelsDirectory
}

func tempURL() -> URL {
    guard let recordingsDir = getRecordingsDirectory() else {
        // Fallback to temp directory if Application Support is unavailable
        return FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")
    }
    let name = "recording_\(Int(Date().timeIntervalSince1970)).wav"
    return recordingsDir.appendingPathComponent(name)
}

func UTGetOSTypeFromString(_ str: String) -> OSType {
    precondition(str.utf8.count == 4, "Must be 4 chars")
    var result: OSType = 0
    for char in str.utf8 {
        result = (result << 8) | OSType(char)
    }
    return result
}
