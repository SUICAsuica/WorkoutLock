#if canImport(DeviceActivity)
import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

final class WorkoutLockActivityMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("WorkoutLock"))
    private let groupDefaults = UserDefaults(suiteName: "group.com.kosakanao.WorkoutLock")
    private let selectionKey = "workout-lock.family-activity-selection"
    private let completedDayKey = "workout-lock.completed-day"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        applyShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
    }

    private func applyShield() {
        guard groupDefaults?.string(forKey: completedDayKey) != Self.dayKey(for: .now),
              let data = groupDefaults?.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
#endif
