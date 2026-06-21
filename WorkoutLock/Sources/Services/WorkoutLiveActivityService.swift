import ActivityKit
import Foundation

@MainActor
enum WorkoutLiveActivityService {
    private static var current: Activity<WorkoutLiveActivityAttributes>?

    /// ワークアウト開始時に Live Activity / Dynamic Island を表示する。
    static func start(exercise: ExerciseKind, targetReps: Int, totalSets: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task { await endAll() }

        let attributes = WorkoutLiveActivityAttributes(exerciseTitle: exercise.title)
        let state = WorkoutLiveActivityAttributes.ContentState(
            currentReps: 0,
            targetReps: targetReps,
            currentSet: 1,
            totalSets: max(1, totalSets),
            isComplete: false
        )

        do {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60))
                current = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } else {
                current = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            }
        } catch {
            // ユーザーが Live Activity を無効にしている等で失敗することがある。
        }
    }

    /// 進捗を更新する。
    static func update(currentReps: Int, targetReps: Int, currentSet: Int, totalSets: Int, isComplete: Bool) {
        guard let activity = current else { return }
        let state = WorkoutLiveActivityAttributes.ContentState(
            currentReps: currentReps,
            targetReps: targetReps,
            currentSet: currentSet,
            totalSets: max(1, totalSets),
            isComplete: isComplete
        )
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60)))
            } else {
                await activity.update(using: state)
            }
        }
    }

    /// 終了する。
    static func end() {
        current = nil
        Task { await endAll() }
    }

    private static func endAll() async {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
