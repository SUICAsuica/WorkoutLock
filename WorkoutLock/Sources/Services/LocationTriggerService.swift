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


    // 場所トリガーの自動通知・自動開始は廃止。到着しても何もしない。
    private func handleInsideRegion(identifier: String) {
        guard monitoredLocations[identifier] != nil else { return }
        insideRegionIdentifiers.insert(identifier)
    }

    private func handleOutsideRegion(identifier: String) {
        insideRegionIdentifiers.remove(identifier)
    }

    func refreshTriggerStates() {
        // 自動トリガー廃止のため何もしない。
    }

    /// 予約済みの到着通知・保留・リージョン監視・滞在タイマーをすべて解除する。
    func cancelAllArrivalTriggers() {
        for task in dwellTasks.values { task.cancel() }
        dwellTasks.removeAll()
        insideRegionIdentifiers.removeAll()

        manager.monitoredRegions
            .filter { $0.identifier.hasPrefix("workout-lock-location-") }
            .forEach { manager.stopMonitoring(for: $0) }

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("workout-lock-arrival-") }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("workout-lock.pending-arrival-start.") {
            defaults.removeObject(forKey: key)
        }

        statusText = "場所トリガーは使いません"
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
