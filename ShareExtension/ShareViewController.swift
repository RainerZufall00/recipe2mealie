import MealieKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point of the share extension: hosts the shared import flow in SwiftUI.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(
            items: extensionContext?.inputItems as? [NSExtensionItem] ?? [],
            onClose: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        .tint(.brand)

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

struct ShareRootView: View {
    let items: [NSExtensionItem]
    let onClose: () -> Void

    @State private var account = MealieAccount()
    @State private var session: ImportSession?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if !account.isSignedIn {
                    ContentUnavailableView {
                        Label("Nicht verbunden", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text(KeychainStore.sharedGroup != nil
                             ? String(localized: "Öffne zuerst die App „Recipe2Mealie“ und verbinde sie mit deinem Mealie-Server.")
                             : String(localized: "Diese Installation darf keine Daten mit der App teilen. Importiere bitte direkt in der App."))
                    }
                } else if let session {
                    ImportFlowView(session: session, account: account, onClose: onClose)
                } else if loadFailed {
                    ContentUnavailableView("Nichts zum Importieren", systemImage: "questionmark.square.dashed",
                                           description: Text("Teile einen Link, Text oder Fotos mit einem Rezept."))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("In Mealie importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", systemImage: "xmark") {
                        session?.cancel()
                        onClose()
                    }
                }
            }
        }
        .environment(account)
        .task { await loadSharedContent() }
    }

    private func loadSharedContent() async {
        guard account.isSignedIn, session == nil, let api = account.api else { return }
        if let source = await SharedContent.source(from: items) {
            session = ImportSession(source: source, api: api)
        } else {
            loadFailed = true
        }
    }
}

/// Turns share-sheet items into an import source. Links win over text, text over images.
enum SharedContent {
    static func source(from items: [NSExtensionItem]) async -> ImportSource? {
        let providers = items.flatMap { $0.attachments ?? [] }
        var texts: [String] = items.compactMap { $0.attributedContentText?.string }
        var images: [Data] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = await loadURL(from: provider), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return .link(url.withoutTrackingParameters)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = await loadText(from: provider) {
                texts.append(text)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadImage(from: provider) {
                images.append(data)
            }
        }

        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL.firstWebLink(in: text) { return .link(url.withoutTrackingParameters) }
        if !images.isEmpty { return .photos(images, note: text.isEmpty ? nil : text) }
        if !text.isEmpty { return .text(text) }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        try? await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? CancellationError()) }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        try? await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, error in
                if let text { continuation.resume(returning: text) } else { continuation.resume(throwing: error ?? CancellationError()) }
            }
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> Data? {
        let data: Data? = try? await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CancellationError()) }
            }
        }
        return data.flatMap { ImageCompressor.jpegForUpload($0) }
    }
}
