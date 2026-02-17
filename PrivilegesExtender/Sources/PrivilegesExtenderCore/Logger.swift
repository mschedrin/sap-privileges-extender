import Foundation

/// Simple file logger that appends timestamped entries to a log file.
public final class Logger: @unchecked Sendable {
    private let filePath: String
    private let fileManager: FileManager
    private let writeQueue = DispatchQueue(label: "com.user.privileges-extender.logger")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(filePath: String, fileManager: FileManager = .default) {
        self.filePath = filePath
        self.fileManager = fileManager
    }

    /// Logs a message with a timestamp to the log file.
    public func log(_ message: String) {
        let date = Date()
        writeQueue.async { [self] in
            let timestamp = dateFormatter.string(from: date)
            let entry = "[\(timestamp)] \(message)\n"
            appendUnsafe(entry)
        }
    }

    /// Reads the entire log file contents.
    public func readAll() -> String? {
        writeQueue.sync {
            guard fileManager.fileExists(atPath: filePath) else { return nil }
            return try? String(contentsOfFile: filePath, encoding: .utf8)
        }
    }

    /// Clears the log file.
    public func clear() {
        writeQueue.sync {
            try? "".write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private

    /// Appends an entry to the log file. Must be called from within writeQueue.
    private func appendUnsafe(_ entry: String) {
        let directory = (filePath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: filePath) {
            guard let handle = FileHandle(forWritingAtPath: filePath) else { return }
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try? entry.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }
}
