import Foundation

/// The personal link Kimono Prayer hands out (`https://<kimono>/api/v1/prayer/feed/<token>`), pasted as is
/// or wrapped in `mawaqit-kimono://connect?link=<link>`. It stands in for signing in.
enum KimonoLink {
    static let scheme = "mawaqit-kimono"

    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == "connect",
                  let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "link" })?.value else { return nil }
            return feed(inner)
        }
        return feed(trimmed)
    }

    private static func feed(_ text: String) -> URL? {
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              components.path.range(of: #"^/api/v1/prayer/feed/[A-Za-z0-9_-]+/?$"#, options: .regularExpression) != nil
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
