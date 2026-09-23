import MealieKit
import SwiftUI

struct RecipesView: View {
    @Environment(MealieAccount.self) private var account

    @State private var recipes: [RecipeSummary] = []
    @State private var tags: [RecipeTag] = []
    @State private var selectedTags: Set<String> = []
    @State private var search = ""
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var error: String?

    private let pageSize = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                if !tags.isEmpty { tagFilter }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 18) {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if recipe.id == recipes.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView().padding()
                }
            }
            .overlay { emptyState }
            .navigationTitle("Rezepte")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Rezepte durchsuchen")
            .refreshable { await reload() }
            .task(id: query) {
                // Debounce typing.
                if !search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await reload()
            }
            .task { tags = (try? await account.api?.allTags()) ?? [] }
            .navigationDestination(for: RecipeSummary.self) { recipe in
                if let api = account.api {
                    RecipeDetailView(slug: recipe.slug, api: api, webURL: account.webURL(forRecipe: recipe.slug))
                }
            }
        }
    }

    private struct Query: Equatable { var search: String; var tags: Set<String> }
    private var query: Query { Query(search: search, tags: selectedTags) }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    let isSelected = selectedTags.contains(tag.slug)
                    Button {
                        selectedTags.formSymmetricDifference([tag.slug])
                    } label: {
                        Text(tag.name)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(isSelected ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.fill.tertiary),
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: isSelected)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if recipes.isEmpty && !isLoading {
            if let error {
                ContentUnavailableView {
                    Label("Keine Verbindung", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await reload() } }
                }
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if page > 0 {
                ContentUnavailableView("Noch keine Rezepte", systemImage: "book.closed",
                                       description: Text("Importiere dein erstes Rezept im Tab „Importieren“."))
            }
        }
    }

    private func reload() async {
        page = 0
        hasMore = true
        await loadPage(replacing: true)
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        await loadPage(replacing: false)
    }

    private func loadPage(replacing: Bool) async {
        guard let api = account.api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.recipes(page: page + 1, perPage: pageSize,
                                               search: search, tagSlugs: Array(selectedTags))
            recipes = replacing ? result.items : recipes + result.items.filter { new in !recipes.contains { $0.slug == new.slug } }
            page = result.page
            hasMore = result.hasMore
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
            if replacing { recipes = [] }
        }
    }
}

private struct RecipeCard: View {
    @Environment(MealieAccount.self) private var account
    let recipe: RecipeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeImage(url: account.api?.imageURL(for: recipe), cornerRadius: 20)
                .aspectRatio(4 / 3, contentMode: .fit)

            Text(recipe.displayName)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)

            if let time = RecipeFormat.duration(recipe.totalTime ?? recipe.cookTime) {
                Label(time, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}
