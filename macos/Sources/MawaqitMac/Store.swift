import Combine
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class MawaqitStore: ObservableObject {
    @Published var state = SavedState()
    @Published var schedule: ScheduleView?
    @Published var query = ""
    @Published var results: [KimonoPlace] = []
    @Published var status = ""
    @Published var isLoading = false
    @Published var isLocating = false
    @Published var locationUnavailable: String?
    @Published var notificationsBlocked = false
    @Published var showingSettings = false
    @Published var statusTitle = ""
    @Published var iconOnlyMenuBar = UserDefaults.standard.bool(forKey: "iconOnlyMenuBar")
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let service = KimonoService()
    private let locationLookup = LocationLookup()
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastAttempt: Date?
    private var scheduledNotificationsKey = ""

    private var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kimono Prayer", isDirectory: true).appendingPathComponent("state.json")
    }

    var isConnected: Bool { state.link != nil }
    var hasLocation: Bool { isConnected && state.place != nil }
    var isCalculated: Bool { state.place?.kind == .calculated }
    /// "Kimono · Mawaqit", "Kimono · MasjidBox" or "Kimono · Calculated".
    var sourceLabel: String { ["Kimono", state.place?.kind.label].compactMap { $0 }.joined(separator: " · ") }
    private var link: URL? { state.link.flatMap(URL.init(string:)) }

    init() {
        load()
        if !isConnected { status = Self.connectPrompt }
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
        if isConnected, Date().timeIntervalSince(lastAttempt ?? .distantPast) > 3600 {
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
                // Kimono answers with the mosques around and times calculated for here.
                self.search(latitude: coordinate.latitude, longitude: coordinate.longitude)
            case .failure(let error):
                self.status = error.localizedDescription
            }
        }
    }

    static let connectPrompt = "Paste your link from Kimono Prayer and press Return."

    /// A Kimono Prayer link, from the search field or a mawaqit-kimono://connect address.
    func connect(_ link: URL) {
        searchTask?.cancel()
        refreshTask?.cancel()
        let notifications = state.notificationsEnabled
        state = SavedState(notificationsEnabled: notifications, link: link.absoluteString)
        query = ""
        results = []
        status = ""
        save()
        render()
        scheduleNotifications()
        refresh()
    }

    func disconnect() {
        searchTask?.cancel()
        refreshTask?.cancel()
        state = SavedState(notificationsEnabled: state.notificationsEnabled)
        query = ""
        results = []
        status = Self.connectPrompt
        isLoading = false
        save()
        render()
        scheduleNotifications()
    }

    func submitSearch() {
        if let link = KimonoLink.parse(query) {
            connect(link)
            return
        }
        guard isConnected else {
            status = Self.connectPrompt
            return
        }
        let text = query
        runSearch { service, link in try await service.search(link: link, query: text) }
    }

    private func search(latitude: Double, longitude: Double) {
        let timezone = TimeZone.current.identifier
        runSearch { service, link in
            try await service.search(link: link, latitude: latitude, longitude: longitude, timezone: timezone)
        }
    }

    private func runSearch(_ lookup: @escaping (KimonoService, URL) async throws -> [KimonoPlace]) {
        guard let link else { status = Self.connectPrompt; return }
        searchTask?.cancel()
        results = []
        isLoading = true
        status = "Searching…"
        searchTask = Task {
            do {
                let places = try await lookup(service, link)
                guard !Task.isCancelled else { return }
                results = Array(places.prefix(10))
                status = places.isEmpty
                    ? "Nothing found. Try another search, a mosque's Mawaqit or MasjidBox link, or your location."
                    : "\(places.count) found; showing up to 10."
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
            isLoading = false
        }
    }

    /// Makes the place the person's own in Kimono, so every device follows.
    func choose(_ place: KimonoPlace) {
        guard let link else { return }
        searchTask?.cancel()
        fetch("Loading prayer times…") { service in try await service.choose(link: link, id: place.id) }
    }

    func refresh() {
        guard let link else { return }
        fetch("Loading prayer times…") { service in try await service.mine(link: link) }
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
                status = "Approve Kimono Prayer under System Settings → General → Login Items."
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "Could not update Launch at Login: \(error.localizedDescription)"
        }
    }

    func remaining(until date: Date) -> String {
        Presentation.remaining(until: date, now: schedule?.now ?? Date())
    }

    private func fetch(_ message: String, _ request: @escaping (KimonoService) async throws -> KimonoMine) {
        refreshTask?.cancel()
        lastAttempt = Date()
        isLoading = true
        status = message
        refreshTask = Task {
            do {
                let mine = try await request(service)
                let calendar = try mine.timetable?.prayerCalendar()
                if let calendar { _ = try ScheduleBuilder.build(calendar) }
                guard !Task.isCancelled else { return }
                apply(mine, calendar: calendar)
            } catch {
                if !Task.isCancelled { fail(error) }
            }
            isLoading = false
        }
    }

    private func apply(_ mine: KimonoMine, calendar: PrayerCalendar?) {
        let samePlace = mine.place?.id == state.place?.id
        state.place = mine.place
        if let calendar {
            state.calendar = calendar
            state.fetched = Date()
            query = ""
            results = []
            status = ""
        } else if mine.place == nil {
            state.calendar = nil
            state.fetched = nil
            status = "Search for your mosque, or use where you are."
        } else {
            // Kimono knows the place but couldn't reach its times: keep the last ones for it.
            if !samePlace { state.calendar = nil; state.fetched = nil }
            status = mine.problem ?? "Kimono couldn't reach the prayer times. Try again in a moment."
        }
        save()
        render()
        scheduleNotifications()
    }

    /// A renewed link answers 401: forget it, keep the times, and ask for the new one.
    private func fail(_ error: Error) {
        if case .linkExpired = error as? MawaqitError {
            state.link = nil
            results = []
            save()
            render()
        }
        status = error.localizedDescription
    }

    private func render() {
        guard let data = state.calendar else {
            schedule = nil
            statusTitle = ""
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
        guard state.notificationsEnabled, let data = state.calendar,
              let events = try? Presentation.upcomingNotifications(data, now: Date(),
                  place: state.place?.name ?? "Kimono Prayer",
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
