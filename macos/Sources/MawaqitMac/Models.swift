import Foundation

struct PrayerCalendar: Codable, Equatable {
    let timezone: String
    let calendar: [[String: [String]]]
}

/// Where Kimono takes a place's times from.
enum PlaceKind: String, Codable {
    case mawaqit, masjidbox, calculated

    var label: String {
        switch self {
        case .mawaqit: "Mawaqit"
        case .masjidbox: "MasjidBox"
        case .calculated: "Calculated"
        }
    }
}

/// A mosque or a position, as Kimono Prayer names it (`Place` in Kimono's prayer model).
struct KimonoPlace: Codable, Identifiable, Equatable {
    let id: String
    let kind: PlaceKind
    let name: String
    /// Where it is; for calculated times, the method.
    let detail: String?
    let url: String?
}

/// One day of a timetable: `times` is Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha.
struct KimonoDay: Codable, Equatable {
    let date: String
    let times: [String]
}

struct KimonoTimetable: Codable, Equatable {
    let timezone: String
    let days: [KimonoDay]

    /// The days in the yearly calendar shape ScheduleBuilder reads: `calendar[month - 1]["<day>"]`.
    /// Kimono sends yesterday to a few weeks ahead, so no month appears for two different years.
    func prayerCalendar() throws -> PrayerCalendar {
        guard TimeZone(identifier: timezone) != nil else {
            throw MawaqitError.message("This place's time zone is invalid.")
        }
        var calendar = Array(repeating: [String: [String]](), count: 12)
        for day in days {
            let parts = day.date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
                  day.times.count == 6 else {
                throw MawaqitError.message("Kimono sent a day of prayer times it couldn't read.")
            }
            calendar[parts[1] - 1][String(parts[2])] = day.times
        }
        return PrayerCalendar(timezone: timezone, calendar: calendar)
    }
}

/// What the link answers: the person's place, its timetable, and why there's none if so.
struct KimonoMine: Codable {
    let place: KimonoPlace?
    let timetable: KimonoTimetable?
    let problem: String?
}

struct SavedState: Codable {
    var notificationsEnabled = true
    /// The personal Kimono Prayer link; nil until someone connects.
    var link: String?
    var place: KimonoPlace?
    var calendar: PrayerCalendar?
    var fetched: Date?
}

struct Prayer: Identifiable, Equatable {
    let name: String
    let time: String
    let start: Date
    let isSunrise: Bool
    var end: Date?
    var dayOffset = 0

    var id: String { "\(name):\(start.timeIntervalSince1970)" }
}

struct NightPeriod {
    let start: Date
    let end: Date
    let midnight: Date
    let lastThird: Date
}

enum NightPhase: String {
    case midnight, lastThird, sunrise
}

struct NightMilestones {
    let midnight: Date
    let lastThird: Date
    let sunrise: Date
    let active: Bool
    let phase: NightPhase?
}

struct ScheduleView {
    let today: [Prayer]
    let next: Prayer?
    let current: Prayer?
    let night: NightPeriod
    let nightActive: Bool
    let lastThirdActive: Bool
    let milestones: NightMilestones
    let now: Date
    let dateText: String
    let timezone: String
}

enum MawaqitError: LocalizedError {
    case message(String)
    /// Kimono answered 401: the link was renewed, so this one is dead.
    case linkExpired(String)

    var errorDescription: String? {
        switch self { case .message(let text), .linkExpired(let text): text }
    }
}
