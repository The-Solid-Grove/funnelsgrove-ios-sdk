import Foundation

/// Errors thrown by FunnelsGroveSDK.
public enum FunnelsGroveError: Error, Equatable, Sendable {
    /// FunnelsGrove rejected the request with 400 or 401, usually because of a wrong `publishableKey`. From
    /// `trackLogin()`, a 400 can also mean that the user ID exists in several funnels of the project.
    case configuration(String)
    /// FunnelsGrove answered with another non-2xx status or a body the SDK cannot read. `statusCode` is 0 when the
    /// answer was not HTTP.
    case server(statusCode: Int)
    /// No answer came from FunnelsGrove: no connection, a timeout or a lost connection. The request may still have
    /// reached it.
    case network(URLError)
    /// `trackLogin()`: FunnelsGrove has no such user in the project of `publishableKey`, for example after a link
    /// from another project's funnel.
    case unknownUser
}
