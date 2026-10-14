import CryptoKit
import Foundation

/// What Mealie's `GET /api/auth/oauth/native/config` returns.
public struct OIDCNativeConfig: Decodable, Sendable {
    var authorizationEndpoint: URL
    var clientID: String
    var scope: String

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case clientID = "client_id"
        case scope
    }
}

/// A sign-in through the OpenID Connect provider Mealie is set up with (Pocket ID, Authentik, …).
///
/// Mealie's web login sends the provider back to Mealie's own login page, which an app can't
/// intercept. Since Mealie 3.23 there are endpoints for apps instead: the app makes the
/// authorization request itself, with PKCE and its own redirect URI, and Mealie exchanges the
/// code for a session. The provider has to allow `redirectURI` on Mealie's client.
public struct OIDCAuthorization: Sendable {
    public let serverURL: URL
    /// The provider's sign-in page, to open in the system browser.
    public let url: URL
    let state: String
    let nonce: String
    let codeVerifier: String

    /// The app's bundle ID: Google only accepts custom schemes that contain a dot.
    public static let callbackScheme = Bundle.main.bundleIdentifier ?? "de.recipe2mealie.app"
    /// The redirect URI to register with the provider.
    public static let redirectURI = "\(callbackScheme):/oauth/callback"

    init(serverURL: URL, config: OIDCNativeConfig) throws {
        self.serverURL = serverURL
        state = Self.randomString()
        nonce = Self.randomString()
        codeVerifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64URLEncodedString()

        guard var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw MealieError.unexpectedResponse
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw MealieError.unexpectedResponse }
        self.url = url
    }

    /// The authorization code from the provider's redirect back to the app.
    func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value?.nilIfBlank }

        if let error = value("error") {
            throw MealieError.oidcFailed(message: value("error_description") ?? error)
        }
        // A different state means the redirect doesn't belong to this sign-in.
        guard value("state") == state, let code = value("code") else { throw MealieError.oidcFailed(message: nil) }
        return code
    }

    private static func randomString() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
