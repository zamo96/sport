import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PersonalActivityReportComposerSheet: View {
    let activity: PersonalActivity
    var onSaved: ((PersonalActivity) -> Void)? = nil
    let onSubmitted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var existing: [PlayerMediaItem] = []
    @State private var pending: [PendingVisitMedia] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickerTask: Task<Void, Never>?
    @State private var pickerToken = UUID()
    @State private var generation: UUID?
    @State private var comment = ""
    @State private var isPreparing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
    private var count: Int { existing.count + pending.count }
    private var commentLength: Int { comment.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activity.sport.title).font(.title2.weight(.semibold))
                        Text(activity.scheduledAt.formattedDateTime()).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        if let court = activity.court { Text(court.name).font(.subheadline).foregroundStyle(.white.opacity(0.7)) }
                    }
                    Text(L10n.string("Photos, videos and a note are optional. Saving marks this visit as completed.", "Фото, видео и заметка — по желанию. Сохранение отмечает визит как состоявшийся."))
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    mediaSection
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("How did it go?", "Как прошло занятие?")).font(.headline)
                        TextField(L10n.string("What would you like to remember?", "Что хочется запомнить?"), text: $comment, axis: .vertical)
                            .lineLimit(3...8).padding(14)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        Text("\(commentLength)/240")
                            .font(.caption).foregroundStyle(commentLength > 240 ? .red : .white.opacity(0.5))
                    }
                    Button { Task { await save() } } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.black) }
                            Text(isSubmitting ? L10n.string("Saving…", "Сохраняем…") : L10n.string("Save result", "Сохранить результат"))
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(lime, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting || isPreparing || commentLength > 240)
                    .accessibilityIdentifier("visit-report-save")
                }
                .padding(20)
            }
            .foregroundStyle(.white).background(Color.black.ignoresSafeArea())
            .navigationTitle(L10n.string("Visit result", "Итог визита"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Close", "Закрыть")) { dismiss() }.disabled(isSubmitting)
                }
            }
        }
        .preferredColorScheme(.dark).tint(lime)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            guard generation == nil else { return }
            generation = appModel.sessionGeneration
            existing = ActivityMediaGalleryItem.media(photos: activity.photoUrls, videos: activity.videoUrls)
            comment = activity.reportComment ?? ""
        }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            pickerTask?.cancel()
            let token = UUID()
            pickerToken = token
            pickerTask = Task { await prepare(items, token: token) }
        }
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
        .onDisappear {
            pickerTask?.cancel()
            pickerToken = UUID()
            for media in pending { try? FileManager.default.removeItem(at: media.url) }
        }
        .alert(L10n.string("Could not save", "Не удалось сохранить"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Photos and videos · \(count)/8", "Фото и видео · \(count)/8")).font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(existing.enumerated()), id: \.offset) { index, item in
                        ZStack(alignment: .topTrailing) {
                            ActivityMediaThumbnail(item: item).frame(width: 108, height: 108).clipShape(RoundedRectangle(cornerRadius: 16))
                            removeButton { existing.remove(at: index) }
                        }
                    }
                    ForEach(pending) { item in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if item.kind == .video {
                                    VideoThumbnailView(url: item.url)
                                        .overlay(Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white))
                                } else if let image = UIImage(contentsOfFile: item.url.path) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                }
                            }
                            .frame(width: 108, height: 108).clipShape(RoundedRectangle(cornerRadius: 16))
                            removeButton {
                                try? FileManager.default.removeItem(at: item.url)
                                pending.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, 8 - count), matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                HStack {
                    if isPreparing { ProgressView().tint(lime) }
                    Label(L10n.string("Add photos or videos", "Добавить фото или видео"), systemImage: "plus")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
            }
            .disabled(count >= 8 || isPreparing || isSubmitting)
            .accessibilityIdentifier("visit-report-add-media")
            Text(L10n.string("Up to 8 attachments. Photos up to 20 MB; MP4 or MOV videos up to 60 MB.", "До 8 вложений. Фото до 20 МБ; видео MP4 или MOV до 60 МБ."))
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white)
                .shadow(color: .black, radius: 3).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).disabled(isSubmitting)
        .accessibilityLabel(L10n.string("Remove attachment", "Удалить вложение"))
    }

    @MainActor private func prepare(_ items: [PhotosPickerItem], token: UUID) async {
        guard let generation, appModel.isCurrentSession(generation), appModel.currentUser?.id == activity.userId else { return }
        isPreparing = true
        defer { if pickerToken == token { isPreparing = false; pickerItems = [] } }
        for item in items {
            var createdURL: URL?
            do {
                guard count < 8 else { throw visitError(L10n.string("You can attach up to 8 files.", "Можно добавить до 8 файлов.")) }
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
                guard let raw = try await item.loadTransferable(type: Data.self) else { throw visitError(L10n.string("Could not read the selected file.", "Не удалось прочитать выбранный файл.")) }
                guard pickerToken == token, appModel.isCurrentSession(generation) else { return }
                let data: Data
                let fileExtension: String
                let mimeType: String
                if isVideo {
                    let ext = item.supportedContentTypes.compactMap(\.preferredFilenameExtension).first { ["mp4", "mov"].contains($0.lowercased()) }?.lowercased()
                    guard let ext, raw.count <= 60 * 1024 * 1024 else { throw visitError(L10n.string("Choose an MP4 or MOV video under 60 MB.", "Выбери видео MP4 или MOV размером до 60 МБ.")) }
                    data = raw; fileExtension = ext; mimeType = ext == "mov" ? "video/quicktime" : "video/mp4"
                } else {
                    guard let image = UIImage(data: raw), let jpeg = image.jpegData(compressionQuality: 0.86), jpeg.count <= 20 * 1024 * 1024 else { throw visitError(L10n.string("Choose a photo under 20 MB.", "Выбери фото размером до 20 МБ.")) }
                    data = jpeg; fileExtension = "jpg"; mimeType = "image/jpeg"
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("visit-media-\(UUID().uuidString).\(fileExtension)")
                createdURL = url
                try data.write(to: url, options: .atomic)
                guard pickerToken == token, appModel.isCurrentSession(generation) else { try? FileManager.default.removeItem(at: url); return }
                pending.append(PendingVisitMedia(id: UUID(), kind: isVideo ? .video : .photo, url: url, mimeType: mimeType, uploadedURL: nil))
            } catch {
                if let createdURL { try? FileManager.default.removeItem(at: createdURL) }
                guard pickerToken == token, appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    @MainActor private func save() async {
        guard !isSubmitting, !isPreparing, let generation, appModel.isCurrentSession(generation),
              appModel.currentUser?.id == activity.userId, commentLength <= 240, count <= 8 else { return }
        guard activity.canComplete || activity.status.lowercased() == "completed" else {
            errorMessage = L10n.string("A result can be recorded after the visit ends.", "Итог можно записать после окончания визита.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var media = existing
            for item in pending {
                guard appModel.isCurrentSession(generation) else { return }
                let path: String
                if let uploaded = item.uploadedURL { path = uploaded }
                else {
                    let data = try Data(contentsOf: item.url)
                    if item.kind == .video {
                        path = try await appModel.repository.uploadPersonalActivityVideo(activityId: activity.id, data: data, fileName: item.url.lastPathComponent, mimeType: item.mimeType)
                    } else {
                        path = try await appModel.repository.uploadPersonalActivityPhoto(activityId: activity.id, data: data, fileName: item.url.lastPathComponent, mimeType: item.mimeType)
                    }
                    guard appModel.isCurrentSession(generation) else { return }
                    if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].uploadedURL = path }
                }
                media.append(PlayerMediaItem(kind: item.kind, path: path))
            }
            guard appModel.isCurrentSession(generation) else { return }
            let updated = try await appModel.repository.updatePersonalActivity(activityId: activity.id, draft: PersonalActivityUpdateDraft(
                scheduledAt: nil, durationMinutes: nil, comment: nil, status: "completed", reportComment: comment,
                photoUrls: media.filter { $0.kind == .photo }.map(\.path), videoUrls: media.filter { $0.kind == .video }.map(\.path)
            ))
            guard appModel.isCurrentSession(generation), appModel.currentUser?.id == activity.userId else { return }
            onSaved?(updated)
            dismiss()
            await onSubmitted()
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func visitError(_ message: String) -> Error { NSError(domain: "VisitMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private struct PendingVisitMedia: Identifiable {
    let id: UUID
    let kind: PlayerMediaKind
    let url: URL
    let mimeType: String
    var uploadedURL: String?
}
