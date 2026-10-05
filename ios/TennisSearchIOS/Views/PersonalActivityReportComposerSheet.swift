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
    private let lime = VisitStyle.accent
    private var count: Int { existing.count + pending.count }
    private var commentLength: Int { comment.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }

    private var isCompleted: Bool { activity.status.lowercased() == "completed" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    visitRow
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("How did it go?", "Как прошло?"))
                            .font(.system(size: 30, weight: .heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(isCompleted
                             ? L10n.string("The session already counts. Photos and a note are for you and your profile, if you like.", "Занятие уже засчитано. Фото и заметка — для себя и для профиля, по желанию.")
                             : L10n.string("Saving marks the session as happened. Photos and a note are optional.", "Сохранение отметит занятие как состоявшееся. Фото и заметка — по желанию."))
                            .font(.system(size: 15))
                            .foregroundStyle(VisitStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    mediaSection
                    noteSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            footer
        }
        .foregroundStyle(.white)
        .background(VisitStyle.sheet.ignoresSafeArea())
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

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel(L10n.string("Close", "Закрыть"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var visitRow: some View {
        HStack(spacing: 12) {
            PersonalVisitArtwork(court: activity.court, sport: activity.sport, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(visitTitle)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let court = activity.court {
                    Text(court.name)
                        .font(.system(size: 13))
                        .foregroundStyle(VisitStyle.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCompleted {
                Text(L10n.string("Marked", "Отмечено"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VisitStyle.onAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(VisitStyle.accent, in: Capsule())
            }
        }
    }

    private var visitTitle: String {
        guard let start = activity.scheduledDate, let range = activity.visitTimeRange else { return activity.sport.title }
        return "\(activity.sport.title) · \(PersonalVisitDateText.day(start, style: .short)) · \(range)"
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(existing.enumerated()), id: \.offset) { index, item in
                    mediaTile {
                        ActivityMediaThumbnail(item: item)
                    } onRemove: {
                        existing.remove(at: index)
                    }
                }
                ForEach(pending) { item in
                    mediaTile {
                        if item.kind == .video {
                            VideoThumbnailView(url: item.url)
                                .overlay(Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white))
                        } else if let image = UIImage(contentsOfFile: item.url.path) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    } onRemove: {
                        try? FileManager.default.removeItem(at: item.url)
                        pending.removeAll { $0.id == item.id }
                    }
                }
                if count < 8 {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, 8 - count), matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                        VStack(spacing: 8) {
                            if isPreparing {
                                ProgressView().tint(lime)
                            } else {
                                Image(systemName: "camera")
                                    .font(.system(size: 24, weight: .semibold))
                            }
                            Text(count == 0 ? L10n.string("Add", "Добавить") : L10n.string("More", "Ещё"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(lime)
                        .frame(maxWidth: .infinity, minHeight: 136)
                        .background(lime.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(lime.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                    }
                    .disabled(isPreparing || isSubmitting)
                    .accessibilityLabel(L10n.string("Add photos or videos", "Добавить фото или видео"))
                    .accessibilityIdentifier("visit-report-add-media")
                }
            }
            Text(L10n.string("\(count) of 8 · photos and videos", "\(count) из 8 · фото и видео"))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private func mediaTile<Content: View>(@ViewBuilder _ content: () -> Content, onRemove: @escaping () -> Void) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 136, maxHeight: 136)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                removeButton(action: onRemove)
            }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Note for yourself", "Заметка для себя"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VisitStyle.secondaryText)
            TextField(L10n.string("What worked, what to work on next time", "Что получилось, над чем поработать в следующий раз"), text: $comment, axis: .vertical)
                .lineLimit(3...8)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
            Text("\(commentLength)/240")
                .font(.caption)
                .foregroundStyle(commentLength > 240 ? VisitStyle.destructive : Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var footer: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 10) {
                if isSubmitting { ProgressView().tint(VisitStyle.onAccent) }
                Text(isSubmitting ? L10n.string("Saving…", "Сохраняем…") : L10n.string("Save", "Сохранить"))
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(VisitStyle.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(lime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || isPreparing || commentLength > 240)
        .accessibilityIdentifier("visit-report-save")
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(VisitStyle.sheet)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.6), in: Circle())
                .frame(width: 44, height: 44)
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
