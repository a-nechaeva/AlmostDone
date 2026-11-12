import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PhotoImportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isRequestingCamera = false
    @State private var showsCameraSettings = false
    @State private var photoError: String?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var catalogLine: PhotoImportLine?

    @Bindable var model: PhotoImportModel

    var body: some View {
        NavigationStack {
            List {
                switch model.phase {
                case .source:
                    sourceOptions
                case .recognizing:
                    ProgressView("Распознаём фото")
                    Button("Отменить распознавание", action: chooseAnotherPhoto)
                case .failed:
                    Text("Не удалось распознать фото")
                    if model.canRetryRecognition {
                        Button("Повторить") { startRecognition { await model.retryRecognition() } }
                    }
                    Button("Выбрать другое фото", action: chooseAnotherPhoto)
                case .empty:
                    Text("На фото не нашли продукты")
                    Button("Выбрать другое фото", action: chooseAnotherPhoto)
                case .review:
                    review
                case .imported:
                    Text("Продукты добавлены")
                    if model.isSaving {
                        ProgressView("Обновляем список")
                    } else {
                        Button("Готово", action: close)
                    }
                }
            }
            .navigationTitle("Добавить по фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: close)
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("products.photo.close")
                }
            }
        }
        .task(id: selectedPhoto) { await loadGalleryPhoto(selectedPhoto) }
        .task(id: isRequestingCamera) {
            if isRequestingCamera { await openCamera() }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            RecognitionCamera { image in
                isCameraPresented = false
                if let image { useCameraPhoto(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $catalogLine) { line in
            RecognitionCatalogScreen(repository: model.pantry.repository) { ingredient in
                model.select(ingredient, for: line.id)
                catalogLine = nil
            }
        }
        .alert("Доступ к камере", isPresented: $showsCameraSettings) {
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Разрешите доступ к камере в настройках или выберите фото из галереи.")
        }
        .onDisappear {
            if model.phase == .recognizing { chooseAnotherPhoto() }
        }
    }

    @ViewBuilder
    private var sourceOptions: some View {
        Section {
            Picker("Что на фото", selection: $model.kind) {
                Text("Чек").tag(RecognitionKind.receipt)
                Text("Продукты").tag(RecognitionKind.products)
            }
            .pickerStyle(.segmented)
            Button("Открыть камеру", systemImage: "camera") { isRequestingCamera = true }
                .accessibilityIdentifier("products.photo.camera")
            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .compatible) {
                Label("Выбрать из галереи", systemImage: "photo")
            }
            .accessibilityIdentifier("products.photo.gallery")
        }
        .disabled(isRequestingCamera || selectedPhoto != nil)

        if selectedPhoto != nil {
            ProgressView("Загружаем фото из галереи")
        }
        if let photoError {
            Text(photoError)
                .foregroundStyle(.secondary)
        }
    }

    private var review: some View {
        Group {
            Section("Проверьте продукты и выберите, что добавить") {
                ForEach(model.lines) { line in
                    reviewRow(line)
                }
                .disabled(!model.canEdit)
            }
            Section {
                if let problem = model.problem {
                    Text(problem.message)
                    if problem == .refreshFailed {
                        Button("Обновить запасы") { Task { await model.retryRefresh() } }
                    }
                }
                if model.isSaving {
                    ProgressView("Подтверждаем импорт")
                } else {
                    Button(model.hasPendingImport ? "Повторить импорт" : "Добавить выбранное") {
                        Task { await model.confirm() }
                    }
                    .disabled(!model.canConfirm)
                    .accessibilityIdentifier("products.photo.import")
                }
            }
        }
    }

    private func reviewRow(_ line: PhotoImportLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { model.lines.first(where: { $0.id == line.id })?.isSelected ?? false },
                    set: { model.setSelected($0, for: line.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.ingredient?.name ?? line.rawName)
                    if let ingredient = line.ingredient, ingredient.name != line.rawName {
                        Text(line.rawName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(line.quantity?.label ?? "Количество неизвестно")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if model.problem == .conflict,
                        let item = model.pantry.snapshot?.items.first(where: { $0.id == line.ingredient?.id })
                    {
                        Text("В запасах сейчас \(item.quantity?.label ?? "неизвестное количество")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(line.ingredient == nil)

            Button(line.ingredient == nil ? "Выбрать продукт в каталоге" : "Заменить продукт в каталоге") {
                catalogLine = line
            }
            .buttonStyle(.borderless)
            if line.quantity != nil {
                Button("Указать, что количество неизвестно") { model.clearQuantity(for: line.id) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func openCamera() async {
        defer { isRequestingCamera = false }
        photoError = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            photoError = "Камера недоступна. Выберите фото из галереи."
            return
        }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard !Task.isCancelled else { return }
        if allowed {
            isCameraPresented = true
        } else {
            showsCameraSettings = true
        }
    }

    private func loadGalleryPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoError = nil
        defer {
            if selectedPhoto == item { selectedPhoto = nil }
        }
        do {
            let photo = try await item.loadTransferable(type: RecognitionPhoto.self)
            guard !Task.isCancelled else { return }
            guard let photo else { throw RecognitionPhoto.InvalidImage.unsupported }
            startRecognition { await model.recognize(photo) }
        } catch {
            guard !Task.isCancelled else { return }
            showPhotoError(error)
        }
    }

    private func useCameraPhoto(_ image: UIImage) {
        do {
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                throw RecognitionPhoto.InvalidImage.unsupported
            }
            let photo = try RecognitionPhoto(data: data)
            startRecognition { await model.recognize(photo) }
        } catch {
            showPhotoError(error)
        }
    }

    private func showPhotoError(_ error: Error) {
        switch error {
        case RecognitionPhoto.InvalidImage.tooLarge:
            photoError = "Выберите фото до 10 МиБ и 25 мегапикселей."
        case RecognitionPhoto.InvalidImage.unsupported:
            photoError = "Выберите изображение JPEG или PNG."
        default:
            photoError = "Не удалось открыть фото. Попробуйте ещё раз."
        }
    }

    private func startRecognition(_ work: @escaping @MainActor () async -> Void) {
        recognitionTask?.cancel()
        recognitionTask = Task { await work() }
    }

    private func chooseAnotherPhoto() {
        recognitionTask?.cancel()
        recognitionTask = nil
        photoError = nil
        model.chooseAnotherPhoto()
    }

    private func close() {
        if model.phase == .recognizing { chooseAnotherPhoto() }
        dismiss()
    }
}

extension PhotoImportModel.ImportProblem {
    fileprivate var message: String {
        switch self {
        case .uncertain: "Сервер не подтвердил импорт. Повторите отправку, чтобы узнать результат."
        case .conflict: "Запасы изменились. Мы обновили список. Проверьте выбранные продукты и подтвердите импорт."
        case .refreshFailed: "Запасы изменились. Обновите список, чтобы продолжить."
        case .units: "Единицы измерения не совпадают с запасами. Проверьте выбранные продукты и количество."
        case .alreadyImported: "Это фото уже импортировано."
        case .failed: "Не удалось добавить продукты. Проверьте выбранные строки."
        }
    }
}

private struct RecognitionCamera: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }
    }
}
