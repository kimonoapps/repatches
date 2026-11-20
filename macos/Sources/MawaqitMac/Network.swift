import Foundation

/// Prayer times from Kimono, through the person's own Kimono Prayer link. Kimono does the
/// Mawaqit, MasjidBox and calculated lookups; this app only reads the result.
struct KimonoService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The person's place and its timetable (yesterday onwards).
    func mine(link: URL) async throws -> KimonoMine {
        try decode(KimonoMine.self, try await send(URLRequest(url: link, timeoutInterval: 30)))
    }

    /// Words, a Mawaqit or MasjidBox link, or "lat, lon".
    func search(link: URL, query: String) async throws -> [KimonoPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw MawaqitError.message("Enter at least two letters, a mosque link or coordinates.")
        }
        return try await search(link: link, items: [URLQueryItem(name: "q", value: trimmed)])
    }

    /// Mosques around a position, and times calculated for it in `timezone`.
    func search(link: URL, latitude: Double, longitude: Double, timezone: String) async throws -> [KimonoPlace] {
        try await search(link: link, items: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "tz", value: timezone),
        ])
    }

    /// Makes `id` the person's place on every device, and answers like `mine`.
    func choose(link: URL, id: String) async throws -> KimonoMine {
        var request = URLRequest(url: link, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": id])
        return try decode(KimonoMine.self, try await send(request))
    }

    private func search(link: URL, items: [URLQueryItem]) async throws -> [KimonoPlace] {
        guard var components = URLComponents(url: link, resolvingAgainstBaseURL: false) else {
            throw MawaqitError.message("The search could not be created.")
        }
        components.queryItems = items
        guard let url = components.url else { throw MawaqitError.message("The search could not be created.") }
        struct Places: Decodable { let places: [KimonoPlace] }
        return try decode(Places.self, try await send(URLRequest(url: url, timeoutInterval: 30))).places
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw MawaqitError.message("Kimono returned an unexpected response.") }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KimonoPrayer-macOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                struct Problem: Decodable { let error: String }
                let message = (try? JSONDecoder().decode(Problem.self, from: data))?.error
                if status == 401 {
                    throw MawaqitError.linkExpired(message ?? "This link no longer works. Connect again from Kimono Prayer.")
                }
                throw MawaqitError.message(message ?? "Kimono returned \(status). Try again later.")
            }
            return data
        } catch let error as MawaqitError {
            throw error
        } catch {
            throw MawaqitError.message(error.localizedDescription)
        }
    }
}
