# Mealie Importer – Konzept v1 (schlank)

Entscheidung vom 22.09.2026: **keine lokale KI in v1.** Die App ist ein schöner, schneller Mealie-Client mit Fokus auf Import. Die ganze Extraktion übernimmt der Mealie-Server (Scraper + Mealie AI inkl. Video-Transkription über den OpenAI-Key auf dem Server). Ziel ist der App Store.
Die Hintergrund-Recherche steht in [Machbarkeitsanalyse.md](Machbarkeitsanalyse.md). Lokale KI bleibt dort als mögliche spätere Erweiterung dokumentiert.

## Umfang v1
1. **Import (Hauptfunktion)**: Link aus dem Share Sheet oder eingefügt, Fotos, Text
2. **Rezepte ansehen**: Liste, Suche, Filter, Detail
3. **Einstellungen**: Server, Anmeldung, Import-Optionen

Nicht in v1: lokale KI, Rezepte umfassend bearbeiten, Essensplan, Einkaufsliste.

## Import über Mealie (geprüft im Code von v3.27.0)

| Quelle | Endpunkt | Was Mealie macht |
|---|---|---|
| **Link** (YouTube, Shorts, Instagram, Blogs …) | `POST /api/recipes/create/url/stream` `{url, includeTags, includeCategories}` | Strategie-Kette: ① schema.org-Scraper (Blogs, ohne KI) → ② **Video: yt-dlp lädt Ton + Beschreibung + Untertitel, OpenAI transkribiert und extrahiert** (wenn Audio-Provider aktiv) → ③ KI auf HTML → ④ OpenGraph |
| **Fotos / Text / Link+Text** | `POST /api/recipes/create/ai/stream` (multipart: `url`, `content`, `images[]`, `translateLanguage`, `createNewOrganizers`) | KI-Import, das erste Foto wird Titelbild |

Beide liefern **Server-Sent Events**:
- `event: progress` · `data: {"message": "…"}`: bereits übersetzte Statustexte (z. B. „Video wird heruntergeladen“, „Audio wird mit KI transkribiert“, „Rezept wird aus Transkript erstellt“, „Bild wird heruntergeladen“)
- `event: done` · `data: {"slug": "…"}`
- `event: error` · `data: {"message": "…"}`

Danach: `GET /api/recipes/{slug}` für die Ergebnis-Ansicht.

Weitere Endpunkte: `GET /api/app/about` (Server-Check), `GET /api/users/self` (Token-Check), `GET /api/recipes` (paginiert, Suche), `GET /api/recipes/{slug}`, `PATCH /api/recipes/{slug}` (Titel/Tags nach dem Import), `DELETE /api/recipes/{slug}` (Verwerfen), `GET/POST /api/organizers/tags|categories`, Bilder unter `/api/media/recipes/{id}/images/{min-original|original|tiny-original}.webp`.

## Import-Erlebnis

```
Share Sheet (YouTube)
 └─ Share-Extension-Sheet
     ① Vorschau-Karte: Thumbnail, Titel, Kanal (YouTube oEmbed, ohne Key), Quelle erkannt: „YouTube Short“
     ② [ Rezept importieren ]   (Optionen einklappbar: Tags übernehmen, Übersetzen nach Deutsch)
     ③ Live-Fortschritt: Schrittliste mit Animation, gespeist aus den SSE-Meldungen
        ✓ Link wird analysiert  ✓ Video wird geladen  ◌ Audio wird transkribiert …  (typisch 20–60 s)
     ④ Ergebnis-Karte: Bild, Titel, 12 Zutaten · 6 Schritte · 25 min
        [ Ansehen ]  [ Tags ]  [ Verwerfen ]  [ Fertig ]
```

- In der App: großer Import-Button auf Home, Eingabe per Link aus der Zwischenablage (mit Erkennung), Fotos (PhotosPicker, Kamera) oder Text. Laufende und letzte Importe erscheinen als Karten.
- Fehler bekommen eine menschliche Erklärung und eine Aktion, z. B.: „Mealie konnte kein Rezept finden. Mit Beschreibung/Text erneut versuchen?“
- Haptik bei Erfolg, Konfetti-freie, ruhige Animationen, Liquid-Glass-Design (iOS 26).

## Rezepte ansehen
- iPhone: `NavigationStack`, Grid/Liste mit großen Bildern, Suche, Filter-Chips (Tags, Kategorien), Pull-to-Refresh.
- iPad: `NavigationSplitView` (Seitenleiste mit Tags/Kategorien | Grid | Detail).
- Detail: Hero-Bild, Metadaten, Portionen-Umrechner, Zutaten abhakbar, Schritte, Quelle öffnen, „In Mealie öffnen“, Kochmodus (Display bleibt an).

## Anmeldung
- Server-URL + **API-Token** (in Mealie unter *Profil → API Tokens* erzeugt). Der Token liegt in der Keychain und ist über die Access Group auch in der Share Extension verfügbar.
- Alternativ Benutzername und Passwort über `POST /api/auth/token`. OIDC später.

## Technik
- Swift 6, SwiftUI, async/await, keine Drittanbieter-Abhängigkeiten
- **Mindestversion iOS/iPadOS 26** (Liquid Glass, aktuelle SwiftUI-APIs)
- Targets: App, Share Extension, lokales Swift Package `MealieKit` (API-Client, Modelle, SSE-Parser, Keychain, gemeinsame Views)
- App Group für Import-Verlauf und gemeinsame Einstellungen
- Protokolle + Dependency Injection (`MealieAPI`-Protokoll, Mock für Previews und Tests)

## Offene Punkte / zu testen
1. Bricht Mealie den Import ab, wenn der Client die SSE-Verbindung trennt (Share-Sheet geschlossen)? Wenn ja: Fallback auf den nicht-streamenden Endpunkt mit Hintergrund-`URLSession`.
2. Speicher- und Zeitlimits der Share Extension bei 60-Sekunden-Importen
3. Verhalten, wenn auf dem Server kein Audio-Provider konfiguriert ist (Fehlermeldung → verständlicher Hinweis in der App)
