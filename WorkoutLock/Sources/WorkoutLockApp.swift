import SwiftUI
import UIKit
import UserNotifications

@main
struct WorkoutLockApp: App {
    @UIApplicationDelegateAdaptor(WorkoutLockAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var locationTrigger = LocationTriggerService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(store)
                .environmentObject(locationTrigger)
                .onAppear {
                    locationTrigger.startMonitoring(locations: store.triggerLocations)
                    store.resumePendingShieldingIfNeeded()
                    if ProcessInfo.processInfo.arguments.contains("--test-arrival-notification") {
                        Task { @MainActor in
                            UserDefaults.standard.removeObject(forKey: AppStore.completedDayKey)
                            AppStore.mirrorCompletedDayToAppGroup(nil)
                            if let triggerDate = try? await NotificationScheduler.scheduleTestStartNotification(
                                exercise: store.selectedExercise,
                                targetReps: store.targetReps,
                                after: 12
                            ) {
                                store.schedulePendingShielding(at: triggerDate)
                            }
                            await WorkoutLiveActivityService.scheduleFinalCountdown(
                                exercise: store.selectedExercise,
                                targetReps: store.targetReps,
                                startDelaySeconds: 12,
                                triggerLabel: "家 到着10分後"
                            )
                        }
                    }
                }
                .onChange(of: store.triggerLocations) { _, locations in
                    locationTrigger.startMonitoring(locations: locations)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // 前面復帰のたびに監視を貼り直し、すでに到着済みの場所を再評価する。
                    locationTrigger.startMonitoring(locations: store.triggerLocations)
                    locationTrigger.refreshTriggerStates()
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
        await MainActor.run {
            AppStore.applyStoredDueShieldingIfNeeded()
            if notification.request.content.userInfo["route"] as? String == "workout" {
                WorkoutLaunchRequest.markPending()
                NotificationCenter.default.post(name: .workoutStartRequested, object: nil)
            }
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
