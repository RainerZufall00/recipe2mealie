import Foundation
import os

let log = Logger(subsystem: "de.recipe2mealie", category: "api")

/// Everything the app needs from a Mealie server. Views depend on this protocol so previews
/// and tests can use `PreviewMealieAPI` instead of a live server.
public protocol MealieAPI: Sendable {
    var serverURL: URL { get }

    func currentUser() async throws -> MealieUser
    func recipes(page: Int, perPage: Int, search: String?, tagSlugs: [String]) async throws -> Page<RecipeSummary>
    func recipe(slug: String) async throws -> Recipe
    func deleteRecipe(slug: String) async throws
    func updateRecipe(slug: String, changes: RecipePatch) async throws -> Recipe
    /// Creates an empty recipe and returns its slug. Used by the on-device pipeline.
    func createRecipe(name: String) async throws -> String
    /// Replaces the cover image. Returns Mealie's new image key (used to bust image caches).
    func uploadImage(slug: String, jpeg: Data) async throws -> String
    /// Asks Mealie's scraper, without AI and without saving, whether a page holds a structured
    /// recipe. Returns the recipe's name, or nil when there is none.
    func probeRecipe(at url: URL) async throws -> String?
    func allTags() async throws -> [RecipeTag]
    func createTag(name: String) async throws -> RecipeTag
    func importRecipe(from source: ImportSource, options: ImportOptions) -> AsyncThrowingStream<ImportEvent, Error>
}

public enum RecipeImageSize: String, Sendable {
    case tiny = "tiny-original"
    case small = "min-original"
    case original = "original"
}

extension MealieAPI {
    public func imageURL(recipeID: String, cacheKey: String?, size: RecipeImageSize) -> URL {
        var url = serverURL.appending(path: "api/media/recipes/\(recipeID)/images/\(size.rawValue).webp")
        if let cacheKey { url.append(queryItems: [URLQueryItem(name: "version", value: cacheKey)]) }
        return url
    }

    public func imageURL(for recipe: RecipeSummary, size: RecipeImageSize = .small) -> URL? {
        guard recipe.hasImage, let id = recipe.recipeID else { return nil }
        return imageURL(recipeID: id, cacheKey: recipe.image, size: size)
    }

    public func imageURL(for recipe: Recipe, size: RecipeImageSize = .original) -> URL? {
        guard recipe.hasImage, let id = recipe.recipeID else { return nil }
        return imageURL(recipeID: id, cacheKey: recipe.image, size: size)
    }

    /// Link to the recipe in Mealie's web UI.
    public func webURL(for recipeSlug: String, groupSlug: String?) -> URL {
        guard let groupSlug else { return serverURL }
        return serverURL.appending(path: "g/\(groupSlug)/r/\(recipeSlug)")
    }
}

public enum MealieError: LocalizedError, Equatable {
    case invalidServerURL
    case unauthorized
    case notFound
    case server(status: Int, message: String?)
    case unexpectedResponse
    case streamEnded

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            L("Die Server-Adresse ist ungültig.")
        case .unauthorized:
            L("Anmeldung fehlgeschlagen. Bitte prüfe Benutzername, Passwort oder API-Token.")
        case .notFound:
            L("Nicht gefunden. Ist das wirklich ein Mealie-Server?")
        case .server(let status, let message):
            message ?? L("Der Mealie-Server hat mit Fehler \(status) geantwortet.")
        case .unexpectedResponse:
            L("Unerwartete Antwort vom Server.")
        case .streamEnded:
            L("Die Verbindung zu Mealie wurde unterbrochen, bevor der Import fertig war.")
        }
    }
}

public final class MealieClient: MealieAPI {
    public let serverURL: URL
    private let token: String
    private let session: URLSession

    public init(serverURL: URL, token: String, session: URLSession = .mealie) {
        self.serverURL = serverURL
        self.token = token
        self.session = session
    }

    // MARK: Sign-in (no token yet)

    /// Normalises user input like `mealie.local:9000/` into a base URL.
    public static func normalizedServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/api") { text.removeLast(4) }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    public static func appInfo(serverURL: URL, session: URLSession = .mealie) async throws -> MealieAppInfo {
        let request = URLRequest(url: serverURL.appending(path: "api/app/about"))
        return try await send(request, session: session)
    }

    /// Logs in with username and password and exchanges the session for a long-lived API token,
    /// so the app never stores the password.
    public static func signIn(serverURL: URL, username: String, password: String,
                              session: URLSession = .mealie) async throws -> String {
        var request = URLRequest(url: serverURL.appending(path: "api/auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "remember_me", value: "true")
        ]
        request.httpBody = form.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        let login: AuthTokenResponse = try await send(request, session: session)

        let client = MealieClient(serverURL: serverURL, token: login.accessToken, session: session)
        do {
            return try await client.createAPIToken(name: "Recipe2Mealie (iOS)")
        } catch {
            // Fall back to the session token; it expires, but the user can sign in again.
            return login.accessToken
        }
    }

    func createAPIToken(name: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let response: APITokenResponse = try await send(path: "api/users/api-tokens", method: "POST", body: body)
        return response.token
    }

    // MARK: MealieAPI

    public func currentUser() async throws -> MealieUser {
        try await send(path: "api/users/self")
    }

    public func recipes(page: Int, perPage: Int, search: String?, tagSlugs: [String]) async throws -> Page<RecipeSummary> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(perPage)),
            URLQueryItem(name: "orderBy", value: "created_at"),
            URLQueryItem(name: "orderDirection", value: "desc")
        ]
        if let search = search?.nilIfBlank {
            query.append(URLQueryItem(name: "search", value: search))
        }
        query += tagSlugs.map { URLQueryItem(name: "tags", value: $0) }
        return try await send(path: "api/recipes", query: query)
    }

    public func recipe(slug: String) async throws -> Recipe {
        try await send(path: "api/recipes/\(slug)")
    }

    public func deleteRecipe(slug: String) async throws {
        let request = makeRequest(path: "api/recipes/\(slug)", method: "DELETE")
        _ = try await Self.data(for: request, session: session)
    }

    public func createRecipe(name: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        // Mealie answers with the slug as a bare JSON string.
        let data = try await Self.data(for: makeRequest(path: "api/recipes", method: "POST", body: body),
                                       session: session)
        guard let slug = try? JSONDecoder().decode(String.self, from: data) else {
            throw MealieError.unexpectedResponse
        }
        return slug
    }

    public func probeRecipe(at url: URL) async throws -> String? {
        let body = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString, "useOpenAI": false])
        var request = makeRequest(path: "api/recipes/test-scrape-url", method: "POST", body: body)
        request.timeoutInterval = 30
        let data = try await Self.data(for: request, session: session)
        // Success is the scraped schema.org Recipe object; failure is a plain JSON string.
        guard let recipe = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = (recipe["name"] as? String)?.nilIfBlank
        let hasContent = recipe["recipeIngredient"] != nil || recipe["recipeInstructions"] != nil
        return hasContent ? (name ?? url.host() ?? L("Rezept")) : nil
    }

    public func uploadImage(slug: String, jpeg: Data) async throws -> String {
        struct Response: Decodable { var image: String }
        var form = MultipartForm()
        form.addFile("image", filename: "cover.jpg", mimeType: "image/jpeg", data: jpeg)
        form.addField("extension", "jpg")
        let request = makeRequest(path: "api/recipes/\(slug)/image", method: "PUT", form: form)
        let response: Response = try await Self.send(request, session: session)
        return response.image
    }

    public func updateRecipe(slug: String, changes: RecipePatch) async throws -> Recipe {
        // PATCH only touches the fields that are present in the body.
        let body = try JSONEncoder().encode(changes)
        return try await send(path: "api/recipes/\(slug)", method: "PATCH", body: body)
    }

    public func allTags() async throws -> [RecipeTag] {
        let page: Page<RecipeTag> = try await send(path: "api/organizers/tags", query: [
            URLQueryItem(name: "perPage", value: "-1"),
            URLQueryItem(name: "orderBy", value: "name"),
            URLQueryItem(name: "orderDirection", value: "asc")
        ])
        return page.items
    }

    public func createTag(name: String) async throws -> RecipeTag {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        return try await send(path: "api/organizers/tags", method: "POST", body: body)
    }

    public func importRecipe(from source: ImportSource, options: ImportOptions) -> AsyncThrowingStream<ImportEvent, Error> {
        let request: URLRequest
        do {
            request = try makeImportRequest(source: source, options: options)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let session = session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw MealieError.unexpectedResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes.prefix(64_000) { body.append(byte) }
                        throw Self.error(status: http.statusCode, body: body)
                    }

                    var parser = ServerSentEventParser()
                    for try await line in bytes.lines {
                        guard let event = parser.consume(line: line) else { continue }
                        continuation.yield(event)
                        switch event {
                        case .done, .failed:
                            continuation.finish()
                            return
                        case .progress:
                            continue
                        }
                    }
                    throw MealieError.streamEnded
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Requests

    private func makeImportRequest(source: ImportSource, options: ImportOptions) throws -> URLRequest {
        switch source {
        case .link(let url) where options.translateLanguage == nil:
            // The plain URL import is cheaper: well-marked-up sites are scraped without AI.
            var request = makeRequest(path: "api/recipes/create/url/stream", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "url": url.absoluteString,
                "includeTags": options.includeTags,
                "includeCategories": options.includeCategories
            ])
            return request.asEventStream()

        case .link(let url):
            // Only the AI import can translate the finished recipe.
            var form = aiForm(options: options)
            form.addField("url", url.absoluteString)
            return makeRequest(path: "api/recipes/create/ai/stream", method: "POST", form: form).asEventStream()

        case .text(let text):
            var form = aiForm(options: options)
            form.addField("content", text)
            return makeRequest(path: "api/recipes/create/ai/stream", method: "POST", form: form).asEventStream()

        case .photos(let images, let note):
            var form = aiForm(options: options)
            if let note = note?.nilIfBlank { form.addField("content", note) }
            for (index, jpeg) in images.enumerated() {
                form.addFile("images", filename: "foto-\(index + 1).jpg", mimeType: "image/jpeg", data: jpeg)
            }
            return makeRequest(path: "api/recipes/create/ai/stream", method: "POST", form: form).asEventStream()
        }
    }

    private func aiForm(options: ImportOptions) -> MultipartForm {
        var form = MultipartForm()
        form.addField("createNewOrganizers", options.includeTags ? "true" : "false")
        if let language = options.translateLanguage { form.addField("translateLanguage", language) }
        return form
    }

    private func makeRequest(path: String, method: String = "GET", query: [URLQueryItem] = [],
                             body: Data? = nil, form: MultipartForm? = nil) -> URLRequest {
        var url = serverURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let form {
            request.httpBody = form.body
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send<T: Decodable>(path: String, method: String = "GET", query: [URLQueryItem] = [],
                                    body: Data? = nil) async throws -> T {
        try await Self.send(makeRequest(path: path, method: method, query: query, body: body), session: session)
    }

    private static func send<T: Decodable>(_ request: URLRequest, session: URLSession) async throws -> T {
        let data = try await data(for: request, session: session)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Mealie's schema is loose; log exactly which field failed so it can be fixed.
            log.error("Decoding \(String(describing: T.self)) from \(request.url?.path() ?? "?") failed: \(error)")
            throw MealieError.unexpectedResponse
        }
    }

    private static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MealieError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else { throw error(status: http.statusCode, body: data) }
        return data
    }

    static func error(status: Int, body: Data) -> MealieError {
        switch status {
        case 401, 403: return .unauthorized
        case 404: return .notFound
        default: return .server(status: status, message: serverMessage(in: body))
        }
    }

    /// Mealie wraps errors as `{"detail": "…"}` or `{"detail": {"message": "…"}}`.
    static func serverMessage(in body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let detail = json["detail"] as? String { return detail }
        if let detail = json["detail"] as? [String: Any], let message = detail["message"] as? String { return message }
        return nil
    }
}

extension URLRequest {
    fileprivate func asEventStream() -> URLRequest {
        var request = self
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Imports that download and transcribe a video can be silent for a while between events.
        request.timeoutInterval = 300
        return request
    }
}

extension URLSession {
    /// Session that sends the user's language so Mealie localises its progress messages.
    public static let mealie: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Accept-Language": Locale.preferredLanguages.first ?? "de-DE"]
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()
}
