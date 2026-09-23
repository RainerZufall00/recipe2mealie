import MealieKit
import SwiftUI

/// First launch: connect to a Mealie server.
struct WelcomeView: View {
    @Environment(MealieAccount.self) private var account

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
        } catch let urlError as URLError {
            error = String(localized: "Der Server ist nicht erreichbar (\(urlError.localizedDescription)). Stimmt die Adresse?")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
