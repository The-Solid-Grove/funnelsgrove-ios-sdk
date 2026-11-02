import XCTest
@testable import FunnelsGroveSDK

final class LinkParserTests: XCTestCase {
    private func user(_ link: String) -> LinkedUser? {
        LinkParser.user(from: URL(string: link)!)
    }

    func testReadsTheUserAndEmailFromAFunnelsGroveLink() {
        XCTAssertEqual(
            user("https://go.example.com/open?user_id=u_123&email=buyer%40example.com&utm_source=fg"),
            LinkedUser(userId: "u_123", email: "buyer@example.com")
        )
    }

    func testAcceptsAnyHostAndScheme() {
        for link in [
            "https://any.example.org/some/path?user_id=u_1",
            "https://GO.Example.com/open?user_id=u_1",
            "http://example.com/?user_id=u_1",
            "fgdemo://open?user_id=u_1",
            "fgdemo:?user_id=u_1",
        ] {
            XCTAssertEqual(user(link), LinkedUser(userId: "u_1"), link)
        }
    }

    func testTakesTheFirstUserIdAndEmail() {
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&user_id=u_2")?.userId, "u_1")
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a%40b.co&email=c%40d.co")?.email, "a@b.co")
        // The first email counts even when it cannot be an address.
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=nonsense&email=c%40d.co"), LinkedUser(userId: "u_1"))
    }

    func testRejectsMissingOrMalformedUserIds() {
        XCTAssertNil(user("https://go.example.com/open"))
        XCTAssertNil(user("https://go.example.com/open?user_id"))
        XCTAssertNil(user("https://go.example.com/open?user_id="))
        XCTAssertNil(user("https://go.example.com/open?User_Id=u_1"))
        XCTAssertNil(user("https://go.example.com/open?user_id=u%201"))
        XCTAssertNil(user("https://go.example.com/open?user_id=u_1%0A"))
        // NUL is a control character but not whitespace.
        XCTAssertNil(user("https://go.example.com/open?user_id=u_1%00"))
        XCTAssertNil(user("https://go.example.com/open?user_id=" + String(repeating: "a", count: 257)))
        // One grapheme, 601 UTF-8 bytes: "a" followed by 300 combining acute accents.
        XCTAssertNil(user("https://go.example.com/open?user_id=a" + String(repeating: "%CC%81", count: 300)))
    }

    func testRejectsAnEmailWithoutAUserId() {
        XCTAssertNil(user("fgdemo://open?email=buyer%40example.com"))
    }

    func testAcceptsTheLongestAllowedUserId() {
        let longest = String(repeating: "a", count: 256)
        XCTAssertEqual(user("https://go.example.com/open?user_id=" + longest)?.userId, longest)
    }

    func testDecodesAndTrimsTheEmail() {
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a%2Bb%40example.com")?.email, "a+b@example.com")
        // A literal + stays a +: FunnelsGrove encodes it, a hand-made link may not.
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a+b@example.com")?.email, "a+b@example.com")
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=%20buyer%40example.com%20")?.email, "buyer@example.com")
    }

    func testDropsAnEmailThatCannotBeOneButKeepsTheUser() {
        for email in [
            "",
            "%20",
            "buyer.example.com",
            "a%20b%40example.com",
            "a%0A%40example.com",
            // A right-to-left override: a control character that is not whitespace.
            "a%E2%80%AE%40example.com",
            String(repeating: "a", count: 250) + "%40b.co",
            // 130 characters, 255 UTF-8 bytes.
            String(repeating: "%C3%BC", count: 125) + "%40b.co",
        ] {
            XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=" + email), LinkedUser(userId: "u_1"), email)
        }
    }

    func testAcceptsTheLongestAllowedEmail() {
        let longest = String(repeating: "a", count: 249) + "@b.co"
        XCTAssertEqual(longest.utf8.count, 254)
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=" + longest)?.email, longest)
    }
}
