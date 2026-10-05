import SwiftUI

/// A personal visit opened on its own: the pass, then what can be done with it right now.
struct PersonalActivityDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel
    @State private var activity: PersonalActivity
    let onUpdated: () async -> Void
    var onOpenCourt: ((Court) -> Void)?
    @State private var isReportPresented = false
    @State private var isPlanEditorPresented = false
    @State private var isCancelConfirmationPresented = false
    @State private var gallery: ActivityMediaGalleryItem?
    @State private var saving: PersonalVisitMark?
    @State private var isCanceling = false
    @State private var stampAnimates = false
    @State private var reportResult: PersonalActivity?
    @State private var calendarState = CalendarState.idle
    @State private var errorMessage: String?

    private enum CalendarState { case idle, adding, added }

    private var media: [PlayerMediaItem] { ActivityMediaGalleryItem.media(photos: activity.photoUrls, videos: activity.videoUrls) }
    private var isOwner: Bool { appModel.currentUser?.id == activity.userId }
    private var reportNote: String? {
        let note = activity.reportComment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return note?.isEmpty == false ? note : nil
    }

    init(activity: PersonalActivity, onUpdated: @escaping () async -> Void, onOpenCourt: ((Court) -> Void)? = nil) {
        _activity = State(initialValue: activity)
        self.onUpdated = onUpdated
        self.onOpenCourt = onOpenCourt
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .foregroundStyle(.white)
        .background(VisitStyle.sheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(VisitStyle.accent)
        .sheet(isPresented: $isReportPresented, onDismiss: applyReportResult) {
            PersonalActivityReportComposerSheet(activity: activity, onSaved: { reportResult = $0 }, onSubmitted: onUpdated)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $isPlanEditorPresented) {
            PersonalVisitComposer(mode: .edit(activity)) { updated in
                withAnimation(AppMotion.standard) { activity = updated }
                await onUpdated()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $gallery) { ActivityMediaGallerySheet(item: $0) }
        .confirmationDialog(L10n.string("Cancel this visit?", "Отменить этот визит?"), isPresented: $isCancelConfirmationPresented, titleVisibility: .visible) {
            Button(L10n.string("Cancel visit", "Отменить визит"), role: .destructive) { Task { await cancelVisit() } }
        }
        .alert(L10n.string("Error", "Ошибка"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
    }

    private func content(now: Date) -> some View {
        let phase = activity.visitMoment.map { PersonalVisitTimeline.phase(of: $0, now: now) } ?? .later

        return VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    PersonalVisitPass(
                        activity: activity,
                        now: now,
                        stampAnimates: stampAnimates,
                        onOpenCourt: courtAction
                    )

                    if isOwner {
                        switch phase {
                        case .today, .later, .inProgress:
                            planActions
                        case .needsMark:
                            markActions
                        case .completed, .canceled:
                            EmptyView()
                        }
                    }

                    if phase == .completed || reportNote != nil || !media.isEmpty {
                        resultSection(isOwner: isOwner && phase == .completed)
                    }

                    if isOwner, phase == .today || phase == .later || phase == .inProgress {
                        planFooter
                    } else if phase == .canceled {
                        Text(activity.hasEnded
                             ? L10n.string("Marked as not happened: it does not count in the week.", "Отмечено, что не получилось: в неделю не засчитано.")
                             : L10n.string("The visit was canceled.", "Визит отменён."))
                            .font(.system(size: 13))
                            .foregroundStyle(VisitStyle.secondaryText)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
    }

    private var courtAction: (() -> Void)? {
        guard let court = activity.court, let onOpenCourt else { return nil }
        return { onOpenCourt(court) }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Color.clear.frame(width: 72, height: 44)
            Spacer()
            Text(L10n.string("Visit", "Визит"))
                .font(.headline.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(L10n.string("Done", "Готово"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VisitStyle.accent)
                    .frame(width: 72, height: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: Actions

    private var planActions: some View {
        HStack(spacing: 10) {
            if let url = activity.court?.visitMapURL {
                actionTile(L10n.string("Directions", "Маршрут"), icon: "arrow.triangle.turn.up.right.diamond") {
                    AppHaptics.selection()
                    openURL(url)
                }
            }
            actionTile(calendarTitle, icon: calendarState == .added ? "checkmark" : "calendar.badge.plus", isBusy: calendarState == .adding) {
                Task { await addToCalendar() }
            }
            .disabled(calendarState != .idle)
            actionTile(L10n.string("Edit", "Изменить"), icon: "pencil") {
                isPlanEditorPresented = true
            }
            .accessibilityIdentifier("visit-detail-edit-plan")
        }
    }

    private var calendarTitle: String {
        calendarState == .added ? L10n.string("In calendar", "В календаре") : L10n.string("Calendar", "В календарь")
    }

    private func actionTile(_ title: String, icon: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isBusy {
                    ProgressView().tint(.white).frame(height: 22)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 22)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var markActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("The session is over — how did it go?", "Занятие закончилось — как прошло?"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VisitStyle.accent)

            HStack(spacing: 10) {
                Button {
                    Task { await mark(happened: true) }
                } label: {
                    ZStack {
                        Text(L10n.string("Happened", "Состоялось")).opacity(saving == .saving(happened: true) ? 0 : 1)
                        if saving == .saving(happened: true) { ProgressView().tint(VisitStyle.onAccent) }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VisitStyle.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(VisitStyle.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(saving != nil)
                .accessibilityIdentifier("visit-detail-mark-done")

                Button {
                    Task { await mark(happened: false) }
                } label: {
                    ZStack {
                        Text(L10n.string("Didn't happen", "Не получилось")).opacity(saving == .saving(happened: false) ? 0 : 1)
                        if saving == .saving(happened: false) { ProgressView().tint(.white) }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(VisitStyle.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(saving != nil)
                .accessibilityIdentifier("visit-detail-mark-missed")
            }

            Button {
                isReportPresented = true
            } label: {
                Label(L10n.string("Mark with photos and a note", "Отметить с фото и заметкой"), systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VisitStyle.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(saving != nil)
            .accessibilityIdentifier("visit-detail-report")
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func resultSection(isOwner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reportNote {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("How it went", "Как прошло"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VisitStyle.secondaryText)
                    Text(reportNote)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !media.isEmpty {
                ActivityMediaStrip(media: media, identifierPrefix: "visit-detail-media") { index in
                    gallery = ActivityMediaGalleryItem(
                        media: media, initialIndex: index, title: activity.sport.title,
                        subtitle: activity.scheduledAt.formattedDateTime(), comment: activity.reportComment
                    )
                }
            }
            if isOwner {
                Button {
                    isReportPresented = true
                } label: {
                    Label(
                        media.isEmpty && reportNote == nil
                            ? L10n.string("Add photos and a note", "Добавить фото и заметку")
                            : L10n.string("Edit the result", "Изменить итог"),
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visit-detail-report")
            }
        }
        .padding(.top, 2)
    }

    private var planFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(L10n.string("This does not book a court", "Корт этим не бронируется"))
                if let bookingURL {
                    Text("·")
                    Button {
                        openURL(bookingURL)
                    } label: {
                        Text(L10n.string("Book with the club ↗", "Бронь у клуба ↗"))
                            .fontWeight(.semibold)
                            .foregroundStyle(VisitStyle.accent)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(VisitStyle.secondaryText)

            Button(role: .destructive) {
                isCancelConfirmationPresented = true
            } label: {
                ZStack {
                    Text(L10n.string("Cancel visit", "Отменить визит")).opacity(isCanceling ? 0 : 1)
                    if isCanceling { ProgressView().tint(VisitStyle.destructive) }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VisitStyle.destructive)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isCanceling)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var bookingURL: URL? {
        guard let raw = activity.court?.bookingUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    // MARK: Behaviour

    /// Applied once the report sheet has gone, so the stamp and the photo develop in view.
    private func applyReportResult() {
        guard let updated = reportResult else { return }
        reportResult = nil
        stampAnimates = updated.status != activity.status
        withAnimation(AppMotion.standard) {
            activity = updated
        }
    }

    @MainActor private func mark(happened: Bool) async {
        let generation = appModel.sessionGeneration
        guard isOwner, activity.status.lowercased() == "planned", saving == nil,
              !happened || activity.canComplete, appModel.isCurrentSession(generation) else { return }
        AppHaptics.impact(.light)
        saving = .saving(happened: happened)
        defer { saving = nil }
        do {
            let updated = try await appModel.repository.updatePersonalActivity(
                activityId: activity.id,
                draft: PersonalActivityUpdateDraft(
                    scheduledAt: nil, durationMinutes: nil, comment: nil,
                    status: happened ? "completed" : "canceled", reportComment: nil, photoUrls: nil
                )
            )
            guard appModel.isCurrentSession(generation), isOwner else { return }
            stampAnimates = true
            withAnimation(AppMotion.standard) {
                activity = updated
            }
            await onUpdated()
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            AppHaptics.notification(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func cancelVisit() async {
        let generation = appModel.sessionGeneration
        guard isOwner, activity.status.lowercased() == "planned", !isCanceling,
              appModel.isCurrentSession(generation) else { return }
        isCanceling = true
        defer { isCanceling = false }
        do {
            let updated = try await appModel.repository.updatePersonalActivity(activityId: activity.id, draft: PersonalActivityUpdateDraft(scheduledAt: nil, durationMinutes: nil, comment: nil, status: "canceled", reportComment: nil, photoUrls: nil))
            guard appModel.isCurrentSession(generation), isOwner else { return }
            stampAnimates = true
            withAnimation(AppMotion.standard) {
                activity = updated
            }
            await onUpdated()
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func addToCalendar() async {
        guard calendarState == .idle else { return }
        calendarState = .adding
        do {
            try await PersonalVisitCalendar.add(activity)
            AppHaptics.notification(.success)
            withAnimation(AppMotion.quick) { calendarState = .added }
        } catch {
            AppHaptics.notification(.warning)
            calendarState = .idle
            errorMessage = error.localizedDescription
        }
    }
}
