# Mealie Importer – Technische Machbarkeitsanalyse

Stand: 22.09.2026 · Zielplattformen: iOS / iPadOS 27 (Xcode 27) · Zielsystem: Mealie ≥ 3.x (geprüft gegen `mealie-next`, v3.27.0)

Legende für Verlässlichkeit:
- ✅ **gesichert**: offizielle, dokumentierte API, stabil
- 🟡 **wahrscheinlich**: dokumentiert, aber im Prototyp zu verifizieren (neu in iOS 27 oder Verhalten nicht spezifiziert)
- 🧪 **theoretisch**: technisch denkbar, aber fragil oder nicht spezifiziert
- ⛔ **nicht erlaubt / problematisch**: verstößt gegen AGB, App-Store-Richtlinien oder wird aktiv blockiert

---

## 0. Kurzantwort auf die Kernfrage

> *„Wie bekommen wir auf einem modernen iPhone möglichst viele Informationen über den tatsächlichen Videoinhalt eines geteilten YouTube Shorts, damit das Foundation Model daraus ein Rezept extrahieren kann?“*

**Allein aus dem geteilten Link bekommen wir den Videoinhalt nicht.** Das Share Sheet der YouTube-App liefert eine URL (z. B. `https://youtube.com/shorts/<id>?si=…`) und keine Mediendaten. Mit offiziellen, erlaubten Wegen bekommt die App aus dieser URL nur:

| Information | Weg | Status |
|---|---|---|
| Video-ID, URL | Share Extension (`public.url`) | ✅ A |
| Titel, Kanalname, Thumbnail | YouTube **oEmbed** (`youtube.com/oembed?url=…&format=json`, kein Key) | ✅ A (Netzabruf bei YouTube, keine KI) |
| **Beschreibung** (enthält bei vielen Rezept-Shorts die Zutaten oder einen Blog-Link) | YouTube Data API v3 `videos.list?part=snippet` (API-Key nötig) | ✅ B (Key vom Nutzer) oder C (Key über eigenen Proxy) |
| Rezept von einer verlinkten Blog-Seite | HTML laden, `schema.org/Recipe` als JSON-LD auslesen | ✅ A (deterministisch, ohne KI) |
| Transkript/Untertitel | nur über inoffizielle Endpunkte | ⛔ D |
| Audio / Video-Frames direkt von YouTube | nur per Stream-Download (yt-dlp-Prinzip) | ⛔ D |

**Den eigentlichen Videoinhalt** (Gesprochenes und Text-Overlays wie „200 g Mehl“) bekommen wir **nur, wenn der Nutzer ihn selbst bereitstellt**. Der beste Weg dafür ist eine **iOS-Bildschirmaufnahme** des Shorts. iOS nimmt dabei das App-Audio mit auf. Die Aufnahme wird an die App geteilt oder im Fotopicker ausgewählt, und die App verarbeitet sie **vollständig on-device**:

```
Bildschirmaufnahme (.mp4/.mov)
 ├─ Audio  → SpeechAnalyzer/SpeechTranscriber (on-device) → Transkript
 ├─ Frames → AVAssetImageGenerator → Vision-Texterkennung (on-device) → Overlay-Text
 └─ 1–3 Keyframes → Foundation Models Bild-Attachment (iOS 27, on-device)
                     ↓
      Titel + Beschreibung + Transkript + OCR → Foundation Model → @Generable-Rezept
```

Damit ist der USP „lokale KI“ haltbar, aber **der Workflow muss ehrlich sein**. Der Ein-Tipp-Import „Short teilen → fertig“ funktioniert on-device nur, wenn Titel und Beschreibung das Rezept enthalten. Bei allen anderen Shorts fragt die App: *„Das Rezept steckt im Video. Nimm den Short kurz per Bildschirmaufnahme auf, oder nutze Mealie AI.“* Später lässt sich das mit einer ReplayKit-Broadcast-Extension („Aufnahme-Modus“) fast nahtlos lösen (siehe §7).

---

## 1. Analyse der zehn Fragestellungen

### 1.1 Share Extension und YouTube
- ✅ Eine Share Extension (`NSExtensionActivationRule`) nimmt `public.url`, `public.plain-text`, `public.image` und `public.movie` an. Die YouTube-App erscheint im Share Sheet und übergibt eine URL.
- 🟡 Ob die YouTube-App zusätzlich Titeltext mitschickt (`attributedContentText`/Plain-Text-Item), ist nicht dokumentiert und ändert sich zwischen App-Versionen. **Nur die URL ist gesichert.** Das klärt Spike S1.
- ✅ Wird aus **Safari** (m.youtube.com) geteilt, kann eine `NSExtensionJavaScriptPreprocessingFile` das DOM der gerade angezeigten Seite lesen (Titel, ggf. Beschreibung). 🧪 Die DOM-Struktur von YouTube ist nicht stabil, deshalb nur als Bonus.
- ✅ Share Extensions haben ein enges Speicherlimit (historisch ca. 120 MB). Video-Transkription und Frame-Analyse gehören daher in die Haupt-App.
- ⛔ Eine Share Extension kann die Haupt-App **nicht offiziell öffnen**. `openURL` steht ihr nicht zur Verfügung, und die bekannten Responder-Chain-Tricks riskieren eine Ablehnung im Review. **Alternative:** Die Extension zeigt selbst eine kompakte SwiftUI-Oberfläche. Für Textquellen führt sie den ganzen Flow dort aus (Analyse → KI → Review → Speichern). Wenn Video-Material nötig ist, legt sie einen „Import-Auftrag“ im App-Group-Container ab und die Haupt-App zeigt ihn beim nächsten Öffnen oben auf Home an.
- 🟡 Ob `LanguageModelSession` **innerhalb** einer Share Extension zuverlässig läuft, ist nicht ausdrücklich dokumentiert. Das Modell läuft in einem Systemprozess, daher sollte das Speicherlimit der Extension kaum belastet werden. Das prüft Spike S4.

### 1.2 URL, Titel, Beschreibung
- ✅ **URL/ID**: direkt verfügbar. Unterstützte Formate: `youtube.com/shorts/ID`, `youtu.be/ID`, `watch?v=ID`. Den Tracking-Parameter `si=` entfernen wir.
- ✅ **Titel/Kanal/Thumbnail**: oEmbed ist öffentlich, braucht keinen Key und ist für Einbettungszwecke gedacht.
- ✅ **Beschreibung**: offiziell nur über die YouTube Data API v3 `videos.list` (1 Quota-Einheit pro Aufruf, Standardkontingent 10.000/Tag). Ein im App-Binary eingebetteter Key ist extrahierbar und wird für alle Nutzer geteilt. Optionen:
  - **B:** Der Nutzer hinterlegt optional einen eigenen Key in den Einstellungen (für Power-User, passt zur Mealie-Selbsthoster-Zielgruppe).
  - **C:** Ein kleiner eigener Proxy hält den Key. Das widerspricht dem Leitbild „kein eigener Server“.
  - **B (manuell):** Der Nutzer kopiert die Beschreibung und fügt sie ein. In der YouTube-App ist Beschreibungstext nicht überall markierbar. 🟡 Screenshot der Beschreibung plus OCR funktioniert immer.
- ⛔ Die Watch-Page per HTML-Scraping auswerten (`ytInitialPlayerResponse`) verstößt gegen die YouTube-AGB und bricht regelmäßig.

### 1.3 YouTube-Transkripte
- ⛔ Die offizielle `captions.download`-Methode der Data API braucht OAuth **und Bearbeitungsrechte am Video**. Für fremde Videos ist sie damit unbrauchbar.
- ⛔ Inoffizielle Endpunkte (`timedtext`, InnerTube `get_transcript`) verstoßen gegen die AGB und werden zunehmend mit PO-Tokens und Bot-Erkennung blockiert. Viele Shorts haben ohnehin nur automatische Untertitel oder gar keine.
- **Alternative (A/B):** ein eigenes Transkript über SpeechAnalyzer aus einer Bildschirmaufnahme (§1.4).

### 1.4 Audio eines YouTube-Videos
- ⛔ **Direkt von YouTube: nicht erlaubt.** Die YouTube-AGB verbieten Zugriff und Download außerhalb der Wiedergabe. App-Store-Richtlinie **5.2.3** untersagt Apps, Medien von Drittquellen wie YouTube ohne deren Autorisierung zu speichern, zu konvertieren oder herunterzuladen. Eine yt-dlp-artige Swift-Implementierung führt mit hoher Wahrscheinlichkeit zur Ablehnung und bricht technisch ständig.
- ⛔ Audio einer anderen App (YouTube) im Hintergrund mitschneiden: Die iOS-Sandbox erlaubt das nicht, außer über ReplayKit (s. u.).
- ✅ **B – Bildschirmaufnahme:** Die System-Bildschirmaufnahme (Kontrollzentrum) nimmt App-Audio auf. Die Datei liegt in Fotos und wird per `PhotosPicker` oder Share Sheet übergeben. `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26+) transkribiert Dateien on-device über `AVAudioFile` und `analyzeSequence(from:)`. Deutsch wird unterstützt; Sprachmodelle lädt man über `AssetInventory`. Ein Short mit ≤ 3 min wird in wenigen Sekunden transkribiert.
- ✅ **B – ReplayKit Broadcast Upload Extension** (spätere Ausbaustufe): Der Nutzer startet „Mealie Importer“ als Broadcast im Kontrollzentrum und spielt den Short in YouTube ab. Die Extension erhält `audioApp`- und Video-Samplebuffer und schreibt sie in den App-Group-Container. Das ist offizielle API mit dem gleichen Rechtsrahmen wie eine Bildschirmaufnahme. Das Extension-Limit liegt bei ca. 50 MB, deshalb wird nur geschrieben und nicht analysiert.
- ⛔ Mikrofon-Mitschnitt, während YouTube auf demselben Gerät läuft: iOS duckt oder unterbricht Audio, und die Qualität ist schlecht. Kein sinnvoller Weg.

### 1.5 Video-Frames / Screenshots
- ⛔ Direkt von YouTube: gleiche Lage wie beim Audio.
- 🧪 YouTube-IFrame-Player in `WKWebView` einbetten und per `takeSnapshot` abgreifen: Die Einbettung selbst ist offiziell erlaubt. Hardware-dekodiertes Video erscheint im Snapshot aber oft schwarz, Canvas-Zugriff ist durch Cross-Origin blockiert, und systematisches Frame-Grabbing ist nach den Player-Richtlinien problematisch. **Nicht weiterverfolgen.**
- ✅ **B:** Aus einer Bildschirmaufnahme holt `AVAssetImageGenerator` Frames, etwa jede Sekunde, mit Szenenwechsel-Dedupe. `RecognizeTextRequest` (Vision, Swift-API) liest Overlays per OCR. Das bringt den größten Informationsgewinn, weil Shorts Mengen oft nur einblenden.
- ✅ **B:** Screenshots (z. B. pausierter Short, Beschreibung, angepinnter Kommentar) direkt teilen → OCR.

### 1.6 iOS-Sandbox
- Kein Zugriff auf Daten oder Cache der YouTube-App, keine systemweite Audioaufnahme außer ReplayKit.
- Share Extension, Haupt-App und später die Broadcast-Extension teilen Daten über **App Group** (`group.<team>.mealieimporter`) und Zugangsdaten über eine **Keychain Access Group**.
- Hintergrundausführung ist begrenzt. Längere Analysen laufen im Vordergrund mit Fortschrittsanzeige. Foundation Models kann im Hintergrund Rate-Limits zurückgeben (`rateLimited`).

### 1.7 Einschränkungen durch YouTube
- AGB und API-Services-Richtlinien: kein Download oder Speichern audiovisueller Inhalte, kein Scraping. Data-API-Daten (z. B. Beschreibung) dürfen angezeigt und verarbeitet werden, Daten von Nicht-Nutzern haben Aufbewahrungsregeln. Wir speichern nur das fertige Rezept plus Quell-URL, keine YouTube-Rohdaten.
- Das Rezept selbst (Zutatenliste, Schritte) ist als Faktensammlung weitgehend nicht urheberrechtlich geschützt. Erklärende Texte, Bilder und Video schon. Deshalb gehört **immer die Quell-URL (`orgURL`)** ins Mealie-Rezept, und das Thumbnail dient nur als Titelbild. 🟡 Das ist eine juristische Einschätzung, keine Rechtsberatung.

### 1.8 Nutzbare Web-APIs
| API | Zweck | Status |
|---|---|---|
| YouTube oEmbed | Titel, Kanal, Thumbnail | ✅ ohne Key |
| YouTube Data API v3 `videos.list` | Beschreibung, Tags, Dauer, Sprache | ✅ mit Key |
| Blog-Seiten (Link aus der Beschreibung) | `application/ld+json` → `Recipe` | ✅ deterministisch, oft vollständiges Rezept |
| Mealie REST API | Ziel- und Fallback-System | ✅ (§3) |
| Mealie `POST /api/recipes/create/ai` | Server-KI inkl. Video-Transkription | ✅ C, nur mit Einwilligung |

### 1.9 Was wirklich offline / on-device läuft
Foundation-Models-Inferenz, SpeechAnalyzer (nach einmaligem Modell-Download), Vision-OCR, AVFoundation-Frame-Extraktion, das deterministische Parsen von Mengen und Einheiten, die Validierung sowie Review und Bearbeitung. **Nicht offline:** oEmbed, Data API, Blog-Abruf und das Speichern in Mealie. Speichern kann über eine Warteschlange nachgeholt werden.

### 1.10 Was zwingend einen Server braucht
- Rezeptspeicherung: der Mealie-Server des Nutzers, per Definition.
- Beschreibung ohne Nutzer-Key: ein Proxy (vermeiden).
- Video-Import „ohne Nutzeraufwand“ (nur Link): **ausschließlich serverseitig**, z. B. über Mealie AI. Mealie 3.27 nutzt dafür selbst `yt-dlp==2026.8.19` und einen konfigurierten Audio-Provider (Whisper-kompatibel). Die AGB-Problematik liegt dann beim Serverbetreiber, also beim Nutzer, und besteht weiter.

---

## 2. Klassifizierung A / B / C / D

| | Fähigkeit |
|---|---|
| **A – vollständig on-device** | URL-Parsing · Foundation-Models-Extraktion aus Text · Bildverständnis (iOS 27) · Vision-OCR · Sprach-Transkription von Dateien · Mengen- und Einheiten-Parsing · Validierung gegen Halluzinationen · Review-UI. *(oEmbed und Blog-Abruf sind Netzabrufe ohne KI und senden keine Rezeptdaten an KI-Anbieter.)* |
| **B – on-device, wenn der Nutzer Daten liefert** | Bildschirmaufnahme → Transkript + Overlay-OCR · Screenshots → OCR · eingefügter Beschreibungstext · eigener YouTube-API-Key → Beschreibung · später ReplayKit-Aufnahme-Modus |
| **C – nur mit Server/API** | Speichern und Lesen in Mealie · Mealie AI (Link → Rezept inkl. Transkription) · Beschreibung ohne Nutzer-Key (Proxy) · Private Cloud Compute (Apple-Server, §4.4) · spätere Cloud-Provider |
| **D – technisch/rechtlich problematisch** | Audio- oder Video-Download von YouTube in der App · inoffizielle Transkript-Endpunkte · Watch-Page-Scraping · Frame-Grabbing aus eingebettetem Player · Öffnen der Haupt-App aus der Share Extension per Hack |

---

## 3. Mealie API (geprüft im Quellcode v3.27.0)

Alle Pfade mit Präfix `/api`. Auth per `Authorization: Bearer <token>`.

| Zweck | Endpunkt | Anmerkung |
|---|---|---|
| Server-Check | `GET /app/about` | Version, `allowPasswordLogin`, `enableOidc` |
| Login (Passwort) | `POST /auth/token` (form: `username`, `password`) | liefert kurzlebiges JWT; `POST /auth/refresh` |
| **Login (empfohlen)** | Langlebiger API-Token, vom Nutzer in Mealie unter *Profil → API Tokens* erzeugt (`POST /users/api-tokens`) | im Keychain speichern, einfachster und robustester Weg |
| Login (OIDC, neu) | `GET /auth/oauth/native/config` + `POST /auth/oauth/native/token` | native PKCE über `ASWebAuthenticationSession`, geeignet für Passkey-/SSO-Setups (später) |
| Rezeptliste | `GET /recipes?page=&perPage=&search=&orderBy=&tags=&categories=` | paginiert, `RecipeSummary` |
| Rezeptdetails | `GET /recipes/{slug}` | vollständiges `Recipe` |
| Rezept anlegen | `POST /recipes` `{ "name": … }` → Slug | `CreateRecipe` enthält **nur** `name` |
| Rezept füllen/bearbeiten | `PATCH /recipes/{slug}` (teilweise) bzw. `PUT` (komplett) | Zutaten, Schritte, Zeiten, Tags … |
| Tags | `GET/POST /organizers/tags`, `GET /organizers/tags/slug/{slug}` | |
| Kategorien | `GET/POST /organizers/categories` | |
| Bild aus URL | `POST /recipes/{slug}/image` `{ "url": … }` | Mealie lädt z. B. das YouTube-Thumbnail selbst |
| Bild hochladen | `PUT /recipes/{slug}/image` (multipart `image`, `extension`) | eigener Keyframe als Bild |
| Bild anzeigen | `GET /media/recipes/{id}/images/{min-original.webp\|original.webp\|tiny-original.webp}` | |
| Einheiten/Lebensmittel | `GET/POST /units`, `GET/POST /foods` | für strukturierte Zutaten (optional) |
| Zutaten-Parser | `POST /parser/ingredients` | ⚠️ mit `parser=openai` gehen Daten an die KI. Im Local-AI-Modus nur `nlp` bzw. `brute` erlauben oder lokal parsen. |
| **Mealie AI** | `POST /recipes/create/ai` bzw. `/create/ai/stream` (SSE) – multipart: `url`, `content`, `images[]`, `translateLanguage`, `createNewOrganizers` | ⚠️ **legt das Rezept direkt an** (liefert Slug), einen reinen Extraktionsmodus gibt es nicht. Details siehe unten. |

**Relevante Rezeptfelder:** `name, description, recipeServings (float), recipeYield, recipeYieldQuantity, prepTime, cookTime, performTime, totalTime (Strings), recipeIngredient[], recipeInstructions[] {title?, text}, notes[] {title, text}, tags[], recipeCategory[], orgURL`.
**Zutat (`RecipeIngredient`):** `quantity (float|null), unit {id,name}|null, food {id,name}|null, note, originalText, display, referenceId`.

**Folgen für den Mapper:**
- `quantity = nil` muss als `null` gesendet werden. Die Mealie-Voreinstellung ist `0`, das würde „0 Olivenöl“ anzeigen.
- Unit und Food brauchen IDs. MVP: Mengen, Einheit und Zutat landen als Text in `note`, `originalText` bleibt erhalten, und bei gesicherter Menge wird `quantity` gesetzt. Das Zuordnen strukturierter Units und Foods (inkl. Anlegen) kommt später.
- Ob Mealie AI verfügbar ist, verrät **kein** öffentliches Flag in `/app/about`. Die Erkennung läuft über einen Probeaufruf oder eine Fehlermeldung. 🟡 Im Prototyp prüfen.

**Mealie AI als Fallback:** Da `create/ai` das Rezept sofort speichert, sieht der Ablauf so aus: `create/ai/stream` (Fortschritt per SSE anzeigen) → Slug → `GET /recipes/{slug}` → zurück in `ExtractedRecipe` mappen → gleiche Review-Oberfläche → `PATCH` beim Speichern oder `DELETE /recipes/{slug}` beim Abbrechen. Das Rezept ist kurz für den Haushalt sichtbar. Wir markieren es mit dem Tag `import-in-review`.

---

## 4. Apple Foundation Models Framework

### 4.1 API-Oberfläche
| Element | Stand | Status |
|---|---|---|
| `SystemLanguageModel.default.availability` → `.available` / `.unavailable(.deviceNotEligible \| .appleIntelligenceNotEnabled \| .modelNotReady)` | iOS 26 | ✅ |
| `LanguageModelSession(instructions:)`, `respond(to:generating:)`, `streamResponse(…)` mit `PartiallyGenerated`-Snapshots, `prewarm()` | iOS 26 | ✅ |
| `@Generable` (Structs, Enums, Optionals, Arrays, verschachtelt) und `@Guide(description:, .count, .range, .anyOf)`: **Constrained Decoding** garantiert schema-konformes Ergebnis | iOS 26 | ✅ |
| `GenerationOptions(sampling: .greedy, temperature:)` | iOS 26 | ✅ |
| `Tool`-Protokoll (Function Calling) | iOS 26 | ✅ |
| Fehler: `exceededContextWindowSize`, `guardrailViolation`, `unsupportedLanguageOrLocale`, `rateLimited`, `refusal` | iOS 26 | ✅ |
| **Bild-Eingabe** über `Attachment` (`UIImage`, `CGImage`, `CVPixelBuffer`, Datei-URL …), **on-device** | iOS 27 | 🟡 (WWDC26, Session 241) |
| `contextSize` (on-device **8.192 Token**, iOS 26: 4.096), `tokenCount(for:)`, `response.usage` | iOS 27 | 🟡 |
| System-Tools `OCRTool`, `BarcodeReaderTool` (Vision-basiert) | iOS 27 | 🟡 |
| `PrivateCloudComputeLanguageModel` (32k Kontext, **Apple-Server**) | iOS 27 | 🟡 (kein on-device) |
| `LanguageModel`-Protokoll (einheitlich für lokal, PCC und Drittanbieter; Anthropic- und Google-Swift-Pakete) | iOS 27 | 🟡 |
| **Audio- oder Video-Eingabe** | – | ⛔ gibt es nicht. Vorverarbeitung per SpeechAnalyzer und Vision ist nötig. |

### 4.2 Geräte und Verfügbarkeit
- Voraussetzung ist ein Apple-Intelligence-fähiges Gerät: iPhone 15 Pro/Pro Max, iPhone 16-Serie inkl. 16e, iPhone 17-Serie, iPads mit A17 Pro oder M1 und neuer. Außerdem muss Apple Intelligence aktiviert, die Sprache unterstützt (Deutsch ✅) und das Modell geladen sein.
- **Umgang mit „nicht verfügbar“**, je Fall eigene UI:
  - `deviceNotEligible` → Local AI ausblenden, Mealie AI mit Einwilligung anbieten, manuelle Eingabe bleibt möglich.
  - `appleIntelligenceNotEnabled` → Hinweis mit Link zu den Einstellungen.
  - `modelNotReady` → „Modell wird geladen“, erneut versuchen oder Mealie AI anbieten.
- Die App bleibt **ohne Apple Intelligence nutzbar** (Rezepte ansehen, manuell bearbeiten, Mealie AI).

### 4.3 Kontext, Tokens, Performance
- Das Budget von 8.192 Token umfasst **Instruktionen + Schema + Input + Output**. Das `@Generable`-Schema wird in den Prompt eingebettet und kostet Token. Ein vollständiges Rezept als Output braucht ca. 800–1.500 Token. **Für Input bleiben realistisch ca. 4.000–5.000 Token.**
- Ein Short dauert ≤ 3 min. Das Transkript hat ca. 400–600 Wörter ≈ 700–1.000 Token. OCR-Text nach Dedupe liegt meist unter 500 Token. Beides passt. Bilder kosten zusätzlich Token (größenabhängig), daher nur 1–3 Keyframes und deren Auflösung begrenzen.
- Strategie: vorher mit `tokenCount(for:)` messen. Bei Überlauf zuerst OCR-Duplikate und Füllwörter kürzen, dann zweistufig extrahieren (Durchlauf 1: Zutaten, Durchlauf 2: Schritte, jeweils in neuer Session).
- Performance: Das ca. 3B-Modell läuft auf der Neural Engine. Erwartet werden einige Sekunden bis ca. 20 s für ein ganzes Rezept. `prewarm()` beim Öffnen des Import-Screens aufrufen und per `streamResponse` Zwischenergebnisse live anzeigen (Titel und Zutaten erscheinen nacheinander).
- 🟡 Guardrails können bei harmlosen Inhalten fälschlich greifen (z. B. Alkohol, Messer). `guardrailViolation` fangen wir sauber ab und bieten „manuell“ oder „Mealie AI“ an.

### 4.4 Private Cloud Compute – Einordnung
PCC bietet ein stärkeres Modell mit 32k Kontext, hohe Datenschutzzusagen von Apple und keine API-Keys. **Es ist aber nicht on-device.** Im Modus „Local AI“ darf PCC **nicht** automatisch genutzt werden. Wenn überhaupt, kommt PCC später als eigener, klar beschrifteter Modus „Apple Private Cloud“ mit eigener Einwilligung.

### 4.5 `@Generable`-Datenmodell (Skizze)

Es beschreibt nur die Form. Vollständiger Code folgt in der Implementierungsphase.

```swift
@Generable
struct RecipeExtraction {
    @Guide(description: "Title exactly as stated in the source. Empty if unknown.")
    var title: String?
    var summary: String?
    @Guide(description: "Only if explicitly stated, e.g. '4 Portionen'. Verbatim.")
    var servingsText: String?
    @Guide(description: "Only if explicitly stated. Verbatim, e.g. '10 min'.")
    var prepTimeText: String?
    var cookTimeText: String?
    var ingredients: [ExtractedIngredient]
    var instructions: [ExtractedInstruction]
    var notes: [String]
    @Guide(description: "Short descriptive tags such as cuisine or dish type", .maximumCount(6))
    var tags: [String]
}

@Generable
struct ExtractedIngredient {
    @Guide(description: "The ingredient text copied verbatim from the source")
    var originalText: String
    @Guide(description: "Numeric amount ONLY if it literally appears in originalText, otherwise empty")
    var quantityText: String?
    @Guide(description: "Unit ONLY if it literally appears in originalText, otherwise empty")
    var unit: String?
    var ingredient: String
    var preparation: String?
    @Guide(description: "Where this came from")
    var source: SourceKind          // .description, .transcript, .onScreenText, .image, .userText
}

@Generable
struct ExtractedInstruction { var position: Int; var text: String }

@Generable enum SourceKind { case description, transcript, onScreenText, image, userText, webPage }
```

`ExtractedRecipe` (App-Domänenmodell, **nicht** `@Generable`) entsteht daraus nach der Validierung. Es ergänzt pro Feld einen `FieldStatus` (`.explicit`, `.normalized`, `.missing`, `.needsReview`), `quantity: Decimal?` (deterministisch aus `quantityText` geparst, inkl. „½“ und „1 1/2“) und die Quell-URL.

### 4.6 Anti-Halluzination: mehrschichtig, nicht nur per Prompt
1. **Instruktionen:** „Extrahiere nur, was im Input steht. Erfinde keine Mengen, Einheiten oder Zutaten. Lass Felder leer.“ Dazu 2–3 kurze Few-Shot-Beispiele wie „add some olive oil“ → keine Menge.
2. **Schema:** Mengen und Einheiten als **optionale Strings**, verbatim. Die Umwandlung in Zahlen übernimmt deterministischer Swift-Code, nicht das Modell.
3. **Greedy Sampling** (`.greedy`) für reproduzierbare Ergebnisse.
4. **Deterministische Nachprüfung (entscheidend):**
   - Kommt die `quantityText`-Zahl in `originalText` vor? Wenn nicht: verwerfen, Status `.needsReview`.
   - Kommt `originalText` (fuzzy, normalisiert) im Gesamt-Input vor? Wenn nicht: Zutat als „nicht belegt“ markieren und im Review hervorheben.
   - Zeiten und Portionen genauso gegen den Input prüfen.
5. **Review-UI:** Fehlende oder unbelegte Felder werden farblich markiert. Leere Mengen erscheinen als „Menge?“ und nicht als 0.

---

## 5. Datenflussdiagramm

```
┌─────────────────────────── iPhone / iPad ─────────────────────────────────────────┐
│                                                                                    │
│  YouTube-App ──Share──▶ Share Extension ──(App Group: ImportJob)──▶ Haupt-App      │
│  Fotos/Screen-Rec ─────▶ (URL, Text, Bild, Video)                                  │
│                                   │                                                │
│                         ┌─────────▼──────────┐                                     │
│                         │ SourceCollector    │── oEmbed ───────────────▶ YouTube ◀─┼─ (nur Video-URL)
│                         │  (Analyse & Sammeln)│── videos.list (opt.) ──▶ Google API◀┼─ (nur Video-ID + Nutzer-Key)
│                         │                    │── Blog-HTML (opt.) ────▶ Blog      ◀─┼─ (nur Blog-URL)
│                         └─────────┬──────────┘                                     │
│             ┌────────────────────┼─────────────────────┐                           │
│      Video? ▼                     ▼ Text                  ▼ Bilder                  │
│  SpeechAnalyzer (Audio)    Titel/Beschreibung/     Vision OCR + Keyframes          │
│  AVAssetImageGenerator     eingefügter Text        (on-device)                     │
│             └────────────────────┼─────────────────────┘                           │
│                                  ▼                                                 │
│                          RecipeAIInput  (Text-Chunks mit Herkunft + Bilder)        │
│                                  │                                                 │
│               AI-Modus-Router ───┤ Local AI (Standard)                              │
│                                  ▼                                                 │
│               FoundationModelsRecipeAIProvider  (on-device, @Generable)           │
│                                  │                                                 │
│                          ExtractionValidator  (deterministisch)                    │
│                                  ▼                                                 │
│                          ExtractedRecipe  ──▶  Review & Bearbeiten (Nutzer)        │
│                                  │                                                 │
│                          MealieRecipeMapper                                        │
└──────────────────────────────────┼────────────────────────────────────────────────┘
                                   ▼  erst bei „In Mealie speichern“
                       Mealie-Server: POST /recipes → PATCH /recipes/{slug} → Bild

   Nur nach ausdrücklicher Einwilligung:
   RecipeAIInput(URL/Text/Bilder) ──▶ Mealie /recipes/create/ai ──▶ Mealies KI-Provider (OpenAI/Ollama/…)
```

---

## 6. Technische Architektur

**Projektstruktur:** Xcode-Projekt mit drei Targets (App iOS+iPadOS, Share Extension, später Broadcast Extension) und einem lokalen Swift Package `MealieImporterKit`, das alle Targets teilen. **Keine Drittanbieter-Abhängigkeiten.**

```
MealieImporterKit/
├─ Core/            Domänenmodelle (ExtractedRecipe, ImportJob, SourceChunk, FieldStatus),
│                   Protokolle, AppEnvironment (DI-Container)
├─ Sources/         SourceCollector-Protokoll + Implementierungen:
│                   ShareItemParser, YouTubeURLParser, YouTubeOEmbedService,
│                   YouTubeDataAPIService (optional), WebRecipeSchemaService (JSON-LD),
│                   MediaAnalyzer → SpeechTranscriptionService, FrameSampler, OCRService
├─ AI/              RecipeAIProvider, RecipeAIInput, FoundationModelsRecipeAIProvider,
│                   RecipeExtraction (@Generable), ExtractionValidator, QuantityParser,
│                   AIModeRouter, MealieAIProvider (MVP spät), Stubs: OpenAI/Anthropic/Gemini
├─ Mealie/          MealieClient (URLSession, async/await), Endpoints, DTOs (Codable),
│                   MealieRecipeMapper (ExtractedRecipe ↔ DTO), MealieAuthService
├─ Persistence/     KeychainStore (Access Group), AppGroupJobStore, Settings
└─ UI/              SwiftUI-Features: Home, Import, ReviewRecipe, Recipes, RecipeDetail, Settings
```

**Kernprotokolle (Signaturen):**
```swift
protocol RecipeAIProvider: Sendable {
    var id: AIProviderID { get }
    var isOnDevice: Bool { get }
    func availability() async -> AIProviderAvailability
    func extractRecipe(from input: RecipeAIInput) async throws -> ExtractedRecipe
}
protocol SourceCollector { func collect(for job: ImportJob, progress: ProgressSink) async throws -> [SourceChunk] }
protocol MealieAPI { /* recipes, recipe(slug:), create, patch, tags, categories, uploadImage, createWithAI */ }
```

- **DI:** Ein `AppEnvironment` enthält alle Services als Protokolltypen und wird per SwiftUI-`@Environment` injiziert. App und Extension bauen jeweils ihre eigene Instanz, Tests und Previews nutzen Mocks.
- **Import als Zustandsmaschine:** `ImportJob.state`: `.analyzingSource → .collecting(step) → .extracting(partial) → .validating → .review → .saving → .done | .needsUserMedia | .needsConsent(.mealieAI) | .failed`. Daraus leiten sich die Statusanzeigen der UI direkt ab.
- **AI-Modus-Router:** `local`, `mealie`, `automatic`. Bei `automatic` gilt: erst lokal, bei Nichtverfügbarkeit oder fehlendem Inhalt **Einwilligungsdialog** (niemals stillschweigend). Die Einwilligung gilt nur für den einzelnen Import. Optional „für diese Sitzung merken“, dauerhaft nur bei explizit gewähltem Modus `mealie`.
- **iOS-27-`LanguageModel`-Protokoll:** Der `FoundationModelsRecipeAIProvider` baut intern darauf auf. Spätere Anthropic- oder Gemini-Provider können dieselbe Extraktionslogik mit einem anderen `LanguageModel` wiederverwenden, ohne die App-Abstraktion `RecipeAIProvider` zu ändern.
- **iPadOS:** `NavigationSplitView` (Rezepte | Detail), Import als Sheet. Review auf dem iPad zweispaltig: Quelle (Transkript/OCR) links, Rezept rechts.

---

## 7. Frameworks und APIs

| Aufgabe | Framework | Status |
|---|---|---|
| Rezeptextraktion | FoundationModels (`LanguageModelSession`, `@Generable`, `Attachment`) | ✅ / 🟡 (Bild: iOS 27) |
| Transkription | Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`) | ✅ |
| Frames | AVFoundation (`AVURLAsset`, `AVAssetImageGenerator.images(for:)`) | ✅ |
| OCR | Vision (`RecognizeTextRequest`), alternativ `OCRTool` | ✅ / 🟡 |
| Medienauswahl | PhotosUI (`PhotosPicker`, `Transferable`) | ✅ |
| Teilen | Share Extension (`NSExtensionContext`, `NSItemProvider`) | ✅ |
| Aufnahme-Modus (später) | ReplayKit Broadcast Upload Extension (`RPBroadcastSampleHandler`) | ✅ |
| Netzwerk | URLSession async/await, SSE über `bytes(for:)` | ✅ |
| Geheimnisse | Security (Keychain, Access Group) | ✅ |
| OIDC (später) | AuthenticationServices (`ASWebAuthenticationSession`) | ✅ |
| Shortcuts (später) | App Intents („Rezept aus Link importieren“) | ✅ |

---

## 8. Einschränkungen (Zusammenfassung)

1. Aus dem Link allein kommt **kein Videoinhalt** (Audio, Frames, Transkript). Das ist eine AGB- und Plattformgrenze, keine technische Lücke, die wir schließen sollten.
2. On-device-KI braucht ein Apple-Intelligence-Gerät, aktivierte Apple Intelligence und eine unterstützte Sprache.
3. Das Kontextfenster (8k in iOS 27) reicht für Shorts, nicht für lange Kochvideos ohne Chunking.
4. Foundation Models versteht kein Audio und kein Video, alles läuft über Vorverarbeitung.
5. Die Share Extension hat Speichergrenzen und kann die App nicht öffnen.
6. Die Beschreibung braucht einen API-Key oder Nutzermithilfe.
7. Mealie AI speichert sofort und ist kein reiner Extraktionsdienst. Welchen KI-Anbieter der Mealie-Server nutzt, kann die App nicht sehen.
8. Das Mengenmodell von Mealie (Units/Foods mit IDs) passt nicht 1:1 zu freiem Text. Das MVP arbeitet textbasiert.

---

## 9. Datenschutzanalyse

| Datum | Verarbeitung im Modus **Local AI** | Empfänger |
|---|---|---|
| Video-URL | oEmbed-Abruf | YouTube (kennt das Video ohnehin) |
| Video-ID | optional `videos.list` | Google, nur mit Nutzer-Key |
| Blog-URL aus Beschreibung | JSON-LD-Abruf | Blog-Betreiber (wie beim Öffnen im Browser) |
| Bildschirmaufnahme, Screenshots | Transkription, OCR, KI | **nur Gerät**. Temporäre Kopien im App-Container werden nach Abschluss gelöscht. |
| Transkript, OCR, Zwischenergebnisse | KI, Review | **nur Gerät** |
| Fertiges Rezept + Quell-URL + Titelbild | beim Tippen auf „In Mealie speichern“ | eigener Mealie-Server des Nutzers |
| Zugangsdaten | Keychain (`kSecAttrAccessibleAfterFirstUnlock`, Access Group) | – |

- **Local AI:** keine Übertragung an KI-Anbieter, kein PCC, kein Mealie-Parser mit `openai`. Kein Analytics- oder Crash-SDK von Dritten.
- **Mealie AI:** Die Quelle (URL, eingefügter Text, ggf. Bilder) geht an den Mealie-Server und von dort an **dessen konfigurierten KI-Anbieter** (z. B. OpenAI, oder selbst gehostet). Der Einwilligungsdialog muss das sagen:
  > „Die lokale Verarbeitung ist für diese Quelle nicht möglich. Soll Mealie AI verwendet werden?
  > Dabei werden der Link und ggf. deine Texte/Bilder an deinen Mealie-Server gesendet. Mealie leitet sie an den dort eingerichteten KI-Dienst weiter und legt das Rezept sofort an.“
  > [Mealie AI verwenden] [Abbrechen]
- **Transparenz-UI:** Während des Imports zeigt ein „Datenblatt“, welche Quellen genutzt wurden, jeweils mit Hinweis „lokal verarbeitet“ bzw. „abgerufen von youtube.com“.
- App-Store-Datenschutzlabel: Voraussichtlich ist „Keine Daten erfasst“ möglich, weil nur zum eigenen Server des Nutzers übertragen wird. `PrivacyInfo.xcprivacy` pflegen.

---

## 10. MVP-Vorschlag

**Phase 0 – Spikes (vor dem eigentlichen Code, je ca. 0,5–1 Tag):**
- **S1** Share Extension: Welche Items liefern die YouTube-App, Safari und die Fotos-App tatsächlich? (loggen)
- **S2** Extraktionsqualität: 15–20 echte Shorts (deutsch und englisch) mit Beschreibung und/oder Transkript durch das `@Generable`-Schema schicken. Messen: Vollständigkeit, erfundene Mengen, Laufzeit, Token.
- **S3** Bildschirmaufnahme: SpeechAnalyzer-Transkript + OCR-Overlay. Wie viel mehr Rezept steckt darin?
- **S4** Foundation Models und SpeechAnalyzer innerhalb der Share Extension (Speicher, Verfügbarkeit).
- **S5** Mealie: API-Token-Login, `create/ai` gegen die eigene Instanz, Verhalten ohne konfigurierten Provider.

**MVP-Umfang:**
1. Einstellungen: Mealie-URL + API-Token (Keychain), Verbindungstest, AI-Modus (`Local`/`Mealie`/`Automatic`), optional YouTube-API-Key, Datenschutzseite.
2. Home: großer Button **„Rezept importieren“** (Link einfügen / Bildschirmaufnahme wählen / Fotos wählen / Text einfügen), offene Import-Aufträge, zuletzt importierte Rezepte.
3. Share Extension: nimmt URL, Text, Bild und Video an. Bei Textquellen läuft der kompakte Flow bis zum Speichern direkt dort, sonst wird ein Auftrag für die App angelegt (Umsetzung abhängig von Spike S4).
4. Quellen: URL-Parsing, oEmbed, optional Data API, JSON-LD-Blog-Parser, Bildschirmaufnahme (Audio→Text, Frames→OCR), Screenshots→OCR, eingefügter Text.
5. `FoundationModelsRecipeAIProvider` mit Streaming-Status, Validator, Review-Screen mit Markierung fehlender Felder.
6. `MealieRecipeMapper` + Speichern (POST → PATCH → Thumbnail-Bild), Tags auswählen oder anlegen.
7. Rezepte-Liste (Suche, Paginierung) und Detailansicht (nur lesen, Link „in Mealie öffnen“).
8. Mealie-AI-Fallback mit Einwilligungsdialog (am Ende des MVP, da nur ein Endpunkt plus Rück-Mapping).

**Mindestversion:** Empfehlung **iOS/iPadOS 27**. On-device-Bildeingabe und 8k-Kontext sind für den Video-Pfad wichtig, und so entfallen `#available`-Zweige. Die Alternative iOS 26 mit reinem Textpfad und 4k-Kontext bringt mehr Reichweite, aber auch mehr Komplexität.

---

## 11. Spätere Erweiterungen
- **Aufnahme-Modus** über ReplayKit Broadcast Extension: Aufnahme starten, Short abspielen, fertig. Das ersetzt den Umweg über die Fotos-Mediathek.
- Safari-JS-Preprocessing (Beschreibung aus der Seite, wenn aus Safari geteilt).
- Strukturierte Units/Foods (Matching gegen `/units` und `/foods`, Anlegen neuer Einträge), Kategorien-Vorschläge.
- Bearbeiten bestehender Mealie-Rezepte in der App, Offline-Speicherwarteschlange.
- OIDC-Login (`/auth/oauth/native/*`), mehrere Mealie-Server.
- Weitere Provider über `RecipeAIProvider`: Apple PCC (eigener Modus), OpenAI, Anthropic, Gemini. Jeweils mit eigener Einwilligung und klarer Kennzeichnung „nicht lokal“.
- Instagram Reels und TikTok (gleiche Grenzen: Link liefert kaum Inhalt, Bildschirmaufnahme funktioniert), Kochbuch-Fotos, Web-Rezepte.
- App Intents / Kurzbefehle, Widgets („zuletzt importiert“), Übersetzung ins Deutsche on-device.
- Evaluations-Framework (iOS 27) für Regressionstests der Extraktionsqualität.

---

## 12. Risiken

| Risiko | Wahrscheinlichkeit | Auswirkung | Gegenmaßnahme |
|---|---|---|---|
| Nutzer erwarten „Link teilen = fertiges Rezept“, on-device klappt das nur bei guter Beschreibung | hoch | hoch (UX, Bewertungen) | ehrliche UX, Bildschirmaufnahme-Assistent, Aufnahme-Modus, Mealie-AI-Fallback |
| Extraktionsqualität des ~3B-Modells (deutsch, gesprochene Sprache, Umgangssprache) | mittel | hoch | Spike S2, zweistufige Extraktion, Validator, Review-UI |
| Halluzinierte Mengen trotz Prompt | mittel | mittel | deterministischer Validator (§4.6) |
| Guardrail-Fehlalarme | mittel | niedrig | abfangen, Alternativen anbieten |
| iOS-27-APIs weichen von der WWDC-Beschreibung ab | niedrig–mittel | mittel | vor Implementierung gegen SDK/Doku prüfen |
| Foundation Models nicht nutzbar in der Share Extension | mittel | mittel | Auftrag an die Haupt-App übergeben |
| App-Review: Bildschirmaufnahme-Workflow oder Broadcast-Extension als „YouTube-Download“ eingestuft | niedrig–mittel | hoch | keine Speicherung von Medien über den Import hinaus, klare Beschreibung, kein YouTube-Branding |
| YouTube-AGB (Data-API-Nutzung, Thumbnails) | niedrig | mittel | nur offizielle APIs, Quellenangabe, keine Rohdaten speichern |
| Mealie-API-Änderungen (3.x entwickelt sich schnell) | mittel | mittel | Versionscheck über `/app/about`, tolerante DTOs (unbekannte Felder ignorieren), PATCH statt PUT |
| Mealie AI legt Rezepte vor dem Review an | sicher | niedrig | Tag `import-in-review`, Löschen bei Abbruch |
| Geringe Reichweite wegen Hardware-Anforderung | sicher | mittel | App funktioniert auch ohne Local AI (Mealie AI, manuell) |

---

## 13. Umgebungshinweis
Auf dem Mac ist die **Xcode-Lizenz noch nicht akzeptiert**, deshalb schlagen `git` und `xcodebuild` fehl. Vor der Implementierung einmal im Terminal ausführen: `sudo xcodebuild -license`.

---

## Quellen
- Apple, WWDC26 „What's new in the Foundation Models framework“: https://developer.apple.com/videos/play/wwdc2026/241/
- Apple, WWDC26 Apple Intelligence Guide: https://developer.apple.com/wwdc26/guides/apple-intelligence/
- Apple Machine Learning Research, Foundation Models: https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models
- SpeechAnalyzer-Überblick: https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer
- Mealie AI Providers (offizielle Doku): https://mealie.io/documentation/getting-started/installation/ai-providers/
- Mealie Quellcode `mealie-next` (v3.27.0): `mealie/routes/recipe/recipe_crud_routes.py`, `mealie/routes/auth/auth.py`, `mealie/schema/recipe/*`, `mealie/services/openai/transcription.py` – https://github.com/mealie-recipes/mealie
- Mealie-Diskussion Video-Import: https://github.com/mealie-recipes/mealie/discussions/5448
- App Store Review Guidelines 5.2.3: https://developer.apple.com/app-store/review/guidelines/
