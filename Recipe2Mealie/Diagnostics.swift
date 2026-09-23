import Foundation
import MetricKit
import OSLog

/// Collects crash reports from Apple's MetricKit and the app's own log, so a problem can be
/// shared as a file. Nothing is sent anywhere automatically; the user decides what to share.
///
/// iOS hands MetricKit crash reports to the app on the next launch after a crash.
nonisolated final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    private static let logger = Logger(subsystem: "de.recipe2mealie", category: "diagnostics")

    struct CrashReport: Identifiable, Hashable {
        let url: URL
        let date: Date
        let summary: String

        var id: URL { url }
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads where !(payload.crashDiagnostics ?? []).isEmpty {
            let name = "crash-\(Self.fileDateFormatter.string(from: payload.timeStampEnd)).json"
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                try payload.jsonRepresentation().write(to: Self.directory.appending(path: name))
                Self.logger.notice("Saved crash report \(name)")
            } catch {
                Self.logger.error("Could not save crash report: \(error)")
            }
        }
    }

    // MARK: Reading

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    static func crashReports() -> [CrashReport] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("crash-") }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return CrashReport(url: url, date: date, summary: summary(of: url))
            }
            .sorted { $0.date > $1.date }
    }

    static func delete(_ report: CrashReport) {
        try? FileManager.default.removeItem(at: report.url)
    }

    /// "SIGSEGV · EXC_BAD_ACCESS" style one-liner from the MetricKit JSON.
    private static func summary(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let crashes = json["crashDiagnostics"] as? [[String: Any]],
              let meta = crashes.first?["diagnosticMetaData"] as? [String: Any] else {
            return String(localized: "Absturz")
        }
        let signal = (meta["signal"] as? Int).map { signalName($0) }
        let exception = (meta["exceptionType"] as? Int).map { exceptionName($0) }
        let reason = meta["terminationReason"] as? String
        let parts = [signal, exception, reason].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Absturz") : parts.joined(separator: " · ")
    }

    private static func signalName(_ signal: Int) -> String {
        switch signal {
        case 4: "SIGILL"
        case 5: "SIGTRAP (Swift-Laufzeitfehler)"
        case 6: "SIGABRT"
        case 9: "SIGKILL"
        case 10: "SIGBUS"
        case 11: "SIGSEGV"
        default: "Signal \(signal)"
        }
    }

    private static func exceptionName(_ type: Int) -> String {
        switch type {
        case 1: "EXC_BAD_ACCESS"
        case 2: "EXC_BAD_INSTRUCTION"
        case 5: "EXC_SOFTWARE"
        case 6: "EXC_BREAKPOINT"
        case 10: "EXC_CRASH"
        case 11: "EXC_RESOURCE"
        case 12: "EXC_GUARD"
        default: "Exception \(type)"
        }
    }

    // MARK: Log export

    /// Writes the app's log messages of the last hours to a text file for sharing.
    static func exportLog(hours: Double = 6) throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let start = store.position(date: Date().addingTimeInterval(-hours * 3600))
        let entries = try store.getEntries(at: start,
                                           matching: NSPredicate(format: "subsystem == %@", "de.recipe2mealie"))

        var lines = [header]
        for case let entry as OSLogEntryLog in entries {
            let time = entry.date.formatted(date: .omitted, time: .standard)
            lines.append("\(time) [\(entry.category)] \(levelName(entry.level)) \(entry.composedMessage)")
        }
        if lines.count == 1 { lines.append("(keine Einträge in dieser Sitzung)") }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "Recipe2Mealie-Protokoll-\(fileDateFormatter.string(from: .now)).txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static var header: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        return "Recipe2Mealie \(version) (\(build)) · iOS \(system)\n"
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .error: "FEHLER"
        case .fault: "SCHWER"
        case .notice: "Hinweis"
        case .info: "Info"
        case .debug: "Debug"
        default: ""
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
