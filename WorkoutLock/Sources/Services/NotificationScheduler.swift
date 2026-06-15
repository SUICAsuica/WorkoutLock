import Foundation
import UserNotifications

enum WorkoutLaunchRequest {
    private static let pendingKey = "workout-lock.pending-workout-launch"

    static func markPending() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func consumePending() -> Bool {
        let isPending = UserDefaults.standard.bool(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return isPending
    }
}

extension Notification.Name {
    static let workoutStartRequested = Notification.Name("workout-lock.workout-start-requested")
}

enum NotificationSchedulerError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "通知が許可されていません"
        }
    }
}

final class NotificationScheduler {
    private let dailyIdentifier = "workout-lock.daily"

    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories([workoutCategory])
    }

    static func scheduleTestStartNotification(
        exercise: ExerciseKind,
        targetReps: Int,
        after seconds: TimeInterval = 12
    ) async throws -> Date {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard granted else {
            throw NotificationSchedulerError.permissionDenied
        }

        center.setNotificationCategories([workoutCategory])

        let content = UNMutableNotificationContent()
        content.title = "筋トレ開始"
        content.body = "\(exercise.title)を\(targetReps)回。今やって、アプリ制限を解除しましょう。"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = workoutCategoryIdentifier
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["route": "workout", "trigger": "debug-arrival"]

        let triggerDate = Date().addingTimeInterval(max(1, seconds))
        let request = UNNotificationRequest(
            identifier: "workout-lock.debug-arrival-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        )
        try await center.add(request)
        return triggerDate
    }

    func scheduleWorkout(
        at date: Date,
        exercise: ExerciseKind,
        targetReps: Int,
        after earliestDate: Date = .now
    ) async throws -> Date {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard granted else {
            throw NotificationSchedulerError.permissionDenied
        }

        await cancelDailyWorkout()
        center.setNotificationCategories([Self.workoutCategory])

        let content = UNMutableNotificationContent()
        content.title = "筋トレロック"
        content.body = "\(exercise.title)を\(targetReps)回。終わるまでスマホを触らない時間です。"
        content.sound = .default
        content.badge = 1
        content.userInfo = ["route": "workout"]
        content.categoryIdentifier = Self.workoutCategoryIdentifier
        content.interruptionLevel = .timeSensitive

        let triggerDate = nextTriggerDate(matchingTimeOf: date, after: earliestDate)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: dailyIdentifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        return triggerDate
    }

    func cancelDailyWorkout() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [dailyIdentifier])
        try? await center.setBadgeCount(0)
    }

    private func nextTriggerDate(matchingTimeOf time: Date, after earliestDate: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let earliestDay = calendar.startOfDay(for: earliestDate)

        for dayOffset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: earliestDay),
                let candidate = calendar.date(
                    bySettingHour: timeComponents.hour ?? 21,
                    minute: timeComponents.minute ?? 0,
                    second: 0,
                    of: day
                ),
                candidate > earliestDate
            else {
                continue
            }
            return candidate
        }

        return earliestDate.addingTimeInterval(24 * 60 * 60)
    }

    static let workoutCategoryIdentifier = "WORKOUT_LOCK_START"

    static var workoutCategory: UNNotificationCategory {
        let start = UNNotificationAction(
            identifier: "WORKOUT_LOCK_START_NOW",
            title: "開始",
            options: [.foreground]
        )
        let later = UNNotificationAction(
            identifier: "WORKOUT_LOCK_LATER",
            title: "あと10分",
            options: []
        )
        return UNNotificationCategory(
            identifier: workoutCategoryIdentifier,
            actions: [start, later],
            intentIdentifiers: [],
            options: []
        )
    }
}
