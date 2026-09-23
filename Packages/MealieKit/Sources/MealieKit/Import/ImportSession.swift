import Foundation
import Observation

/// Runs one import against Mealie and turns its progress events into UI state.
@MainActor
@Observable
public final class ImportSession: Identifiable {
    public enum Phase: Equatable {
        case ready
        case running
        case succeeded(Recipe)
        case failed(String)
    }

    public struct Step: Identifiable, Equatable {
        public enum State: Equatable { case active, done, failed }
        public let id: Int
        public var title: String
        public var state: State
    }

    public let id = UUID()
    /// What the user shared or picked. The import may use something derived from it, e.g. the
    /// recipe link found in a video description.
    public let source: ImportSource
    public private(set) var phase: Phase = .ready
    public private(set) var steps: [Step] = []
    public private(set) var startedAt: Date?
    public private(set) var preview: LinkPreview?

    /// YouTube title, description and length, when a YouTube API key is set.
    public private(set) var videoInfo: YouTubeVideoInfo?
    /// What the video description offers: a recipe link, the recipe itself, or nothing.
    public private(set) var findings: DescriptionFindings?
    public private(set) var isCheckingDescription = false
    /// Name of the recipe Mealie found behind the first verified link in the description.
    public private(set) var recipeLinkName: String?

    private let api: any MealieAPI
    private var task: Task<Void, Never>?
    /// The source the last attempt used, so "try again" repeats the same choice.
    private var activeSource: ImportSource?

    public init(source: ImportSource, api: any MealieAPI) {
        self.source = source
        self.api = api
        guard case .link(let url) = source else { return }

        if let demo = api as? DemoMealieAPI {
            loadDemoDetails(for: url, from: demo)
            return
        }

        Task { [weak self] in
            let preview = await LinkPreview.load(for: url)
            self?.preview = preview
        }
        if let videoID = url.youTubeVideoID, let key = YouTubeAPIKey.current {
            isCheckingDescription = true
            Task { [weak self] in
                do {
                    let info = try await YouTubeDataAPI.video(id: videoID, apiKey: key)
                    var findings = DescriptionAnalyzer.analyze(info.description)
                    // A link is only worth offering if the page really holds a recipe.
                    if let verified = await self?.verifiedRecipeLink(among: findings.recipeLinks) {
                        findings.recipeLinks = [verified.url]
                        self?.recipeLinkName = verified.name
                    } else {
                        findings.recipeLinks = []
                    }
                    self?.videoInfo = info
                    self?.findings = findings
                } catch {
                    log.error("YouTube lookup failed: \(error.localizedDescription, privacy: .public)")
                }
                self?.isCheckingDescription = false
            }
        }
    }

    /// The demo shows the same preview and description choices, but offline.
    private func loadDemoDetails(for url: URL, from demo: DemoMealieAPI) {
        isCheckingDescription = demo.videoInfo(for: url) != nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.preview = demo.preview(for: url)
            try? await Task.sleep(for: .milliseconds(800))
            if let found = demo.findings(for: url) {
                self?.videoInfo = demo.videoInfo(for: url)
                self?.findings = found.findings
                self?.recipeLinkName = found.recipeLinkName
            }
            self?.isCheckingDescription = false
        }
    }

    public var isRunning: Bool { phase == .running }

    /// Tries the candidate links in order and returns the first one Mealie can read a recipe from.
    private func verifiedRecipeLink(among links: [URL]) async -> (url: URL, name: String)? {
        for link in links.prefix(3) {
            do {
                if let name = try await api.probeRecipe(at: link) {
                    log.notice("Recipe link verified: \(link.host() ?? "-", privacy: .public)")
                    return (link, name)
                }
                log.notice("No recipe behind link: \(link.absoluteString, privacy: .public)")
            } catch {
                log.error("Checking link failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    public var importedRecipe: Recipe? {
        if case .succeeded(let recipe) = phase { return recipe }
        return nil
    }

    /// True when the failed attempt ran on the device, so the server is still worth a try.
    public private(set) var canRetryWithServerAI = false

    /// Photos and text can be processed on the device; links need Mealie's server.
    public func usesLocalAI(with options: ImportOptions) -> Bool {
        Self.usesLocalAI(for: source, options: options)
    }

    private static func usesLocalAI(for source: ImportSource, options: ImportOptions) -> Bool {
        guard options.preferLocalAI, LocalRecipeAI.availability.isAvailable else { return false }
        switch source {
        case .photos, .text: return true
        case .link: return false
        }
    }

    /// The video description as import text, title first so the recipe gets a proper name.
    public var descriptionSource: ImportSource? {
        guard let videoInfo, findings?.containsRecipe == true else { return nil }
        return .text("\(videoInfo.title)\n\n\(videoInfo.description)")
    }

    /// Starts the import. `override` imports something derived from the shared source instead,
    /// like the recipe link or text from a video description.
    public func start(options: ImportOptions, using override: ImportSource? = nil) {
        guard !isRunning else { return }
        let importSource = override ?? source
        activeSource = importSource
        phase = .running
        startedAt = .now
        canRetryWithServerAI = false
        let local = Self.usesLocalAI(for: importSource, options: options)
        log.notice("Import started: \(importSource.kind.title, privacy: .public), local AI: \(local)")

        if local {
            startLocal(importSource)
            return
        }

        steps = [Step(id: 0, title: L("Verbindung zu Mealie wird hergestellt"), state: .active)]

        task = Task { [weak self, api] in
            do {
                for try await event in api.importRecipe(from: importSource, options: options) {
                    guard let self else { return }
                    switch event {
                    case .progress(let message):
                        self.advance(to: message)
                    case .done(let slug):
                        self.advance(to: L("Rezept wird geladen"))
                        var recipe = try await api.recipe(slug: slug)
                        if let link = self.linkToKeep(for: importSource), recipe.orgURL?.nilIfBlank == nil {
                            recipe = try await api.updateRecipe(slug: slug, changes: RecipePatch(orgURL: link))
                        }
                        self.finish(with: recipe)
                    case .failed(let message):
                        self.fail(message)
                    }
                }
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    /// Repeats the last attempt, optionally with other options (e.g. Mealie AI instead of local).
    public func retry(options: ImportOptions) {
        start(options: options, using: activeSource)
    }

    /// When the recipe came from a video's description, it should still point to the video.
    private func linkToKeep(for importSource: ImportSource) -> String? {
        guard case .link(let url) = source, importSource != source, case .text = importSource else { return nil }
        return url.absoluteString
    }

    /// Photos and text, processed entirely on the device. Mealie only sees the finished recipe.
    private func startLocal(_ importSource: ImportSource) {
        steps = [Step(id: 0, title: L("Quelle wird auf dem Gerät gelesen"), state: .active)]
        let link = linkToKeep(for: importSource)

        task = Task { [weak self, api] in
            do {
                var text: String
                switch importSource {
                case .text(let pasted):
                    text = pasted
                case .photos(let images, let note):
                    var parts: [String] = []
                    for (index, image) in images.enumerated() {
                        self?.advance(to: images.count == 1
                            ? L("Text wird im Foto erkannt")
                            : L("Text wird erkannt (Foto \(index + 1) von \(images.count))"))
                        parts.append(try await LocalRecipeAI.recognizeText(in: image))
                    }
                    if let note = note?.nilIfBlank { parts.append(note) }
                    text = parts.joined(separator: "\n\n")
                case .link:
                    return
                }

                self?.advance(to: L("Rezept wird auf dem iPhone erstellt"))
                let draft = try await LocalRecipeAI.extract(from: text)

                self?.advance(to: L("Rezept wird in Mealie gespeichert"))
                let slug = try await api.createRecipe(name: draft.displayName)
                let saved = try await api.updateRecipe(slug: slug, changes: RecipePatch(
                    name: draft.name,
                    description: draft.description ?? "",
                    recipeServings: draft.recipeServings ?? 0,
                    totalTime: draft.totalTime ?? "",
                    recipeIngredient: draft.recipeIngredient,
                    recipeInstructions: draft.recipeInstructions,
                    orgURL: link
                ))
                self?.finish(with: saved)
            } catch is CancellationError {
                return
            } catch {
                self?.failLocally(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        phase = .ready
        steps = []
    }

    /// Deletes the imported recipe from Mealie again.
    public func discard() async throws {
        guard let recipe = importedRecipe else { return }
        try await api.deleteRecipe(slug: recipe.slug)
        ImportHistory.remove(slug: recipe.slug)
    }

    /// Applies edits made right after the import (tags today, more later).
    public func apply(_ changes: RecipePatch) async throws {
        guard let recipe = importedRecipe else { return }
        var updated = try await api.updateRecipe(slug: recipe.slug, changes: changes)
        // PATCH responses can omit nested data; keep what we already have.
        if updated.recipeIngredient == nil { updated.recipeIngredient = recipe.recipeIngredient }
        if updated.recipeInstructions == nil { updated.recipeInstructions = recipe.recipeInstructions }
        phase = .succeeded(updated)
    }

    /// Takes over a recipe that was changed elsewhere, e.g. after a new cover image.
    public func replaceRecipe(_ recipe: Recipe) {
        guard importedRecipe != nil else { return }
        phase = .succeeded(recipe)
    }

    // MARK: Private

    private func advance(to title: String) {
        guard steps.last?.title != title else { return }
        if let last = steps.indices.last { steps[last].state = .done }
        steps.append(Step(id: steps.count, title: title, state: .active))
    }

    private func finish(with recipe: Recipe) {
        log.notice("Import finished: \(recipe.slug, privacy: .public), \(recipe.ingredients.count) ingredients, \(recipe.instructions.count) steps")
        if let last = steps.indices.last { steps[last].state = .done }
        phase = .succeeded(recipe)
        guard !(api is DemoMealieAPI) else { return } // the demo keeps the real history untouched
        ImportHistory.add(ImportRecord(
            slug: recipe.slug,
            name: recipe.displayName,
            recipeID: recipe.recipeID,
            imageKey: recipe.image,
            sourceTitle: source.kind.title,
            sourceURL: { if case .link(let url) = source { url } else { nil } }(),
            date: .now
        ))
    }

    /// A failure on the device is not the end: Mealie AI can still try.
    private func failLocally(_ message: String) {
        canRetryWithServerAI = true
        fail(message)
    }

    private func fail(_ message: String) {
        log.error("Import failed at step '\(self.steps.last?.title ?? "-", privacy: .public)': \(message, privacy: .public)")
        if let last = steps.indices.last { steps[last].state = .failed }
        phase = .failed(Self.friendly(message))
    }

    /// Adds a hint for errors users can actually fix.
    static func friendly(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("openai") || lower.contains("audio") || lower.contains("transcri") {
            return message + "\n\n" + L("Tipp: Für Videos braucht Mealie einen KI-Anbieter mit Audio-Transkription (Einstellungen → KI in Mealie).")
        }
        return message
    }
}
