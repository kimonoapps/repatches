import Foundation

struct MawaqitService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [MosqueResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://mawaqit.net/api/2.0/mosque/search")!
        let pieces = trimmed.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if pieces.count == 2, let latitude = Double(pieces[0]), let longitude = Double(pieces[1]) {
            guard abs(latitude) <= 90, abs(longitude) <= 180 else {
                throw MawaqitError.message("Enter valid latitude, longitude coordinates.")
            }
            components.queryItems = [URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lon", value: String(longitude))]
        } else {
            guard trimmed.count >= 2 else {
                throw MawaqitError.message("Enter at least two letters, a mosque URL or coordinates.")
            }
            components.queryItems = [URLQueryItem(name: "word", value: trimmed)]
        }
        guard let url = components.url else {
            throw MawaqitError.message("The search could not be created.")
        }
        let data = try await get(url)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MawaqitError.message("The search service returned an unexpected response.")
        }
        return array.compactMap { item in
            let closed = (item["closed"] as? Bool) == true || (item["closed"] as? Int) == 1
            guard !closed, let slug = item["slug"] as? String, let name = item["name"] as? String else { return nil }
            return MosqueResult(slug: slug, name: name, location: item["localisation"] as? String)
        }
    }

    func calendar(slug: String) async throws -> PrayerCalendar {
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://mawaqit.net/en/m/\(encoded)") else {
            throw MawaqitError.message("The mosque address is invalid.")
        }
        let data = try await get(url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw MawaqitError.message("Mawaqit returned unreadable data.")
        }
        return try CalendarParser.parse(html: html)
    }

    func calculatedCalendar(query: String, year: Int) async throws -> CalculatedPrayerCalendar {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw MawaqitError.message("Enter a city, address or coordinates for calculated times.")
        }
        var components: URLComponents
        let pieces = trimmed.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if pieces.count == 2, let latitude = Double(pieces[0]), let longitude = Double(pieces[1]) {
            guard abs(latitude) <= 90, abs(longitude) <= 180 else {
                throw MawaqitError.message("Enter valid latitude, longitude coordinates.")
            }
            components = URLComponents(string: "https://api.aladhan.com/v1/calendar/\(year)")!
            components.queryItems = [URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude))]
        } else {
            components = URLComponents(string: "https://api.aladhan.com/v1/calendarByAddress/\(year)")!
            components.queryItems = [URLQueryItem(name: "address", value: trimmed)]
        }
        guard let url = components.url else {
            throw MawaqitError.message("The calculated-times request could not be created.")
        }
        return try AlAdhanParser.parse(try await get(url))
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("AkramB-Mawaqit-macOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw MawaqitError.message("Service returned \(status). Try again later.")
            }
            return data
        } catch let error as MawaqitError {
            throw error
        } catch {
            throw MawaqitError.message(error.localizedDescription)
        }
    }
}

enum AlAdhanParser {
    static func parse(_ data: Data) throws -> CalculatedPrayerCalendar {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int) == 200,
              let months = root["data"] as? [String: Any] else {
            throw MawaqitError.message("The calculated prayer-time service returned an unexpected response.")
        }
        let names = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        var calendar = Array(repeating: [String: [String]](), count: 12)
        var timezone: String?
        var method: String?
        for month in 1...12 {
            guard let days = months[String(month)] as? [[String: Any]], !days.isEmpty else {
                throw MawaqitError.message("Calculated prayer times are incomplete for this year.")
            }
            for item in days {
                guard let timings = item["timings"] as? [String: Any],
                      let date = item["date"] as? [String: Any],
                      let gregorian = date["gregorian"] as? [String: Any],
                      let rawDay = gregorian["day"] as? String,
                      let day = Int(rawDay) else {
                    throw MawaqitError.message("A calculated prayer-time entry is invalid.")
                }
                let values = try names.map { name -> String in
                    guard let raw = timings[name] as? String,
                          let match = raw.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) else {
                        throw MawaqitError.message("A calculated prayer time is invalid.")
                    }
                    return String(raw[match])
                }
                calendar[month - 1][String(day)] = values
                if let meta = item["meta"] as? [String: Any] {
                    timezone = timezone ?? meta["timezone"] as? String
                    if let methodInfo = meta["method"] as? [String: Any] {
                        method = method ?? methodInfo["name"] as? String
                    }
                }
            }
        }
        guard let timezone, TimeZone(identifier: timezone) != nil else {
            throw MawaqitError.message("The calculated location has an invalid timezone.")
        }
        return CalculatedPrayerCalendar(
            calendar: PrayerCalendar(timezone: timezone, calendar: calendar),
            method: method ?? "Automatic local method"
        )
    }
}
