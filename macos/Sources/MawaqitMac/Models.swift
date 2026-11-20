import Foundation

struct PrayerCalendar: Codable, Equatable {
    let timezone: String
    let calendar: [[String: [String]]]
}

enum PrayerSource: String, Codable {
    case mawaqit
    case aladhan
}

struct CalculatedPrayerCalendar {
    let calendar: PrayerCalendar
    let method: String
}

struct SavedState: Codable {
    var notificationsEnabled = true
    var slug: String?
    var name: String?
    var calendar: PrayerCalendar?
    var fetched: Date?
    var year: Int?
    var source: PrayerSource?
    var calculationQuery: String?
    var calculationMethod: String?
}

struct MosqueResult: Identifiable, Equatable {
    let slug: String
    let name: String
    let location: String?
    var id: String { slug }
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

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
