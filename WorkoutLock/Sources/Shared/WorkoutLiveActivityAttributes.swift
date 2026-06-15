import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
        var targetReps: Int
        var triggerLabel: String
        var startAt: Date
    }

    var exerciseTitle: String
}
