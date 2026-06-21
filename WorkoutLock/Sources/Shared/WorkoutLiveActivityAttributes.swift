import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentReps: Int
        var targetReps: Int
        var currentSet: Int
        var totalSets: Int
        var isComplete: Bool
    }

    var exerciseTitle: String
}
