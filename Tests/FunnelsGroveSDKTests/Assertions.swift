import XCTest
@testable import FunnelsGroveSDK

/// Fails unless `body` throws exactly `expected`.
func assertThrows(
    _ expected: FunnelsGroveError,
    message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected) \(message)", file: file, line: line)
    } catch let error as FunnelsGroveError {
        XCTAssertEqual(error, expected, message, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error) \(message)", file: file, line: line)
    }
}
