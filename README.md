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

## Get the app

Recipe2Mealie is coming to the App Store. Until then, a TestFlight beta will be linked here.

1. Install the app and open it.
2. Enter your Mealie server address and sign in with your Mealie account or an API token.
3. Share a video, website or photo to **Recipe2Mealie** from any app, or use the import screen in the app.

Just curious? Tap *Try without a server* to explore the app with built-in sample recipes.

## Privacy

The app has no accounts, analytics or tracking. It talks only to your Mealie server and, for YouTube links,
to the YouTube Data API. Details: [Privacy Policy](https://rainerzufall00.github.io/recipe2mealie/privacy).

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/RainerZufall00/recipe2mealie/issues/new/choose)
or use *Feedback* in the app's settings.

## Contributing

The app is open source. Issues and pull requests are welcome – see [CONTRIBUTING.md](CONTRIBUTING.md) for how to
build it and how the project is structured.

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
