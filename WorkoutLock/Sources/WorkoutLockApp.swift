import SwiftUI
import UIKit
import UserNotifications

@main
struct WorkoutLockApp: App {
    @UIApplicationDelegateAdaptor(WorkoutLockAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()
    @StateObject private var locationTrigger = LocationTriggerService()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(store)
                .environmentObject(locationTrigger)
                .onAppear {
                    locationTrigger.startMonitoring(locations: store.triggerLocations)
                    ScreenShieldingService.reapplyWorkoutSessionLockIfActive()
                    WorkoutLaunchRequest.consumePending()
                    store.resumePendingShieldingIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    locationTrigger.startMonitoring(locations: store.triggerLocations)
                    ScreenShieldingService.reapplyWorkoutSessionLockIfActive()
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
