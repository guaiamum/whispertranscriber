import SwiftUI
import Carbon
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Hold a strong reference to the activity token to keep the app alive
    var lifetimeActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a focused activity to stop the OS from killing the app as "NonInteractive"
        self.lifetimeActivity = ProcessInfo.processInfo.beginActivity(
             options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled],
             reason: "App operates as an agent and must remain active"
        )
        
        // Explicitly disable automatic termination
        // This reinforces the ProcessInfo assertion against CacheDelete/RunningBoard
        ProcessInfo.processInfo.disableAutomaticTermination("Agent must remain active")
        
        Log.setupFileLogging()
        CrashHandler.shared.setup()
        
        let settings = SettingsManager.shared
        // A shortcut saved before modifiers were required would fail to register
        if !HotKeyManager.hasRequiredModifier(settings.hotkey) {
            settings.hotkey = SettingsManager.defaultHotkey
        }
        RecorderViewModel.registerHotkey(settings.hotkey)
    }
}

@main
struct WhisperTranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var vm = RecorderViewModel.shared
    @StateObject private var settings = SettingsManager.shared

    @State private var recordsWindowController: RecordsWindowController?

    var body: some Scene {
        MenuBarExtra {
            WhisperTranscriberView(showRecords: showRecords)
        } label: {
            Image(nsImage: menuBarImage(for: vm.activity))
        }
        .menuBarExtraStyle(.window)
        .commands {
            appCommands
        }
    }


    private func showRecords() {
        if recordsWindowController == nil {
            let controller = RecordsWindowController()
            controller.onWindowClose = { [self] in
                self.recordsWindowController = nil
            }
            self.recordsWindowController = controller
        }
        recordsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension WhisperTranscriberApp {
    @CommandsBuilder
    var appCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Show Records") {
                showRecords()
            }
            .keyboardShortcut("r", modifiers: [.command, .control])
        }
    }
}

private extension WhisperTranscriberApp {
    func menuBarImage(for activity: RecorderActivity) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: activity.symbolName, accessibilityDescription: "WhisperTranscriber")?
            .withSymbolConfiguration(config) else { return NSImage() }

        guard let color = activity.tint else {
            symbol.isTemplate = true
            return symbol
        }

        // Bake the color in, since the menu bar renders template images monochrome
        let nsColor = NSColor(color)
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            nsColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}