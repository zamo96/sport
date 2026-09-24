import SwiftUI

/// Соперник по сыгранной игре — для аватаров в календаре и в карточке занятия.
struct WorkoutPartner: Identifiable, Hashable {
    let id: String
    let name: String
    let avatarPath: String?

    /// Все, кроме самого владельца истории: состав игры, а если его нет —
    /// автор и получатель предложения.
    static func partners(of game: MatchGameRequest, ownerID: String) -> [WorkoutPartner] {
        let roster = game.participants
            .filter { $0.id != ownerID }
            .map { WorkoutPartner(id: $0.id, name: $0.displayName, avatarPath: $0.profileHeroImagePath) }
        if !roster.isEmpty { return roster }

        return [game.createdByUser, game.matchedUser].compactMap { sender in
            guard let sender, let id = sender.id, id != ownerID else { return nil }
            return WorkoutPartner(id: id, name: sender.name ?? "", avatarPath: sender.avatarUrl)
        }
    }
}

struct ProfileWorkoutsSection: View {
    let items: [ProfileWorkoutHistoryItem]
    let isLoading: Bool
    let gameError: String?
    let visitError: String?
    let onRetryGames: () -> Void
    let onRetryVisits: () -> Void
    let onOpenPlans: () -> Void
    /// Соперники по `sourceID` игры. Визиты и игры без состава в словаре не нуждаются.
    var partnersBySourceID: [String: [WorkoutPartner]] = [:]

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var monthAnchor = Date()
    @State private var selectedDay: Date?
    @State private var isCalendarExpanded = true
    @State private var visibleLimit = 8
    @State private var selectedGallery: ActivityMediaGalleryItem?

    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
    private let panel = Color(red: 0.065, green: 0.08, blue: 0.065)
    private var month: ProfileWorkoutHistoryMonth {
        .make(containing: monthAnchor, items: items, calendar: calendar)
    }
    private var monthItems: [ProfileWorkoutHistoryItem] {
        items.filter { $0.date >= month.interval.start && $0.date < month.interval.end }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    private var filteredItems: [ProfileWorkoutHistoryItem] {
        guard let selectedDay else { return monthItems }
        return ProfileWorkoutHistoryItem.onDay(selectedDay, from: monthItems, calendar: calendar)
    }
    private var visibleGroups: [(date: Date, items: [ProfileWorkoutHistoryItem])] {
        let groups = Dictionary(grouping: Array(filteredItems.prefix(visibleLimit))) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
    private var hasSourceError: Bool { gameError != nil || visitError != nil }
    private var isCurrentMonth: Bool { calendar.isDate(monthAnchor, equalTo: Date(), toGranularity: .month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let gameError { errorCard(title: L10n.string("Games", "Игры"), message: gameError, retry: onRetryGames, id: "games") }
            if let visitError { errorCard(title: L10n.string("Visits", "Визиты"), message: visitError, retry: onRetryVisits, id: "visits") }
            calendarPanel

            if isLoading && filteredItems.isEmpty {
                ProgressView(L10n.string("Loading workouts for this period…", "Загружаем занятия за этот период…"))
                    .tint(lime).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if filteredItems.isEmpty {
                emptyState
            } else {
                ForEach(visibleGroups, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.leading, 4)
                        ForEach(group.items) { item in
                            WorkoutJournalCard(item: item, partners: partnersBySourceID[item.sourceID] ?? []) { selectedGallery = $0 }
                        }
                    }
                }
                if filteredItems.count > visibleLimit {
                    Button(L10n.string("Show more workouts", "Показать ещё тренировки")) { visibleLimit += 8 }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(lime)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(panel, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("profile-workouts-show-more")
                }
            }
        }
        .sheet(item: $selectedGallery) { ActivityMediaGallerySheet(item: $0) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("My workouts", "Мои тренировки"))
                    .font(.title2.weight(.semibold)).foregroundStyle(.white)
                Text(L10n.string("Games and visits. Every completed activity has a place here.", "Игры и визиты. Здесь есть место каждому состоявшемуся занятию."))
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isLoading { ProgressView().tint(lime).padding(.top, 5).accessibilityLabel(L10n.string("Refreshing history", "Обновляем историю")) }
        }
    }

    private var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 4))) {
                    Text(month.interval.start, format: .dateTime.month(.wide).year())
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    HStack(spacing: 4) {
                        monthButton("chevron.left", label: L10n.string("Previous month", "Предыдущий месяц"), offset: -1)
                        monthButton("chevron.right", label: L10n.string("Next month", "Следующий месяц"), offset: 1)
                            .disabled(isCurrentMonth)
                            .opacity(isCurrentMonth ? 0.35 : 1)
                    }
                }
                if !isCurrentMonth {
                    Button(L10n.string("Current month", "Текущий месяц")) { moveToMonth(Date()) }
                        .font(.caption.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                        .accessibilityIdentifier("profile-workouts-current-month")
                }
            }
            stats
            if hasSourceError {
                Text(L10n.string("Totals reflect loaded records. Part of your history is unavailable and saved records may be out of date.", "Итоги по загруженным записям. Часть истории недоступна; сохранённые данные могут быть неактуальны."))
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Button { isCalendarExpanded.toggle() } label: {
                HStack {
                    Label(L10n.string("Choose a day", "Выбрать день"), systemImage: "calendar")
                    Spacer(minLength: 4)
                    Image(systemName: isCalendarExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(lime).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isCalendarExpanded ? L10n.string("Expanded", "Развёрнут") : L10n.string("Collapsed", "Свёрнут"))
            .accessibilityIdentifier("profile-workouts-calendar-toggle")
            if isCalendarExpanded {
                if dynamicTypeSize.isAccessibilitySize {
                    dayStrip
                } else {
                    ViewThatFits(in: .horizontal) {
                        calendarGrid.frame(minWidth: 308)
                        dayStrip
                    }
                }
            }
            if let selectedDay {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDay, format: .dateTime.day().month(.wide))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Button(L10n.string("Entire month", "Весь месяц")) { self.selectedDay = nil; visibleLimit = 8 }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                        .accessibilityIdentifier("profile-workouts-entire-month")
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color(red: 0.09, green: 0.135, blue: 0.09), panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }

    private var stats: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        return layout {
            stat(monthItems.count, label: L10n.string("Workouts this month", "Занятия за месяц"))
            stat(month.days.filter { $0.count > 0 }.count, label: L10n.string("Active days", "Активные дни"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ count: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((hasSourceError || isLoading) && count == 0 ? "—" : "\(count)")
                .font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(lime)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }

    private var calendarGrid: some View {
        let weekdays = [1, 2, 3, 4, 5, 6, 0].map { calendar.veryShortStandaloneWeekdaySymbols[$0] }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: 7), spacing: 4) {
            ForEach(weekdays.indices, id: \.self) { index in
                Text(weekdays[index]).font(.caption2).foregroundStyle(.white.opacity(0.45)).accessibilityHidden(true)
            }
            ForEach(0..<month.leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
            ForEach(month.days) { day in dayButton(day, expanded: false) }
        }
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 10) {
                ForEach(month.days) { day in dayButton(day, expanded: true) }
            }
            .padding(.vertical, 3)
        }
        .accessibilityElement(children: .contain)
    }

    private func dayButton(_ day: ProfileWorkoutHistoryDay, expanded: Bool) -> some View {
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
        return Button {
            selectedDay = day.date
            visibleLimit = 8
            AppHaptics.selection()
        } label: {
            VStack(spacing: 4) {
                if expanded {
                    Text(day.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.subheadline.weight(.medium))
                    Text(dayCountDescription(day.count))
                        .font(.caption)
                } else {
                    Text(day.date, format: .dateTime.day()).font(.subheadline.weight(.medium))
                    dayPreview(day, selected: selected)
                }
            }
            .foregroundStyle(selected ? Color.black : .white.opacity(day.count > 0 ? 1 : 0.6))
            .padding(.horizontal, expanded ? 14 : 0)
            .padding(.vertical, expanded ? 12 : 0)
            .padding(.vertical, !expanded && dayHasPreview(day) ? 5 : 0)
            .frame(minWidth: expanded ? 130 : 44, minHeight: 44)
            .frame(maxWidth: expanded ? nil : .infinity)
            .background(selected ? lime : day.count > 0 ? lime.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: expanded ? 16 : 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(dayCountDescription(day.count) + (selected ? L10n.string(" Selected", " Выбрано") : ""))
        .accessibilityIdentifier("profile-workouts-day-\(calendar.component(.day, from: day.date))")
    }

    private func dayItems(_ day: ProfileWorkoutHistoryDay) -> [ProfileWorkoutHistoryItem] {
        day.count > 0 ? ProfileWorkoutHistoryItem.onDay(day.date, from: monthItems, calendar: calendar) : []
    }

    private func dayPhotoPath(_ day: ProfileWorkoutHistoryDay) -> String? {
        dayItems(day).lazy.compactMap(\.photoPaths.first).first
    }

    private func dayPartners(_ day: ProfileWorkoutHistoryDay) -> [WorkoutPartner] {
        var seen = Set<String>()
        return dayItems(day)
            .flatMap { partnersBySourceID[$0.sourceID] ?? [] }
            .filter { seen.insert($0.id).inserted }
    }

    private func dayHasPreview(_ day: ProfileWorkoutHistoryDay) -> Bool {
        dayPhotoPath(day) != nil || !dayPartners(day).isEmpty
    }

    /// В клетке дня: фото с занятия, если оно есть; иначе — с кем играли;
    /// иначе — прежняя точка. Несколько занятий за день помечены счётчиком.
    @ViewBuilder
    private func dayPreview(_ day: ProfileWorkoutHistoryDay, selected: Bool) -> some View {
        let ring = selected ? lime : panel
        if let path = dayPhotoPath(day) {
            WorkoutJournalPhoto(path: path)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(ring, lineWidth: 1.5))
                .overlay(alignment: .bottomTrailing) {
                    if day.count > 1 { dayCountBadge(day.count, selected: selected).offset(x: 6, y: 4) }
                }
                .accessibilityHidden(true)
        } else if !dayPartners(day).isEmpty {
            let partners = dayPartners(day)
            HStack(spacing: -9) {
                ForEach(partners.prefix(2)) { partner in
                    RemoteAvatarView(name: partner.name, path: partner.avatarPath, size: 22)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ring, lineWidth: 1.5))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if day.count > 1 { dayCountBadge(day.count, selected: selected).offset(x: 6, y: 4) }
            }
            .accessibilityHidden(true)
        } else {
            Circle().fill(day.count > 0 ? (selected ? Color.black : lime) : .clear).frame(width: 4, height: 4)
        }
    }

    private func dayCountBadge(_ count: Int, selected: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold)).monospacedDigit()
            .foregroundStyle(.black)
            .frame(minWidth: 15, minHeight: 15)
            .background(lime, in: Circle())
            .overlay(Circle().stroke(selected ? Color.black.opacity(0.35) : panel, lineWidth: 1.5))
    }

    private func monthButton(_ image: String, label: String, offset: Int) -> some View {
        Button {
            guard let date = calendar.date(byAdding: .month, value: offset, to: month.interval.start) else { return }
            moveToMonth(date)
        } label: {
            Image(systemName: image).font(.subheadline.weight(.semibold)).foregroundStyle(.white).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "profile-workouts-previous-month" : "profile-workouts-next-month")
    }

    private func dayCountDescription(_ count: Int) -> String {
        if count == 0 && (hasSourceError || isLoading) {
            return L10n.string("No records loaded yet", "Записи пока не загружены")
        }
        return L10n.string("Workouts: \(count)", "Занятия: \(count)")
    }

    private func moveToMonth(_ date: Date) {
        monthAnchor = date
        selectedDay = nil
        visibleLimit = 8
    }

    private func errorCard(title: String, message: String, retry: @escaping () -> Void, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "wifi.exclamationmark").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(message).font(.footnote).foregroundStyle(.white.opacity(0.65))
            Button(L10n.string("Try again", "Повторить"), action: retry)
                .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                .disabled(isLoading).accessibilityIdentifier("profile-workouts-retry-\(id)")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: hasSourceError ? "arrow.triangle.2.circlepath" : "figure.cooldown")
                .font(.largeTitle.weight(.light)).foregroundStyle(lime)
            Text(emptyTitle).font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text(emptySubtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if !hasSourceError, selectedDay != nil {
                Button(L10n.string("See the entire month", "Посмотреть весь месяц")) { selectedDay = nil; visibleLimit = 8 }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
            } else if !hasSourceError, let latest = items.max(by: { $0.date < $1.date }), monthItems.isEmpty {
                Button(L10n.string("Go to latest workout", "К последней тренировке")) { moveToMonth(latest.date) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                    .accessibilityIdentifier("profile-workouts-latest")
            } else if !hasSourceError, items.isEmpty {
                Button(L10n.string("Open plans and results", "Открыть планы и результаты"), action: onOpenPlans)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                    .accessibilityIdentifier("profile-workouts-open-plans")
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var emptyTitle: String {
        if hasSourceError { return L10n.string("Part of your history is unavailable", "Часть истории пока недоступна") }
        if selectedDay != nil { return L10n.string("No workouts marked on this day", "В этот день нет отмеченных занятий") }
        if items.isEmpty { return L10n.string("Your first workout starts the story", "Первое занятие — начало истории") }
        return L10n.string("No workouts marked this month", "В этом месяце нет отмеченных занятий")
    }

    private var emptySubtitle: String {
        if hasSourceError { return L10n.string("Try loading the missing sources above. Missing data does not mean you had no workouts.", "Повтори загрузку источников выше. Недоступные данные не означают, что тренировок не было.") }
        if selectedDay != nil { return L10n.string("Choose another day or see all workouts in the month.", "Выбери другой день или посмотри все занятия месяца.") }
        if items.isEmpty { return L10n.string("Mark a completed game or visit in your plans. Photos are optional.", "Отметь состоявшуюся игру или визит в своих планах. Фото не обязательно.") }
        return L10n.string("Browse another month to revisit your activities.", "Переключи месяц, чтобы вернуться к своим занятиям.")
    }
}

/// Shared journal card for a completed activity in the profile and a selected week day.
struct WorkoutJournalCard: View {
    let item: ProfileWorkoutHistoryItem
    var partners: [WorkoutPartner] = []
    let onOpenGallery: (ActivityMediaGalleryItem) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
    private let panel = Color(red: 0.055, green: 0.075, blue: 0.065)
    private var media: [PlayerMediaItem] { ActivityMediaGalleryItem.media(photos: item.photoPaths, videos: item.videoPaths) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            if !media.isEmpty { mediaStrip.padding(.top, 14) }
            if item.courtName != nil || item.durationMinutes != nil || item.comment != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if let court = item.courtName {
                        Label(court, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    if let minutes = item.durationMinutes {
                        Label(L10n.string("Recorded duration: \(minutes) min", "Длительность в записи: \(minutes) мин"), systemImage: "clock")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    if let comment = item.comment {
                        Text(comment).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            } else if !media.isEmpty {
                Color.clear.frame(height: 16)
            }
        }
        .background(panel, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.065), lineWidth: 1))
    }

    private var cardHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        return layout {
            VStack(alignment: .leading, spacing: 9) {
                Text(item.kind == .activity ? L10n.string("PERSONAL VISIT", "ЛИЧНЫЙ ВИЗИТ") : L10n.string("GAME", "ИГРА"))
                    .font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(lime)
                Text(item.sport.title).font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.date, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
                if !partners.isEmpty { partnerAvatars }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SportIconView(sport: item.sport, color: lime, size: 38)
                .frame(width: 76, height: 76)
                .background(lime.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(lime.opacity(0.18), lineWidth: 1))
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.105, green: 0.185, blue: 0.115), panel], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// С кем была игра: до трёх аватаров, остальные — счётчиком.
    private var partnerAvatars: some View {
        HStack(spacing: -8) {
            ForEach(partners.prefix(3)) { partner in
                RemoteAvatarView(name: partner.name, path: partner.avatarPath, size: 30)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(panel, lineWidth: 2))
            }
            if partners.count > 3 {
                Text("+\(partners.count - 3)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(panel, lineWidth: 2))
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Played with ", "Играли с ") + partners.map(\.name).filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var mediaStrip: some View {
        ActivityMediaStrip(media: media, identifierPrefix: "workout-media-\(item.id)") { index in
            onOpenGallery(ActivityMediaGalleryItem(
                media: media, initialIndex: index, title: item.sport.title,
                subtitle: item.date.formatted(date: .abbreviated, time: .shortened), comment: item.comment
            ))
        }
        .padding(.horizontal, 16)
    }

}

struct WorkoutJournalPhoto: View {
    let path: String

    var body: some View {
        Group {
            if let url = resolveAppRemoteURL(path) {
                RemoteImage(url: url, contentMode: .fill, indicator: .spinner) { phase in
                    if phase == .failed { placeholder }
                }
            } else { placeholder }
        }
        .background(Color.white.opacity(0.05))
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.title2).foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
