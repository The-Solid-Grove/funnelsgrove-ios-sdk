import Foundation

/// Stands in for `Task.sleep` and remembers the requested delays.
actor SleepRecorder {
    private(set) var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }
}
