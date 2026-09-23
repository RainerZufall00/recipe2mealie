import SwiftUI

/// Crash reports and the app log, ready to share (AirDrop, Mail, Dateien …).
struct DiagnosticsView: View {
    @State private var reports: [Diagnostics.CrashReport] = []
    @State private var logFile: URL?
    @State private var logError: String?
    @State private var isCreatingLog = false

    var body: some View {
        List {
            Section {
                if reports.isEmpty {
                    Text("Keine Abstürze erfasst.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reports) { report in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(report.summary)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: report.url) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { reports[$0] }.forEach(Diagnostics.delete)
                    reports.remove(atOffsets: offsets)
                }
            } header: {
                Text("Absturzberichte")
            } footer: {
                Text("iOS liefert einen Bericht beim nächsten Start nach einem Absturz, manchmal mit etwas Verzögerung. Die Berichte bleiben auf dem Gerät, bis du sie teilst.")
            }

            Section {
                if let logFile {
                    ShareLink(item: logFile) {
                        Label("Protokoll teilen", systemImage: "square.and.arrow.up")
                    }
                } else if isCreatingLog {
                    HStack {
                        ProgressView()
                        Text("Protokoll wird erstellt …").foregroundStyle(.secondary)
                    }
                } else {
                    Button("Protokoll erstellen", systemImage: "doc.text.magnifyingglass") {
                        Task { await createLog() }
                    }
                }
                if let logError {
                    Text(logError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Protokoll")
            } footer: {
                Text("Enthält die Meldungen der App seit dem letzten Start: Importe, Fehler und Serverantworten. Keine Passwörter oder Tokens.")
            }
        }
        .navigationTitle("Diagnose")
        .onAppear { reports = Diagnostics.crashReports() }
        .refreshable { reports = Diagnostics.crashReports() }
    }

    private func createLog() async {
        isCreatingLog = true
        defer { isCreatingLog = false }
        do {
            // Reading the log store takes a moment; keep the UI responsive.
            logFile = try await Task.detached { try Diagnostics.exportLog() }.value
            logError = nil
        } catch {
            logError = error.localizedDescription
        }
    }
}
