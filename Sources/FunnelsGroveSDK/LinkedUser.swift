import Foundation

/// A FunnelsGrove buyer: the user ID and, when a link carried one, the email they bought with. Also the keychain
/// record: the coding keys are a stored format, and renaming one loses the user saved by an earlier version.
struct LinkedUser: Codable, Equatable, Sendable {
    let userId: String
    /// Not verified: the address the buyer typed in the funnel, known to anyone who has the link.
    let email: String?

    init(userId: String, email: String? = nil) {
        self.userId = userId
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case userId
        case email
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        // An explicit null rather than a missing key.
        try container.encode(email, forKey: .email)
    }
}
