import CoreLocation
import Foundation
import UserNotifications

@MainActor
final class LocationTriggerService: NSObject, ObservableObject {
    @Published private(set) var statusText = "帰宅地点は未設定です"
    @Published private(set) var capturedHomeLocation: HomeLocation?

    private let manager = CLLocationManager()
    private var isWaitingForPermission = false
    private var pendingKind: TriggerLocationKind = .home
    private var pendingDelayMinutes = 10
    private var monitoredLocations: [String: HomeLocation] = [:]
    private var isCapturingLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestHomeLocation() {
        requestLocation(kind: .home, delayMinutes: 10)
    }

    func requestLocation(kind: TriggerLocationKind, delayMinutes: Int) {
        pendingKind = kind
        pendingDelayMinutes = delayMinutes
        isCapturingLocation = true

        guard CLLocationManager.locationServicesEnabled() else {
            statusText = "位置情報サービスがオフです"
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            isWaitingForPermission = true
            statusText = "位置情報の許可を確認しています"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "\(kind.title)の現在地を取得しています"
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "位置情報が許可されていません。設定アプリから許可してください。"
        @unknown default:
            statusText = "位置情報の状態を確認できません"
        }
    }

    func startMonitoring(locations: [HomeLocation]) {
        guard !locations.isEmpty else {
            applyMonitoring(locations: [])
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            statusText = "この端末では位置トリガーが使えません"
            return
        }

        monitoredLocations = Dictionary(uniqueKeysWithValues: locations.map { (regionIdentifier(for: $0), $0) })

        switch manager.authorizationStatus {
        case .notDetermined:
            isWaitingForPermission = true
            statusText = "位置トリガーの許可を確認しています"
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            statusText = "バックグラウンド位置トリガーの許可を確認しています"
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            applyMonitoring(locations: locations)
        case .denied, .restricted:
            statusText = "位置情報が許可されていません。設定アプリから許可してください。"
        @unknown default:
            statusText = "位置情報の状態を確認できません"
        }
    }

    private func applyMonitoring(locations: [HomeLocation]) {
        manager.monitoredRegions
            .filter { $0.identifier.hasPrefix("workout-lock-location-") }
            .forEach { manager.stopMonitoring(for: $0) }

        for location in locations.prefix(20) {
            let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let region = CLCircularRegion(
                center: center,
                radius: 150,
                identifier: regionIdentifier(for: location)
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }

        statusText = locations.isEmpty ? "位置トリガーは未設定です" : "\(locations.count)件の位置トリガーを監視中"
    }

    private func regionIdentifier(for location: HomeLocation) -> String {
        "workout-lock-location-\(location.id.uuidString)"
    }

    private func scheduleArrivalNotification(for location: HomeLocation) {
        guard UserDefaults.standard.string(forKey: AppStore.completedDayKey) != AppStore.dayKey(for: .now) else {
            statusText = "今日は完了済みなので通知しません"
            return
        }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    statusText = "通知が許可されていないため、到着後通知を出せません"
                    return
                }
                center.setNotificationCategories([NotificationScheduler.workoutCategory])

                let content = UNMutableNotificationContent()
                content.title = "筋トレ開始"
                content.body = "\(location.kind.title)に着いて\(location.startDelayMinutes)分。スクワットを始めてアプリ制限を解除しましょう。"
                content.sound = .default
                content.categoryIdentifier = NotificationScheduler.workoutCategoryIdentifier
                content.interruptionLevel = .timeSensitive
                content.userInfo = ["route": "workout", "trigger": "location"]

                let startDelaySeconds = TimeInterval(max(1, location.startDelayMinutes) * 60)
                let startDate = Date().addingTimeInterval(startDelaySeconds)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: startDelaySeconds, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "workout-lock-arrival-\(location.id.uuidString)-\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
                AppStore.scheduleStoredShielding(at: startDate)

                let targetReps = max(1, UserDefaults.standard.integer(forKey: AppStore.liveActivityTargetRepsKey))
                let exerciseRawValue = UserDefaults.standard.string(forKey: AppStore.liveActivityExerciseKey)
                let exercise = exerciseRawValue.flatMap(ExerciseKind.init(rawValue:)) ?? .squat

                await WorkoutLiveActivityService.scheduleFinalCountdown(
                    exercise: exercise,
                    targetReps: targetReps,
                    startDelaySeconds: startDelaySeconds,
                    triggerLabel: location.triggerSummary
                )
            } catch {
                statusText = "到着後通知の予約に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

extension LocationTriggerService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isWaitingForPermission else { return }
            self.isWaitingForPermission = false
            if !self.monitoredLocations.isEmpty {
                self.applyMonitoring(locations: Array(self.monitoredLocations.values))
            } else {
                self.requestLocation(kind: self.pendingKind, delayMinutes: self.pendingDelayMinutes)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isCapturingLocation else { return }
            self.isCapturingLocation = false
            let home = HomeLocation(
                name: self.pendingKind.title,
                kind: self.pendingKind,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                capturedAt: .now,
                startDelayMinutes: self.pendingDelayMinutes
            )
            self.capturedHomeLocation = home
            self.statusText = "\(home.triggerSummary)を保存しました: \(home.shortLabel)"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isCapturingLocation = false
            self?.statusText = "現在地を取得できませんでした: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            guard let self, let location = self.monitoredLocations[region.identifier] else { return }
            self.statusText = "\(location.triggerSummary)の通知を予約しました"
            self.scheduleArrivalNotification(for: location)
        }
    }
}
