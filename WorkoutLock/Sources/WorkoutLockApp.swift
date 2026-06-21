import SwiftUI
import UIKit
import UserNotifications

@main
struct WorkoutLockApp: App {
    @UIApplicationDelegateAdaptor(WorkoutLockAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var locationTrigger = LocationTriggerService()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(store)
                .environmentObject(locationTrigger)
                .onAppear {
                    // 場所トリガーの自動通知/自動開始は廃止。残っている予約を一掃する。
                    locationTrigger.cancelAllArrivalTriggers()
                    WorkoutLaunchRequest.consumePending()
                    store.resumePendingShieldingIfNeeded()
                }
        }
    }
}

final class WorkoutLockAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 前面で通知が出ても勝手に開始しない（バナー表示のみ）。開始はタップ時だけ。
        await MainActor.run {
            AppStore.applyStoredDueShieldingIfNeeded()
        }
        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            AppStore.applyStoredDueShieldingIfNeeded()
            if response.notification.request.content.userInfo["route"] as? String == "workout" {
                WorkoutLaunchRequest.markPending()
                NotificationCenter.default.post(name: .workoutStartRequested, object: nil)
            }
        }
    }
}
