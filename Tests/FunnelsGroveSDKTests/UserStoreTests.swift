import XCTest
@testable import FunnelsGroveSDK

/// The keychain calls themselves need a signed app: see the demo app. These tests cover the stored data.
final class UserStoreTests: XCTestCase {
    func testStoresTheIdAndEmailAsJSON() throws {
        let data = try KeychainUserStore.encode(LinkedUser(userId: "u_1", email: "buyer@example.com"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["userId": "u_1", "email": "buyer@example.com"])
    }

    func testStoresAMissingEmailAsNull() throws {
        let data = try KeychainUserStore.encode(LinkedUser(userId: "u_1"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["userId"] as? String, "u_1")
        XCTAssertTrue(object["email"] is NSNull)
    }

    func testReadsBackWhatItStores() throws {
        for user in [
            LinkedUser(userId: "u_1", email: "buyer@example.com"),
            LinkedUser(userId: "u_1"),
            LinkedUser(userId: String(repeating: "a", count: 256)),
            LinkedUser(userId: "u_1", email: String(repeating: "a", count: 249) + "@b.co"),
        ] {
            XCTAssertEqual(KeychainUserStore.decode(try KeychainUserStore.encode(user)), user)
        }
        // The stored email is read by the link rules, which trim it.
        XCTAssertEqual(
            KeychainUserStore.decode(Data(#"{"userId":"u_1","email":" buyer@example.com "}"#.utf8)),
            LinkedUser(userId: "u_1", email: "buyer@example.com")
        )
    }

    func testReadsAnItemWithoutAUsableEmail() {
        for email in [
            "",
            " ",
            "a b",
            "buyer.example.com",
            #"a\n@example.com"#,
            // A right-to-left override (JSON escape): a control character that is not whitespace.
            #"a\u202E@example.com"#,
            // 255 UTF-8 bytes.
            String(repeating: "a", count: 250) + "@b.co",
        ] {
            let json = #"{"userId":"u_1","email":""# + email + #""}"#
            XCTAssertEqual(KeychainUserStore.decode(Data(json.utf8)), LinkedUser(userId: "u_1"), json)
        }
        XCTAssertEqual(KeychainUserStore.decode(Data(#"{"userId":"u_1"}"#.utf8)), LinkedUser(userId: "u_1"))
    }

    func testTreatsDamagedDataAsNoUser() {
        for json in [
            "not json",
            "{}",
            #"{"userId":""}"#,
            #"{"userId":"u 1"}"#,
            #"{"userId":"u_1\n"}"#,
            // NUL is a control character but not whitespace.
            #"{"userId":"u_1\u0000"}"#,
            #"{"userId":""# + String(repeating: "a", count: 257) + #""}"#,
            #"{"userId":1}"#,
            // An email that is not a string makes the whole item unreadable, not just the email.
            #"{"userId":"u_1","email":5}"#,
            #""u_1""#,
        ] {
            XCTAssertNil(KeychainUserStore.decode(Data(json.utf8)), json)
        }
    }
}
