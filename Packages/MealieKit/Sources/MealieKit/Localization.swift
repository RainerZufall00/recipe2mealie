import Foundation

/// Text from MealieKit's own String Catalog (Resources/Localizable.xcstrings).
///
/// SwiftUI looks up `Text("…")` in the app's main bundle, which doesn't contain the package's
/// translations, so every user-facing string in this package goes through `L(…)`.
/// Interpolations become format specifiers: `L("\(count) Zutaten")` is the key "%lld Zutaten".
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
