import ActivityKit
import Foundation

@MainActor
enum WorkoutLiveActivityService {
    static let finalCountdownSeconds: TimeInterval = 10

    static func scheduleFinalCountdown(
        exercise: ExerciseKind,
        targetReps: Int,
        startDelaySeconds: TimeInterval,
        triggerLabel: String
    ) async {
        let waitSeconds = max(0, startDelaySeconds - finalCountdownSeconds)
        if waitSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
        }

        let remainingSeconds = min(finalCountdownSeconds, max(1, startDelaySeconds - waitSeconds))
        await startCountdown(
            exercise: exercise,
            targetReps: targetReps,
            remainingSeconds: remainingSeconds,
            triggerLabel: triggerLabel
        )
    }

    static func startCountdown(
        exercise: ExerciseKind,
        targetReps: Int,
        remainingSeconds: TimeInterval = 10,
        triggerLabel: String
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        await endAll()

        let seconds = max(1, remainingSeconds)
        let startAt = Date().addingTimeInterval(seconds)
        let attributes = WorkoutLiveActivityAttributes(exerciseTitle: exercise.title)
        let state = WorkoutLiveActivityAttributes.ContentState(
            message: "あと\(Int(seconds.rounded()))秒で開始",
            targetReps: targetReps,
            triggerLabel: triggerLabel,
            startAt: startAt
        )

        do {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: startAt.addingTimeInterval(20 * 60))
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } else {
                _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            }
        } catch {
            // Live Activities can be disabled by the user or unavailable while backgrounded.
        }
    }

    static func endAll() async {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
