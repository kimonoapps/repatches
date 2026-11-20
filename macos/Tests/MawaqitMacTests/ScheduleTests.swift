import Foundation
import Testing
@testable import MawaqitMac

@Suite("Mawaqit schedule")
struct ScheduleTests {
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

    @Test func kimonoTimetableFillsTheCalendarAcrossTheYearEnd() throws {
        let json = #"""
        {"place":{"id":"mawaqit:example","kind":"mawaqit","name":"Example Mosque","detail":"Gatineau","url":null},
         "timetable":{"place":{"id":"mawaqit:example","kind":"mawaqit","name":"Example Mosque","detail":null,"url":null},
           "timezone":"America/Toronto","fetchedAt":1,
           "days":[{"date":"2026-12-31","times":["06:20","07:40","12:10","14:20","16:30","18:00"],"iqama":null,"jumua":[]},
                   {"date":"2027-01-01","times":["06:21","07:41","12:11","14:21","16:31","18:01"],"iqama":["06:40",null,null,null,null],"jumua":[]},
                   {"date":"2027-01-02","times":["06:22","07:42","12:12","14:22","16:32","18:02"],"iqama":null,"jumua":["13:00"]}]},
         "recent":[]}
        """#
        let mine = try JSONDecoder().decode(KimonoMine.self, from: Data(json.utf8))
        #expect(mine.place?.kind == .mawaqit)
        let calendar = try #require(try mine.timetable?.prayerCalendar())
        #expect(calendar.timezone == "America/Toronto")
        #expect(calendar.calendar[11]["31"]?.first == "06:20")
        #expect(calendar.calendar[0]["1"]?.first == "06:21")
        // New Year’s Day at 13:00 in Toronto: yesterday, today and tomorrow all come from the feed.
        let view = try ScheduleBuilder.build(calendar, now: try #require(ISO8601DateFormatter().date(from: "2027-01-01T18:00:00Z")))
        #expect(view.current?.name == "Dhuhr")
        #expect(view.next?.name == "Asr")
    }

    @Test func kimonoTimetableRefusesUnreadableDays() {
        let bad = KimonoTimetable(timezone: "America/Toronto", days: [KimonoDay(date: "2026-13-01", times: ["05:00"])])
        #expect(throws: (any Error).self) { try bad.prayerCalendar() }
        let zone = KimonoTimetable(timezone: "Mars/Olympus", days: [])
        #expect(throws: (any Error).self) { try zone.prayerCalendar() }
    }

    @Test func aPlaceWithoutATimetableStillDecodes() throws {
        let json = #"{"place":null,"timetable":null,"recent":[],"problem":"Pick a place first."}"#
        let mine = try JSONDecoder().decode(KimonoMine.self, from: Data(json.utf8))
        #expect(mine.place == nil && mine.timetable == nil && mine.problem == "Pick a place first.")
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
