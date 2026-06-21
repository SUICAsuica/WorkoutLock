import CoreLocation
import Foundation
import UserNotifications

@MainActor
final class LocationTriggerService: NSObject, ObservableObject {
    private static let triggerRadiusMeters: CLLocationDistance = 100
    private static let minimumStayMinutes = 10

    @Published private(set) var statusText = "帰宅地点は未設定です"
    @Published private(set) var capturedHomeLocation: HomeLocation?

    private let manager = CLLocationManager()
    private var isWaitingForPermission = false
    private var pendingKind: TriggerLocationKind = .home
    private var pendingDelayMinutes = 10
    private var monitoredLocations: [String: HomeLocation] = [:]
    private var isCapturingLocation = false
    private var insideRegionIdentifiers: Set<String> = []
    private var dwellTasks: [String: Task<Void, Never>] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
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
                radius: Self.triggerRadiusMeters,
                identifier: regionIdentifier(for: location)
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }

        statusText = locations.isEmpty ? "位置トリガーは未設定です" : "\(locations.count)件の位置トリガーを監視中"
    }

    private func regionIdentifier(for location: HomeLocation) -> String {
        "workout-lock-location-\(location.id.uuidString)"
    }

    private func arrivalNotificationIdentifier(for location: HomeLocation) -> String {
        "workout-lock-arrival-\(location.id.uuidString)"
    }

    private func pendingArrivalStartKey(for location: HomeLocation) -> String {
        "workout-lock.pending-arrival-start.\(location.id.uuidString)"
    }

    private func effectiveDelayMinutes(for location: HomeLocation) -> Int {
        max(Self.minimumStayMinutes, location.effectiveStartDelayMinutes)
    }

    private func pendingArrivalStartDate(for location: HomeLocation) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: pendingArrivalStartKey(for: location))
        guard timestamp > Date().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func scheduleArrivalNotification(for location: HomeLocation) {
        guard UserDefaults.standard.string(forKey: AppStore.completedDayKey) != AppStore.dayKey(for: .now) else {
            statusText = "今日は完了済みなので通知しません"
            return
        }

        if pendingArrivalStartDate(for: location) != nil {
            statusText = "\(location.triggerSummary)の通知を予約済みです"
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
                content.body = "\(location.kind.title)に着いて\(self.effectiveDelayMinutes(for: location))分。スクワットを始めてアプリ制限を解除しましょう。"
                content.sound = .default
                content.categoryIdentifier = NotificationScheduler.workoutCategoryIdentifier
                content.interruptionLevel = .timeSensitive
                content.userInfo = ["route": "workout", "trigger": "location"]

                let startDelaySeconds = TimeInterval(self.effectiveDelayMinutes(for: location) * 60)
                let startDate = Date().addingTimeInterval(startDelaySeconds)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: startDelaySeconds, repeats: false)
                let request = UNNotificationRequest(
                    identifier: self.arrivalNotificationIdentifier(for: location),
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
                UserDefaults.standard.set(startDate.timeIntervalSince1970, forKey: self.pendingArrivalStartKey(for: location))
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

    private func cancelArrivalNotification(for location: HomeLocation) {
        let key = pendingArrivalStartKey(for: location)
        let timestamp = UserDefaults.standard.double(forKey: key)
        let scheduledDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [arrivalNotificationIdentifier(for: location)]
        )
        UserDefaults.standard.removeObject(forKey: key)

        if let scheduledDate {
            AppStore.cancelStoredShielding(scheduledAt: scheduledDate)
        }

        Task { @MainActor in
            await WorkoutLiveActivityService.endAll()
        }

        statusText = "\(location.triggerSummary)の通知を解除しました"
    }

    private func handleInsideRegion(identifier: String) {
        guard let location = monitoredLocations[identifier] else { return }
        insideRegionIdentifiers.insert(identifier)
        statusText = "\(location.triggerSummary)に滞在中。\(effectiveDelayMinutes(for: location))分で開始します"
        // 背面/終了向け: 到着+遅延で通知（タップで開始）
        scheduleArrivalNotification(for: location)
        // 前面向け: アプリ内の滞在タイマーで自動開始（通知許可に依存しない）
        startDwellTimer(for: location)
    }

    private func handleOutsideRegion(identifier: String) {
        guard let location = monitoredLocations[identifier] else { return }
        insideRegionIdentifiers.remove(identifier)
        dwellTasks[identifier]?.cancel()
        dwellTasks[identifier] = nil
        cancelArrivalNotification(for: location)
    }

    /// 監視中リージョンの内外を再評価する。起動・前面復帰時に呼ぶと
    /// 「すでに到着済み」でも滞在判定・タイマー再開ができる。
    func refreshTriggerStates() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("workout-lock-location-") {
            manager.requestState(for: region)
        }
    }

    /// 前面滞在タイマー。残り時間後にまだ滞在中なら自動でワークアウト開始要求を出す。
    private func startDwellTimer(for location: HomeLocation) {
        guard UserDefaults.standard.string(forKey: AppStore.completedDayKey) != AppStore.dayKey(for: .now) else { return }

        let identifier = regionIdentifier(for: location)
        dwellTasks[identifier]?.cancel()

        let fireDate = pendingArrivalStartDate(for: location)
            ?? Date().addingTimeInterval(TimeInterval(effectiveDelayMinutes(for: location) * 60))
        let remaining = max(0, fireDate.timeIntervalSinceNow)

        dwellTasks[identifier] = Task { [weak self] in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            if Task.isCancelled { return }
            await self?.fireDwell(identifier: identifier, location: location)
        }
    }

    private func fireDwell(identifier: String, location: HomeLocation) {
        dwellTasks[identifier] = nil
        guard insideRegionIdentifiers.contains(identifier) else { return }
        guard UserDefaults.standard.string(forKey: AppStore.completedDayKey) != AppStore.dayKey(for: .now) else { return }
        WorkoutLaunchRequest.markPending()
        NotificationCenter.default.post(name: .workoutStartRequested, object: nil)
        statusText = "\(location.triggerSummary)で自動開始しました"
    }

    /// 動作確認用。現地に行かなくても、前面の滞在タイマー→自動開始の経路を短時間で試す。
    func runForegroundTriggerTest(afterSeconds seconds: Int = 30) {
        let identifier = "workout-lock-location-test"
        insideRegionIdentifiers.insert(identifier)
        dwellTasks[identifier]?.cancel()
        statusText = "テスト: \(seconds)秒後に自動開始します（今日タブで確認）"

        dwellTasks[identifier] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
            if Task.isCancelled { return }
            await self?.fireTestDwell(identifier: identifier)
        }
    }

    private func fireTestDwell(identifier: String) {
        dwellTasks[identifier] = nil
        insideRegionIdentifiers.remove(identifier)
        WorkoutLaunchRequest.markPending()
        NotificationCenter.default.post(name: .workoutStartRequested, object: nil)
        statusText = "テスト: 自動開始しました"
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
            self?.handleInsideRegion(identifier: region.identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            self?.handleOutsideRegion(identifier: region.identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        Task { @MainActor [weak self] in
            switch state {
            case .inside:
                self?.handleInsideRegion(identifier: region.identifier)
            case .outside:
                self?.handleOutsideRegion(identifier: region.identifier)
            case .unknown:
                break
            }
        }
    }
}
