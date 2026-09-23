import MealieKit
import SwiftUI

@main
struct Recipe2MealieApp: App {
    @State private var account = MealieAccount()

    init() {
        Diagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(account)
                .environment(\.keepScreenAwake, KeepScreenAwakeAction { UIApplication.shared.isIdleTimerDisabled = $0 })
                .tint(.brand)
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-demo") { account.startDemo() }
                }
        }
    }
}

enum AppTab: String, Hashable {
    case home, recipes, settings

    /// Key of the "start screen" setting.
    static let startTabKey = "startTab"
}

struct RootView: View {
    @Environment(MealieAccount.self) private var account
    // Opens on the tab chosen in Settings → Startbildschirm.
    @State private var selectedTab = AppTab(
        rawValue: UserDefaults.standard.string(forKey: AppTab.startTabKey) ?? "") ?? .home

    var body: some View {
        if account.isSignedIn {
            TabView(selection: $selectedTab) {
                Tab("Importieren", systemImage: "square.and.arrow.down.on.square", value: AppTab.home) {
                    HomeView()
                }
                Tab("Rezepte", systemImage: "book.pages", value: AppTab.recipes) {
                    RecipesView()
                }
                Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .task { await account.refreshUser() }
        } else {
            WelcomeView()
        }
    }
}
