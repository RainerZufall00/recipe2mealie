import Foundation
import Security

/// Storage shared between the app and the share extension through the App Group.
public enum AppGroup {
    /// Must match the App Group entitlement of both targets (Config/*.entitlements).
    public static let identifier = "group.de.recipe2mealie"

    // UserDefaults is thread-safe but not marked Sendable.
    nonisolated(unsafe) public static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// Free Apple IDs (sideloading via SideStore/AltStore) can't use App Groups. Without one the
    /// app still works, but the share extension can't see the login.
    public static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

/// Stores the Mealie login in the Keychain, shared with the share extension.
///
/// Sharing runs through a Keychain access group rather than the App Group, because Apple grants
/// keychain sharing to free developer accounts but not App Groups. The group is declared per
/// target in Info.plist so the team prefix is filled in at build time.
public struct KeychainStore: Sendable {
    public static let shared = KeychainStore(service: "de.recipe2mealie.token")

    let service: String

    /// The shared access group, or nil when this build can't share (e.g. unsigned builds).
    public static var sharedGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    }

    /// Access groups to try, most shared first.
    private var groups: [String?] { [Self.sharedGroup, AppGroup.identifier, nil] }

    public func read(account: String) -> String? {
        for group in groups {
            var query = baseQuery(account: account, accessGroup: group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }

    @discardableResult
    public func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        // Prefer the shared group; builds without that entitlement fall back to the app's own keychain.
        for group in groups {
            var query = baseQuery(account: account, accessGroup: group)
            query[kSecValueData as String] = Data(value.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess { return true }
            if status != errSecMissingEntitlement { return false }
        }
        return false
    }

    public func delete(account: String) {
        for group in groups {
            SecItemDelete(baseQuery(account: account, accessGroup: group) as CFDictionary)
        }
    }

    private func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

/// A recipe imported through this app, shown on the home screen.
public struct ImportRecord: Codable, Hashable, Identifiable, Sendable {
    public var slug: String
    public var name: String
    public var recipeID: String?
    public var imageKey: String?
    public var sourceTitle: String
    public var sourceURL: URL?
    public var date: Date

    public var id: String { slug }
}

public enum ImportHistory {
    private static let key = "importHistory"
    private static let limit = 30

    public static func load() -> [ImportRecord] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ImportRecord].self, from: data)) ?? []
    }

    public static func add(_ record: ImportRecord) {
        var records = load().filter { $0.slug != record.slug }
        records.insert(record, at: 0)
        save(Array(records.prefix(limit)))
    }

    public static func remove(slug: String) {
        save(load().filter { $0.slug != slug })
    }

    public static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }

    private static func save(_ records: [ImportRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }
}
