import os
import Foundation

/// Centralized logging that writes to both OSLog and a file in the app container
struct Log {
    static let subsystem = "com.joaoanes.WhisperTranscriber"
    
    // OSLog instances
    private static let osGeneral = Logger(subsystem: subsystem, category: "general")
    private static let osSpeech = Logger(subsystem: subsystem, category: "speech")
    private static let osRecording = Logger(subsystem: subsystem, category: "recording")
    private static let osHotkey = Logger(subsystem: subsystem, category: "hotkey")
    
    // Dual-output loggers
    static let general = DualLogger(osLogger: osGeneral, category: "general")
    static let speech = DualLogger(osLogger: osSpeech, category: "speech")
    static let recording = DualLogger(osLogger: osRecording, category: "recording")
    static let hotkey = DualLogger(osLogger: osHotkey, category: "hotkey")
    
    // File handle for log file
    private static var fileHandle: FileHandle?
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()
    
    private static let maxLogBytes: UInt64 = 1_000_000
    private static let maxCrashLogs = 5

    /// Logs live in the app's own sandbox container (Library/Logs/WhisperTranscriber),
    /// so no sandbox exception is needed.
    static var logDirectory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs")
            .appendingPathComponent("WhisperTranscriber")
    }

    static func ensureLogDirectory() -> URL? {
        guard let logDir = logDirectory else { return nil }
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
            return logDir
        } catch {
            osGeneral.error("Failed to create log directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func setupFileLogging() {
        guard let logDir = ensureLogDirectory() else { return }
        let logFile = logDir.appendingPathComponent("app.log")
        let fm = FileManager.default

        // Rotate so logs cannot grow without bound.
        if let size = (try? fm.attributesOfItem(atPath: logFile.path))?[.size] as? UInt64, size > maxLogBytes {
            let rotated = logDir.appendingPathComponent("app.log.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: logFile, to: rotated)
        }
        pruneCrashLogs(in: logDir)

        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: nil, attributes: nil)
        }
        do {
            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()
            writeToFile("--- App Started ---")
        } catch {
            osGeneral.error("Failed to setup file logging: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func pruneCrashLogs(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let crashes = files
            .filter { $0.lastPathComponent.hasPrefix("Crash_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in crashes.dropFirst(maxCrashLogs) {
            try? fm.removeItem(at: old)
        }
    }

    static func writeToFile(_ message: String, category: String = "general", level: String = "INFO") {
        guard let handle = fileHandle else { return }
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }
}

/// A logger that writes to both OSLog and a file
struct DualLogger {
    let osLogger: Logger
    let category: String
    
    func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        Log.writeToFile(message, category: category, level: "DEBUG")
    }
    
    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        Log.writeToFile(message, category: category, level: "INFO")
    }
    
    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        Log.writeToFile(message, category: category, level: "ERROR")
    }
    
    func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        Log.writeToFile(message, category: category, level: "FAULT")
    }
}
