import Foundation

#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif

@MainActor
final class ScreenShieldingService: ObservableObject {
    @Published private(set) var statusText = "未接続"

    private static let appGroupIdentifier = "group.com.kosakanao.WorkoutLock"
    private static let sessionLockActiveKey = "workout-lock.session-lock-active"
    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var isWorkoutSessionLockActive: Bool {
        sharedDefaults.bool(forKey: sessionLockActiveKey)
    }

    static func setWorkoutSessionLockActive(_ isActive: Bool) {
        sharedDefaults.set(isActive, forKey: sessionLockActiveKey)
    }

    static func reapplyWorkoutSessionLockIfActive() {
        guard isWorkoutSessionLockActive else { return }

        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("WorkoutLock"))
        let selection = loadSelection()
        let hasSelection =
            !selection.applicationTokens.isEmpty ||
            !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty

        guard hasSelection else {
            managedSettingsStore.clearAllSettings()
            setWorkoutSessionLockActive(false)
            return
        }

        apply(selection: selection, to: managedSettingsStore)
        #endif
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Published var selection: FamilyActivitySelection = ScreenShieldingService.loadSelection() {
        didSet {
            saveSelection()
            updateSelectionStatus()
        }
    }

    private let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("WorkoutLock"))
    private static let selectionKey = "workout-lock.family-activity-selection"
    #endif

    var capabilityText: String {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        return "Screen Time権限とブロック対象アプリの選択が必要です。実機ではApple Developer側のFamily Controls capabilityも必要です。"
        #else
        return "この環境ではScreen Time APIを読み込めません。"
        #endif
    }

    var selectionSummary: String {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let normalized = Self.normalizedSelection(selection)
        let count = normalized.applicationTokens.count + normalized.categoryTokens.count + normalized.webDomainTokens.count
        guard count > 0 else { return "未選択" }

        var parts: [String] = []
        if !normalized.categoryTokens.isEmpty {
            parts.append("カテゴリ全体\(normalized.categoryTokens.count)件")
        }
        if !normalized.applicationTokens.isEmpty {
            parts.append("アプリ\(normalized.applicationTokens.count)件")
        }
        if !normalized.webDomainTokens.isEmpty {
            parts.append("Web\(normalized.webDomainTokens.count)件")
        }
        return parts.joined(separator: " / ")
        #else
        return "利用不可"
        #endif
    }

    var hasConfiguredSelection: Bool {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let normalized = Self.normalizedSelection(selection)
        return
            !normalized.applicationTokens.isEmpty ||
            !normalized.categoryTokens.isEmpty ||
            !normalized.webDomainTokens.isEmpty
        #else
        return false
        #endif
    }

    func readinessText(isEnabled: Bool) -> String {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard isEnabled else { return "オフ" }
        guard hasConfiguredSelection else { return "対象未選択" }
        if statusText.contains("適用しました") {
            return "適用済み"
        }
        if statusText.contains("権限を取得") {
            return "準備OK"
        }
        return "対象選択済み"
        #else
        return "利用不可"
        #endif
    }

    func requestAuthorization() async {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if #available(iOS 16.0, *) {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                updateSelectionStatus(prefix: "Screen Time権限を取得しました。")
                Haptics.success()
            } catch {
                statusText = "権限取得に失敗しました: \(error.localizedDescription)"
                Haptics.error()
            }
        } else {
            statusText = "iOS 16以上が必要です。"
        }
        #else
        statusText = "FamilyControlsが利用できません。"
        #endif
    }

    func applyShielding(isEnabled: Bool) {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard isEnabled else {
            managedSettingsStore.clearAllSettings()
            updateSelectionStatus(prefix: "アプリブロックをオフにしました。")
            Haptics.lightTap()
            return
        }

        let normalized = Self.normalizedSelection(selection)
        let hasSelection =
            !normalized.applicationTokens.isEmpty ||
            !normalized.categoryTokens.isEmpty ||
            !normalized.webDomainTokens.isEmpty

        guard hasSelection else {
            managedSettingsStore.clearAllSettings()
            statusText = "ブロック対象アプリを選択してください"
            Haptics.warning()
            return
        }

        Self.apply(selection: normalized, to: managedSettingsStore)

        statusText = "ブロックを適用しました: \(selectionSummary)"
        Haptics.success()
        #else
        statusText = "この環境ではアプリブロックを適用できません"
        Haptics.warning()
        #endif
    }

    func applyWorkoutSessionLock() async {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasConfiguredSelection else {
            statusText = "ブロック対象が未選択です。設定で選ぶと開始時にロックできます"
            Self.setWorkoutSessionLockActive(false)
            return
        }

        guard await requestAuthorizationIfNeededForSessionLock() else {
            Self.setWorkoutSessionLockActive(false)
            return
        }
        guard !Task.isCancelled else { return }

        let normalized = Self.normalizedSelection(selection)
        Self.apply(selection: normalized, to: managedSettingsStore)
        Self.setWorkoutSessionLockActive(true)
        statusText = "ワークアウト中のブロックを適用しました: \(selectionSummary)"
        Haptics.success()
        #else
        statusText = "この環境ではアプリブロックを適用できません"
        #endif
    }

    func clearWorkoutSessionLock() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        managedSettingsStore.clearAllSettings()
        Self.setWorkoutSessionLockActive(false)
        updateSelectionStatus(prefix: "ワークアウト中のブロックを解除しました。")
        #else
        Self.setWorkoutSessionLockActive(false)
        statusText = "この環境ではアプリブロックを解除できません"
        #endif
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private func requestAuthorizationIfNeededForSessionLock() async -> Bool {
        if #available(iOS 16.0, *) {
            let center = AuthorizationCenter.shared
            guard center.authorizationStatus != .approved else {
                return true
            }

            do {
                try await center.requestAuthorization(for: .individual)
            } catch {
                statusText = "Screen Time権限を取得できませんでした: \(error.localizedDescription)"
                return false
            }

            guard center.authorizationStatus == .approved else {
                statusText = "Screen Time権限が未認可です。設定で許可すると開始時にロックできます"
                return false
            }
            return true
        } else {
            statusText = "iOS 16以上が必要です。"
            return false
        }
    }

    @discardableResult
    static func applyStoredShielding(isEnabled: Bool) -> Bool {
        let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("WorkoutLock"))
        guard isEnabled else {
            managedSettingsStore.clearAllSettings()
            return false
        }

        let selection = loadSelection()
        let hasSelection =
            !selection.applicationTokens.isEmpty ||
            !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty

        guard hasSelection else {
            managedSettingsStore.clearAllSettings()
            return false
        }

        apply(selection: selection, to: managedSettingsStore)
        return true
    }

    private static func loadSelection() -> FamilyActivitySelection {
        let defaults = sharedDefaults
        let data = defaults.data(forKey: selectionKey) ?? UserDefaults.standard.data(forKey: selectionKey)
        guard
            let data,
            let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection(includeEntireCategory: true)
        }

        let normalized = normalizedSelection(decoded)
        if normalized != decoded, let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: selectionKey)
        } else if defaults.data(forKey: selectionKey) == nil {
            defaults.set(data, forKey: selectionKey)
        }
        return normalized
    }

    private static func normalizedSelection(_ selection: FamilyActivitySelection) -> FamilyActivitySelection {
        guard !selection.includeEntireCategory else { return selection }

        var normalized = FamilyActivitySelection(includeEntireCategory: true)
        normalized.applicationTokens = selection.applicationTokens
        normalized.categoryTokens = selection.categoryTokens
        normalized.webDomainTokens = selection.webDomainTokens
        return normalized
    }

    private static func apply(selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    private func saveSelection() {
        let normalized = Self.normalizedSelection(selection)
        guard let data = try? JSONEncoder().encode(normalized) else {
            return
        }

        Self.sharedDefaults.set(data, forKey: Self.selectionKey)
    }

    private func updateSelectionStatus(prefix: String? = nil) {
        let base = selectionSummary == "未選択" ? "ブロック対象は未選択です" : "ブロック対象: \(selectionSummary)"
        statusText = [prefix, base].compactMap { $0 }.joined(separator: " ")
    }
    #endif
}
