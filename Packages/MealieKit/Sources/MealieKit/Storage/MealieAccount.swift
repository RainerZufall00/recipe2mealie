import Foundation
import Observation

/// The signed-in Mealie server. Shared by the app and the share extension.
@MainActor
@Observable
public final class MealieAccount {
    public private(set) var api: (any MealieAPI)?
    public private(set) var user: MealieUser?

    public var importOptions: ImportOptions {
        didSet { Self.saveOptions(importOptions) }
    }

    public var isSignedIn: Bool { api != nil }
    public var serverURL: URL? { api?.serverURL }

    private static let serverKey = "serverURL"
    private static let userKey = "user"
    private static let optionsKey = "importOptions"
    private static let tokenAccount = "apiToken"
    private static let loginAccount = "login"

    /// Server plus token in one Keychain item, so the share extension can sign in even when
    /// App Groups aren't available (free developer accounts).
    private struct StoredLogin: Codable {
        var server: URL
        var token: String
        var user: MealieUser?
    }

    public init() {
        importOptions = Self.loadOptions()
        user = AppGroup.defaults.data(forKey: Self.userKey)
            .flatMap { try? JSONDecoder().decode(MealieUser.self, from: $0) }
        if let stored = Self.loadLogin() {
            api = MealieClient(serverURL: stored.server, token: stored.token)
            user = stored.user ?? user
        } else if let server = AppGroup.defaults.url(forKey: Self.serverKey),
                  let token = KeychainStore.shared.read(account: Self.tokenAccount) {
            // A login from an earlier version: move it to the shared Keychain item so the
            // share extension can see it too.
            api = MealieClient(serverURL: server, token: token)
            Self.saveLogin(StoredLogin(server: server, token: token, user: user))
            if Self.loadLogin() != nil {
                KeychainStore.shared.delete(account: Self.tokenAccount)
            }
        }
    }

    /// For previews and tests.
    public init(api: any MealieAPI, user: MealieUser? = nil) {
        self.api = api
        self.user = user
        importOptions = ImportOptions()
    }

    public private(set) var isDemo = false

    /// Try the app without a server. Nothing is stored.
    public func startDemo() {
        let demo = DemoMealieAPI()
        api = demo
        isDemo = true
        Task { user = try? await demo.currentUser() }
    }

    public func signIn(server: String, apiToken: String) async throws {
        guard let url = MealieClient.normalizedServerURL(server) else { throw MealieError.invalidServerURL }
        try await finishSignIn(serverURL: url, token: apiToken.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func signIn(server: String, username: String, password: String) async throws {
        guard let url = MealieClient.normalizedServerURL(server) else { throw MealieError.invalidServerURL }
        let token = try await MealieClient.signIn(serverURL: url, username: username, password: password)
        try await finishSignIn(serverURL: url, token: token)
    }

    /// Checks that the server is reachable and actually Mealie.
    public func checkServer(_ server: String) async throws -> MealieAppInfo {
        guard let url = MealieClient.normalizedServerURL(server) else { throw MealieError.invalidServerURL }
        return try await MealieClient.appInfo(serverURL: url)
    }

    public func refreshUser() async {
        guard let api, let user = try? await api.currentUser() else { return }
        setUser(user)
    }

    public func signOut() {
        KeychainStore.shared.delete(account: Self.loginAccount)
        KeychainStore.shared.delete(account: Self.tokenAccount)
        AppGroup.defaults.removeObject(forKey: Self.serverKey)
        AppGroup.defaults.removeObject(forKey: Self.userKey)
        ImportHistory.clear()
        api = nil
        user = nil
        isDemo = false
    }

    public func webURL(forRecipe slug: String) -> URL? {
        api?.webURL(for: slug, groupSlug: user?.groupSlug)
    }

    private func finishSignIn(serverURL: URL, token: String) async throws {
        guard !token.isEmpty else { throw MealieError.unauthorized }
        let client = MealieClient(serverURL: serverURL, token: token)
        let user = try await client.currentUser()
        Self.saveLogin(StoredLogin(server: serverURL, token: token, user: user))
        AppGroup.defaults.set(serverURL, forKey: Self.serverKey)
        api = client
        setUser(user)
    }

    private static func loadLogin() -> StoredLogin? {
        guard let json = KeychainStore.shared.read(account: loginAccount) else { return nil }
        return try? JSONDecoder().decode(StoredLogin.self, from: Data(json.utf8))
    }

    private static func saveLogin(_ login: StoredLogin) {
        guard let data = try? JSONEncoder().encode(login) else { return }
        KeychainStore.shared.save(String(decoding: data, as: UTF8.self), account: loginAccount)
    }

    private func setUser(_ user: MealieUser) {
        self.user = user
        AppGroup.defaults.set(try? JSONEncoder().encode(user), forKey: Self.userKey)
        if var login = Self.loadLogin() {
            login.user = user
            Self.saveLogin(login)
        }
    }

    private static func loadOptions() -> ImportOptions {
        AppGroup.defaults.data(forKey: optionsKey)
            .flatMap { try? JSONDecoder().decode(ImportOptions.self, from: $0) } ?? ImportOptions()
    }

    private static func saveOptions(_ options: ImportOptions) {
        AppGroup.defaults.set(try? JSONEncoder().encode(options), forKey: optionsKey)
    }
}
