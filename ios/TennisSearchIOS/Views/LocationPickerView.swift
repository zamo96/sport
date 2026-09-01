import CoreLocation
import SwiftUI

struct GlobalLocationPickerSheet: View {
    private enum Screen {
        case countries
        case cities
        case detected
    }

    let repository: TennisRepository
    let initialLocation: GeoPlace?
    let automaticallyRequestsLocation: Bool
    let onSelect: (GeoPlace, LocationSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeStore: LocaleStore
    @StateObject private var locationProvider = GlobalLocationProvider()
    @State private var screen: Screen = .countries
    @State private var countries: [GeoCountry] = []
    @State private var citySuggestions: [GeoPlace] = []
    @State private var citySearchResults: [GeoPlace] = []
    @State private var selectedCountry: GeoCountry?
    @State private var detectedPlace: GeoPlace?
    @State private var countryQuery = ""
    @State private var cityQuery = ""
    @State private var isLoading = false
    @State private var didLoadCitySuggestions = false
    @State private var didSearchCities = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                switch screen {
                case .countries:
                    countriesScreen
                case .cities:
                    citiesScreen
                case .detected:
                    detectedScreen
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadCountries()
            if automaticallyRequestsLocation, initialLocation == nil {
                isLoading = true
                locationProvider.request()
            }
        }
        .onChange(of: locationProvider.detectedCoordinate) { coordinate in
            guard let coordinate else { return }
            Task { await reverseGeocode(coordinate.value) }
        }
        .onChange(of: locationProvider.failureMessage) { message in
            guard message != nil else { return }
            isLoading = false
            errorMessage = l(
                "Location is unavailable. Choose a country and city manually.",
                "Геопозиция недоступна. Выберите страну и город вручную."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if screen != .countries {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screen = screen == .detected ? .countries : .countries
                            detectedPlace = nil
                            errorMessage = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(l("Close", "Закрыть")) { dismiss() }
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)

            Text(headerTitle)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(headerSubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var countriesScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    errorMessage = nil
                    isLoading = true
                    locationProvider.request()
                } label: {
                    locationRow(
                        title: isLoading ? l("Finding your location", "Определяем местоположение") : l("Use my location", "Определить автоматически"),
                        subtitle: l("We will show the country and city before saving.", "Покажем найденные страну и город перед сохранением"),
                        systemImage: "location.fill",
                        showsChevron: !isLoading
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)

                        if countries.isEmpty {
                            Button(l("Try again", "Повторить")) {
                                Task { await loadCountries() }
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                searchField(l("Search for a country", "Найти страну"), text: $countryQuery)

                if isLoading && countries.isEmpty {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 28)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredCountries) { country in
                            Button {
                                selectedCountry = country
                                cityQuery = ""
                                citySuggestions = []
                                citySearchResults = []
                                didLoadCitySuggestions = false
                                didSearchCities = false
                                errorMessage = nil
                                withAnimation(.easeInOut(duration: 0.2)) { screen = .cities }
                                Task { await loadCitySuggestions(for: country) }
                            } label: {
                                locationRow(
                                    title: country.name,
                                    subtitle: country.code,
                                    systemImage: "globe.europe.africa.fill",
                                    leadingText: country.flagEmoji,
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var citiesScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedCountry {
                    HStack(spacing: 8) {
                        Text(selectedCountry.flagEmoji)
                            .font(.system(size: 24))
                        Text(selectedCountry.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    searchField(l("Search for a city", "Найти город"), text: $cityQuery)
                        .onSubmit { Task { await loadCities() } }
                        .submitLabel(.search)
                        .onChange(of: cityQuery) { _ in
                            citySearchResults = []
                            didSearchCities = false
                            errorMessage = nil
                        }

                    Button {
                        Task { await loadCities() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 50, height: 50)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isLoading)
                }

                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 28)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)

                        Button(l("Try again", "Повторить")) {
                            Task {
                                if cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   let selectedCountry {
                                    await loadCitySuggestions(for: selectedCountry)
                                } else {
                                    await loadCities()
                                }
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                } else if displayedCities.isEmpty {
                    Text(emptyCitiesMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? l("Major cities", "Крупные города")
                             : l("Search results", "Результаты поиска"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.52))

                        LazyVStack(spacing: 10) {
                            ForEach(displayedCities) { place in
                                Button { select(place, source: .manual) } label: {
                                    locationRow(
                                        title: place.city,
                                        subtitle: place.displaySubtitle,
                                        systemImage: "building.2.fill",
                                        showsChevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Link(destination: URL(string: "https://simplemaps.com/data/world-cities")!) {
                    HStack(spacing: 5) {
                        Text(l("City data: SimpleMaps", "Данные о городах: SimpleMaps"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var detectedScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(.green)

            if let place = detectedPlace {
                VStack(spacing: 7) {
                    Text(l("Is \(place.city) your city?", "Ваш город — \(place.city)?"))
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(place.displaySubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Button(l("Yes, that's right", "Да, всё верно")) { select(place, source: .geolocation) }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 18))

                Button(l("Choose manually", "Выбрать вручную")) {
                    detectedPlace = nil
                    withAnimation(.easeInOut(duration: 0.2)) { screen = .countries }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private func searchField(_ prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.48))
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .tint(.green)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
    }

    private func locationRow(
        title: String,
        subtitle: String,
        systemImage: String,
        leadingText: String? = nil,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 13) {
            Group {
                if let leadingText {
                    Text(leadingText)
                        .font(.system(size: 27))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.14), in: Circle())
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline.weight(.bold)).foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.54))
                }
            }
            Spacer(minLength: 4)
            if isLoading && systemImage == "location.fill" {
                ProgressView().tint(.white)
            } else if showsChevron {
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10)))
    }

    private var filteredCountries: [GeoCountry] {
        let query = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedCities: [GeoPlace] {
        cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? citySuggestions
            : citySearchResults
    }

    private var emptyCitiesMessage: String {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return didLoadCitySuggestions
                ? l("No city suggestions are ready for this country yet. Search by name.", "Для этой страны пока нет готовых предложений. Найдите город по названию.")
                : l("Loading available cities…", "Загружаем доступные города…")
        }
        if query.count < 2 {
            return l("Enter at least 2 characters and tap search.", "Введите минимум 2 символа и нажмите кнопку поиска")
        }
        return didSearchCities
            ? l("City not found. Check the spelling.", "Город не найден. Проверьте написание.")
            : l("Tap search to find a city.", "Нажмите кнопку поиска, чтобы найти город")
    }

    private var headerTitle: String {
        switch screen {
        case .countries: return l("Choose a country", "Выберите страну")
        case .cities: return l("Choose a city", "Выберите город")
        case .detected: return l("Confirm your location", "Проверьте локацию")
        }
    }

    private var headerSubtitle: String {
        switch screen {
        case .countries: return l("Choose any country or detect it from your location.", "Можно выбрать любую страну или определить её по геопозиции.")
        case .cities: return l("Choose a city from the results; free-form text is not saved.", "Выберите город из результатов поиска — свободный ввод не сохраняется.")
        case .detected: return l("Nothing changes until you confirm the detected city.", "Мы ничего не изменим, пока вы не подтвердите найденный город.")
        }
    }

    private func loadCountries() async {
        isLoading = true
        defer { isLoading = false }
        do {
            countries = try await repository.fetchLocationCountries(query: nil)
            errorMessage = nil
        } catch {
            guard !error.isCancellationLike else { return }
            errorMessage = l("Could not load countries. Try again.", "Не удалось загрузить страны. Попробуйте ещё раз.")
        }
    }

    private func loadCities() async {
        guard let selectedCountry else { return }
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            citySearchResults = []
            return
        }
        didSearchCities = true
        isLoading = true
        defer { isLoading = false }
        do {
            citySearchResults = try await repository.fetchLocationCities(
                countryCode: selectedCountry.code,
                query: query,
                limit: 20
            )
            errorMessage = nil
        } catch {
            guard !error.isCancellationLike else { return }
            citySearchResults = []
            errorMessage = l("Could not find cities. Try again.", "Не удалось найти города. Попробуйте ещё раз.")
        }
    }

    private func loadCitySuggestions(for country: GeoCountry) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let suggestions = try await repository.fetchLocationCities(
                countryCode: country.code,
                query: "",
                limit: 20
            )
            guard selectedCountry?.code == country.code else { return }
            citySuggestions = suggestions
            didLoadCitySuggestions = true
            errorMessage = nil
        } catch {
            guard !error.isCancellationLike, selectedCountry?.code == country.code else { return }
            citySuggestions = []
            didLoadCitySuggestions = true
            errorMessage = l("Could not load city suggestions. You can still search by name.", "Не удалось загрузить города. Их всё ещё можно найти по названию.")
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }
        do {
            detectedPlace = try await repository.reverseGeocodeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            errorMessage = nil
            withAnimation(.easeInOut(duration: 0.2)) { screen = .detected }
        } catch {
            guard !error.isCancellationLike else { return }
            errorMessage = l("Could not detect your city. Choose it manually.", "Не удалось определить город. Выберите его вручную.")
        }
    }

    private func select(_ place: GeoPlace, source: LocationSource) {
        onSelect(place, source)
        AppHaptics.notification(.success)
        dismiss()
    }

    private func l(_ english: String, _ russian: String) -> String {
        localeStore.effectiveLocale == .ru ? russian : english
    }
}

private final class GlobalLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    struct DetectedCoordinate: Equatable {
        let latitude: Double
        let longitude: Double

        var value: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    @Published var detectedCoordinate: DetectedCoordinate?
    @Published var failureMessage: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        detectedCoordinate = nil
        failureMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            failureMessage = "Доступ к геопозиции выключен. Выберите страну и город вручную."
        @unknown default:
            failureMessage = "Не удалось запросить геопозицию. Выберите город вручную."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            failureMessage = "Доступ к геопозиции выключен. Выберите страну и город вручную."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            failureMessage = "Не удалось получить геопозицию. Выберите город вручную."
            return
        }
        detectedCoordinate = DetectedCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failureMessage = "Не удалось получить геопозицию. Выберите город вручную."
    }
}
