import MealieKit
import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(MealieAccount.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeImport: ImportSession?
    @State private var history: [ImportRecord] = []
    @State private var showingLinkEntry = false
    @State private var showingTextEntry = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var showingCamera = false
    @State private var clipboardHasContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    @State private var openedRecipe: ImportRecord?
    @AppStorage("showShareTip") private var showShareTip = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    importCard
                    if showShareTip { shareTip }
                    recentImports
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                reloadHistory()
                await account.refreshUser()
            }
            .navigationTitle(greeting)
            .navigationDestination(item: $openedRecipe) { record in
                if let api = account.api {
                    RecipeDetailView(slug: record.slug, api: api, webURL: account.webURL(forRecipe: record.slug))
                }
            }
        }
        .sheet(item: $activeImport, onDismiss: reloadHistory) { session in
            NavigationStack {
                ImportFlowView(session: session, account: account) { activeImport = nil }
                    .navigationTitle("Import")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen", systemImage: "xmark") {
                                session.cancel()
                                activeImport = nil
                            }
                        }
                    }
            }
            .interactiveDismissDisabled(session.isRunning)
        }
        .sheet(isPresented: $showingLinkEntry) {
            LinkEntryView { url in startImport(.link(url)) }
        }
        .sheet(isPresented: $showingTextEntry) {
            TextEntryView { text in startImport(.text(text)) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            // The scanner straightens cookbook pages and takes several in a row; the plain
            // camera is the fallback on devices without it.
            Group {
                if DeviceCapabilities.canScanDocuments {
                    DocumentScanner { pages in
                        showingCamera = false
                        importCaptured(pages)
                    }
                } else {
                    CameraPicker { image in
                        showingCamera = false
                        importCaptured(image.map { [$0] } ?? [])
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            reloadHistory() // the share extension may have imported something
            refreshClipboardState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshClipboardState()
        }
        .onAppear(perform: reloadHistory)
    }

    private var greeting: String {
        if let name = account.user?.fullName?.split(separator: " ").first {
            return String(localized: "Hallo, \(String(name))")
        }
        return String(localized: "Importieren")
    }

    // MARK: Import card

    private var importCard: some View {
        // Built here on the main actor; the PhotosPicker label closure is not isolated.
        let photosLabel = ImportTileLabel(title: "Fotos", subtitle: "Aus der Mediathek",
                                          systemImage: "photo.on.rectangle", isLoading: isLoadingPhotos)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rezept importieren")
                        .font(.title2.bold())
                        .fontDesign(.serif)
                    Text("Aus Videos, Webseiten, Fotos oder Text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Only offered when there is something to paste. Checking this doesn't read the
            // clipboard, so iOS shows no paste prompt.
            if clipboardHasContent {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        if let url = URL.firstWebLink(in: text) {
                            startImport(.link(url))
                        } else {
                            startImport(.text(text))
                        }
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                // A darker orange than the brand colour keeps the white label readable.
                .tint(Color(red: 0.72, green: 0.36, blue: 0.10))
            }

            // Two pairs: things you type or paste, and things that are pictures.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    ImportTile(title: "Link", subtitle: "YouTube, Instagram, Web", systemImage: "link") {
                        showingLinkEntry = true
                    }
                    ImportTile(title: "Text", subtitle: "Rezept einfügen", systemImage: "text.alignleft") {
                        showingTextEntry = true
                    }
                }
                GridRow {
                    if DeviceCapabilities.canScanDocuments || DeviceCapabilities.canTakePhotos {
                        ImportTile(title: "Kamera", subtitle: "Kochbuch scannen", systemImage: "camera") {
                            showingCamera = true
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                        photosLabel
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 28))
    }

    private var shareTip: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundStyle(.brand)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("Noch schneller: direkt teilen").font(.headline)
                Text("Tippe in YouTube oder Instagram auf **Teilen** und wähle **Recipe2Mealie**. Falls die App fehlt: ganz rechts auf **Mehr** tippen und sie hinzufügen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Ausblenden", systemImage: "xmark") {
                withAnimation { showShareTip = false }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background.secondary, in: .rect(cornerRadius: 24))
    }

    // MARK: History

    @ViewBuilder
    private var recentImports: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zuletzt importiert")
                .font(.title2.bold())
                .fontDesign(.serif)

            if history.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Importe", systemImage: "tray")
                } description: {
                    Text("Importierte Rezepte erscheinen hier.")
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(history) { record in
                        Button { openedRecipe = record } label: { HistoryRow(record: record) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func startImport(_ source: ImportSource) {
        guard let api = account.api else { return }
        let normalized: ImportSource = if case .link(let url) = source { .link(url.withoutTrackingParameters) } else { source }
        activeImport = ImportSession(source: normalized, api: api)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer {
            isLoadingPhotos = false
            photoItems = []
        }
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let jpeg = ImageCompressor.jpegForUpload(data) {
                images.append(jpeg)
            }
        }
        if !images.isEmpty { startImport(.photos(images, note: nil)) }
    }

    private func importCaptured(_ images: [UIImage]) {
        let jpegs = images.compactMap { ImageCompressor.jpegForUpload($0) }
        guard !jpegs.isEmpty else { return }
        // Let the camera finish dismissing before the import sheet slides up.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            startImport(.photos(jpegs, note: nil))
        }
    }

    private func refreshClipboardState() {
        clipboardHasContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    }

    private func reloadHistory() {
        history = ImportHistory.load()
    }
}

// MARK: - Pieces

/// One way to import: orange icon, title and a short hint, on a white tile.
private struct ImportTile: View {
    // LocalizedStringKey, so Text() looks the words up in the String Catalog.
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ImportTileLabel(title: title, subtitle: subtitle, systemImage: systemImage, isLoading: false)
        }
        .buttonStyle(.plain)
    }
}

private struct ImportTileLabel: View {
    // LocalizedStringKey, so Text() looks the words up in the String Catalog.
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().fill(Color.brand.gradient)
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tertiary background is white in light mode and a step lighter than the card in dark
        // mode, so the tiles sit on top of the card in both.
        .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .contentShape(.rect(cornerRadius: 20))
    }
}

private struct HistoryRow: View {
    @Environment(MealieAccount.self) private var account
    let record: ImportRecord

    var body: some View {
        HStack(spacing: 14) {
            RecipeImage(url: imageURL, cornerRadius: 14)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(record.sourceTitle) · \(record.date.formatted(.relative(presentation: .named)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
    }

    private var imageURL: URL? {
        guard let id = record.recipeID, let api = account.api else { return nil }
        return api.imageURL(recipeID: id, cacheKey: record.imageKey, size: .tiny)
    }
}

/// Manual link entry.
private struct LinkEntryView: View {
    let onImport: (URL) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $text, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                } footer: {
                    Text("Link zu einem Video (YouTube, Instagram, TikTok) oder einer Rezeptseite.")
                }
            }
            .navigationTitle("Link importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren", systemImage: "arrow.down") {
                        guard let url else { return }
                        dismiss()
                        onImport(url)
                    }
                    .disabled(url == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var url: URL? {
        URL.firstWebLink(in: text) ?? URL.firstWebLink(in: "https://" + text.trimmingCharacters(in: .whitespaces))
    }
}

/// Paste or type a recipe as text; Mealie AI structures it.
private struct TextEntryView: View {
    let onImport: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Rezepttext einfügen, z. B. aus einer Nachricht oder Videobeschreibung …")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("Text importieren")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importieren", systemImage: "arrow.down") {
                            dismiss()
                            onImport(text)
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                    }
                }
        }
    }
}
