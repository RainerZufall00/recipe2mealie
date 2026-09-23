import SwiftUI

/// The complete import experience: source preview → import → live progress → result.
/// Used by the app's import sheet and by the share extension.
public struct ImportFlowView: View {
    @Bindable var session: ImportSession
    let account: MealieAccount
    let onClose: () -> Void

    @State private var showingRecipe: Recipe?
    @State private var editingTags = false
    @State private var confirmingDiscard = false
    @State private var actionError: String?

    public init(session: ImportSession, account: MealieAccount, onClose: @escaping () -> Void) {
        self.session = session
        self.account = account
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SourcePreviewCard(session: session, usesLocalAI: session.usesLocalAI(with: account.importOptions))

                switch session.phase {
                case .ready:
                    readyContent
                case .running:
                    ImportProgressCard(session: session)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .succeeded(let recipe):
                    ImportResultCard(recipe: recipe, api: account.api,
                                     onShow: { showingRecipe = recipe },
                                     onEditTags: { editingTags = true },
                                     onDiscard: { confirmingDiscard = true },
                                     onDone: onClose,
                                     onRecipeUpdated: { session.replaceRecipe($0) })
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                case .failed(let message):
                    failureContent(message)
                        .transition(.opacity)
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.35), value: session.phase)
            .animation(.snappy(duration: 0.35), value: session.steps)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { if canRunLocally { LocalRecipeAI.prewarm() } }
        .sensoryFeedback(.success, trigger: session.importedRecipe != nil) { _, new in new }
        .sensoryFeedback(.error, trigger: session.phase) { _, new in
            if case .failed = new { true } else { false }
        }
        .sheet(item: $showingRecipe) { recipe in
            NavigationStack {
                if let api = account.api {
                    RecipeDetailView(slug: recipe.slug, api: api, initial: recipe,
                                     webURL: account.webURL(forRecipe: recipe.slug))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("Fertig"), systemImage: "checkmark") { showingRecipe = nil }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $editingTags) {
            if let api = account.api, let recipe = session.importedRecipe {
                TagEditorView(api: api, selection: recipe.tags ?? []) { tags in
                    try await session.apply(RecipePatch(tags: tags))
                }
            }
        }
        .confirmationDialog(L("Rezept verwerfen?"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button(L("Aus Mealie löschen"), role: .destructive) {
                Task {
                    do {
                        try await session.discard()
                        onClose()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(L("Das importierte Rezept wird wieder aus Mealie entfernt."))
        }
        .alert(L("Das hat nicht geklappt"), isPresented: .constant(actionError != nil)) {
            Button(L("OK")) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Phases

    @ViewBuilder
    private var readyContent: some View {
        @Bindable var account = account
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $account.importOptions.includeTags) {
                    Label(L("Tags übernehmen"), systemImage: "tag")
                }
                if case .link = session.source {
                    Toggle(isOn: $account.importOptions.includeCategories) {
                        Label(L("Kategorien übernehmen"), systemImage: "square.grid.2x2")
                    }
                }
                if canRunLocally {
                    Toggle(isOn: $account.importOptions.preferLocalAI) {
                        Label(L("Auf dem iPhone verarbeiten"), systemImage: DeviceCapabilities.deviceSymbol)
                    }
                }
                Toggle(isOn: $account.importOptions.translates) {
                    Label(L("Auf \(ImportOptions.deviceLanguageLocalized) übersetzen"),
                          systemImage: "character.bubble")
                }
                .disabled(session.usesLocalAI(with: account.importOptions))
                if account.importOptions.translates, case .link = session.source {
                    Text(L("Zum Übersetzen wertet Mealie AI die Quelle aus, auch bei Webseiten."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.brand)
            .card()

            if session.isCheckingDescription {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L("Videobeschreibung wird geprüft …"))
                        .foregroundStyle(.secondary)
                }
                .card()
            } else if let findings = session.findings, !findings.isEmpty {
                descriptionChoices(findings)
            } else {
                Button {
                    session.start(options: account.importOptions)
                } label: {
                    Label(L("Rezept importieren"), systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                .controlSize(.large)
                .disabled(account.api == nil)
            }

            privacyNote
        }
    }

    /// Recipe link → description → whole video: cheapest and most exact option first.
    private func descriptionChoices(_ findings: DescriptionFindings) -> some View {
        let options = account.importOptions
        let descriptionIsLocal = options.preferLocalAI && LocalRecipeAI.availability.isAvailable
        let link = findings.recipeLinks.first
        let durationText = session.videoInfo?.durationText

        return VStack(alignment: .leading, spacing: 12) {
            Label(L("In der Videobeschreibung gefunden"), systemImage: "text.magnifyingglass")
                .font(.headline)

            if let link {
                let site = link.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
                ChoiceButton(title: L("„\(session.recipeLinkName ?? site)“ übernehmen"),
                             subtitle: L("Rezept auf \(site) gefunden – schnell und genau"),
                             systemImage: "safari", prominent: true) {
                    session.start(options: options, using: .link(link))
                }
            }
            if let descriptionSource = session.descriptionSource {
                ChoiceButton(title: L("Aus der Beschreibung übernehmen"),
                             subtitle: descriptionIsLocal ? L("Wird auf dem iPhone ausgewertet – kostenlos")
                                                          : L("Wird mit Mealie AI ausgewertet"),
                             systemImage: "text.alignleft", prominent: link == nil) {
                    session.start(options: options, using: descriptionSource)
                }
            }
            ChoiceButton(title: L("Ganzes Video analysieren"),
                         subtitle: [durationText, L("Mealie wertet Ton und Untertitel aus, dauert länger")]
                            .compactMap { $0 }.joined(separator: " · "),
                         systemImage: "play.rectangle", prominent: false) {
                session.start(options: options)
            }
        }
        .card()
    }

    private var privacyNote: some View {
        Label {
            Text(privacyText)
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Photos and text can be read on the device; links always need the server.
    private var canRunLocally: Bool {
        guard LocalRecipeAI.availability.isAvailable else { return false }
        if case .link = session.source { return session.descriptionSource != nil }
        return true
    }

    private var privacyText: String {
        let host = account.serverURL?.host() ?? L("deinen Mealie-Server")
        if session.usesLocalAI(with: account.importOptions) {
            return L("Die Auswertung passiert auf deinem iPhone. An \(host) geht erst das fertige Rezept.")
        }
        switch session.source {
        case .link where session.videoInfo != nil:
            return L("Titel und Beschreibung stammen aus der YouTube-API. Für den Import geht nur deine Wahl an \(host) – beim ganzen Video wertet Mealie es mit dem dort eingerichteten KI-Dienst aus.")
        case .link:
            return L("Der Link wird an \(host) gesendet. Mealie erstellt daraus das Rezept – bei Videos mit dem dort eingerichteten KI-Dienst.")
        case .text, .photos:
            return L("Der Inhalt wird an \(host) gesendet und dort mit Mealie AI ausgewertet.")
        }
    }

    private func failureContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ImportProgressCard(session: session)

            VStack(alignment: .leading, spacing: 12) {
                Label(L("Import fehlgeschlagen"), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .card()

            Button {
                session.retry(options: account.importOptions)
            } label: {
                Label(L("Erneut versuchen"), systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.brand)
            .controlSize(.large)

            if session.canRetryWithServerAI {
                Button {
                    session.retry(options: account.importOptions.usingServerAI)
                } label: {
                    Label(L("Mit Mealie AI erneut versuchen"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Text(L("Dabei wird die Quelle an deinen Mealie-Server gesendet und dort vom eingerichteten KI-Dienst ausgewertet."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(L("Schließen"), action: onClose)
                .frame(maxWidth: .infinity)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }
}

// MARK: - Source preview

struct SourcePreviewCard: View {
    let session: ImportSession
    let usesLocalAI: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnail
                .frame(width: session.source.kind == .youTubeShort ? 84 : 112,
                       height: session.source.kind == .youTubeShort ? 136 : 84)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Label(session.source.kind.title, systemImage: session.source.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.brand.opacity(0.14), in: .capsule)

                Text(title)
                    .font(.headline)
                    .lineLimit(3)
                    .redacted(reason: isLoadingPreview ? .placeholder : [])

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var isLoadingPreview: Bool {
        if case .link = session.source { return session.preview == nil }
        return false
    }

    private var title: String {
        switch session.source {
        case .link(let url):
            return session.preview?.title?.nilIfBlank ?? (isLoadingPreview ? L("Titel wird geladen …") : url.absoluteString)
        case .text(let text):
            return text.nilIfBlank.map { String($0.prefix(140)) } ?? L("Text")
        case .photos(let images, _):
            return images.count == 1 ? L("1 Foto") : L("\(images.count) Fotos")
        }
    }

    private var subtitle: String? {
        switch session.source {
        case .link(let url):
            if let info = session.videoInfo {
                [info.channel, info.durationText].compactMap { $0 }.joined(separator: " · ")
            } else {
                session.preview?.subtitle ?? url.host()
            }
        case .text: processingHint
        case .photos(_, let note): note?.nilIfBlank ?? processingHint
        }
    }

    private var processingHint: String {
        usesLocalAI ? L("Wird auf dem iPhone ausgewertet") : L("Wird mit Mealie AI ausgewertet")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch session.source {
        case .link:
            if let data = session.preview?.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RecipeImage(url: session.preview?.imageURL, cornerRadius: 0)
            }
        case .photos(let images, _):
            if let data = images.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        case .text:
            ZStack {
                Color.brand.opacity(0.15)
                Image(systemName: "text.alignleft").font(.title).foregroundStyle(.brand)
            }
        }
    }
}

// MARK: - Progress

struct ImportProgressCard: View {
    let session: ImportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(session.isRunning ? L("Mealie arbeitet …") : L("Verlauf"))
                    .font(.headline)
                Spacer()
                if let start = session.startedAt, session.isRunning {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(start)),
                             format: .time(pattern: .minuteSecond))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(session.steps) { step in
                    StepRow(step: step)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
            }

            if session.isRunning {
                Text(session.source.kind.durationHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(L("Abbrechen"), role: .cancel) { session.cancel() }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
            }
        }
        .card()
    }
}

private struct StepRow: View {
    let step: ImportSession.Step

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                switch step.state {
                case .active:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.title3)
            .frame(width: 24)

            Text(step.title)
                .font(.body.weight(step.state == .active ? .semibold : .regular))
                .foregroundStyle(step.state == .done ? .secondary : .primary)
        }
    }
}

// MARK: - Result

struct ImportResultCard: View {
    let recipe: Recipe
    let api: (any MealieAPI)?
    let onShow: () -> Void
    let onEditTags: () -> Void
    let onDiscard: () -> Void
    let onDone: () -> Void
    let onRecipeUpdated: (Recipe) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(url: api?.imageURL(for: recipe, size: .original), cornerRadius: 0)
                .frame(height: 200)
                .overlay(alignment: .topLeading) {
                    Label(L("Gespeichert"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.green.opacity(0.35)))
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let api {
                        CoverImageMenu(recipe: recipe, api: api, onUpdated: onRecipeUpdated) {
                            CoverImageButtonLabel(hasImage: recipe.hasImage)
                        }
                        .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(recipe.displayName)
                    .font(.title2.bold())
                    .fontDesign(.serif)

                FlowLayout {
                    InfoChip(L("\(recipe.ingredients.count) Zutaten"), systemImage: "carrot")
                    InfoChip(L("\(recipe.instructions.count) Schritte"), systemImage: "list.number")
                    if let time = RecipeFormat.duration(recipe.totalTime ?? recipe.cookTime) {
                        InfoChip(time, systemImage: "clock")
                    }
                    if let servings = recipe.servings {
                        InfoChip(L("\(RecipeFormat.servings(servings)) Portionen"), systemImage: "person.2")
                    }
                }

                if let tags = recipe.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0.name)" }.joined(separator: "  "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if recipe.ingredients.isEmpty || recipe.instructions.isEmpty {
                    Label(L("Mealie hat nicht alles gefunden. Prüfe das Rezept am besten kurz."),
                          systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button(action: onShow) {
                    Label(L("Rezept ansehen"), systemImage: "book")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                .controlSize(.large)

                HStack(spacing: 10) {
                    Button(L("Tags"), systemImage: "tag", action: onEditTags)
                        .frame(maxWidth: .infinity)
                    Button(L("Fertig"), systemImage: "checkmark", action: onDone)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

                Button(L("Rezept wieder aus Mealie löschen"), systemImage: "trash",
                       role: .destructive, action: onDiscard)
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 28))
    }
}

/// One option in the description choices: icon, title and a short explanation.
private struct ChoiceButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.footnote)
                        .opacity(0.8)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(ChoiceStyle(prominent: prominent))
    }
}

private struct ChoiceStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent).tint(.brand)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
