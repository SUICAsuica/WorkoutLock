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
    private let sessionLockActiveKey = "workout-lock.session-lock-active"
    private var sharedDefaults: UserDefaults {
        groupDefaults ?? .standard
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if applyShield() {
            sharedDefaults.set(true, forKey: sessionLockActiveKey)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
    }

    private func applyShield() -> Bool {
        guard sharedDefaults.string(forKey: completedDayKey) != Self.dayKey(for: .now),
              let data = sharedDefaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return false
        }

        let hasSelection =
            !selection.applicationTokens.isEmpty ||
            !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty

        guard hasSelection else {
            store.clearAllSettings()
            return false
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        return true
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
#endif
