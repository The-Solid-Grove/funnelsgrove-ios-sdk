import Foundation

/// Values come from Config/Local.xcconfig through Info.plist.
enum DemoConfig {
    static let publishableKey = value(for: "FGPublishableKey")

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            preconditionFailure("\(key) is empty: fill in Config/Local.xcconfig")
        }
        return value
    }
}
