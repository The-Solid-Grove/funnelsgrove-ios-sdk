import Foundation

/// The buyer a FunnelsGrove link points at: the user ID and, when the link carries one, the email they bought with.
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
