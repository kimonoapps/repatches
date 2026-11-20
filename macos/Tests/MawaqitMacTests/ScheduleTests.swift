import Foundation
import Testing
@testable import MawaqitMac

@Suite("Mawaqit schedule")
struct ScheduleTests {
    @Test func parserIgnoresBracesInsideStrings() throws {
        let months = (1...12).map { _ in #"{"1":["05:00","06:30","13:00","16:30","19:00","20:30"]}"# }.joined(separator: ",")
        let html = #"<script>const confData = {"timezone":"America/Toronto","calendar":["# + months + #"],"message":"}; still inside"};</script>"#
        let parsed = try CalendarParser.parse(html: html)
        #expect(parsed.timezone == "America/Toronto")
        #expect(parsed.calendar.count == 12)
    }

    @Test func slugAcceptsMawaqitURL() throws {
        #expect(try CalendarParser.slug(from: "https://mawaqit.net/en/m/aylmer-mosque") == "aylmer-mosque")
        #expect(throws: (any Error).self) { try CalendarParser.slug(from: "https://example.com/nope") }
    }

    @Test func scheduleBuildsPrayerAndNightWindows() throws {
        var months = Array(repeating: [String: [String]](), count: 12)
        for month in months.indices {
            for day in 1...31 {
                months[month][String(day)] = ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"]
            }
        }
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: months)
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-09-16T18:00:00Z")) // 14:00 local
        let view = try ScheduleBuilder.build(data, now: now)
        #expect(view.current?.name == "Dhuhr")
        #expect(view.next?.name == "Asr")
        #expect(view.today.count == 6)
    }

    @Test func activePrayerUsesItsOpenWindowNotMostRecentOrNext() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        for (instant, expectedCurrent, expectedNext) in [
            ("2026-09-19T09:00:00Z", "Fajr", "Dhuhr"),
            ("2026-09-19T10:30:00Z", nil, "Dhuhr"),
            ("2026-09-19T15:36:00Z", nil, "Dhuhr"),
            ("2026-09-19T17:00:00Z", "Dhuhr", "Asr"),
            ("2026-09-19T20:30:00Z", "Asr", "Maghrib"),
        ] as [(String, String?, String)] {
            let now = try #require(formatter.date(from: instant))
            let view = try ScheduleBuilder.build(data, now: now)
            #expect(view.current?.name == expectedCurrent)
            #expect(view.next?.name == expectedNext)
        }
    }

    @Test func parsesCalculatedAnnualCalendarAndAttribution() throws {
        var months: [String: Any] = [:]
        for month in 1...12 {
            months[String(month)] = [[
                "timings": ["Fajr": "05:15 (EDT)", "Sunrise": "06:40 (EDT)",
                    "Dhuhr": "13:00 (EDT)", "Asr": "16:30 (EDT)",
                    "Maghrib": "19:20 (EDT)", "Isha": "20:45 (EDT)"],
                "date": ["gregorian": ["day": "01"]],
                "meta": ["timezone": "America/Toronto", "method": ["name": "ISNA"]],
            ]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "status": "OK", "data": months])
        let result = try AlAdhanParser.parse(data)
        #expect(result.calendar.timezone == "America/Toronto")
        #expect(result.calendar.calendar[0]["1"]?[0] == "05:15")
        #expect(result.method == "ISNA")
    }

    @Test func oldSavedStateStillDecodesAsMawaqit() throws {
        let data = Data(#"{"notificationsEnabled":true,"slug":"example"}"#.utf8)
        let state = try JSONDecoder().decode(SavedState.self, from: data)
        #expect(state.slug == "example")
        #expect(state.source == nil)
        #expect(state.calculationQuery == nil)
    }

    @Test func countdownsUseCompactMinutesAndNoSeparator() throws {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Presentation.remaining(until: now.addingTimeInterval(8100), now: now) == "2h15min")
        #expect(Presentation.remaining(until: now.addingTimeInterval(3900), now: now) == "1h05min")
        #expect(Presentation.remaining(until: now.addingTimeInterval(840), now: now) == "14min")
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        // 16:45 local: Maghrib at 19:00 is 2h15min away.
        let view = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T20:45:00Z")))
        #expect(Presentation.panelTitle(view) == "Maghrib in 2h15min")
        let dhuhr = try #require(view.today.first { $0.name == "Dhuhr" })
        #expect(Presentation.prayerDetail(dhuhr, view: view) == "Ended 16:30")
    }

    @Test func overnightRowsReplaceInsteadOfAppending() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["04:00", "05:30", "13:00", "17:00", "21:00", "22:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        // 00:15 local: yesterday's Isha stays open until Islamic midnight at 00:30.
        let view = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T04:15:00Z")))
        let rows = Presentation.displayPrayers(view)
        #expect(rows.count == 5)
        #expect(rows.last?.id == view.current?.id)
        #expect(Presentation.nextSummary(view).isEmpty)
    }

    @Test func notificationsAreScheduledAheadForTwoDays() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-19T18:00:00Z")) // 14:00 local
        let events = try Presentation.upcomingNotifications(data, now: now, place: "Test", calculated: false)
        // Covers the rest of today, all of tomorrow, and the following morning, without duplicates.
        #expect(events.allSatisfy { $0.date > now && $0.date <= now.addingTimeInterval(48 * 3600) })
        #expect(events.first?.title == "Asr time")
        #expect(events.filter { $0.title == "Last third of the night" }.count == 2)
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(events.first?.body == "Test · Ends at 19:00 (America/Toronto)")
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.date <= $1.date })
    }
}
