import Foundation

/// Errors thrown by FunnelsGroveSDK.
public enum FunnelsGroveError: Error, Equatable, Sendable {
    /// FunnelsGrove rejected the request with 400 or 401: check `publishableKey`.
    case configuration(String)
    /// FunnelsGrove answered with another non-2xx status or a body the SDK cannot read.
    case server(statusCode: Int)
    /// The request did not reach FunnelsGrove.
    case network(URLError)
    /// `trackLogin()`: FunnelsGrove has no such user in the project of `publishableKey`, for example after a link
    /// from another project's funnel.
    case unknownUser
}
