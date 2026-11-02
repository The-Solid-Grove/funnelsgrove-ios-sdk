import Foundation

enum LinkParser {
    static let maxUserIdLength = 256
    static let maxEmailLength = 254

    /// Returns the buyer a FunnelsGrove link carries, or `nil` when the first `user_id` in its query is missing or
    /// not valid.
    /// Any scheme and host pass: the app's entitlements, its AASA file and its URL types decide which links open it.
    static func user(from url: URL) -> LinkedUser? {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let userId = items.first(where: { $0.name == "user_id" })?.value,
            isValidUserId(userId)
        else {
            return nil
        }
        return LinkedUser(userId: userId, email: validEmail(items.first(where: { $0.name == "email" })?.value))
    }

    /// Non-empty, at most 256 UTF-8 bytes, no whitespace or control characters. The byte limit keeps a letter
    /// with a thousand combining marks from passing as one character.
    static func isValidUserId(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maxUserIdLength && !value.unicodeScalars.contains(where: isForbidden)
    }

    /// The trimmed value if it passes a loose check: at most 254 UTF-8 bytes, an `@`, no whitespace or control
    /// characters inside. It keeps blanks, line breaks and invisible characters out of the app, but `@` alone still
    /// passes, and it does not prove that the address works or belongs to the user.
    static func validEmail(_ value: String?) -> String? {
        guard
            let email = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty,
            email.utf8.count <= maxEmailLength,
            email.contains("@"),
            !email.unicodeScalars.contains(where: isForbidden)
        else {
            return nil
        }
        return email
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
    }
}
