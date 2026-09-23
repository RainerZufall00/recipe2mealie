# App Store listing

Character limits from App Store Connect in brackets. Checked with `docs/app-store/check-lengths.py`.

## Shared

- **Category:** Food & Drink (secondary: Productivity)
- **Price:** Free
- **Age rating:** 4+ (no objectionable content; the app shows the user's own recipes)
- **App Privacy:** "Data Not Collected"
- **Privacy Policy URL:** `https://rainerzufall00.github.io/recipe2mealie/privacy` (GitHub Pages from `docs/`)
- **Support URL:** `https://github.com/RainerZufall00/recipe2mealie/issues`
- **Copyright:** 2026 RainerZufall00

---

## Deutsch (de-DE)

**Name** [30]
Recipe2Mealie

**Untertitel** [30]
Rezepte importieren für Mealie

**Werbetext** [170]
Rezept im Short gesehen? Teilen, fertig. Recipe2Mealie holt Rezepte aus Videos, Webseiten, Kochbuchfotos und Text in deinen eigenen Mealie-Server.

**Schlüsselwörter** [100]
Rezepte,Kochbuch,Rezeptverwaltung,YouTube,Import,Kochen,selfhosted,Instagram,TikTok,Scan,Rezeptbuch

**Beschreibung** [4000]
Recipe2Mealie bringt Rezepte mit einem Tipp in deinen eigenen Mealie-Server – egal ob sie in einem Video, auf einer Webseite, in einem Kochbuch oder in einer Nachricht stecken.

TEILEN UND FERTIG
Teile einen YouTube Short, ein Instagram Reel, ein TikTok oder eine Rezeptseite aus jeder App mit Recipe2Mealie. Du siehst live, was gerade passiert, und am Ende das fertige Rezept mit Zutaten, Schritten und Bild.

ERST DIE BESCHREIBUNG, DANN DAS VIDEO
Bei YouTube schaut die App zuerst in die Videobeschreibung. Steht dort ein Link zur Rezeptseite oder das Rezept selbst, übernimmst du es direkt – schneller und genauer, als das ganze Video transkribieren zu lassen.

KOCHBÜCHER UND FOTOS
Scanne Kochbuchseiten mit der Kamera, wähle Fotos aus oder füge Text ein. Auf Geräten mit Apple Intelligence wertet Recipe2Mealie sie direkt auf dem iPhone aus. Dein Mealie-Server bekommt nur das fertige Rezept.

DEINE REZEPTE, ÜBERALL
Durchsuche deine Sammlung, filtere nach Tags, rechne Portionen um, hake Zutaten ab und nutze den Kochmodus, bei dem der Bildschirm an bleibt. Bearbeite jedes Rezept direkt in der App und setze Titelbilder mit der Kamera, aus deinen Fotos oder mit Image Playground.

PRIVAT
Kein Konto, keine Werbung, kein Tracking. Deine Rezepte gehen nur an deinen eigenen Server.

VORAUSSETZUNGEN
Du brauchst einen eigenen Mealie-Server (mealie.io). Für Video-Importe muss in Mealie ein KI-Anbieter mit Audio-Transkription eingerichtet sein. Die Auswertung auf dem Gerät setzt Apple Intelligence voraus.

Recipe2Mealie ist Open Source und eine unabhängige App. Sie ist nicht mit dem Mealie-Projekt verbunden und wird nicht von ihm unterstützt.

**Neu in dieser Version** [4000]
Erste Version.

---

## English (en-US)

**Name** [30]
Recipe2Mealie

**Subtitle** [30]
Recipe importer for Mealie

**Promotional text** [170]
Saw a recipe in a Short? Share it, done. Recipe2Mealie brings recipes from videos, websites, cookbook photos and text into your own Mealie server.

**Keywords** [100]
recipes,cookbook,recipe manager,YouTube,import,cooking,self-hosted,Instagram,TikTok,scan,meal

**Description** [4000]
Recipe2Mealie brings recipes into your own Mealie server with a single tap – whether they're in a video, on a website, in a cookbook or in a message.

SHARE AND YOU'RE DONE
Share a YouTube Short, an Instagram Reel, a TikTok or a recipe website from any app with Recipe2Mealie. You see live what's happening, and at the end the finished recipe with ingredients, steps and image.

DESCRIPTION FIRST, THEN THE VIDEO
For YouTube, the app looks at the video description first. If it links to the recipe page or contains the recipe itself, you import that directly – faster and more accurate than transcribing the whole video.

COOKBOOKS AND PHOTOS
Scan cookbook pages with the camera, pick photos or paste text. On devices with Apple Intelligence, Recipe2Mealie processes them right on your iPhone. Your Mealie server only receives the finished recipe.

YOUR RECIPES, EVERYWHERE
Search your collection, filter by tags, scale servings, check off ingredients and use cooking mode, which keeps the screen on. Edit every recipe right in the app and set cover images from the camera, your photos or Image Playground.

PRIVATE
No account, no ads, no tracking. Your recipes only go to your own server.

REQUIREMENTS
You need your own Mealie server (mealie.io). Video imports require an AI provider with audio transcription set up in Mealie. On-device processing requires Apple Intelligence.

Recipe2Mealie is open source and an independent app. It is not affiliated with or endorsed by the Mealie project.

**What's New** [4000]
First release.

---

## Screenshots

Required: iPhone 6.9" (1320 × 2868) and iPad 13" (2064 × 2752), up to 10 each, per language.
Suggested order:

1. Import home screen
2. Share sheet import with live progress (a YouTube Short)
3. "Found in the video description" choices
4. Import result card
5. Recipe detail with ingredients and steps
6. Recipe list with images
7. Cookbook scan / photo import
8. Editing a recipe

Screens 1–6 and 8 come from the demo mode: launch with `-demo` (add `-AppleLanguages "(en)"` for English), import
`https://youtube.com/shorts/demo` via *Link* and pick *Analyze the whole video* for the progress screen. Use the
iPhone 18 Pro Max and iPad Pro 13-inch (M5) simulators; `xcrun simctl status_bar <device> override --time 9:41`
cleans up the status bar, and on iPad set the simulator's system language too, since the date in the status bar
follows it. Screen 7 needs a real device with a camera.

The PNGs live in `docs/app-store/screenshots/<language>/<device>/`, which is git-ignored (about 34 MB).
