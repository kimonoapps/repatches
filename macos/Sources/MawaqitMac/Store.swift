import Combine
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class MawaqitStore: ObservableObject {
    @Published var state = SavedState()
    @Published var schedule: ScheduleView?
    @Published var query = ""
    @Published var results: [MosqueResult] = []
    @Published var calculatedSuggestion: String?
    @Published var status = "Enter a mosque or city and press Return"
    @Published var isLoading = false
    @Published var isLocating = false
    @Published var locationUnavailable: String?
    @Published var notificationsBlocked = false
    @Published var showingSettings = false
    @Published var statusTitle = ""
    @Published var iconOnlyMenuBar = UserDefaults.standard.bool(forKey: "iconOnlyMenuBar")
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let service = MawaqitService()
    private let locationLookup = LocationLookup()
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastAttempt: Date?
    private var scheduledNotificationsKey = ""

    private var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mawaqit", isDirectory: true).appendingPathComponent("state.json")
    }

    var hasLocation: Bool { state.slug != nil || state.calculationQuery != nil }
    var isCalculated: Bool { state.source == .aladhan || (state.slug == nil && state.calculationQuery != nil) }

    init() {
        load()
        render()
        locationLookup.onAvailabilityChange = { [weak self] reason in self?.locationUnavailable = reason }
        if state.notificationsEnabled {
            // Notifications default to on, so ask once up front like GNOME's Shell notifications.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func tick() {
        render()
        // The system-wide switch has no callback; recheck whenever the panel refreshes.
        locationLookup.refreshAvailability()
        scheduleNotifications()
        if hasLocation, Date().timeIntervalSince(lastAttempt ?? .distantPast) > 3600 {
            refresh()
        }
    }

    func useCurrentLocation() {
        guard !isLocating else { return }
        searchTask?.cancel()
        isLocating = true
        status = "Finding your location…"
        locationLookup.request { [weak self] result in
            guard let self else { return }
            self.isLocating = false
            switch result {
            case .success(let coordinate):
                let coordinates = String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"),
                                         coordinate.latitude, coordinate.longitude)
                self.query = coordinates
                // Coordinates use the same dual-provider flow as a typed location:
                // nearby Mawaqit mosques plus the AlAdhan calculation option.
                self.submitSearch()
            case .failure(let error):
                self.status = error.localizedDescription
            }
        }
    }

    func submitSearch() {
        searchTask?.cancel()
        results = []
        calculatedSuggestion = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("http") {
            do { choose(slug: try CalendarParser.slug(from: text), name: nil) }
            catch { status = error.localizedDescription }
            return
        }
        if text.count >= 2 { calculatedSuggestion = text }
        let direct = text.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil
            ? MosqueResult(slug: text, name: text, location: "Open mosque directly") : nil
        if let direct { results = [direct] }
        isLoading = true
        status = "Searching…"
        searchTask = Task {
            do {
                var matches = try await service.search(text)
                guard !Task.isCancelled else { return }
                if let direct, !matches.contains(where: { $0.slug == direct.slug }) {
                    matches.insert(direct, at: 0)
                }
                results = Array(matches.prefix(10))
                status = matches.isEmpty
                    ? "No mosques found. Choose calculated times or try another location."
                    : "\(matches.count) mosques found; showing up to 10."
            } catch {
                guard !Task.isCancelled else { return }
                status = "Mawaqit search failed: \(error.localizedDescription) Calculated times are still available."
            }
            isLoading = false
        }
    }

    func choose(slug: String, name: String?) {
        refresh(candidateSlug: slug, candidateName: name ?? slug)
    }

    func useCalculatedTimes() {
        guard let suggestion = calculatedSuggestion else { return }
        searchTask?.cancel()
        refreshCalculated(query: suggestion, name: suggestion)
    }

    func refresh() {
        if isCalculated, let calculationQuery = state.calculationQuery {
            refreshCalculated(query: calculationQuery, name: state.name)
        } else if let slug = state.slug {
            refresh(candidateSlug: slug, candidateName: state.name)
        }
    }

    func setNotifications(_ enabled: Bool) {
        state.notificationsEnabled = enabled
        save()
        scheduleNotifications()
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func setIconOnlyMenuBar(_ enabled: Bool) {
        iconOnlyMenuBar = enabled
        UserDefaults.standard.set(enabled, forKey: "iconOnlyMenuBar")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                status = "Approve Mawaqit under System Settings → General → Login Items."
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "Could not update Launch at Login: \(error.localizedDescription)"
        }
    }

    func remaining(until date: Date) -> String {
        Presentation.remaining(until: date, now: schedule?.now ?? Date())
    }

    private func refresh(candidateSlug: String, candidateName: String?) {
        refreshTask?.cancel()
        lastAttempt = Date()
        isLoading = true
        status = "Loading prayer times…"
        refreshTask = Task {
            do {
                let calendar = try await service.calendar(slug: candidateSlug)
                _ = try ScheduleBuilder.build(calendar)
                guard !Task.isCancelled else { return }
                state = SavedState(notificationsEnabled: state.notificationsEnabled, slug: candidateSlug,
                    name: candidateName, calendar: calendar, fetched: Date(), year: utcYear(),
                    source: .mawaqit, calculationQuery: nil, calculationMethod: nil)
                query = ""
                results = []
                calculatedSuggestion = nil
                status = ""
                save()
                render()
                scheduleNotifications()
            } catch {
                if !Task.isCancelled { status = error.localizedDescription }
            }
            isLoading = false
        }
    }

    private func refreshCalculated(query calculationQuery: String, name: String?) {
        refreshTask?.cancel()
        lastAttempt = Date()
        isLoading = true
        status = "Calculating prayer times…"
        refreshTask = Task {
            do {
                let result = try await service.calculatedCalendar(query: calculationQuery, year: utcYear())
                _ = try ScheduleBuilder.build(result.calendar)
                guard !Task.isCancelled else { return }
                state = SavedState(notificationsEnabled: state.notificationsEnabled, slug: nil,
                    name: name ?? calculationQuery, calendar: result.calendar, fetched: Date(), year: utcYear(),
                    source: .aladhan, calculationQuery: calculationQuery, calculationMethod: result.method)
                query = ""
                results = []
                calculatedSuggestion = nil
                status = ""
                save()
                render()
                scheduleNotifications()
            } catch {
                if !Task.isCancelled { status = error.localizedDescription }
            }
            isLoading = false
        }
    }

    private func render() {
        guard let data = state.calendar else {
            schedule = nil
            statusTitle = ""
            return
        }
        guard state.year == utcYear() else {
            schedule = nil
            statusTitle = ""
            status = "Refresh required for the new year."
            return
        }
        do {
            let view = try ScheduleBuilder.build(data)
            schedule = view
            statusTitle = Presentation.panelTitle(view)
        } catch {
            schedule = nil
            statusTitle = ""
            status = error.localizedDescription
        }
    }

    /// Hands macOS the next two days of alerts so they arrive on time even while the
    /// app is napping or the Mac was asleep; a timer-based check would miss them.
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let blocked = settings.authorizationStatus == .denied
            Task { @MainActor in self.notificationsBlocked = blocked }
        }
        // Reschedule when the source, setting, or hour changes, so the 48-hour window keeps rolling.
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        let key = "\(state.notificationsEnabled)|\(state.fetched?.timeIntervalSince1970 ?? 0)|\(hour)"
        guard key != scheduledNotificationsKey else { return }
        scheduledNotificationsKey = key
        center.removeAllPendingNotificationRequests()
        guard state.notificationsEnabled, let data = state.calendar, state.year == utcYear(),
              let events = try? Presentation.upcomingNotifications(data, now: Date(),
                  place: state.name ?? state.slug ?? state.calculationQuery ?? "Mawaqit",
                  calculated: isCalculated) else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            center.add(UNNotificationRequest(identifier: event.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    private func time(_ date: Date, _ view: ScheduleView) -> String {
        ScheduleBuilder.time(date, timezone: view.timezone)
    }

    private func utcYear() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: Date())
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        state = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
        } catch {
            status = "Could not save your mosque: \(error.localizedDescription)"
        }
    }
}
