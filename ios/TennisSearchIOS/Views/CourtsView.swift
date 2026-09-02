import SwiftUI
import MapKit
import UIKit

struct CourtsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openURL) private var openURL
    private let initialSport: Sport?
    @State private var courts: [Court] = []
    @State private var query = ""
    @State private var displayMode: CentersDisplayMode = .list
    @State private var selectedCourtId: String?
    @State private var selectedSport: Sport?
    @State private var isLoadingCourts = false
    @State private var selectedCourtForDetail: Court?
    @State private var selectedCourtForSearch: Court?
    @State private var selectedCourtForPersonalVisit: Court?
    @State private var selectedCourtPlayerProposal: CourtPlayerProposalContext?
    @State private var focusedDistrictId: String?
    @State private var mapFocusRevision = 0
    @State private var focusesUserLocation = false
    @State private var showFavoritesOnly = false
    @StateObject private var locationProvider = UserLocationProvider()
    @AppStorage("savedCourtIDs") private var savedCourtIDsRaw = ""
    @FocusState private var isSearchFocused: Bool

    init(initialSport: Sport? = nil) {
        self.initialSport = initialSport
        _selectedSport = State(initialValue: initialSport)
    }

    private var coveredActiveCity: SupportedCity? {
        SupportedCity.resolve(appModel.currentUser?.city)
            ?? SupportedCity.resolve(appModel.guestDraft.city)
    }

    private var activeCityName: String {
        appModel.currentUser?.location?.city
            ?? appModel.currentUser?.city
            ?? appModel.guestDraft.location?.city
            ?? appModel.guestDraft.city
    }

    private var activeMapCenter: CLLocationCoordinate2D {
        if let location = appModel.currentUser?.location ?? appModel.guestDraft.location {
            return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        }
        return coveredActiveCity?.mapCenter ?? SupportedCity.saintPetersburg.mapCenter
    }

    private var activeMapDiameterMeters: CLLocationDistance {
        coveredActiveCity?.mapDiameterMeters ?? 50_000
    }

    private var clubsEnabledForActiveCity: Bool {
        appModel.currentUser?.location?.coverage.clubsEnabled
            ?? appModel.guestDraft.location?.coverage.clubsEnabled
            ?? (coveredActiveCity != nil)
    }

    private var courtsCacheKey: String {
        let user = appModel.currentUser
        return [
            activeCityName,
            user?.id ?? "guest",
            user?.district ?? "",
            (user?.preferredDistricts ?? []).joined(separator: ","),
            String(user?.searchRadiusKm ?? appModel.guestDraft.searchRadiusKm)
        ].joined(separator: "|")
    }

    private var cityCourts: [Court] {
        let normalizedActiveCity = activeCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return courts.filter { court in
            guard let courtCity = court.city?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !courtCity.isEmpty else { return false }
            if let coveredActiveCity, let coveredCourtCity = SupportedCity.resolve(courtCity) {
                return coveredCourtCity == coveredActiveCity
            }
            return courtCity.localizedCaseInsensitiveCompare(normalizedActiveCity) == .orderedSame
        }
    }

    private var sortedCourts: [Court] {
        let preferredDistricts = preferredDistrictIDs
        guard !preferredDistricts.isEmpty else {
            return cityCourts
        }

        return cityCourts.enumerated()
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
        let districtsEnabled = appModel.currentUser?.location.map(\.coverage.districtsEnabled)
            ?? appModel.guestDraft.location.map(\.coverage.districtsEnabled)
            ?? (coveredActiveCity != nil)
        guard districtsEnabled else {
            return []
        }

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
        let foundSports = Set(cityCourts.flatMap { $0.supportedSports ?? [] })
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
            searchableText(for: court).contains(normalizedQuery)
        }
    }

    private var suggestedCourts: [Court] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let prefixMatches = filteredCourts.filter { $0.name.lowercased().hasPrefix(normalizedQuery) }
        let metroMatches = filteredCourts.filter { court in
            guard let metro = court.metroDisplayName?.lowercased() else { return false }
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
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return suggestedCourts.first
        }

        return nil
    }

    private var mapPreviewCourts: [Court] {
        filteredCourts
    }

    private var mapSelectedCourt: Court? {
        focusedCourt ?? filteredCourts.first
    }

    private var savedCourtIDs: Set<String> {
        Set(savedCourtIDsRaw.split(separator: ",").map(String.init))
    }

    private func courtAccessLabel(_ court: Court) -> String? {
        if let currentCoordinate = locationProvider.coordinate {
            let distanceKm = haversineDistanceKm(from: currentCoordinate, to: court.coordinate)
            let distance = formattedDistance(distanceKm)
            let driveMinutes = estimatedDriveMinutes(distanceKm)
            return L10n.string(
                "\(distance) · \(driveMinutes) min by car",
                "\(distance) · на машине \(driveMinutes) мин"
            )
        }

        if LocaleStore.currentEffectiveLocale == .en, court.distanceLabel == "Рядом" {
            return "Nearby"
        }
        return court.distanceLabel
    }

    private func formattedDistance(_ distanceKm: Double) -> String {
        if distanceKm < 1 {
            return L10n.string(
                "\(max(Int((distanceKm * 1_000).rounded()), 50)) m",
                "\(max(Int((distanceKm * 1_000).rounded()), 50)) м"
            )
        }

        return String(
            format: L10n.string("%.1f km", "%.1f км"),
            locale: LocaleStore.currentEffectiveLocale.locale,
            distanceKm
        )
    }

    private func estimatedDriveMinutes(_ distanceKm: Double) -> Int {
        max(5, Int(ceil((distanceKm / 28) * 60 + 3)))
    }

    private var preferredDistrictId: String? {
        preferredDistrictIDs.first { districtAreasByID[$0.lowercased()] != nil }
    }

    private var preferredVisibleDistrictIDs: [String] {
        preferredDistrictIDs
            .map { $0.lowercased() }
            .filter { districtAreasByID[$0] != nil }
            .reduce(into: [String]()) { result, district in
                if !result.contains(district) {
                    result.append(district)
                }
            }
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
                TennisBallsLoader(title: L10n.string("Loading courts", "Загружаем центры"))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        searchField {
                            focusUserLocation()
                        }
                        suggestionsRail { court in
                            focusCourtOnMap(court)
                        }
                        displayModePicker
                        sportFilterRail

                        if displayMode == .list {
                            courtsListSection
                        } else {
                            mapModeSection
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
        .toolbar(.hidden, for: .navigationBar)
        .task(id: courtsCacheKey) {
            selectedCourtId = nil
            focusedDistrictId = nil
            focusesUserLocation = false
            await loadCourts()
        }
        .onAppear {
            isSearchFocused = false
            selectedSport = initialSport
        }
        .onReceive(locationProvider.$coordinate) { coordinate in
            guard focusesUserLocation, coordinate != nil else {
                return
            }
            mapFocusRevision += 1
        }
        .onReceive(locationProvider.$authorizationDenied) { isDenied in
            guard focusesUserLocation, isDenied else {
                return
            }
            focusesUserLocation = false
            appModel.errorMessage = L10n.string(
                "Allow location access in Settings to show your position on the map.",
                "Разрешите доступ к геолокации в настройках, чтобы показать вашу точку на карте."
            )
        }
        .onReceive(locationProvider.$locationFailureMessage) { message in
            guard focusesUserLocation, let message else {
                return
            }
            focusesUserLocation = false
            appModel.errorMessage = message
        }
        .sheet(item: $selectedCourtForDetail) { court in
            CourtDetailSheet(
                court: court,
                isSaved: savedCourtIDs.contains(court.id),
                accessLabel: courtAccessLabel(court),
                onToggleSave: {
                    toggleSavedCourt(court)
                },
                onToggleMembership: {
                    await setCourtMembership(court, isMember: !court.isMember)
                },
                onProposeGame: {
                    presentSearchComposer(for: court)
                },
                onPlanPersonalVisit: {
                    presentPersonalVisitComposer(for: court)
                },
                onProposeToPlayer: { player in
                    presentPlayerProposal(to: player, at: court)
                }
            )
            .presentationDetents([.height(650), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedCourtForSearch) { court in
            SearchComposerView(initialCourt: court, initialSport: selectedSport ?? court.primarySport) { search in
                selectedCourtForSearch = nil
                appModel.navigate(to: .discover(search.searchType == .hot ? .hot : .seeking, highlightedSearchID: search.id))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedCourtForPersonalVisit) { court in
            PersonalActivityComposerSheet(court: court, initialSport: selectedSport ?? court.primarySport) {
                selectedCourtForPersonalVisit = nil
                appModel.navigate(to: .discover(.upcoming))
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedCourtPlayerProposal) { context in
            GameProposalSheet(match: context.match, initialCourt: context.court) {
                selectedCourtPlayerProposal = nil
                await loadCourts(forceRefresh: true)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Centers", "Центры"))
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                Text(L10n.string(
                    "\(activeCityName) · clubs, courts, and classes",
                    "\(activeCityName) · клубы, корты и секции"
                ))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()
        }
    }

    private func searchField(onLocate: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text(L10n.string("Club, metro, district, or sport", "Клуб, метро, район или спорт"))
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
                Button {
                    onLocate()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                        .frame(width: 34, height: 34)
                        .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.13), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Show my area on the map", "Показать мой район на карте"))
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

    private func focusUserLocation() {
        isSearchFocused = false
        selectedCourtId = nil
        focusedDistrictId = nil
        focusesUserLocation = true
        displayMode = .map
        locationProvider.requestCurrentLocation()
        mapFocusRevision += 1
        AppHaptics.selection()
    }

    private func focusCourtOnMap(_ court: Court) {
        selectedCourtId = court.id
        focusedDistrictId = nil
        focusesUserLocation = false
        displayMode = .map
        mapFocusRevision += 1
        isSearchFocused = false
        AppHaptics.selection()
    }

    /// Открывает корт, выбранный на другом экране (например, в пустой колоде).
    private func openPendingCourtIfNeeded() {
        guard let pendingCourtID = appModel.pendingCourtID,
              let court = courts.first(where: { $0.id == pendingCourtID }) else {
            return
        }

        appModel.pendingCourtID = nil
        openCourtDetail(court)
    }

    private func openCourtDetail(_ court: Court) {
        selectedCourtId = court.id
        focusedDistrictId = nil
        focusesUserLocation = false
        mapFocusRevision += 1
        isSearchFocused = false
        selectedCourtForDetail = court
        AppHaptics.impact(.light)

        Task {
            await refreshCourtDetail(courtId: court.id)
        }
    }

    private func refreshCourtDetail(courtId: String) async {
        do {
            let freshCourt = try await appModel.repository.fetchCourt(courtId: courtId)
            updateCourt(freshCourt)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func requireAuthenticatedCourtAction() -> Bool {
        guard appModel.isAuthenticated else {
            selectedCourtForDetail = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                appModel.presentAuth(step: .email)
            }
            return false
        }

        return true
    }

    private func presentSearchComposer(for court: Court) {
        guard requireAuthenticatedCourtAction() else {
            return
        }

        selectedCourtForDetail = nil
        AppHaptics.impact(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            selectedCourtForSearch = court
        }
    }

    private func presentPersonalVisitComposer(for court: Court) {
        guard requireAuthenticatedCourtAction() else {
            return
        }

        selectedCourtForDetail = nil
        AppHaptics.impact(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            selectedCourtForPersonalVisit = court
        }
    }

    private func presentPlayerProposal(to player: DiscoverUser, at court: Court) {
        guard requireAuthenticatedCourtAction() else {
            return
        }

        AppHaptics.impact(.medium)
        Task {
            do {
                let match = try await appModel.repository.ensureMatch(userId: player.id)
                await MainActor.run {
                    selectedCourtForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        selectedCourtPlayerProposal = CourtPlayerProposalContext(court: court, match: match)
                    }
                }
            } catch {
                guard !error.isCancellationLike else {
                    return
                }
                await MainActor.run {
                    appModel.present(error: error)
                }
            }
        }
    }

    private func setCourtMembership(_ court: Court, isMember: Bool) async {
        guard requireAuthenticatedCourtAction() else {
            return
        }

        do {
            let updated = try await appModel.repository.setCourtMembership(courtId: court.id, isMember: isMember)
            updateCourt(updated)
            AppHaptics.notification(isMember ? .success : .warning)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func updateCourt(_ updated: Court) {
        if let index = courts.firstIndex(where: { $0.id == updated.id }) {
            courts[index] = updated
        }
        CourtsViewCache.entries[courtsCacheKey] = CourtsViewCache.Entry(courts: courts, loadedAt: Date())
        if selectedCourtForDetail?.id == updated.id {
            selectedCourtForDetail = updated
        }
    }

    private func searchableText(for court: Court) -> String {
        [
            court.name,
            court.city,
            court.address,
            court.metroDisplayName,
            localizedDistrictName(court.district),
            court.supportedSports?.map { [$0.title, $0.rawValue] }.flatMap { $0 }.joined(separator: " ")
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
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
                                Text(court.metroDisplayName ?? localizedDistrictName(court.district) ?? court.address)
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
                sportFilterChip(title: L10n.string("All", "Все"), sport: nil)

                ForEach(availableSports) { sport in
                    sportFilterChip(title: sport.title, sport: sport)
                }

                favoritesChip
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
                    SportIconView(
                        sport: sport,
                        color: isSelected ? .black : .white,
                        size: 14
                    )
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

    private var displayModePicker: some View {
        HStack(spacing: 4) {
            displayModeButton(.list, title: L10n.string("List", "Список"), icon: "list.bullet")
            displayModeButton(.map, title: L10n.string("Map", "Карта"), icon: "map.fill")
        }
        .padding(4)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(darkStroke, lineWidth: 1)
        )
    }

    private func displayModeButton(_ mode: CentersDisplayMode, title: String, icon: String) -> some View {
        let isSelected = displayMode == mode

        return Button {
            displayMode = mode
            isSearchFocused = false
            AppHaptics.selection()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : .white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected ? Color(red: 6 / 255, green: 82 / 255, blue: 52 / 255) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
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
                Text(L10n.string("Favorites", "Избранные"))
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

    private var mapModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                SearchClubPickerMapView(
                    courts: mapPreviewCourts,
                    focusedCourt: focusedCourt,
                    focusedDistrictID: focusedDistrictId,
                    highlightedDistrictIDs: mapHighlightedDistrictIDs,
                    focusRevision: mapFocusRevision,
                    annotationLimit: nil,
                    cityCenter: activeMapCenter,
                    cityDiameterMeters: activeMapDiameterMeters,
                    userCoordinate: focusesUserLocation ? locationProvider.coordinate : nil,
                    userDistrictLabel: locationProvider.districtName,
                    focusesUserLocation: focusesUserLocation,
                    showsDistrictReference: focusesUserLocation,
                    onSelectCourt: { courtId in
                        selectedCourtId = courtId
                        focusedDistrictId = nil
                        focusesUserLocation = false
                        mapFocusRevision += 1
                        AppHaptics.selection()
                    }
                )
                .frame(height: 520)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                LinearGradient(
                    colors: [.black.opacity(0.64), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)

                if let court = mapSelectedCourt {
                    mapSelectedCourtCard(court)
                        .padding(12)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(darkStroke, lineWidth: 1)
            )

            Button {
                focusUserLocation()
            } label: {
                Label(L10n.string("My location", "Моё местоположение"), systemImage: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(darkStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func mapSelectedCourtCard(_ court: Court) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CourtImageTile(court: court, size: 86)

                VStack(alignment: .leading, spacing: 5) {
                    Text(court.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(court.sportsTitle(fallback: selectedSport))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                        .lineLimit(1)

                    Text([court.metroDisplayName, courtAccessLabel(court)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)

                    Text(court.displayTags.prefix(3).joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }

            HStack(spacing: 10) {
                activeSearchBadge(for: court)
                Spacer()
                CourtActiveSearchAvatars(
                    users: court.activeSearchPreviewUsers,
                    overflowCount: max(court.activeSearchPlayersCount - court.activeSearchPreviewUsers.count, 0),
                    size: 26
                )
            }

            HStack(spacing: 10) {
                Button {
                    openCourtDetail(court)
                } label: {
                    Text(L10n.string("Details", "Подробнее"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    presentSearchComposer(for: court)
                } label: {
                    Text(L10n.string("Find a game", "Найти игру"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 12)
    }

    @ViewBuilder
    private var mapSummaryCard: some View {
        ZStack(alignment: .bottomLeading) {
            SearchClubPickerMapView(
                courts: mapPreviewCourts,
                focusedCourt: focusedCourt,
                focusedDistrictID: focusedDistrictId,
                highlightedDistrictIDs: mapHighlightedDistrictIDs,
                focusRevision: mapFocusRevision,
                annotationLimit: nil,
                cityCenter: activeMapCenter,
                cityDiameterMeters: activeMapDiameterMeters,
                userCoordinate: focusesUserLocation ? locationProvider.coordinate : nil,
                userDistrictLabel: locationProvider.districtName,
                focusesUserLocation: focusesUserLocation,
                showsDistrictReference: focusesUserLocation,
                onSelectCourt: { courtId in
                    selectedCourtId = courtId
                    focusedDistrictId = nil
                    focusesUserLocation = false
                    mapFocusRevision += 1
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
                Text(focusesUserLocation
                     ? L10n.string("You are here", "Вы здесь")
                     : L10n.string("On the map", "На карте"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(L10n.string("\(filteredCourts.count) centers", "\(filteredCourts.count) центров"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text(mapFocusSubtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(20)
            .allowsHitTesting(false)

            if let focusedCourt {
                Button {
                    selectedCourtForDetail = focusedCourt
                    AppHaptics.impact(.light)
                } label: {
                    HStack(spacing: 8) {
                        Text(L10n.string("Open details", "Открыть карточку"))
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
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(darkStroke, lineWidth: 1)
        )
    }

    private var mapHighlightedDistrictIDs: [String] {
        if focusesUserLocation, let districtID = locationProvider.districtID {
            return [districtID]
        }

        return focusedDistrictId == nil ? [] : preferredVisibleDistrictIDs
    }

    private var mapFocusSubtitle: String {
        if focusesUserLocation {
            let locationLabel = [locationProvider.cityName, locationProvider.districtName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return locationLabel.isEmpty ? activeCityName : locationLabel
        }

        if let focusedCourt {
            return focusedCourt.name
        }

        if let focusedDistrictId,
           let area = districtAreasByID[focusedDistrictId.lowercased()] {
            let labels = preferredVisibleDistrictIDs.compactMap { districtAreasByID[$0]?.label }
            return labels.isEmpty ? area.label : labels.prefix(3).joined(separator: ", ")
        }

        return activeCityName
    }

    private var courtsListSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(focusesUserLocation
                         ? L10n.string("Near you", "Рядом с вами")
                         : L10n.string("All centers", "Все центры"))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L10n.string("\(filteredCourts.count) centers found", "Найдено \(filteredCourts.count) центров"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Text(L10n.string("Sort", "Сортировка"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
            }

            if filteredCourts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    Text(cityCourts.isEmpty
                         ? L10n.string("There are no clubs in \(activeCityName) yet", "В \(activeCityName) пока нет клубов")
                         : L10n.string("Nothing found", "Ничего не найдено"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(cityCourts.isEmpty
                         ? L10n.string(
                            "Clubs have not been added yet, but you can already find partners in this city.",
                            "Клубы ещё не добавлены, но поиск партнёров в городе уже доступен."
                         )
                         : L10n.string("Try another sport or search query.", "Попробуйте другой вид спорта или запрос."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(darkStroke, lineWidth: 1))
            } else {
                ForEach(filteredCourts) { court in
                    courtCard(court)
                }
            }
        }
    }

    private func courtCard(_ court: Court) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CourtImageTile(court: court, size: 112)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(court.name)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            Text(court.sportsTitle(fallback: selectedSport))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Button {
                            toggleSavedCourt(court)
                            AppHaptics.selection()
                        } label: {
                            Image(systemName: savedCourtIDs.contains(court.id) ? "heart.fill" : "heart")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                    }

                    Text([localizedDistrictName(court.district), courtAccessLabel(court)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    Label(court.metroDisplayName ?? court.displayAddress, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        ForEach(court.displayTags.prefix(3), id: \.self) { tag in
                            CourtAmenityPill(title: tag)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 10) {
                activeSearchBadge(for: court)

                Spacer(minLength: 8)

                CourtActiveSearchAvatars(
                    users: court.activeSearchPreviewUsers,
                    overflowCount: max(court.activeSearchPlayersCount - court.activeSearchPreviewUsers.count, 0),
                    size: 28
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .padding(12)
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
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            openCourtDetail(court)
        }
    }

    private func activeSearchBadge(for court: Court) -> some View {
        let count = court.activeSearchPlayersCount > 0 ? court.activeSearchPlayersCount : court.activeSearchesCount
        let hasSearches = count > 0

        return HStack(spacing: 7) {
            Circle()
                .fill(hasSearches ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : Color.white.opacity(0.28))
                .frame(width: 8, height: 8)
            Text(hasSearches ? activeSearchText(count) : L10n.string("No active searches", "Нет активных поисков"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasSearches ? .white.opacity(0.82) : .white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private func activeSearchText(_ count: Int) -> String {
        if LocaleStore.currentEffectiveLocale == .en {
            return count == 1 ? "1 player is looking for a game" : "\(count) players are looking for a game"
        }
        return "\(count) \(playerPlural(count)) \(count == 1 ? "ищет" : "ищут") игру"
    }

    private func playerPlural(_ count: Int) -> String {
        let remainder100 = count % 100
        if (11...14).contains(remainder100) {
            return "игроков"
        }

        switch count % 10 {
        case 1:
            return "игрок"
        case 2, 3, 4:
            return "игрока"
        default:
            return "игроков"
        }
    }

    private func courtContactItems(for court: Court) -> [CourtContactItem] {
        var items: [CourtContactItem] = []

        if let bookingUrl = court.bookingLinkURL {
            items.append(
                CourtContactItem(
                    id: "booking-\(court.id)",
                    title: L10n.string("Book", "Бронь"),
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
        let city = activeCityName
        let cacheKey = courtsCacheKey
        guard clubsEnabledForActiveCity else {
            courts = []
            isLoadingCourts = false
            return
        }
        if !forceRefresh,
           let cachedEntry = CourtsViewCache.entries[cacheKey],
           Date().timeIntervalSince(cachedEntry.loadedAt) < CourtsViewCache.maxAge {
            courts = cachedEntry.courts
            return
        }

        courts = []
        isLoadingCourts = true
        defer {
            isLoadingCourts = false
        }

        do {
            let fetchedCourts = try await appModel.repository.fetchCourts(city: city)
            guard cacheKey == courtsCacheKey else {
                return
            }
            CourtsViewCache.entries[cacheKey] = CourtsViewCache.Entry(courts: fetchedCourts, loadedAt: Date())
            courts = fetchedCourts
            openPendingCourtIfNeeded()
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
    struct Entry {
        let courts: [Court]
        let loadedAt: Date
    }

    static let maxAge: TimeInterval = 60
    static var entries: [String: Entry] = [:]
}

private struct CourtPlayerProposalContext: Identifiable {
    let court: Court
    let match: MatchSummary

    var id: String {
        "\(court.id)-\(match.id)"
    }
}

private struct CentersMapOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum CentersDisplayMode: Equatable {
    case list
    case map
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

private struct CourtAmenityPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.white.opacity(0.055), in: Capsule())
    }
}

private struct CourtActiveSearchAvatars: View {
    let users: [DiscoverUser]
    let overflowCount: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(users.prefix(3).enumerated()), id: \.element.id) { _, user in
                RemoteAvatarView(name: user.displayName, path: user.avatarUrl, size: size)
                    .overlay(Circle().stroke(Color.black.opacity(0.72), lineWidth: 1.5))
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.72), lineWidth: 1.5))
            }
        }
        .opacity(users.isEmpty && overflowCount == 0 ? 0 : 1)
    }
}

struct CourtImageTile: View {
    let court: Court
    let size: CGFloat
    var showsCarousel = true

    private var photoURLs: [URL] {
        let urls = court.photoUrls.compactMap { resolveAppRemoteURL($0) }
        if !urls.isEmpty {
            return urls
        }

        return resolveAppRemoteURL(court.primaryPhotoUrl).map { [$0] } ?? []
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if photoURLs.isEmpty {
                fallback
            } else if showsCarousel, photoURLs.count > 1 {
                TabView {
                    ForEach(Array(photoURLs.enumerated()), id: \.offset) { _, url in
                        photo(url)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                photo(photoURLs[0])
            }

            if showsCarousel, photoURLs.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                    Text("\(photoURLs.count)")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.black.opacity(0.48), in: Capsule())
                .padding(8)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func photo(_ url: URL) -> some View {
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
        .frame(width: size, height: size)
        .clipped()
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
            SportIconView(
                sport: court.primarySport ?? .tennis,
                color: .white.opacity(0.84),
                size: size * 0.34
            )
        }
    }
}

private struct CourtDetailSheet: View {
    let court: Court
    let isSaved: Bool
    let accessLabel: String?
    let onToggleSave: () -> Void
    let onToggleMembership: () async -> Void
    let onProposeGame: () -> Void
    let onPlanPersonalVisit: () -> Void
    let onProposeToPlayer: (DiscoverUser) -> Void
    @Environment(\.openURL) private var openURL
    @State private var isUpdatingMembership = false
    @State private var selectedPlayerProfile: DiscoverUser?

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

            ViewThatFits(in: .vertical) {
                compactContent

                ScrollView(showsIndicators: false) {
                    compactContent
                }
            }
        }
        .sheet(item: $selectedPlayerProfile) { player in
            CourtPlayerProfileSheet(player: player, court: court) {
                selectedPlayerProfile = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    onProposeToPlayer(player)
                }
            }
            .presentationDetents([.fraction(0.68), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactHeader
            compactContactRail
            compactSummaryBlock
            compactActivityBlock
            membershipBlock
            compactFooterActions
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var compactHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            CourtImageTile(court: court, size: 118)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    Text(court.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Spacer(minLength: 4)

                    Button {
                        onToggleSave()
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(court.sportsTitle(fallback: nil))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .lineLimit(1)

                Text([court.metroDisplayName, accessLabel ?? court.distanceLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)

                Text(court.displayAddress)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var compactContactRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                CompactCourtAction(title: L10n.string("Book", "Бронь"), icon: "calendar.badge.plus", isEnabled: court.bookingLinkURL != nil) {
                    open(court.bookingLinkURL)
                }
                CompactCourtAction(title: L10n.string("Website", "Сайт"), icon: "globe", isEnabled: court.websiteLinkURL != nil) {
                    open(court.websiteLinkURL)
                }
                CompactCourtAction(title: L10n.string("Call", "Позвонить"), icon: "phone.fill", isEnabled: court.phoneURL != nil) {
                    open(court.phoneURL)
                }
                CompactCourtAction(title: court.messengerTitle, icon: "paperplane.fill", isEnabled: court.messengerLinkURL != nil) {
                    open(court.messengerLinkURL)
                }
            }
        }
    }

    private var compactSummaryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let workingHours = court.workingHours, !workingHours.isEmpty {
                    CourtInfoPill(icon: "clock", title: workingHours)
                }
                if let priceRange = court.priceRange, !priceRange.isEmpty {
                    CourtInfoPill(icon: "creditcard", title: priceRange)
                }
            }

            Text(court.detailDescription)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineSpacing(3)
                .lineLimit(3)

            if !court.displayTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(court.displayTags.prefix(6), id: \.self) { tag in
                            CourtAmenityPill(title: tag)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var compactActivityBlock: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(activeSearchPeopleCount > 0 ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : Color.white.opacity(0.28))
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSearchPeopleCount > 0
                         ? activeSearchLine
                         : L10n.string("No active searches yet", "Активных поисков пока нет"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(activeSearchPeopleCount > 0
                         ? L10n.string("Respond or create your own game", "Можно откликнуться или создать свою игру")
                         : L10n.string("Create a search at this club", "Создайте поиск в этом клубе"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            CourtActiveSearchAvatars(
                users: court.activeSearchPreviewUsers,
                overflowCount: max(activeSearchPeopleCount - court.activeSearchPreviewUsers.count, 0),
                size: 32
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var activeSearchPeopleCount: Int {
        court.activeSearchPlayersCount > 0 ? court.activeSearchPlayersCount : court.activeSearchesCount
    }

    private var activeSearchLine: String {
        if LocaleStore.currentEffectiveLocale == .en {
            return activeSearchPeopleCount == 1
                ? "1 player is looking for a game"
                : "\(activeSearchPeopleCount) players are looking for a game"
        }
        return "\(activeSearchPeopleCount) \(playerPlural(activeSearchPeopleCount)) \(activeSearchPeopleCount == 1 ? "ищет" : "ищут") игру"
    }

    private func playerPlural(_ count: Int) -> String {
        let remainder100 = count % 100
        if (11...14).contains(remainder100) {
            return "игроков"
        }

        switch count % 10 {
        case 1:
            return "игрок"
        case 2, 3, 4:
            return "игрока"
        default:
            return "игроков"
        }
    }

    private var compactPlayersBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Club players", "Игроки клуба"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if court.memberCount > 0 {
                    Text("\(court.memberCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

            if court.members.isEmpty {
                Text(court.isMember
                     ? L10n.string("You are the first to check in at this club.", "Вы первый отметились в этом клубе.")
                     : L10n.string("Check in if you play here.", "Отметьтесь, если ходите сюда."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(court.members.prefix(8)) { player in
                            compactPlayerChip(player)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func compactPlayerChip(_ player: DiscoverUser) -> some View {
        Button {
            AppHaptics.selection()
            selectedPlayerProfile = player
        } label: {
            VStack(spacing: 6) {
                RemoteAvatarView(name: player.displayName, path: player.avatarUrl, size: 44)
                Text(player.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .frame(width: 64)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var compactFooterActions: some View {
        HStack(spacing: 10) {
            Button {
                onPlanPersonalVisit()
            } label: {
                Label(L10n.string("Visit", "Визит"), systemImage: "figure.run.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onProposeGame()
            } label: {
                Label(L10n.string("Find a game", "Найти игру"), systemImage: "calendar.badge.plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var hero: some View {
        CourtPhotoHero(court: court)
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
                [court.metroDisplayName, accessLabel ?? court.distanceLabel].compactMap { $0 }.joined(separator: " · "),
                systemImage: "mappin.and.ellipse"
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))

            Text(court.displayAddress)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            CourtDetailActionButton(
                title: L10n.string("Call", "Позвонить"),
                subtitle: court.phone ?? L10n.string("No phone number", "Нет номера"),
                icon: "phone.fill",
                isEnabled: court.phoneURL != nil
            ) {
                open(court.phoneURL)
            }

            CourtDetailActionButton(
                title: L10n.string("Book", "Забронировать"),
                subtitle: court.bookingHostLabel ?? L10n.string("No online booking", "Нет онлайн-брони"),
                icon: "calendar.badge.plus",
                isEnabled: court.bookingLinkURL != nil
            ) {
                open(court.bookingLinkURL)
            }

            CourtDetailActionButton(
                title: L10n.string("Website", "Сайт"),
                subtitle: court.websiteHostLabel ?? L10n.string("Not provided", "Не указан"),
                icon: "globe",
                isEnabled: court.websiteLinkURL != nil
            ) {
                open(court.websiteLinkURL)
            }

            CourtDetailActionButton(
                title: court.messengerTitle,
                subtitle: court.messengerSubtitle,
                icon: "paperplane.fill",
                isEnabled: court.messengerLinkURL != nil
            ) {
                open(court.messengerLinkURL)
            }

            CourtDetailActionButton(
                title: L10n.string("Save", "Сохранить"),
                subtitle: isSaved
                    ? L10n.string("In favorites", "В избранном")
                    : L10n.string("Add to favorites", "В избранное"),
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
            CourtInfoPill(icon: "clock", title: court.workingHours ?? L10n.string("Hours not provided", "Часы не указаны"))
            CourtInfoPill(icon: "creditcard", title: court.priceRange ?? L10n.string("Price not provided", "Цена не указана"))
        }
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("About the club", "О клубе"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(court.detailDescription)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)
        }
    }

    private var membershipBlock: some View {
        Button {
            Task {
                isUpdatingMembership = true
                await onToggleMembership()
                isUpdatingMembership = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: court.isMember ? "checkmark.circle.fill" : "figure.tennis")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(court.isMember ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255) : .white.opacity(0.86))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.075), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(court.isMember
                         ? L10n.string("You play here", "Вы ходите сюда")
                         : L10n.string("I play here", "Я хожу сюда"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L10n.string("Players will see you in the club list and can invite you to a game.", "Игроки увидят вас в списке клуба и смогут предложить игру."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                if isUpdatingMembership {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: court.isMember ? "minus.circle" : "plus.circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(14)
            .background(Color.white.opacity(court.isMember ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(court.isMember ? Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.42) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingMembership)
    }

    private var playersBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Club players", "Игроки клуба"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if court.memberCount > 0 {
                    Text("\(court.memberCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

            if court.members.isEmpty {
                Text(court.isMember
                     ? L10n.string(
                        "You are the first to check in at this club. When other players join, you can propose a game from here.",
                        "Вы первый отметились в этом клубе. Когда появятся другие игроки, им можно будет предложить игру отсюда."
                     )
                     : L10n.string(
                        "No one has checked in yet. Check in if you play here so the club can start gathering players.",
                        "Пока никто не отметился. Отметьтесь, если ходите сюда, чтобы клуб начал собирать игроков."
                     ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(court.members.prefix(6)) { player in
                        courtPlayerRow(player)
                    }
                }
            }
        }
    }

    private func courtPlayerRow(_ player: DiscoverUser) -> some View {
        HStack(spacing: 12) {
            Button {
                AppHaptics.selection()
                selectedPlayerProfile = player
            } label: {
                HStack(spacing: 12) {
                    RemoteAvatarView(name: player.displayName, path: player.avatarUrl, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(courtPlayerSubtitle(player))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.88))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onProposeToPlayer(player)
            } label: {
                Text(L10n.string("Invite", "Предложить"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private struct CourtPlayerProfileSheet: View {
        @Environment(\.dismiss) private var dismiss
        let player: DiscoverUser
        let court: Court
        let onProposeGame: () -> Void

        private var courtSports: [Sport] {
            let supported = court.supportedSports ?? []
            return supported.isEmpty ? player.preferredSports : supported
        }

        private var commonSports: [Sport] {
            let supported = Set(courtSports)
            let common = player.preferredSports.filter { supported.contains($0) }
            return common.isEmpty ? Array(courtSports.prefix(4)) : common
        }

        private var primarySport: Sport {
            commonSports.first ?? court.primarySport ?? player.preferredSports.first ?? .tennis
        }

        private var levelSummary: String {
            guard let level = player.sportLevels[primarySport.rawValue] ?? player.tennisLevel else {
                return L10n.string("level not provided", "уровень не указан")
            }
            return "\(level)/10"
        }

        var body: some View {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            RemoteAvatarView(name: player.displayName, path: player.avatarUrl, size: 86)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(player.displayName)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)

                                Text([player.age.map { L10n.string("\($0) years old", "\($0) лет") }, player.city].compactMap { $0 }.joined(separator: ", "))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.62))

                                Text(player.districtDisplaySummary)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.court)
                                    .lineLimit(2)
                            }
                        }

                        if let bio = player.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineSpacing(3)
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.string("At this club", "В этом клубе"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 10) {
                            SportIconView(sport: primarySport, color: AppTheme.court, size: 20)
                                .frame(width: 42, height: 42)
                                .background(Color.white.opacity(0.08), in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(court.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text("\(commonSports.map(\.title).joined(separator: " · ")) · \(levelSummary)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(2)
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button {
                            AppHaptics.impact(.medium)
                            dismiss()
                            onProposeGame()
                        } label: {
                            Label(L10n.string("Invite to a game here", "Предложить игру здесь"), systemImage: "calendar.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(AppTheme.court, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    private func courtPlayerSubtitle(_ player: DiscoverUser) -> String {
        let sport = player.preferredSports.first?.title ?? court.primarySport?.title ?? L10n.string("Sport", "Спорт")
        let district = player.districtLabel ?? localizedDistrictName(player.district) ?? L10n.string("area not provided", "район не указан")
        return "\(sport) · \(district)"
    }

    private var sportsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Sports", "Виды спорта"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach((court.supportedSports ?? [.tennis])) { sport in
                    HStack(spacing: 10) {
                        SportIconView(
                            sport: sport,
                            color: Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255),
                            size: 18
                        )
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
            Text(L10n.string("Amenities", "Удобства"))
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
            onProposeGame()
        } label: {
            VStack(spacing: 4) {
                Text(L10n.string("Create an urgent search here", "Создать срочный поиск здесь"))
                    .font(.system(size: 20, weight: .bold))
                Text(L10n.string("Find players for a game at this club", "Найти игроков для игры в этом клубе"))
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

    private var personalVisitButton: some View {
        Button {
            onPlanPersonalVisit()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255))
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Plan a visit", "Запланировать визит"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L10n.string("Without searching for players: practice, court time, or an individual session.", "Без поиска игроков: тренировка, зал или индивидуальная игра."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(16)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(0.28), lineWidth: 1)
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

private struct PersonalActivityComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let court: Court
    let onCreated: () -> Void

    @State private var selectedSport: Sport
    @State private var selectedDate: Date
    @State private var selectedTime = "09:00"
    @State private var durationMinutes: Int
    @State private var comment = ""
    @State private var isSaving = false

    private var availableSports: [Sport] {
        let sports = court.supportedSports ?? []
        return sports.isEmpty ? [.tennis] : sports
    }

    private var quickTimes: [String] {
        stride(from: 9 * 60, through: 23 * 60 + 30, by: 30)
            .map { minutes in
                String(format: "%02d:%02d", minutes / 60, minutes % 60)
            }
    }

    init(court: Court, initialSport: Sport?, onCreated: @escaping () -> Void) {
        self.court = court
        self.onCreated = onCreated
        let sports = court.supportedSports ?? []
        let resolvedSport = initialSport.flatMap { sports.isEmpty || sports.contains($0) ? $0 : nil } ?? sports.first ?? .tennis
        _selectedSport = State(initialValue: resolvedSport)
        _durationMinutes = State(initialValue: resolvedSport.defaultDurationMinutes)
        _selectedDate = State(initialValue: Self.defaultVisitDate())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    courtBlock
                    sportSection
                    dateSection
                    timeSection
                    durationSection
                    commentSection
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()
            Text(L10n.string("Personal visit", "Личный визит"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private var courtBlock: some View {
        HStack(spacing: 14) {
            CourtImageTile(court: court, size: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(court.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text([court.metroDisplayName, localizedDistrictName(court.district)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .lineLimit(2)
                Text(court.displayAddress)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var sportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("What are you planning?", "Что планируете?"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableSports) { sport in
                        let selected = selectedSport == sport
                        Button {
                            selectedSport = sport
                            durationMinutes = sport.defaultDurationMinutes
                            AppHaptics.selection()
                        } label: {
                            HStack(spacing: 8) {
                                SportIconView(sport: sport, color: selected ? .black : .white, size: 15)
                                Text(sport.title)
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(selected ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(selected ? AppTheme.court : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        FieldShell(title: L10n.string("Date", "Дата")) {
            DatePicker(
                "",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppTheme.court)
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Time", "Время"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickTimes, id: \.self) { time in
                        let selected = selectedTime == time
                        Button {
                            selectedTime = time
                            AppHaptics.selection()
                        } label: {
                            Text(time)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(selected ? .black : .white)
                                .frame(width: 84, height: 48)
                                .background(selected ? AppTheme.court : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selected ? AppTheme.court.opacity(0.42) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var durationSection: some View {
        FieldShell(title: L10n.string("Duration", "Длительность")) {
            Stepper(value: $durationMinutes, in: 15 ... 360, step: 15) {
                Text(L10n.string("\(durationMinutes) min", "\(durationMinutes) мин"))
                    .font(.headline)
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Note", "Заметка"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            TextField(L10n.string("For example: leg workout, 40 minutes on the track", "Например: тренировка ног, дорожка 40 минут"), text: $comment, axis: .vertical)
                .lineLimit(3 ... 5)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(isSaving
                     ? L10n.string("Saving...", "Сохраняем...")
                     : L10n.string("Plan visit", "Запланировать визит"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))
        .disabled(isSaving)
    }

    private func save() async {
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await appModel.repository.createPersonalActivity(
                PersonalActivityDraft(
                    courtId: court.id,
                    sport: selectedSport,
                    scheduledAt: combinedDateTime,
                    durationMinutes: durationMinutes,
                    comment: comment
                )
            )
            AppHaptics.notification(.success)
            onCreated()
            dismiss()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private var combinedDateTime: Date {
        let calendar = Calendar.current
        let timeParts = selectedTime.split(separator: ":").compactMap { Int($0) }
        return calendar.date(
            bySettingHour: timeParts.first ?? 9,
            minute: timeParts.dropFirst().first ?? 0,
            second: 0,
            of: selectedDate
        ) ?? selectedDate
    }

    private static func defaultVisitDate() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60)
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

private struct CourtPhotoHero: View {
    let court: Court

    private var urls: [URL] {
        court.photoUrls.compactMap { resolveAppRemoteURL($0) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if urls.isEmpty {
                CourtImageTile(court: court, size: UIScreen.main.bounds.width - 36)
            } else {
                TabView {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                CourtImageTile(court: court, size: UIScreen.main.bounds.width - 36, showsCarousel: false)
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            }

            if urls.count > 1 {
                Text(L10n.string("\(urls.count) photos", "\(urls.count) фото"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipped()
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

private struct CompactCourtAction: View {
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.34))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white.opacity(isEnabled ? 0.075 : 0.04), in: Capsule())
                .overlay(
                    Capsule()
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
        subtitle = [localizedDistrictName(court.district), court.displayAddress]
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

private final class UserLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var districtID: String?
    @Published var districtName: String?
    @Published var cityName: String?
    @Published var authorizationDenied = false
    @Published var locationFailureMessage: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        geocoder.cancelGeocode()
        authorizationDenied = false
        locationFailureMessage = nil
        coordinate = nil
        districtID = nil
        districtName = nil
        cityName = nil
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        coordinate = location.coordinate
        let nearestCity = Self.nearestSupportedCity(to: location.coordinate)
        let polygonDistrictID = Self.districtID(containing: location.coordinate, city: nearestCity)

        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else {
                return
            }

            guard let placemark = placemarks?.first else {
                DispatchQueue.main.async {
                    self.cityName = nearestCity?.rawValue
                    self.districtID = polygonDistrictID
                    self.districtName = localizedDistrictName(polygonDistrictID)
                        ?? L10n.string("Area not identified", "Район не определён")
                }
                return
            }

            let city = [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea]
                .compactMap(SupportedCity.resolve)
                .first
            let resolvedCity = city ?? nearestCity
            let resolvedDistrict = [placemark.subLocality, placemark.subAdministrativeArea]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && SupportedCity.resolve($0) == nil }
            let geocodedDistrictID = resolvedDistrictID(forDisplayName: resolvedDistrict, city: resolvedCity)
            let cityPolygonDistrictID = Self.districtID(containing: location.coordinate, city: resolvedCity)

            DispatchQueue.main.async {
                self.cityName = resolvedCity?.rawValue
                self.districtID = geocodedDistrictID
                    ?? cityPolygonDistrictID
                    ?? polygonDistrictID
                self.districtName = self.districtID.flatMap(localizedDistrictName) ?? resolvedDistrict
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.coordinate = nil
            self.districtID = nil
            self.districtName = nil
            self.cityName = nil
            self.locationFailureMessage = L10n.string("Could not determine your location. Try again.", "Не удалось определить геопозицию. Попробуйте ещё раз.")
        }
    }

    private static func districtID(
        containing coordinate: CLLocationCoordinate2D,
        city: SupportedCity?
    ) -> String? {
        districtAreasByID.values
            .filter { area in
                city.map { area.city == $0 } ?? true
            }
            .filter { area in
                contains(coordinate, in: area.rawPolygon)
            }
            .min { left, right in
                haversineDistanceKm(from: coordinate, to: center(of: left))
                    < haversineDistanceKm(from: coordinate, to: center(of: right))
            }?
            .id
    }

    private static func center(of area: DistrictMapArea) -> CLLocationCoordinate2D {
        let count = Double(max(area.rawPolygon.count, 1))
        let longitude = area.rawPolygon.reduce(0) { $0 + $1.0 } / count
        let latitude = area.rawPolygon.reduce(0) { $0 + $1.1 } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func nearestSupportedCity(to coordinate: CLLocationCoordinate2D) -> SupportedCity? {
        SupportedCity.selectableCases
            .map { city in
                (city, haversineDistanceKm(from: coordinate, to: city.mapCenter))
            }
            .filter { city, distanceKm in
                distanceKm <= city.mapDiameterMeters / 1_000
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func contains(_ coordinate: CLLocationCoordinate2D, in polygon: [(Double, Double)]) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = polygon.count - 1

        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let intersectsLatitude = (current.1 > coordinate.latitude) != (previous.1 > coordinate.latitude)

            if intersectsLatitude {
                let projectedLongitude = (previous.0 - current.0)
                    * (coordinate.latitude - current.1)
                    / (previous.1 - current.1)
                    + current.0
                if coordinate.longitude < projectedLongitude {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }
}

func haversineDistanceKm(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
    let radius = 6_371.0
    let lat1 = start.latitude * .pi / 180
    let lat2 = end.latitude * .pi / 180
    let deltaLat = (end.latitude - start.latitude) * .pi / 180
    let deltaLon = (end.longitude - start.longitude) * .pi / 180
    let a = sin(deltaLat / 2) * sin(deltaLat / 2)
        + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return radius * c
}

struct DistrictMapArea {
    let id: String
    let label: String
    let color: UIColor
    let city: SupportedCity
    let rawPolygon: [(Double, Double)]

    init(
        id: String,
        label: String,
        color: UIColor,
        city: SupportedCity = .saintPetersburg,
        rawPolygon: [(Double, Double)]
    ) {
        self.id = id
        self.label = label
        self.color = color
        self.city = city
        self.rawPolygon = rawPolygon
    }

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
    ),
    "moscow_central": DistrictMapArea(
        id: "moscow_central",
        label: "Центральный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.545, 55.795), (37.626, 55.805), (37.704, 55.775), (37.694, 55.713), (37.620, 55.695), (37.548, 55.724)]
    ),
    "moscow_northern": DistrictMapArea(
        id: "moscow_northern",
        label: "Северный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.455, 55.925), (37.545, 55.965), (37.665, 55.945), (37.704, 55.806), (37.626, 55.805), (37.545, 55.795), (37.475, 55.825)]
    ),
    "moscow_northeastern": DistrictMapArea(
        id: "moscow_northeastern",
        label: "Северо-Восточный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.665, 55.945), (37.835, 55.925), (37.850, 55.830), (37.704, 55.775), (37.704, 55.806)]
    ),
    "moscow_eastern": DistrictMapArea(
        id: "moscow_eastern",
        label: "Восточный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.850, 55.830), (37.955, 55.820), (37.970, 55.705), (37.815, 55.675), (37.694, 55.713), (37.704, 55.775)]
    ),
    "moscow_southeastern": DistrictMapArea(
        id: "moscow_southeastern",
        label: "Юго-Восточный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.694, 55.713), (37.815, 55.675), (37.855, 55.585), (37.710, 55.565), (37.625, 55.650), (37.620, 55.695)]
    ),
    "moscow_southern": DistrictMapArea(
        id: "moscow_southern",
        label: "Южный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.620, 55.695), (37.625, 55.650), (37.710, 55.565), (37.650, 55.515), (37.500, 55.560), (37.515, 55.650), (37.548, 55.724)]
    ),
    "moscow_southwestern": DistrictMapArea(
        id: "moscow_southwestern",
        label: "Юго-Западный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.548, 55.724), (37.515, 55.650), (37.500, 55.560), (37.355, 55.560), (37.350, 55.665), (37.455, 55.735)]
    ),
    "moscow_western": DistrictMapArea(
        id: "moscow_western",
        label: "Западный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.455, 55.825), (37.545, 55.795), (37.548, 55.724), (37.455, 55.735), (37.350, 55.665), (37.260, 55.700), (37.285, 55.805)]
    ),
    "moscow_northwestern": DistrictMapArea(
        id: "moscow_northwestern",
        label: "Северо-Западный административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.285, 55.805), (37.455, 55.825), (37.455, 55.925), (37.315, 55.930), (37.235, 55.875)]
    ),
    "moscow_zelenograd": DistrictMapArea(
        id: "moscow_zelenograd",
        label: "Зеленоградский административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.130, 56.030), (37.270, 56.030), (37.285, 55.945), (37.145, 55.940)]
    ),
    "moscow_novomoskovsky": DistrictMapArea(
        id: "moscow_novomoskovsky",
        label: "Новомосковский административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.260, 55.700), (37.350, 55.665), (37.355, 55.560), (37.500, 55.560), (37.410, 55.425), (37.185, 55.465)]
    ),
    "moscow_troitsky": DistrictMapArea(
        id: "moscow_troitsky",
        label: "Троицкий административный округ",
        color: UIColor(hex: "#24D68A"),
        city: .moscow,
        rawPolygon: [(37.185, 55.465), (37.410, 55.425), (37.345, 55.230), (36.815, 55.220), (36.905, 55.455)]
    ),
    "kazan_aviastroitelny": DistrictMapArea(
        id: "kazan_aviastroitelny",
        label: "Авиастроительный",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.045, 55.925), (49.205, 55.925), (49.205, 55.855), (49.105, 55.835), (49.025, 55.865)]
    ),
    "kazan_vakhitovsky": DistrictMapArea(
        id: "kazan_vakhitovsky",
        label: "Вахитовский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.060, 55.815), (49.145, 55.825), (49.195, 55.770), (49.145, 55.730), (49.055, 55.750)]
    ),
    "kazan_kirovsky": DistrictMapArea(
        id: "kazan_kirovsky",
        label: "Кировский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(48.825, 55.900), (49.025, 55.865), (49.060, 55.815), (49.055, 55.750), (48.865, 55.730), (48.765, 55.815)]
    ),
    "kazan_moskovsky": DistrictMapArea(
        id: "kazan_moskovsky",
        label: "Московский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.025, 55.865), (49.105, 55.835), (49.120, 55.795), (49.060, 55.815), (48.930, 55.825)]
    ),
    "kazan_novo_savinovsky": DistrictMapArea(
        id: "kazan_novo_savinovsky",
        label: "Ново-Савиновский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.105, 55.835), (49.245, 55.850), (49.260, 55.785), (49.195, 55.770), (49.145, 55.825)]
    ),
    "kazan_privolzhsky": DistrictMapArea(
        id: "kazan_privolzhsky",
        label: "Приволжский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.055, 55.750), (49.145, 55.730), (49.250, 55.655), (49.145, 55.585), (48.930, 55.640), (48.865, 55.730)]
    ),
    "kazan_sovetsky": DistrictMapArea(
        id: "kazan_sovetsky",
        label: "Советский",
        color: UIColor(hex: "#24D68A"),
        city: .kazan,
        rawPolygon: [(49.195, 55.770), (49.260, 55.785), (49.385, 55.775), (49.410, 55.650), (49.250, 55.655), (49.145, 55.730)]
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
    sport.appSystemIconName
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
    case .running:
        return UIColor(red: 0.13, green: 0.71, blue: 0.49, alpha: 1)
    case .supboard:
        return UIColor(red: 0.13, green: 0.58, blue: 0.78, alpha: 1)
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

extension Court {
    var primarySport: Sport? {
        supportedSports?.first
    }

    func sportsTitle(fallback: Sport?) -> String {
        let sports = supportedSports?.isEmpty == false ? supportedSports : fallback.map { [$0] }
        return (sports ?? [.tennis])
            .map(\.title)
            .joined(separator: " · ")
    }

    var displayAddress: String {
        guard let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return address
        }

        if address.localizedCaseInsensitiveContains(city) {
            return address
        }

        return "\(city), \(address)"
    }

    var displayTags: [String] {
        if !amenities.isEmpty {
            return Array(amenities.prefix(8))
        }

        var tags: [String] = []

        if let workingHours, !workingHours.isEmpty {
            tags.append(L10n.string("Open: \(workingHours)", "Открыто: \(workingHours)"))
        }

        if let supportedSports, supportedSports.contains(where: { [.tennis, .padel, .badminton, .squash, .tableTennis].contains($0) }) {
            tags.append(L10n.string("Indoor courts", "Крытые корты"))
        }

        tags.append(L10n.string("Showers", "Душевые"))
        tags.append(L10n.string("Parking", "Парковка"))

        if bookingLinkURL != nil {
            tags.append(L10n.string("Online booking", "Онлайн-бронь"))
        }

        return Array(tags.prefix(6))
    }

    var detailDescription: String {
        if let about, !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return about
        }

        let sports = sportsTitle(fallback: nil).lowercased()
        let place = metroDisplayName ?? localizedDistrictName(district) ?? L10n.string("Saint Petersburg", "Санкт-Петербурге")
        return L10n.string(
            "A club for \(sports) near \(place). Contact details and the booking link are shown above so you can quickly check availability.",
            "Клуб для игры в \(sports) рядом с \(place). Контакты и ссылка на бронирование вынесены выше, чтобы быстро связаться с клубом и уточнить свободное время."
        )
    }

    var websiteLinkURL: URL? {
        guard let websiteUrl, let url = URL(string: websiteUrl) else {
            return nil
        }
        return url
    }

    var bookingLinkURL: URL? {
        guard let bookingUrl, let url = URL(string: bookingUrl) else {
            return nil
        }
        return url
    }

    var messengerLinkURL: URL? {
        guard let messengerUrl, let url = URL(string: messengerUrl) else {
            return nil
        }
        return url
    }

    var messengerTitle: String {
        switch messengerType?.lowercased() {
        case "telegram", "tg":
            return "Telegram"
        case "max":
            return L10n.string("MAX", "МАКС")
        default:
            return L10n.string("Messenger", "Мессенджер")
        }
    }

    var messengerSubtitle: String {
        guard messengerLinkURL != nil else {
            return L10n.string("Not specified", "Не указан")
        }

        return L10n.string("Message", "Написать")
    }

    var websiteHostLabel: String? {
        guard let host = websiteLinkURL?.host, !host.isEmpty else {
            return nil
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }

    var bookingHostLabel: String? {
        guard let host = bookingLinkURL?.host, !host.isEmpty else {
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
