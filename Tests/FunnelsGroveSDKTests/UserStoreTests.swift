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
        for user in [LinkedUser(userId: "u_1", email: "buyer@example.com"), LinkedUser(userId: "u_1")] {
            XCTAssertEqual(KeychainUserStore.decode(try KeychainUserStore.encode(user)), user)
        }
    }

    func testReadsAnItemWithoutAUsableEmail() {
        for json in [#"{"userId":"u_1"}"#, #"{"userId":"u_1","email":""}"#, #"{"userId":"u_1","email":"a b"}"#] {
            XCTAssertEqual(KeychainUserStore.decode(Data(json.utf8)), LinkedUser(userId: "u_1"), json)
        }
    }

    func testTreatsDamagedDataAsNoUser() {
        for json in ["not json", "{}", #"{"userId":""}"#, #"{"userId":"u 1"}"#, #"{"userId":1}"#, #""u_1""#] {
            XCTAssertNil(KeychainUserStore.decode(Data(json.utf8)), json)
        }
    }
}
