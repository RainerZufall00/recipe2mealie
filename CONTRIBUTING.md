# Contributing to Recipe2Mealie

You don't need to build the app to use it – it is distributed through the App Store. This page is for people
who want to work on the code.

## Building

You need Xcode 26 or later. The project has no third-party dependencies.

```bash
git clone https://github.com/RainerZufall00/recipe2mealie.git
cd recipe2mealie
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
open Recipe2Mealie.xcodeproj
```

In `Config/Secrets.xcconfig` set:

- `DEVELOPMENT_TEAM` – your Apple team ID, needed to run on a device
- `APP_BUNDLE_ID_PREFIX` – forks should use their own prefix, bundle IDs are unique per account
- `YOUTUBE_API_KEY` – optional, a YouTube Data API v3 key for the description check. Restrict it to your bundle
  IDs and to the YouTube Data API. Without a key, YouTube links go straight to Mealie.

Where in-app feedback goes is set in `Config/Base.xcconfig` (public, committed): `GITHUB_REPOSITORY` as
`owner/repo` for prefilled issue forms and `FEEDBACK_EMAIL`. Leave them empty to hide the feedback screen.

`Secrets.xcconfig` is ignored by Git. The simulator build works without any of these values; launch with the argument
`-demo` (or tap *Try without a server*) to use built-in sample recipes.

## Tests

```bash
cd Packages/MealieKit
xcodebuild -scheme MealieKit -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

## Project structure

| Folder | Contents |
|---|---|
| `Recipe2Mealie/` | App target: import home screen, recipe list, settings, sign-in, diagnostics |
| `ShareExtension/` | Share extension: takes links, text and photos from the share sheet |
| `Packages/MealieKit/` | Shared Swift package: Mealie API client, import flow, on-device AI, recipe views |
| `Config/` | Build settings, entitlements and Info.plist files |
| `ci_scripts/` | Xcode Cloud scripts for the App Store builds |
| `docs/` | Privacy policy, App Store material, and the original (German) concept documents |

Translations live in String Catalogs: `Recipe2Mealie/Localizable.xcstrings`,
`ShareExtension/Localizable.xcstrings` and `Packages/MealieKit/Sources/MealieKit/Resources/Localizable.xcstrings`.
Strings inside the package go through `L("…")` so they are looked up in the package's own catalog.

## Guidelines

Please keep the app free of third-party dependencies, trackers and analytics, and run the tests before opening a
pull request. New user-facing text needs a German and an English entry in the matching String Catalog.

If you publish your own build, please use a different name and icon (see the license note in the
[README](README.md#license)).
