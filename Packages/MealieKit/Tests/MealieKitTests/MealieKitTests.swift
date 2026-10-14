import Foundation
import Testing
@testable import MealieKit

struct ServerSentEventParserTests {
    @Test func parsesMealieProgressStream() {
        var parser = ServerSentEventParser()
        let lines = [
            ": ping",
            "event: progress",
            #"data: {"message": "Video wird heruntergeladen"}"#,
            "",
            "event: progress",
            #"data: {"message": "Audio wird transkribiert"}"#,
            "event: done",
            #"data: {"slug": "one-pot-pasta"}"#
        ]
        let events = lines.compactMap { parser.consume(line: $0) }
        #expect(events == [
            .progress("Video wird heruntergeladen"),
            .progress("Audio wird transkribiert"),
            .done(slug: "one-pot-pasta")
        ])
    }

    @Test func parsesErrorEvent() {
        var parser = ServerSentEventParser()
        _ = parser.consume(line: "event: error")
        #expect(parser.consume(line: #"data: {"message": "No recipe found"}"#) == .failed("No recipe found"))
    }

    @Test func ignoresUnknownEvents() {
        var parser = ServerSentEventParser()
        _ = parser.consume(line: "event: something")
        #expect(parser.consume(line: "data: {}") == nil)
    }
}

struct FormattingTests {
    @Test func parsesIsoDurations() {
        // The unit names are localised, so assert on the numbers.
        #expect(RecipeFormat.duration("PT20M")?.contains("20") == true)
        let long = RecipeFormat.duration("PT1H30M")
        #expect(long?.contains("1") == true && long?.contains("30") == true)
    }

    @Test func normalizesSpelledOutDurations() {
        // Mealie stores whatever the source wrote, in any language.
        #expect(RecipeFormat.duration("3 hours") == RecipeFormat.duration("3 Stunden"))
        #expect(RecipeFormat.duration("25 Minuten") == RecipeFormat.duration("25 minutes"))
        #expect(RecipeFormat.duration("1 hr 30 min") == RecipeFormat.duration("PT1H30M"))
    }

    @Test func keepsUnparsableTimesAsWritten() {
        #expect(RecipeFormat.duration("über Nacht") == "über Nacht")
        #expect(RecipeFormat.duration("ca. eine Stunde") == "ca. eine Stunde")
        #expect(RecipeFormat.duration("") == nil)
        #expect(RecipeFormat.duration(nil) == nil)
    }

    @Test func editorShowsIsoTimesReadablyAndKeepsThemWhenUntouched() {
        typealias Draft = RecipeEditorView.Draft
        let shown = Draft.editableDuration("PT10M")
        #expect(shown == RecipeFormat.duration("PT10M"))
        #expect(Draft.storedDuration(shown, original: "PT10M") == "PT10M")
        #expect(Draft.storedDuration("15 min", original: "PT10M") == "15 min")
        #expect(Draft.editableDuration("über Nacht") == "über Nacht")
    }

    @Test func quantities() {
        #expect(RecipeFormat.quantity(0.5) == "½")
        #expect(RecipeFormat.quantity(1.5) == "1½")
        #expect(RecipeFormat.quantity(3) == "3")
        #expect(RecipeFormat.quantity(1.0 / 3) == "⅓")
    }

    @Test func ingredientWithoutQuantityIsNotScaled() {
        let ingredient = RecipeIngredient(note: "etwas Olivenöl", display: "etwas Olivenöl")
        #expect(ingredient.text(scaledBy: 2) == "etwas Olivenöl")
    }

    @Test func ingredientScalesStructuredQuantity() {
        let ingredient = RecipeIngredient(quantity: 250, unit: IngredientUnit(name: "g"),
                                          food: IngredientFood(name: "Spaghetti"), display: "250 g Spaghetti")
        #expect(ingredient.text(scaledBy: 2) == "500 g Spaghetti")
        #expect(ingredient.text() == "250 g Spaghetti")
    }
}

struct LinkTests {
    @Test func detectsYouTubeShorts() {
        #expect(SourceKind(url: URL(string: "https://youtube.com/shorts/abc123?si=xyz")!) == .youTubeShort)
        #expect(SourceKind(url: URL(string: "https://youtu.be/abc123")!) == .youTube)
        #expect(SourceKind(url: URL(string: "https://www.instagram.com/reel/abc/")!) == .instagram)
        #expect(SourceKind(url: URL(string: "https://www.chefkoch.de/rezepte/1")!) == .website)
    }

    @Test func removesTrackingParameters() {
        let url = URL(string: "https://youtube.com/shorts/abc123?si=tracking&feature=share")!
        #expect(url.withoutTrackingParameters.absoluteString == "https://youtube.com/shorts/abc123")
        let video = URL(string: "https://www.youtube.com/watch?v=abc&si=x")!
        #expect(video.withoutTrackingParameters.absoluteString == "https://www.youtube.com/watch?v=abc")
    }

    @Test func findsLinkInSharedText() {
        let text = "Schau mal! https://youtube.com/shorts/abc123?si=x 😋"
        #expect(URL.firstWebLink(in: text)?.host() == "youtube.com")
        #expect(URL.firstWebLink(in: "200 g Mehl, 2 Eier") == nil)
    }

    @Test func normalizesServerAddress() {
        #expect(MealieClient.normalizedServerURL("mealie.local:9000/")?.absoluteString == "https://mealie.local:9000")
        #expect(MealieClient.normalizedServerURL("http://192.168.1.5:9925/api")?.absoluteString == "http://192.168.1.5:9925")
        #expect(MealieClient.normalizedServerURL("https://example.com/mealie/")?.absoluteString == "https://example.com/mealie")
        #expect(MealieClient.normalizedServerURL("") == nil)
        #expect(MealieClient.normalizedServerURL("ftp://example.com") == nil)
    }

    @Test func readsMealieErrorMessages() {
        #expect(MealieClient.serverMessage(in: Data(#"{"detail": "Nope"}"#.utf8)) == "Nope")
        #expect(MealieClient.serverMessage(in: Data(#"{"detail": {"message": "Kaputt"}}"#.utf8)) == "Kaputt")
        #expect(MealieClient.error(status: 401, body: Data()) == .unauthorized)
    }
}

struct LocalAITests {
    @Test func readsServingsNumberWithoutGuessing() {
        #expect(LocalRecipeAI.servingsNumber(from: "4 Portionen") == 4)
        #expect(LocalRecipeAI.servingsNumber(from: "2,5 Portionen") == 2.5)
        #expect(LocalRecipeAI.servingsNumber(from: "für eine Familie") == nil)
        #expect(LocalRecipeAI.servingsNumber(from: "") == nil)
    }

    @Test func freeTextIngredientKeepsNoAmount() throws {
        let ingredient = RecipeIngredient.freeText("etwas Olivenöl")
        #expect(ingredient.quantity == nil)
        #expect(ingredient.text() == "etwas Olivenöl")

        // quantity must be written as null, otherwise Mealie shows a 0 in front of the ingredient.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ingredient)) as? [String: Any]
        #expect(json?.keys.contains("quantity") == true)
        #expect(json?["quantity"] is NSNull)
    }
}

struct DecodingTests {
    @Test func decodesSnakeCasePagination() throws {
        // Mealie sends per_page/total_pages, unlike the rest of its API.
        let json = #"{"page": 1, "per_page": 30, "total": 42, "total_pages": 2, "items": []}"#
        let page = try JSONDecoder().decode(Page<RecipeTag>.self, from: Data(json.utf8))
        #expect(page.perPage == 30)
        #expect(page.totalPages == 2)
        #expect(page.hasMore)
    }

    @Test func decodesCamelCasePagination() throws {
        let json = #"{"page": 2, "perPage": 10, "total": 15, "totalPages": 2, "items": []}"#
        let page = try JSONDecoder().decode(Page<RecipeTag>.self, from: Data(json.utf8))
        #expect(page.perPage == 10)
        #expect(!page.hasMore)
    }

    @Test func decodesMealieRecipe() throws {
        let json = """
        {"id": "7f3c", "slug": "pasta", "name": "Pasta", "image": "abc", "recipeServings": 2,
         "totalTime": "PT20M", "orgURL": "https://youtube.com/shorts/x", "unknownField": true,
         "tags": [{"id": "1", "name": "Schnell", "slug": "schnell", "groupId": "g"}],
         "recipeIngredient": [{"quantity": null, "unit": null, "food": null, "note": "etwas Öl",
                               "display": "etwas Öl", "originalText": "some oil", "referenceId": "r"}],
         "recipeInstructions": [{"id": "s", "title": "", "summary": "", "text": "Kochen",
                                 "ingredientReferences": []}]}
        """
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(recipe.displayName == "Pasta")
        #expect(recipe.ingredients.first?.quantity == nil)
        #expect(recipe.ingredients.first?.text() == "etwas Öl")
        #expect(recipe.instructions.count == 1)
        #expect(recipe.servings == 2)
        #expect(recipe.hasImage)
    }
}

struct YouTubeTests {
    @Test func extractsVideoIDs() {
        #expect(URL(string: "https://www.youtube.com/watch?v=abc123&t=42")!.youTubeVideoID == "abc123")
        #expect(URL(string: "https://youtu.be/abc123?si=x")!.youTubeVideoID == "abc123")
        #expect(URL(string: "https://youtube.com/shorts/abc123")!.youTubeVideoID == "abc123")
        #expect(URL(string: "https://m.youtube.com/watch?v=abc123")!.youTubeVideoID == "abc123")
        #expect(URL(string: "https://www.chefkoch.de/rezepte/1")!.youTubeVideoID == nil)
    }

    @Test func parsesVideoLength() {
        #expect(YouTubeDataAPI.isoDurationSeconds("PT18M32S") == 1112)
        #expect(YouTubeDataAPI.isoDurationSeconds("PT1H2M3S") == 3723)
        #expect(YouTubeDataAPI.isoDurationSeconds("PT45S") == 45)
    }
}

struct DescriptionAnalyzerTests {
    @Test func findsRecipeLinkAndIgnoresSocialAndShops() {
        let description = """
            Heute gibt es die besten Käsespätzle!

            👉 Zum Rezept: https://www.meinblog.de/kaesespaetzle
            Mein Kochbuch: https://amzn.to/abc
            Instagram: https://instagram.com/koch
            Shop: https://shop.example.com/merch
            """
        let findings = DescriptionAnalyzer.analyze(description)
        #expect(findings.recipeLinks.map(\.absoluteString) == ["https://www.meinblog.de/kaesespaetzle"])
    }

    @Test func linkOnLineAfterHeadingCounts() {
        let findings = DescriptionAnalyzer.analyze("Das ganze Rezept:\nhttps://example.org/p/123")
        #expect(findings.recipeLinks.count == 1)
    }

    @Test func recognisesRecipeInDescription() {
        let description = """
            Zutaten für 4 Personen:
            - 400 g Mehl
            - 4 Eier
            - 150 ml Mineralwasser
            - 1 TL Salz
            - etwas Butter

            Zubereitung: Alles verrühren und durch die Spätzlepresse drücken.
            """
        #expect(DescriptionAnalyzer.analyze(description).containsRecipe)
    }

    @Test func timestampsAndPricesAreNotIngredients() {
        let description = """
            0:00 Intro
            1:23 Der Teig
            5:40 Fazit
            20 % Rabatt mit dem Code KOCHEN
            """
        let findings = DescriptionAnalyzer.analyze(description)
        #expect(!findings.containsRecipe)
        #expect(findings.isEmpty)
    }
}

struct TikTokTests {
    @Test func recognisesRecipeWithoutLineBreaks() {
        let caption = "Die Weltbesten Zimtschnecken 😍 Rezept: 250 ml lauwarme Milch 20 g frische Hefe 60 g Zucker "
            + "1 Ei 3 EL geschmolzene Butter 1 Prise Salz 500 g Mehl #backen #zimtschnecken"
        #expect(DescriptionAnalyzer.analyze(caption).containsRecipe)
        #expect(DescriptionAnalyzer.analyze("Zutaten: ✳️800g Rindfleisch ✳️2 EL Tomatenmark ✳️1,5 l Brühe ✳️1kg Kloßteig")
            .containsRecipe)
        #expect(DescriptionAnalyzer.analyze("Zutaten: 500gr Hähnchenbrust, 2 große Kartoffeln, 1 EL Tomatenmark, "
            + "200ml Sahne, 1 EL Frischkäse").containsRecipe)
        #expect(DescriptionAnalyzer.analyze("Ihr braucht: 🌸600gr Kartoffeln 🌸1x große Zwiebel 🌸400ml Schlagsahne "
            + "🌸2 Esl. Gemüsebrühe 🌸2 Esl. Sojasauce").containsRecipe)
        #expect(!DescriptionAnalyzer.analyze("Unser Urlaub 2 Liter Wasser, 3 Gläser und 0:00 Intro").containsRecipe)
    }

    @Test func recognisesVideoLinks() {
        #expect(URL(string: "https://www.tiktok.com/@koch/video/7686878595041463585")!.isTikTokVideo)
        #expect(!URL(string: "https://vm.tiktok.com/ZTR45GpSF/")!.isTikTokVideo)
    }
}

struct InstagramTests {
    @Test func extractsShortcodes() {
        #expect(URL(string: "https://www.instagram.com/reel/DePb6WLuVae/?igsh=abc")!.instagramShortcode == "DePb6WLuVae")
        #expect(URL(string: "https://instagram.com/p/DePb6WLuVae")!.instagramShortcode == "DePb6WLuVae")
        #expect(URL(string: "https://www.instagram.com/koch/reel/Dd9RyBWBVih/")!.instagramShortcode == "Dd9RyBWBVih")
        #expect(URL(string: "https://www.instagram.com/koch/reels/")!.instagramShortcode == nil)
        #expect(URL(string: "https://www.youtube.com/p/abc")!.instagramShortcode == nil)
    }

    @Test func readsEmbedCaption() throws {
        let html = """
            <div class="Caption"><a class="CaptionUsername" href="https://www.instagram.com/koch/?utm_source=ig_embed&amp;ig_rid=x" \
            target="_blank">koch</a><br /><br />Käsespätzle &#x1f9c0;\u{2063}<br />\u{2063}<br />Zutaten:<br />400 g Mehl<br />\
            4 Eier<br />Rezept von <a href="/oma/?utm_source=ig_embed">&#064;oma</a><div class="CaptionComments">x</div></div>
            """
        let info = try #require(InstagramPost.embedCaption(in: html, code: "abc"))
        #expect(info.channel == "@koch")
        #expect(info.description == "Käsespätzle 🧀\n\nZutaten:\n400 g Mehl\n4 Eier\nRezept von @oma")
    }

    @Test func readsOpenGraphCaption() throws {
        let html = """
            <meta property="og:description" content="711K likes, 22K comments - koch on October 8, 2026: &quot;Der \
            &quot;beste&quot; Kuchen\u{2063}
            \u{2063}
            200 g Zucker&quot;. " />
            """
        let info = try #require(InstagramPost.openGraphCaption(in: html, code: "abc"))
        #expect(info.channel == "@koch")
        #expect(info.description == "Der \"beste\" Kuchen\n\n200 g Zucker")
    }

    @Test func emptyCaptionIsNoInfo() {
        #expect(InstagramPost.embedCaption(in: #"<div class="Caption"><div class="CaptionComments">"#, code: "abc") == nil)
    }
}
