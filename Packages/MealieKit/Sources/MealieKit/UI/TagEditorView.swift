import SwiftUI

/// Pick existing Mealie tags or create new ones for a recipe.
public struct TagEditorView: View {
    let api: any MealieAPI
    let onSave: ([RecipeTag]) async throws -> Void

    @State private var allTags: [RecipeTag] = []
    @State private var selection: [RecipeTag]
    @State private var search = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(api: any MealieAPI, selection: [RecipeTag], onSave: @escaping ([RecipeTag]) async throws -> Void) {
        self.api = api
        self.onSave = onSave
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        NavigationStack {
            List {
                if let newName = newTagName {
                    Button {
                        Task { await create(newName) }
                    } label: {
                        Label(L("„\(newName)“ als neuen Tag anlegen"), systemImage: "plus.circle.fill")
                    }
                }

                ForEach(filteredTags) { tag in
                    let isSelected = selection.contains { $0.slug == tag.slug }
                    Button {
                        toggle(tag)
                    } label: {
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark").foregroundStyle(.brand).fontWeight(.semibold)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Tag suchen oder anlegen"))
            .navigationTitle(L("Tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern"), systemImage: "checkmark") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .top) {
                if !selection.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selection) { tag in
                                Button {
                                    toggle(tag)
                                } label: {
                                    Label(tag.name, systemImage: "xmark")
                                        .labelStyle(TrailingIconLabelStyle())
                                }
                                .buttonStyle(.glass)
                                .tint(.brand)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }
            }
            .alert(L("Fehler"), isPresented: .constant(error != nil)) {
                Button(L("OK")) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task { await load() }
        }
    }

    private var filteredTags: [RecipeTag] {
        guard let query = search.nilIfBlank else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newTagName: String? {
        guard let query = search.nilIfBlank,
              !allTags.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) else { return nil }
        return query
    }

    private func toggle(_ tag: RecipeTag) {
        if let index = selection.firstIndex(where: { $0.slug == tag.slug }) {
            selection.remove(at: index)
        } else {
            selection.append(tag)
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            allTags = try await api.allTags()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create(_ name: String) async {
        do {
            let tag = try await api.createTag(name: name)
            allTags.append(tag)
            allTags.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            selection.append(tag)
            search = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(selection)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
