import MealieKit
import SwiftUI

/// First launch: connect to a Mealie server.
struct WelcomeView: View {
    @Environment(MealieAccount.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    enum Method: String, CaseIterable, Identifiable {
        case token = "API-Token"
        case password = "Passwort"
        var id: Self { self }

        var title: String {
            switch self {
            case .token: String(localized: "API-Token")
            case .password: String(localized: "Passwort")
            }
        }
    }

    @State private var server = ""
    @State private var method = Method.token
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var saveToICloud = false
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(.rect(cornerRadius: 24))
                        Text("Recipe2Mealie")
                            .font(.largeTitle.bold())
                            .fontDesign(.serif)
                        Text("Rezepte aus Videos, Webseiten, Fotos und Text mit einem Tipp in dein Mealie holen.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)

                if let saved = account.iCloudLogin {
                    Section {
                        Button {
                            Task { await connectFromICloud() }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aus iCloud übernehmen")
                                    Text(savedLoginDescription(saved))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                        }
                        .disabled(isConnecting)
                    } footer: {
                        Text("Server und API-Token aus deinem iCloud-Schlüsselbund, gesichert auf einem deiner Geräte.")
                    }
                }

                Section {
                    TextField("mealie.example.com", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                }

                Section {
                    Picker("Anmeldung", selection: $method) {
                        ForEach(Method.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    switch method {
                    case .token:
                        SecureField("API-Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .password:
                        TextField("Benutzername oder E-Mail", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Passwort", text: $password)
                            .textContentType(.password)
                    }
                } footer: {
                    switch method {
                    case .token:
                        Text("Einen API-Token erstellst du in Mealie unter **Profil → API-Tokens**. Er wird sicher im Schlüsselbund gespeichert.")
                    case .password:
                        Text("Dein Passwort wird nicht gespeichert. Die App legt damit einen eigenen API-Token in Mealie an.")
                    }
                }

                Section {
                    Toggle("Im iCloud-Schlüsselbund sichern", isOn: $saveToICloud)
                } footer: {
                    Text("Deine anderen Geräte mit demselben Apple Account können sich dann ohne erneute Eingabe verbinden.")
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting { ProgressView() } else { Text("Verbinden").font(.headline) }
                            Spacer()
                        }
                    }
                    .disabled(!canConnect || isConnecting)
                }

                Section {
                    Button("Ohne Server ausprobieren") { account.startDemo() }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .task { account.refreshICloudLogin() }
            .onChange(of: scenePhase) { _, phase in
                // iCloud Keychain may sync the login while the app is in the background.
                if phase == .active { account.refreshICloudLogin() }
            }
            .alert("Verbindung fehlgeschlagen", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var canConnect: Bool {
        guard MealieClient.normalizedServerURL(server) != nil else { return false }
        switch method {
        case .token: return !token.isEmpty
        case .password: return !username.isEmpty && !password.isEmpty
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            _ = try await account.checkServer(server)
            switch method {
            case .token: try await account.signIn(server: server, apiToken: token)
            case .password: try await account.signIn(server: server, username: username, password: password)
            }
            password = ""
            if saveToICloud { account.setSavedToICloud(true) }
        } catch let urlError as URLError {
            error = String(localized: "Der Server ist nicht erreichbar (\(urlError.localizedDescription)). Stimmt die Adresse?")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func savedLoginDescription(_ login: MealieAccount.ICloudLogin) -> String {
        let host = login.server.host() ?? login.server.absoluteString
        guard let user = login.user?.displayName else { return host }
        return "\(host) · \(user)"
    }

    private func connectFromICloud() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await account.signInFromICloud()
        } catch let urlError as URLError {
            error = String(localized: "Der Server ist nicht erreichbar (\(urlError.localizedDescription)). Stimmt die Adresse?")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
