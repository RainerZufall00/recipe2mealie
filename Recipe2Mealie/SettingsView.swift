import MealieKit
import SwiftUI

struct SettingsView: View {
    @Environment(MealieAccount.self) private var account
    @State private var confirmingSignOut = false
    @AppStorage(AppTab.startTabKey) private var startTab = AppTab.home.rawValue

    var body: some View {
        @Bindable var account = account
        NavigationStack {
            Form {
                Section("Mealie") {
                    LabeledContent("Server", value: account.isDemo ? String(localized: "Demo") : account.serverURL?.host() ?? "–")
                    if let user = account.user {
                        LabeledContent("Angemeldet als", value: user.displayName)
                        if let household = user.household {
                            LabeledContent("Haushalt", value: household)
                        }
                    }
                    if let url = account.serverURL, !account.isDemo {
                        Link(destination: url) {
                            Label("Mealie im Browser öffnen", systemImage: "safari")
                        }
                    }
                }

                Section("Allgemein") {
                    Picker("Startbildschirm", selection: $startTab) {
                        Text("Importieren").tag(AppTab.home.rawValue)
                        Text("Rezepte").tag(AppTab.recipes.rawValue)
                    }
                }

                Section {
                    Toggle("Tags übernehmen", isOn: $account.importOptions.includeTags)
                    Toggle("Kategorien übernehmen", isOn: $account.importOptions.includeCategories)
                    Toggle("Auf \(ImportOptions.deviceLanguageLocalized) übersetzen",
                           isOn: $account.importOptions.translates)
                    Toggle("Fotos und Text auf dem iPhone verarbeiten",
                           isOn: $account.importOptions.preferLocalAI)
                        .disabled(!LocalRecipeAI.availability.isAvailable)
                    if let hint = LocalRecipeAI.availability.message {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Übernimmt Schlagwörter der Quelle und legt fehlende Tags in Mealie an. Die Übersetzung erledigt Mealie AI, nachdem das Rezept erstellt wurde.")
                }

                Section {
                    Label {
                        Text("Fotos und Texte wertet die App auf dem iPhone aus, wenn das oben eingeschaltet ist. Dein Mealie-Server bekommt dann nur das fertige Rezept.")
                    } icon: {
                        Image(systemName: "iphone.gen3").foregroundStyle(.brand)
                    }
                    Label {
                        Text("Links, Texte und Fotos gehen **nur an deinen Mealie-Server**. Für Videos lädt Mealie den Ton und transkribiert ihn mit dem KI-Dienst, den du in Mealie eingerichtet hast.")
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(.brand)
                    }
                    Label {
                        Text("Die App selbst sammelt keine Daten und nutzt keine Analyse- oder Werbedienste. Nur für die Vorschau fragt sie bei YouTube bzw. der Webseite Titel und Vorschaubild ab.")
                    } icon: {
                        Image(systemName: "hand.raised").foregroundStyle(.brand)
                    }
                    Label {
                        Text("Bei YouTube-Links liest die App Titel und Beschreibung über die YouTube-API-Dienste; dabei geht nur die Video-ID an Google. [YouTube-Nutzungsbedingungen](https://www.youtube.com/t/terms) · [Datenschutzerklärung von Google](https://policies.google.com/privacy)")
                    } icon: {
                        Image(systemName: "play.rectangle").foregroundStyle(.brand)
                    }
                } header: {
                    Text("Datenschutz")
                }

                Section {
                    LabeledContent("Teilen aus anderen Apps",
                                   value: KeychainStore.sharedGroup != nil ? String(localized: "verfügbar") : String(localized: "nicht verfügbar"))
                    if FeedbackTarget.isAvailable {
                        NavigationLink {
                            FeedbackView()
                        } label: {
                            Label("Feedback geben", systemImage: "bubble.left.and.text.bubble.right")
                        }
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnose & Absturzberichte", systemImage: "stethoscope")
                    }
                    Link(destination: URL(string: "https://docs.mealie.io/documentation/getting-started/installation/ai-providers/")!) {
                        Label("KI in Mealie einrichten", systemImage: "sparkles")
                    }
                } header: {
                    Text("Hilfe")
                } footer: {
                    Text("Für Video-Importe braucht Mealie einen KI-Anbieter mit Audio-Transkription.")
                }

                Section {
                    Button(account.isDemo ? String(localized: "Demo beenden") : String(localized: "Abmelden"), role: .destructive) {
                        if account.isDemo { account.signOut() } else { confirmingSignOut = true }
                    }
                } footer: {
                    Text(appVersion)
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog("Abmelden?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { account.signOut() }
            } message: {
                Text("Der API-Token wird von diesem Gerät entfernt. Deine Rezepte bleiben in Mealie.")
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Recipe2Mealie \(version) (\(build))"
    }
}
