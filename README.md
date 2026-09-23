<p align="center">
  <img src="Recipe2Mealie/Assets.xcassets/AppLogo.imageset/AppLogo.png" width="128" alt="Recipe2Mealie icon">
</p>

<h1 align="center">Recipe2Mealie</h1>

<p align="center">
  Import recipes from videos, websites, photos and text into your own <a href="https://mealie.io">Mealie</a> –
  and browse, cook and edit them on iPhone and iPad.
</p>

> **Unofficial app.** Recipe2Mealie is an independent project and is not affiliated with or endorsed by the
> Mealie project.

## Features

- **Share to import** – share a YouTube Short, Instagram Reel, TikTok or recipe website from any app and the
  recipe lands in Mealie, with live progress.
- **Description first** – for YouTube links, the app checks the video description before anything else. If it
  links to a recipe page (verified by your Mealie server) or contains the recipe itself, you can import that
  directly instead of having the whole video transcribed.
- **Photos, cookbook scans and text** – scan cookbook pages with the document camera, pick photos or paste text.
  On devices with Apple Intelligence this runs **entirely on the iPhone** (Vision text recognition + Apple's
  on-device model); Mealie only receives the finished recipe. Mealie AI is available as a fallback.
- **A full recipe browser** – search, tag filters, a scalable ingredient list, cooking mode, editing of every
  field, and cover images from the camera, your photos or Image Playground.
- **Private by design** – no accounts, no analytics, no tracking. Your recipes only go to *your* server.
- German and English, iPhone and iPad, light and dark mode.

## How importing works

| Source | What happens | AI needed? |
|---|---|---|
| Recipe website | Mealie reads the page's structured recipe data | No |
| YouTube with a recipe link in the description | Mealie reads the linked page | No |
| YouTube with the recipe in the description | Extracted on the iPhone, or by Mealie AI | On-device, or Mealie AI |
| Video without either | Mealie downloads the audio, uses subtitles or transcribes it | Mealie AI with an audio provider |
| Photos, scans, text | Extracted on the iPhone, or by Mealie AI | On-device, or Mealie AI |

## Requirements

- iOS / iPadOS 26 or later
- A Mealie server, version 3.x recommended
- For video imports: an [AI provider with audio transcription](https://docs.mealie.io/documentation/getting-started/installation/ai-providers/) configured in Mealie
- For on-device processing: a device that supports Apple Intelligence

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

### Tests

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
| `docs/` | Privacy policy, App Store material, and the original (German) concept documents |

Translations live in String Catalogs: `Recipe2Mealie/Localizable.xcstrings`,
`ShareExtension/Localizable.xcstrings` and `Packages/MealieKit/Sources/MealieKit/Resources/Localizable.xcstrings`.
Strings inside the package go through `L("…")` so they are looked up in the package's own catalog.

## Contributing

Issues and pull requests are welcome. Please keep the app free of third-party dependencies, trackers and
analytics, and run the tests before opening a pull request. New user-facing text needs a German and an English
entry in the matching String Catalog.

## License

The code is released under the [MIT License](LICENSE).

The name **Recipe2Mealie** and the app icon are not covered by the license. If you publish your own build, please
use a different name and icon. *Mealie* is the name of an independent open-source project. *YouTube* is a
trademark of Google LLC. This app uses YouTube API Services; see the
[YouTube Terms of Service](https://www.youtube.com/t/terms) and the
[Google Privacy Policy](https://policies.google.com/privacy).

### Demo photos

The demo mode ("Try without a server") uses eight photos from [Unsplash](https://unsplash.com), in
`Packages/MealieKit/Sources/MealieKit/Resources/DemoImages/`. They are not covered by the MIT License but by the
[Unsplash License](https://unsplash.com/license): free to use, but not to be sold unaltered or used to build a
competing photo service.

| Recipe | Photo by |
|---|---|
| Crispy Salmon with Zucchini Noodles | [Caroline Attwood](https://unsplash.com/photos/bpPTlXWTOvg) |
| Shakshuka | [Yoav Aziz](https://unsplash.com/photos/422N7Nwq5XY) |
| Thai Red Curry with Tofu | [iMattSmart](https://unsplash.com/photos/wgvbmn4d0Wk) |
| One-Pot Tomato Pasta | [Aleksandra Tanasiienko](https://unsplash.com/photos/0y6eMd8vevA) |
| Carnitas Tacos | [Frankie Lopez](https://unsplash.com/photos/_j4S4V2C8ew) |
| Rainbow Buddha Bowl | [Mariana Medvedeva](https://unsplash.com/photos/fk6IiypMWss) |
| Fluffy Blueberry Pancakes | [Adam Bartoszewicz](https://unsplash.com/photos/s8iYlK9ByQE) |
| Banana Bread | [Cody Chan](https://unsplash.com/photos/a0fBbS8RZAo) |
