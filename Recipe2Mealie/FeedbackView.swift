import MealieKit
import MessageUI
import SwiftUI

/// Where feedback goes, from Config/Base.xcconfig. Empty values hide the option.
enum FeedbackTarget {
    static var githubRepository: String? { infoValue("GitHubRepository") }
    static var email: String? { infoValue("FeedbackEmail") }
    static var isAvailable: Bool { githubRepository != nil || email != nil }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}

/// Feedback through a prefilled GitHub issue form or an email. Nothing is sent without the user
/// pressing send, and neither includes the server address or recipes.
struct FeedbackView: View {
    @Environment(MealieAccount.self) private var account
    @Environment(\.openURL) private var openURL

    @State private var mealieVersion: String?
    @State private var attachLog = false
    @State private var mail: MailDraft?
    @State private var isPreparingMail = false

    enum Kind { case bug, idea }

    var body: some View {
        Form {
            Section {
                Text("Danke, dass du hilfst, die App besser zu machen! Beschreib kurz, was passiert ist oder was du dir wünschst.")
            }

            if FeedbackTarget.githubRepository != nil {
                Section {
                    Button("Fehler melden", systemImage: "ladybug") { openGitHub(.bug) }
                    Button("Idee vorschlagen", systemImage: "lightbulb") { openGitHub(.idea) }
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("Öffnet ein vorausgefülltes Formular auf GitHub. Du brauchst dafür ein kostenloses GitHub-Konto, die Meldung ist öffentlich sichtbar.")
                }
            }

            if FeedbackTarget.email != nil {
                Section {
                    Toggle("Protokoll anhängen", isOn: $attachLog)
                    Button {
                        Task { await writeEmail() }
                    } label: {
                        if isPreparingMail {
                            ProgressView()
                        } else {
                            Label("E-Mail schreiben", systemImage: "envelope")
                        }
                    }
                } header: {
                    Text("E-Mail")
                } footer: {
                    Text("Das Protokoll zeigt, was die App seit dem Start getan hat, etwa importierte Links und Fehlermeldungen – aber keine Passwörter, Tokens oder Server-Adresse.")
                }
            }

            Section {
                Text(details)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Diese Angaben werden mitgeschickt")
            }
        }
        .navigationTitle("Feedback")
        .task { await loadMealieVersion() }
        .sheet(item: $mail) { draft in
            MailComposer(draft: draft).ignoresSafeArea()
        }
    }

    // MARK: Details

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var iOSVersion: String { UIDevice.current.systemVersion }

    /// "iPhone16,1" rather than just "iPhone"; tells the model without anything personal.
    private var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private var details: String {
        """
        Recipe2Mealie \(appVersion)
        iOS \(iOSVersion) · \(deviceModel)
        Mealie \(mealieVersion ?? "–")
        \(Locale.current.identifier)
        """
    }

    private func loadMealieVersion() async {
        guard !account.isDemo, let server = account.serverURL else { return }
        mealieVersion = try? await MealieClient.appInfo(serverURL: server).version
    }

    // MARK: GitHub

    /// Issue forms can be prefilled through query parameters named after their field IDs
    /// (see .github/ISSUE_TEMPLATE).
    private func openGitHub(_ kind: Kind) {
        guard let repository = FeedbackTarget.githubRepository,
              var url = URL(string: "https://github.com/\(repository)/issues/new") else { return }
        url.append(queryItems: [
            URLQueryItem(name: "template", value: kind == .bug ? "bug_report.yml" : "feature_request.yml"),
            URLQueryItem(name: "app-version", value: appVersion),
            URLQueryItem(name: "ios-version", value: "\(iOSVersion) · \(deviceModel)"),
            URLQueryItem(name: "mealie-version", value: mealieVersion ?? "")
        ])
        openURL(url)
    }

    // MARK: Email

    private func writeEmail() async {
        guard let address = FeedbackTarget.email else { return }
        let subject = "Recipe2Mealie Feedback"
        let body = "\n\n\n---\n\(details)"

        guard MFMailComposeViewController.canSendMail() else {
            // No mail account set up: hand over to whatever mail app is installed.
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = address
            components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                     URLQueryItem(name: "body", value: body)]
            if let url = components.url { openURL(url) }
            return
        }

        isPreparingMail = true
        defer { isPreparingMail = false }
        var attachment: URL?
        if attachLog {
            attachment = try? await Task.detached { try Diagnostics.exportLog() }.value
        }
        mail = MailDraft(recipient: address, subject: subject, body: body, attachment: attachment)
    }
}

struct MailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
    let attachment: URL?
}

/// The system mail sheet with everything prefilled.
private struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        if let attachment = draft.attachment, let data = try? Data(contentsOf: attachment) {
            controller.addAttachmentData(data, mimeType: "text/plain", fileName: attachment.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                               didFinishWith result: MFMailComposeResult, error: Error?) {
            Task { @MainActor in dismiss() }
        }
    }
}
