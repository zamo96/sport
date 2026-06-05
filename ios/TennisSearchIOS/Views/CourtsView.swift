import SwiftUI
import MapKit
import UIKit

struct CourtsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openURL) private var openURL
    @State private var courts: [Court] = []
    @State private var query = ""
    @State private var selectedCourtId: String?
    @State private var selectedSport: Sport?
    @State private var isLoadingCourts = false
    @State private var selectedCourtForDetail: Court?
    @State private var showFavoritesOnly = false
    @AppStorage("savedCourtIDs") private var savedCourtIDsRaw = ""
    @FocusState private var isSearchFocused: Bool

    private var sortedCourts: [Court] {
        let preferredDistricts = preferredDistrictIDs
        guard !preferredDistricts.isEmpty else {
            return courts
        }

        return courts.enumerated()
            .sorted { left, right in
                let leftRank = districtRank(for: left.element, preferredDistricts: preferredDistricts)
                let rightRank = districtRank(for: right.element, preferredDistricts: preferredDistricts)

                if leftRank != rightRank {
                    return leftRank < rightRank
                }

                return left.offset < right.offset
            }
            .map(\.element)
    }

    private var preferredDistrictIDs: [String] {
        let profileDistricts = appModel.currentUser?.preferredDistricts ?? []

        if !profileDistricts.isEmpty {
            return profileDistricts
        }

        if let district = appModel.currentUser?.district, !district.isEmpty {
            return [district]
        }

        return []
    }

    private func districtRank(for court: Court, preferredDistricts: [String]) -> Int {
        guard let district = court.district,
              let index = preferredDistricts.firstIndex(of: district) else {
            return Int.max
        }

        return index
    }

    private var availableSports: [Sport] {
        let foundSports = Set(courts.flatMap { $0.supportedSports ?? [] })
        return Sport.allCases.filter(foundSports.contains)
    }

    private var sportFilteredCourts: [Court] {
        let baseCourts = showFavoritesOnly
            ? sortedCourts.filter { savedCourtIDs.contains($0.id) }
            : sortedCourts

        guard let selectedSport else {
            return baseCourts
        }

        return baseCourts.filter { court in
            guard let supportedSports = court.supportedSports, !supportedSports.isEmpty else {
                return true
            }
            return supportedSports.contains(selectedSport)
        }
    }

    private var filteredCourts: [Court] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return sportFilteredCourts
        }

        return sportFilteredCourts.filter { court in
            [
                court.name,
                court.address,
                court.nearestMetroName,
                localizedDistrictName(court.district)
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            .contains(normalizedQuery)
        }
    }

    private var suggestedCourts: [Court] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let prefixMatches = filteredCourts.filter { $0.name.lowercased().hasPrefix(normalizedQuery) }
        let metroMatches = filteredCourts.filter { court in
            guard let metro = court.nearestMetroName?.lowercased() else { return false }
            return metro.contains(normalizedQuery) && !prefixMatches.contains(where: { $0.id == court.id })
        }
        let districtMatches = filteredCourts.filter { court in
            guard let district = localizedDistrictName(court.district)?.lowercased() else { return false }
            return district.contains(normalizedQuery)
                && !prefixMatches.contains(where: { $0.id == court.id })
                && !metroMatches.contains(where: { $0.id == court.id })
        }

        return Array((prefixMatches + metroMatches + districtMatches).prefix(4))
    }

    private var focusedCourt: Court? {
        if let selectedCourtId,
           let selectedCourt = filteredCourts.first(where: { $0.id == selectedCourtId }) {
            return selectedCourt
        }
        return suggestedCourts.first ?? filteredCourts.first
    }

    private var mapPreviewCourts: [Court] {
        var items: [Court] = []

        if let focusedCourt {
            items.append(focusedCourt)
        }

        for court in filteredCourts {
            guard items.count < 18 else { break }
            if !items.contains(where: { $0.id == court.id }) {
                items.append(court)
            }
        }

        return items
    }

    private var savedCourtIDs: Set<String> {
        Set(savedCourtIDsRaw.split(separator: ",").map(String.init))
    }

    private var darkStroke: Color {
        Color.white.opacity(0.1)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 4 / 255, green: 13 / 255, blue: 13 / 255),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isLoadingCourts && courts.isEmpty {
                TennisBallsLoader(title: "Загружаем центры")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            headerSection
                            searchField
                            suggestionsRail { court in
                                selectedCourtId = court.id
                                isSearchFocused = false
                                AppHaptics.selection()
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    proxy.scrollTo("centers-map", anchor: .center)
                                }
                            }
                            sportFilterRail
                            mapSummaryCard
                                .id("centers-map")
                            courtsListSection { court in
                                selectedCourtId = court.id
                                isSearchFocused = false
                                AppHaptics.selection()
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    proxy.scrollTo("centers-map", anchor: .center)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 116)
                    }
                    .refreshable {
                        await loadCourts(forceRefresh: true)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if courts.isEmpty {
                await loadCourts()
            }
        }
        .onAppear {
            isSearchFocused = false
        }
        .sheet(item: $selectedCourtForDetail) { court in
            CourtDetailSheet(
                court: court,
                isSaved: savedCourtIDs.contains(court.id),
                onToggleSave: {
                    toggleSavedCourt(court)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Центры")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                Text("Найдите клуб, корт или секцию рядом")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            Button {
                AppHaptics.selection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Фильтры")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(darkStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Клуб, метро или район")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                }

                TextField("", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .focused($isSearchFocused)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.34))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .frame(width: 34, height: 34)
                    .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.13), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(darkStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func suggestionsRail(onFocusMap: @escaping (Court) -> Void) -> some View {
        if !suggestedCourts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestedCourts) { court in
                        Button {
                            onFocusMap(court)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(court.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(court.nearestMetroName ?? localizedDistrictName(court.district) ?? court.address)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(selectedCourtId == court.id ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selectedCourtId == court.id ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.55) : darkStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sportFilterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                sportFilterChip(title: "Все", sport: nil)
                favoritesChip

                ForEach(availableSports) { sport in
                    sportFilterChip(title: sport.title, sport: sport)
                }
            }
        }
    }

    private func sportFilterChip(title: String, sport: Sport?) -> some View {
        let isSelected = selectedSport == sport

        return Button {
            selectedSport = sport
            showFavoritesOnly = false
            AppHaptics.selection()
        } label: {
            HStack(spacing: 8) {
                if let sport {
                    Image(systemName: sportSymbolName(for: sport))
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : Color.white.opacity(0.06), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : darkStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var favoritesChip: some View {
        Button {
            showFavoritesOnly.toggle()
            selectedSport = nil
            AppHaptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .bold))
                Text("Избранные")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(showFavoritesOnly ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(showFavoritesOnly ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : Color.white.opacity(0.06), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(showFavoritesOnly ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : darkStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mapSummaryCard: some View {
        if !mapPreviewCourts.isEmpty {
            ZStack(alignment: .bottomLeading) {
                SearchClubPickerMapView(
                    courts: mapPreviewCourts,
                    focusedCourt: focusedCourt,
                    onSelectCourt: { courtId in
                        selectedCourtId = courtId
                        AppHaptics.selection()
                    }
                )
                .frame(height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                LinearGradient(
                    colors: [.black.opacity(0.58), .black.opacity(0.08)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    Text("На карте")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(filteredCourts.count) центров")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text(focusedCourt?.name ?? "Санкт-Петербург")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(20)
                .allowsHitTesting(false)

                Button {
                    if let focusedCourt {
                        selectedCourtForDetail = focusedCourt
                        AppHaptics.impact(.light)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Открыть")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Color.black.opacity(0.48), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .disabled(focusedCourt == nil)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(darkStroke, lineWidth: 1)
            )
        }
    }

    private func courtsListSection(onFocusMap: @escaping (Court) -> Void) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Рядом с вами")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Найдено \(filteredCourts.count) центров")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Text("Сортировка")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
            }

            if filteredCourts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    Text("Ничего не найдено")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Попробуйте другой вид спорта или запрос.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(darkStroke, lineWidth: 1))
            } else {
                ForEach(filteredCourts) { court in
                    courtCard(court, onFocusMap: onFocusMap)
                }
            }
        }
    }

    private func courtCard(_ court: Court, onFocusMap: @escaping (Court) -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CourtImageTile(court: court, size: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(court.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(court.sportsTitle(fallback: selectedSport))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 5) {
                        if let distance = court.distanceLabel {
                            Text(distance)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        if let rating = court.rating {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                Label(court.nearestMetroName ?? localizedDistrictName(court.district) ?? "Метро не указано", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(court.address)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)

                HStack(spacing: 7) {
                    ForEach(court.displayTags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tag.contains(":") ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : .white.opacity(0.72))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        selectedCourtId = court.id
                        selectedCourtForDetail = court
                        AppHaptics.impact(.light)
                    } label: {
                        Text("Подробнее")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text("Тап по карточке покажет на карте")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.075), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selectedCourtId == court.id ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.48) : darkStroke, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Button {
                toggleSavedCourt(court)
                AppHaptics.selection()
            } label: {
                Image(systemName: savedCourtIDs.contains(court.id) ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onFocusMap(court)
        }
    }

    private func courtContactItems(for court: Court) -> [CourtContactItem] {
        var items: [CourtContactItem] = []

        if let bookingUrl = court.bookingLinkURL {
            items.append(
                CourtContactItem(
                    id: "booking-\(court.id)",
                    title: "Бронь",
                    icon: "calendar.badge.plus",
                    url: bookingUrl
                )
            )
        }

        if let phone = court.phone, let phoneURL = court.phoneURL {
            items.append(
                CourtContactItem(
                    id: "phone-\(court.id)",
                    title: phone,
                    icon: "phone.fill",
                    url: phoneURL
                )
            )
        }

        if let websiteHost = court.websiteHostLabel, let websiteURL = court.websiteLinkURL {
            items.append(
                CourtContactItem(
                    id: "site-\(court.id)",
                    title: websiteHost,
                    icon: "globe",
                    url: websiteURL
                )
            )
        }

        return items
    }

    private func loadCourts(forceRefresh: Bool = false) async {
        if !forceRefresh, !CourtsViewCache.courts.isEmpty {
            courts = CourtsViewCache.courts
            return
        }

        isLoadingCourts = courts.isEmpty
        defer {
            isLoadingCourts = false
        }

        do {
            let fetchedCourts = try await appModel.repository.fetchCourts()
            CourtsViewCache.courts = fetchedCourts
            courts = fetchedCourts
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func toggleSavedCourt(_ court: Court) {
        var ids = savedCourtIDs
        if ids.contains(court.id) {
            ids.remove(court.id)
        } else {
            ids.insert(court.id)
        }
        savedCourtIDsRaw = ids.sorted().joined(separator: ",")
    }
}

@MainActor
private enum CourtsViewCache {
    static var courts: [Court] = []
}

private struct TennisBallsLoader: View {
    let title: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    tennisBall(index: index)
                }
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .opacity(isAnimating ? 0.86 : 0.58)
        }
        .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }

    private func tennisBall(index: Int) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 212 / 255, green: 245 / 255, blue: 65 / 255),
                        Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 22, height: 22)
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.72), lineWidth: 1.4)
                    .frame(width: 4, height: 24)
                    .rotationEffect(.degrees(28))
            )
            .scaleEffect(isAnimating ? 1.04 : 0.76)
            .offset(y: isAnimating ? -10 : 10)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .shadow(
                color: Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(isAnimating ? 0.44 : 0.2),
                radius: isAnimating ? 14 : 6,
                x: 0,
                y: 6
            )
            .animation(
                .easeInOut(duration: 0.58)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.16),
                value: isAnimating
            )
        }
}

private struct CourtImageTile: View {
    let court: Court
    let size: CGFloat

    var body: some View {
        ZStack {
            if let photoUrl = court.photoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    sportTint(for: court.primarySport).opacity(0.78),
                    Color(red: 7 / 255, green: 20 / 255, blue: 18 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: sportSymbolName(for: court.primarySport ?? .tennis))
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.white.opacity(0.84))
        }
    }
}

private struct CourtDetailSheet: View {
    let court: Court
    let isSaved: Bool
    let onToggleSave: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 4 / 255, green: 13 / 255, blue: 13 / 255),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    titleBlock
                    actionGrid
                    metaRow
                    aboutBlock
                    sportsBlock
                    amenitiesBlock
                    proposeButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    private var hero: some View {
        CourtImageTile(court: court, size: UIScreen.main.bounds.width - 36)
            .frame(height: 250)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Button {
                        onToggleSave()
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)

                    if let url = court.websiteLinkURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                    }
                }
                .padding(14)
            }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(court.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let rating = court.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            Text(court.sportsTitle(fallback: nil))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))

            Label(
                [court.nearestMetroName, court.distanceLabel].compactMap { $0 }.joined(separator: " · "),
                systemImage: "mappin.and.ellipse"
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))

            Text(court.address)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
    }

    private var actionGrid: some View {
        HStack(spacing: 10) {
            CourtDetailActionButton(
                title: "Позвонить",
                subtitle: court.phone ?? "Нет номера",
                icon: "phone.fill",
                isEnabled: court.phoneURL != nil
            ) {
                open(court.phoneURL)
            }

            CourtDetailActionButton(
                title: "Забронировать",
                subtitle: court.websiteHostLabel ?? "Сайт не указан",
                icon: "globe",
                isEnabled: court.bookingLinkURL != nil
            ) {
                open(court.bookingLinkURL)
            }

            CourtDetailActionButton(
                title: "Сохранить",
                subtitle: isSaved ? "В избранном" : "В избранное",
                icon: isSaved ? "bookmark.fill" : "bookmark",
                isEnabled: true
            ) {
                onToggleSave()
                AppHaptics.selection()
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            CourtInfoPill(icon: "clock", title: court.workingHours ?? "Часы не указаны")
            CourtInfoPill(icon: "creditcard", title: court.priceRange ?? "Цена не указана")
        }
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("О клубе")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(court.detailDescription)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)
        }
    }

    private var sportsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Виды спорта")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach((court.supportedSports ?? [.tennis])) { sport in
                    HStack(spacing: 10) {
                        Image(systemName: sportSymbolName(for: sport))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                            .frame(width: 36, height: 36)
                            .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.14), in: Circle())
                        Text(sport.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var amenitiesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Удобства")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                ForEach(court.displayTags, id: \.self) { tag in
                    VStack(spacing: 8) {
                        Image(systemName: iconName(for: tag))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.64))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var proposeButton: some View {
        Button {
            AppHaptics.impact(.medium)
        } label: {
            VStack(spacing: 4) {
                Text("Предложить игру здесь")
                    .font(.system(size: 20, weight: .bold))
                Text("Найти игроков для игры в этом клубе")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.78)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                LinearGradient(
                    colors: [Color(red: 13 / 255, green: 128 / 255, blue: 79 / 255), Color(red: 38 / 255, green: 183 / 255, blue: 119 / 255)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        openURL(url)
        AppHaptics.selection()
    }

    private func iconName(for tag: String) -> String {
        let lowercased = tag.lowercased()
        if lowercased.contains("крыт") { return "rectangle.split.3x1" }
        if lowercased.contains("душ") { return "shower" }
        if lowercased.contains("каф") { return "cup.and.saucer" }
        if lowercased.contains("парков") { return "parkingsign" }
        if lowercased.contains("wi") { return "wifi" }
        if lowercased.contains("арен") { return "tennis.racket" }
        return "checkmark.circle"
    }
}

private struct CourtDetailActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : .white.opacity(0.28))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isEnabled ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : .white.opacity(0.36))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 98)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct CourtInfoPill: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct DistrictCourtsMapView: UIViewRepresentable {
    let courts: [Court]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsTraffic = false
        mapView.showsScale = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(mapView: mapView, courts: courts)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var hasSetVisibleRect = false

        func update(mapView: MKMapView, courts: [Court]) {
            let districtAreas = uniqueDistrictAreas(for: courts)

            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            mapView.removeOverlays(mapView.overlays)

            let annotations = courts.map(CourtAnnotation.init)
            mapView.addAnnotations(annotations)

            for area in districtAreas {
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                polygon.title = area.id
                mapView.addOverlay(polygon)
            }

            let targetRect = targetVisibleRect(annotations: annotations, districtAreas: districtAreas)
            guard !targetRect.isNull, !targetRect.isEmpty else {
                return
            }

            if !hasSetVisibleRect {
                hasSetVisibleRect = true
                mapView.setVisibleMapRect(
                    targetRect,
                    edgePadding: UIEdgeInsets(top: 56, left: 28, bottom: 56, right: 28),
                    animated: false
                )
            } else {
                mapView.setVisibleMapRect(
                    targetRect,
                    edgePadding: UIEdgeInsets(top: 56, left: 28, bottom: 56, right: 28),
                    animated: true
                )
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let overlayID = polygon.title ?? nil,
                  let area = districtAreasByID[overlayID] else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = area.color.withAlphaComponent(0.16)
            renderer.strokeColor = area.color.withAlphaComponent(0.7)
            renderer.lineWidth = 1.5
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? CourtAnnotation else {
                return nil
            }

            let reuseID = SportCourtAnnotationView.reuseID
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? SportCourtAnnotationView)
                ?? SportCourtAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        private func targetVisibleRect(annotations: [CourtAnnotation], districtAreas: [DistrictMapArea]) -> MKMapRect {
            let annotationRects = annotations.map {
                MKMapRect(
                    origin: MKMapPoint($0.coordinate),
                    size: MKMapSize(width: 0, height: 0)
                )
            }

            let overlayRects = districtAreas.map { area -> MKMapRect in
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                return polygon.boundingMapRect
            }

            return (annotationRects + overlayRects).reduce(MKMapRect.null) { partial, next in
                partial.isNull ? next : partial.union(next)
            }
        }
    }
}

private final class CourtAnnotation: NSObject, MKAnnotation {
    let court: Court
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(court: Court) {
        self.court = court
        coordinate = court.coordinate
        title = court.name
        subtitle = [localizedDistrictName(court.district), court.address]
            .compactMap { $0 }
            .joined(separator: " · ")
        super.init()
    }
}

private final class SportCourtAnnotationView: MKAnnotationView {
    static let reuseID = "SportCourtAnnotationView"

    override var annotation: MKAnnotation? {
        didSet {
            configure()
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        centerOffset = CGPoint(x: 0, y: -18)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        guard let annotation = annotation as? CourtAnnotation else {
            image = nil
            return
        }

        image = sportMarkerImage(for: annotation.court.primarySport)
    }
}

struct DistrictMapArea {
    let id: String
    let label: String
    let color: UIColor
    let rawPolygon: [(Double, Double)]

    var coordinates: [CLLocationCoordinate2D] {
        rawPolygon.map { longitude, latitude in
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

let districtAreasByID: [String: DistrictMapArea] = [
    "admiralteysky": DistrictMapArea(
        id: "admiralteysky",
        label: "Адмиралтейский",
        color: UIColor(hex: "#D47A45"),
        rawPolygon: [(30.225, 59.895), (30.35, 59.895), (30.345, 59.845), (30.24, 59.84)]
    ),
    "vasileostrovsky": DistrictMapArea(
        id: "vasileostrovsky",
        label: "Василеостровский",
        color: UIColor(hex: "#7B61FF"),
        rawPolygon: [(30.19, 59.962), (30.276, 59.962), (30.292, 59.925), (30.205, 59.913)]
    ),
    "vyborgsky": DistrictMapArea(
        id: "vyborgsky",
        label: "Выборгский",
        color: UIColor(hex: "#4B7BE5"),
        rawPolygon: [(30.205, 60.105), (30.435, 60.105), (30.43, 60.01), (30.235, 60.002)]
    ),
    "kalininsky": DistrictMapArea(
        id: "kalininsky",
        label: "Калининский",
        color: UIColor(hex: "#23A27A"),
        rawPolygon: [(30.292, 60.055), (30.497, 60.055), (30.478, 59.982), (30.32, 59.982)]
    ),
    "kirovsky": DistrictMapArea(
        id: "kirovsky",
        label: "Кировский",
        color: UIColor(hex: "#A8663A"),
        rawPolygon: [(30.142, 59.918), (30.301, 59.918), (30.305, 59.833), (30.16, 59.83)]
    ),
    "kolpinsky": DistrictMapArea(
        id: "kolpinsky",
        label: "Колпинский",
        color: UIColor(hex: "#B47BDA"),
        rawPolygon: [(30.46, 59.815), (30.72, 59.815), (30.74, 59.665), (30.49, 59.665)]
    ),
    "krasnogvardeysky": DistrictMapArea(
        id: "krasnogvardeysky",
        label: "Красногвардейский",
        color: UIColor(hex: "#B86482"),
        rawPolygon: [(30.345, 59.995), (30.535, 59.995), (30.54, 59.91), (30.36, 59.91)]
    ),
    "krasnoselsky": DistrictMapArea(
        id: "krasnoselsky",
        label: "Красносельский",
        color: UIColor(hex: "#D98B5C"),
        rawPolygon: [(29.98, 59.885), (30.265, 59.885), (30.27, 59.73), (30.03, 59.73)]
    ),
    "kronshtadtsky": DistrictMapArea(
        id: "kronshtadtsky",
        label: "Кронштадтский",
        color: UIColor(hex: "#4A92A2"),
        rawPolygon: [(29.64, 60.055), (29.86, 60.055), (29.86, 59.95), (29.64, 59.95)]
    ),
    "kurortny": DistrictMapArea(
        id: "kurortny",
        label: "Курортный",
        color: UIColor(hex: "#65A06C"),
        rawPolygon: [(29.76, 60.18), (30.24, 60.18), (30.24, 60.01), (29.78, 60.01)]
    ),
    "moskovsky": DistrictMapArea(
        id: "moskovsky",
        label: "Московский",
        color: UIColor(hex: "#C66A63"),
        rawPolygon: [(30.173, 59.925), (30.355, 59.925), (30.35, 59.81), (30.265, 59.81)]
    ),
    "nevsky": DistrictMapArea(
        id: "nevsky",
        label: "Невский",
        color: UIColor(hex: "#E85B7B"),
        rawPolygon: [(30.368, 59.926), (30.57, 59.926), (30.585, 59.848), (30.39, 59.84)]
    ),
    "petrogradsky": DistrictMapArea(
        id: "petrogradsky",
        label: "Петроградский",
        color: UIColor(hex: "#2F7A65"),
        rawPolygon: [(30.233, 59.983), (30.332, 59.983), (30.343, 59.948), (30.251, 59.942)]
    ),
    "petrodvortsovy": DistrictMapArea(
        id: "petrodvortsovy",
        label: "Петродворцовый",
        color: UIColor(hex: "#9B7A45"),
        rawPolygon: [(29.63, 59.95), (30.15, 59.95), (30.14, 59.78), (29.67, 59.78)]
    ),
    "primorsky": DistrictMapArea(
        id: "primorsky",
        label: "Приморский",
        color: UIColor(hex: "#548BFF"),
        rawPolygon: [(30.153, 60.04), (30.318, 60.04), (30.339, 59.982), (30.205, 59.956)]
    ),
    "pushkinsky": DistrictMapArea(
        id: "pushkinsky",
        label: "Пушкинский",
        color: UIColor(hex: "#8C9A4F"),
        rawPolygon: [(30.17, 59.79), (30.62, 59.79), (30.63, 59.57), (30.22, 59.57)]
    ),
    "frunzensky": DistrictMapArea(
        id: "frunzensky",
        label: "Фрунзенский",
        color: UIColor(hex: "#C76A5E"),
        rawPolygon: [(30.28, 59.91), (30.46, 59.91), (30.46, 59.81), (30.29, 59.81)]
    ),
    "central": DistrictMapArea(
        id: "central",
        label: "Центральный",
        color: UIColor(hex: "#D96A47"),
        rawPolygon: [(30.314, 59.948), (30.402, 59.948), (30.412, 59.917), (30.33, 59.907), (30.302, 59.924)]
    )
]

private func uniqueDistrictAreas(for courts: [Court]) -> [DistrictMapArea] {
    let districtIDs = Set(courts.compactMap { $0.district?.lowercased() })
    return districtIDs.compactMap { districtAreasByID[$0] }
}

func sportMarkerImage(for sport: Sport?) -> UIImage? {
    let sport = sport ?? .tennis
    let size = CGSize(width: 42, height: 52)
    let renderer = UIGraphicsImageRenderer(size: size)
    let color = sportUIColor(for: sport)
    let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
    let symbol = UIImage(systemName: sportSymbolName(for: sport), withConfiguration: symbolConfig)?
        .withTintColor(.white, renderingMode: .alwaysOriginal)

    return renderer.image { context in
        let badgeRect = CGRect(x: 5, y: 2, width: 32, height: 32)
        let tailPath = UIBezierPath()
        tailPath.move(to: CGPoint(x: 21, y: 48))
        tailPath.addLine(to: CGPoint(x: 14, y: 28))
        tailPath.addLine(to: CGPoint(x: 28, y: 28))
        tailPath.close()
        UIColor.white.setFill()
        tailPath.fill()

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = CGSize(width: 0, height: 4)

        context.cgContext.saveGState()
        context.cgContext.setShadow(offset: shadow.shadowOffset, blur: shadow.shadowBlurRadius, color: UIColor.black.withAlphaComponent(0.22).cgColor)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: badgeRect).fill()
        context.cgContext.restoreGState()

        color.setFill()
        UIBezierPath(ovalIn: badgeRect.insetBy(dx: 2, dy: 2)).fill()

        if let symbol {
            let symbolRect = CGRect(x: 10, y: 7, width: 22, height: 22)
            symbol.draw(in: symbolRect)
        }
    }
}

func sportSymbolName(for sport: Sport) -> String {
    switch sport {
    case .tableTennis:
        return "circle.grid.cross"
    case .tennis:
        return "tennis.racket"
    case .padel:
        return "sportscourt"
    case .squash:
        return "figure.racquetball"
    case .badminton:
        return "bird"
    case .volleyball:
        return "volleyball"
    case .fitness:
        return "dumbbell"
    case .boxing:
        return "figure.boxing"
    case .yoga:
        return "figure.mind.and.body"
    case .football:
        return "soccerball"
    }
}

private func sportTint(for sport: Sport?) -> Color {
    Color(sportUIColor(for: sport))
}

private func sportUIColor(for sport: Sport?) -> UIColor {
    guard let sport else {
        return UIColor(AppTheme.court)
    }

    switch sport {
    case .tennis:
        return UIColor(AppTheme.court)
    case .padel:
        return UIColor(red: 0.87, green: 0.63, blue: 0.16, alpha: 1)
    case .squash:
        return UIColor(red: 0.85, green: 0.47, blue: 0.22, alpha: 1)
    case .badminton:
        return UIColor(red: 0.24, green: 0.58, blue: 0.96, alpha: 1)
    case .football:
        return UIColor(red: 0.19, green: 0.63, blue: 0.37, alpha: 1)
    case .volleyball:
        return UIColor(red: 0.71, green: 0.53, blue: 0.18, alpha: 1)
    case .fitness:
        return UIColor(red: 0.49, green: 0.43, blue: 0.92, alpha: 1)
    case .boxing:
        return UIColor(red: 0.86, green: 0.27, blue: 0.23, alpha: 1)
    case .yoga:
        return UIColor(red: 0.49, green: 0.69, blue: 0.55, alpha: 1)
    case .tableTennis:
        return UIColor(red: 0.24, green: 0.62, blue: 0.78, alpha: 1)
    }
}

private extension Court {
    var primarySport: Sport? {
        supportedSports?.first
    }

    func sportsTitle(fallback: Sport?) -> String {
        let sports = supportedSports?.isEmpty == false ? supportedSports : fallback.map { [$0] }
        return (sports ?? [.tennis])
            .map(\.title)
            .joined(separator: " · ")
    }

    var displayTags: [String] {
        var tags: [String] = []

        if let workingHours, !workingHours.isEmpty {
            tags.append("Открыто: \(workingHours)")
        }

        if let supportedSports, supportedSports.contains(where: { [.tennis, .padel, .badminton, .squash, .tableTennis].contains($0) }) {
            tags.append("Крытые корты")
        }

        tags.append("Душевые")
        tags.append("Парковка")

        if bookingLinkURL != nil {
            tags.append("Онлайн-бронь")
        }

        return Array(tags.prefix(6))
    }

    var detailDescription: String {
        let sports = sportsTitle(fallback: nil).lowercased()
        let place = nearestMetroName ?? localizedDistrictName(district) ?? "Санкт-Петербурге"
        return "Клуб для игры в \(sports) рядом с \(place). Контакты и ссылка на бронирование вынесены выше, чтобы быстро связаться с клубом и уточнить свободное время."
    }

    var phoneURL: URL? {
        guard let phone else {
            return nil
        }

        let normalized = phone.filter { $0.isNumber || $0 == "+" }
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(string: "tel://\(normalized)")
    }

    var websiteLinkURL: URL? {
        guard let websiteUrl, let url = URL(string: websiteUrl) else {
            return nil
        }
        return url
    }

    var bookingLinkURL: URL? {
        guard let bookingUrl, let url = URL(string: bookingUrl) else {
            return websiteLinkURL
        }
        return url
    }

    var websiteHostLabel: String? {
        if let bookingHost = bookingLinkURL?.host, !bookingHost.isEmpty {
            return bookingHost.replacingOccurrences(of: "www.", with: "")
        }

        guard let host = websiteLinkURL?.host, !host.isEmpty else {
            return nil
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }
}

private struct CourtContactItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let url: URL?
}

private extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
