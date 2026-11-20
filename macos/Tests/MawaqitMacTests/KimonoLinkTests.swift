import Foundation
import Testing
@testable import MawaqitMac

@Suite("Kimono link")
struct KimonoLinkTests {
    let link = "https://kimono.example/api/v1/prayer/feed/abc_DEF-123"

    @Test func acceptsThePastedLink() {
        #expect(KimonoLink.parse("  \(link)\n")?.absoluteString == link)
    }

    @Test func acceptsTheConnectAddress() {
        let encoded = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(KimonoLink.parse("mawaqit-kimono://connect?link=\(encoded)")?.absoluteString == link)
    }

    @Test func dropsAQueryAndRefusesOtherAddresses() {
        #expect(KimonoLink.parse("\(link)?q=paris")?.absoluteString == link)
        #expect(KimonoLink.parse("https://kimono.example/prayer") == nil)
        #expect(KimonoLink.parse("ftp://kimono.example/api/v1/prayer/feed/abc") == nil)
        #expect(KimonoLink.parse("mawaqit-kimono://other?link=\(link)") == nil)
        #expect(KimonoLink.parse("Paris") == nil)
    }
}
