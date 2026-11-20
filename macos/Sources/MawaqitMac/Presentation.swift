import Foundation

/// Shared presentation rules, mirroring the GNOME extension's presentation.js.
enum Presentation {
    static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        return minutes >= 60
            ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))min"
            : "\(minutes)min"
    }

    static func prayerDetail(_ prayer: Prayer, view: ScheduleView) -> String {
        if prayer.id == view.next?.id { return "in \(remaining(until: prayer.start, now: view.now))" }
        guard let end = prayer.end else { return "" }
        let time = ScheduleBuilder.time(end, timezone: view.timezone)
        return end <= view.now ? "Ended \(time)" : "Ends \(time)"
    }

    static func panelTitle(_ view: ScheduleView) -> String {
        let milestones = view.milestones, now = view.now
        if milestones.active && now < milestones.midnight {
            return "Midnight in \(remaining(until: milestones.midnight, now: now))"
        }
        if milestones.active && now < milestones.lastThird {
            return "Last third in \(remaining(until: milestones.lastThird, now: now))"
        }
        if milestones.active && now < view.night.end {
            return "Fajr in \(remaining(until: view.night.end, now: now))"
        }
        if milestones.active {
            return "Sunrise in \(remaining(until: milestones.sunrise, now: now))"
        }
        guard let next = view.next else { return "" }
        return "\(next.name) in \(remaining(until: next.start, now: now))"
    }

    /// Overnight, the open prayer replaces today's row of the same name instead of adding a row.
    static func displayPrayers(_ view: ScheduleView) -> [Prayer] {
        view.today.filter { !$0.isSunrise }.map { prayer in
            if let current = view.current, current.name == prayer.name,
               !view.today.contains(where: { $0.id == current.id }) { return current }
            return prayer
        }
    }

    static func nextSummary(_ view: ScheduleView) -> String {
        guard let next = view.next, !view.today.contains(where: { $0.id == next.id }) else { return "" }
        return "Next: \(next.name) at \(next.time) tomorrow"
    }

    struct NotificationEvent: Equatable {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// Prayer starts and last-third alerts after `now`, up to `horizon` ahead, for macOS to deliver on time.
    static func upcomingNotifications(_ data: PrayerCalendar, now: Date, horizon: TimeInterval = 48 * 3600,
                                      place: String, calculated: Bool) throws -> [NotificationEvent] {
        var events: [String: NotificationEvent] = [:]
        let source = calculated ? " · Calculated by AlAdhan" : ""
        // Each day's view covers that day's prayers and its night, so step a day at a time.
        for offset in stride(from: 0.0, through: horizon, by: 86400) {
            let view = try ScheduleBuilder.build(data, now: now.addingTimeInterval(offset))
            func add(_ id: String, _ date: Date, _ title: String, _ detail: String) {
                guard date > now, date <= now.addingTimeInterval(horizon) else { return }
                events[id] = NotificationEvent(id: id, date: date, title: title,
                    body: "\(place) · \(detail) (\(view.timezone))\(source)")
            }
            for prayer in view.today where !prayer.isSunrise {
                guard let end = prayer.end else { continue }
                let suffix = prayer.name == "Isha" ? " · Islamic midnight" : ""
                add("prayer:\(prayer.name):\(prayer.start.timeIntervalSince1970)", prayer.start,
                    "\(prayer.name) time", "Ends at \(ScheduleBuilder.time(end, timezone: view.timezone))\(suffix)")
            }
            add("last-third:\(view.night.lastThird.timeIntervalSince1970)", view.night.lastThird,
                "Last third of the night", "Until Fajr at \(ScheduleBuilder.time(view.night.end, timezone: view.timezone))")
        }
        return events.values.sorted { $0.date < $1.date }
    }
}
