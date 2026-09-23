import ImagePlayground
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// What this process is allowed to do. App extensions may not use the camera.
@MainActor
public enum DeviceCapabilities {
    public static var isAppExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }

    public static var canTakePhotos: Bool {
        !isAppExtension && UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// The document scanner crops and straightens pages, which suits cookbooks best.
    public static var canScanDocuments: Bool {
        !isAppExtension && VNDocumentCameraViewController.isSupported
    }
}

/// One photo from the camera.
public struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    public init(onFinish: @escaping (UIImage?) -> Void) {
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    public final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        public func imagePickerController(_ picker: UIImagePickerController,
                                          didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// Scans one or more pages with automatic cropping and perspective correction.
public struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    public init(onFinish: @escaping ([UIImage]) -> Void) {
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    public func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFailWithError error: any Error) {
            onFinish([])
        }
    }
}

/// Lets the user replace a recipe's cover: camera, photo library or Image Playground.
public struct CoverImageMenu<Label: View>: View {
    let recipe: Recipe
    let api: any MealieAPI
    let onUpdated: (Recipe) -> Void
    let label: Label

    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingPlayground = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isPreparingIdea = false
    @State private var concepts: [ImagePlaygroundConcept] = []
    @State private var error: String?
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    public init(recipe: Recipe, api: any MealieAPI, onUpdated: @escaping (Recipe) -> Void,
                @ViewBuilder label: () -> Label) {
        self.recipe = recipe
        self.api = api
        self.onUpdated = onUpdated
        self.label = label()
    }

    public var body: some View {
        Menu {
            if DeviceCapabilities.canTakePhotos {
                Button(L("Foto aufnehmen"), systemImage: "camera") { showingCamera = true }
            }
            Button(L("Aus Fotos wählen"), systemImage: "photo.on.rectangle") { showingLibrary = true }
            if supportsImagePlayground {
                Button(L("Mit Image Playground erstellen"), systemImage: "apple.image.playground") {
                    Task { await openPlayground() }
                }
            }
        } label: {
            if isUploading || isPreparingIdea {
                ProgressView()
                    .padding(10)
                    .glassEffect(.regular, in: .circle)
            } else {
                label
            }
        }
        .disabled(isUploading || isPreparingIdea)
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await upload(data) }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                if let data = image?.jpegData(compressionQuality: 0.9) {
                    Task { await upload(data) }
                }
            }
            .ignoresSafeArea()
        }
        .imagePlaygroundSheet(isPresented: $showingPlayground, concepts: concepts) { url in
            Task {
                if let data = try? Data(contentsOf: url) { await upload(data) }
            }
        }
        .alert(L("Titelbild konnte nicht gespeichert werden"), isPresented: .constant(error != nil)) {
            Button(L("OK")) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    /// Opens the Playground with the dish name plus two phrases that ask for the finished,
    /// plated dish. Ingredients are left out on purpose: the model would draw eggs and butter
    /// instead of Spätzle. Words like "recipe" or "cover" are avoided too, they tend to produce
    /// books and paper.
    private func openPlayground() async {
        var dish = recipe.displayName
        if LocalRecipeAI.availability.isAvailable {
            isPreparingIdea = true
            dish = (try? await LocalRecipeAI.dishName(from: dish)) ?? dish
            isPreparingIdea = false
        }
        concepts = [.text(dish)] + Self.platingPhrases.map { .text($0) }
        showingPlayground = true
    }

    private static var platingPhrases: [String] {
        Locale.current.language.languageCode == .german
            ? ["fertig angerichtet", "appetitlich serviert"]
            : ["plated dish", "appetizing"]
    }

    private func upload(_ data: Data) async {
        guard let jpeg = ImageCompressor.jpegForUpload(data) else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let key = try await api.uploadImage(slug: recipe.slug, jpeg: jpeg)
            // Reload so the new image key (and with it the image URL) is current everywhere.
            var updated = (try? await api.recipe(slug: recipe.slug)) ?? recipe
            updated.image = key
            onUpdated(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The round camera button shown on top of cover images.
public struct CoverImageButtonLabel: View {
    let hasImage: Bool

    public init(hasImage: Bool) { self.hasImage = hasImage }

    public var body: some View {
        Label(hasImage ? L("Titelbild ändern") : L("Titelbild hinzufügen"),
              systemImage: hasImage ? "camera.fill" : "photo.badge.plus")
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(12)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
