import Foundation
import Security

@MainActor
final class AppStore: ObservableObject {
    @Published var onboardingCompleted = false {
        didSet { saveSettings() }
    }

    @Published var didSignInWithApple = false {
        didSet { saveSettings() }
    }

    @Published var dataConsentAccepted: Bool? {
        didSet { saveSettings() }
    }

    @Published var userGender: UserGender = .noAnswer {
        didSet { saveSettings() }
    }

    @Published var heightCm: Double = 170 {
        didSet { saveSettings() }
    }

    @Published var currentWeightKg: Double = 65 {
        didSet { saveSettings() }
    }

    @Published var goalWeightKg: Double = 60 {
        didSet { saveSettings() }
    }

    @Published var goalDurationMonths: Int = 3 {
        didSet { saveSettings() }
    }

    @Published var planOptions: [TrainingPlan] = []

    @Published var selectedPlan: TrainingPlan? {
        didSet { saveSettings() }
    }

    @Published var planStartedAt: Date? {
        didSet { saveSettings() }
    }

    @Published private(set) var weightCheckIns: [WeightCheckIn] = [] {
        didSet { saveSettings() }
    }

    @Published private(set) var lastWeightPromptAt: Date? {
        didSet { saveSettings() }
    }

    @Published var tutorialCompleted = false {
        didSet { saveSettings() }
    }

    @Published var tutorialCalibration: TutorialCalibration? {
        didSet { saveSettings() }
    }

    @Published var triggerPreference: TriggerPreference = .time {
        didSet { saveSettings() }
    }

    @Published var workoutTimeBand: WorkoutTimeBand = .evening {
        didSet {
            applyWorkoutTimeBand()
            saveSettings()
        }
    }

    @Published var homeLocation: HomeLocation? {
        didSet { saveSettings() }
    }

    @Published var triggerLocations: [HomeLocation] = [] {
        didSet { saveSettings() }
    }

    @Published var appBlockingEnabled = false {
        didSet { saveSettings() }
    }

    @Published var selectedExercise: ExerciseKind = .squat {
        didSet { saveSettings() }
    }

    @Published var targetReps: Int = 8 {
        didSet { saveSettings() }
    }

    @Published var alarmTime: Date = Calendar.current.date(
        bySettingHour: 21,
        minute: 30,
        second: 0,
        of: .now
    ) ?? .now {
        didSet { saveSettings() }
    }

    @Published var isAlarmEnabled = false {
        didSet { saveSettings() }
    }

    @Published var inAppLockEnabled = true {
        didSet { saveSettings() }
    }

    @Published var workoutMusicEnabled = true {
        didSet { saveSettings() }
    }

    @Published var selectedMusicTrack: WorkoutMusicTrack = .neonDrive {
        didSet { saveSettings() }
    }

    @Published var workoutMusicVolume: Double = 0.72 {
        didSet { saveSettings() }
    }

    @Published private(set) var records: [WorkoutRecord] = []
    @Published var notificationMessage = "通知は未設定です"

    private let notificationScheduler = NotificationScheduler()
    private var isLoadingPersistedState = false
    private let settingsKey = "workout-lock.settings"
    private let recordsKey = "workout-lock.records"
    static let completedDayKey = "workout-lock.completed-day"
    static let liveActivityTargetRepsKey = "workout-lock.live-activity-target-reps"
    static let liveActivityExerciseKey = "workout-lock.live-activity-exercise"
    static let appBlockingEnabledKey = "workout-lock.app-blocking-enabled"
    static let pendingShieldStartKey = "workout-lock.pending-shield-start"

    init() {
        NotificationScheduler.registerCategories()
        AppDurableBackup.restoreLocalDataIfNeeded(
            settingsKey: settingsKey,
            recordsKey: recordsKey,
            completedDayKey: Self.completedDayKey
        )
        isLoadingPersistedState = true
        loadSettings()
        loadRecords()
        isLoadingPersistedState = false
        UserDefaults.standard.set(appBlockingEnabled, forKey: Self.appBlockingEnabledKey)
        if planOptions.isEmpty {
            planOptions = makePlanOptions()
        }
        normalizeTriggerPreference()
        syncTargetRepsWithPlan()
        resumePendingShieldingIfNeeded()
        AppDurableBackup.backupSettingsData(UserDefaults.standard.data(forKey: settingsKey))
        AppDurableBackup.backupRecords(records)
        AppDurableBackup.backupCompletedDay(UserDefaults.standard.string(forKey: Self.completedDayKey))
    }

    var todayRecordCount: Int {
        let calendar = Calendar.current
        return records.filter { calendar.isDateInToday($0.completedAt) }.count
    }

    var todayRecords: [WorkoutRecord] {
        let calendar = Calendar.current
        return records.filter { calendar.isDateInToday($0.completedAt) }
    }

    var latestTodayRecord: WorkoutRecord? {
        todayRecords.first
    }

    var todayReps: Int {
        todayRecords.reduce(0) { $0 + $1.actualReps }
    }

    var totalReps: Int {
        records.reduce(0) { $0 + $1.actualReps }
    }

    var totalWorkoutDuration: TimeInterval {
        records.reduce(0) { $0 + $1.duration }
    }

    var recordSnapshotCount: Int {
        records.filter { $0.snapshotData != nil }.count
    }

    // MARK: - ログ用の集計

    /// 1セットの最高回数（自己ベスト）。
    var bestReps: Int {
        records.map(\.actualReps).max() ?? 0
    }

    /// 今週（月曜始まり）にこなした合計回数。
    var thisWeekReps: Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return records
            .filter { interval.contains($0.completedAt) }
            .reduce(0) { $0 + $1.actualReps }
    }

    /// 今週こなしたセット数。
    var thisWeekSetCount: Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return records.filter { interval.contains($0.completedAt) }.count
    }

    /// 直近7日間の日別合計回数（古い→新しい順）。簡易バーグラフ用。
    var weeklyRepBars: [DailyRepBar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset -> DailyRepBar? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let reps = records
                .filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.actualReps }
            return DailyRepBar(date: day, reps: reps)
        }
    }

    var goalSummary: String {
        "\(currentWeightKg.formatted(.number.precision(.fractionLength(1))))kg -> \(goalWeightKg.formatted(.number.precision(.fractionLength(1))))kg / \(goalDurationMonths)ヶ月"
    }

    var latestWeightCheckIn: WeightCheckIn? {
        weightCheckIns.first
    }

    var isWeeklyWeightCheckInDue: Bool {
        guard onboardingCompleted || ProcessInfo.processInfo.arguments.contains("--skip-onboarding") else { return false }
        guard let anchor = lastWeightPromptAt ?? latestWeightCheckIn?.loggedAt ?? planStartedAt else { return false }
        guard !Calendar.current.isDateInToday(anchor) else { return false }
        return Date().timeIntervalSince(anchor) >= 7 * 24 * 60 * 60
    }

    var nextWeightCheckInLabel: String {
        let anchor = lastWeightPromptAt ?? latestWeightCheckIn?.loggedAt ?? planStartedAt ?? .now
        let nextDate = Calendar.current.date(byAdding: .day, value: 7, to: anchor) ?? anchor
        if nextDate <= .now {
            return "入力できます"
        }
        return nextDate.formatted(date: .numeric, time: .omitted)
    }

    var goalProgress: Double {
        if let selectedPlan {
            return min(1, Double(currentPlanWeek) / Double(max(1, selectedPlan.durationWeeks)))
        }

        return min(1, Double(totalReps) / Double(max(1, targetReps * 30)))
    }

    var currentPlanWeek: Int {
        guard let planStartedAt else { return 0 }
        let startDay = Calendar.current.startOfDay(for: planStartedAt)
        let today = Calendar.current.startOfDay(for: .now)
        let days = Calendar.current.dateComponents([.day], from: startDay, to: today).day ?? 0
        return max(0, days / 7)
    }

    var plannedTargetReps: Int {
        guard let selectedPlan else { return targetReps }
        let ramped = selectedPlan.startReps + (currentPlanWeek * selectedPlan.weeklyIncrease)
        return min(selectedPlan.endReps, max(selectedPlan.startReps, ramped))
    }

    var nextPlanTargetSummary: String {
        guard let selectedPlan else { return "\(targetReps)回" }
        let nextWeekTarget = min(
            selectedPlan.endReps,
            selectedPlan.startReps + ((currentPlanWeek + 1) * selectedPlan.weeklyIncrease)
        )
        return nextWeekTarget == plannedTargetReps ? "上限 \(selectedPlan.endReps)回" : "来週 \(nextWeekTarget)回"
    }

    /// プレフィックス無しの「次の目標回数」。ホームの今日/次チップ用。
    var nextPlanTargetValue: String {
        guard let selectedPlan else { return "\(targetReps)回" }
        let nextWeekTarget = min(
            selectedPlan.endReps,
            selectedPlan.startReps + ((currentPlanWeek + 1) * selectedPlan.weeklyIncrease)
        )
        return nextWeekTarget == plannedTargetReps ? "上限 \(selectedPlan.endReps)回" : "\(nextWeekTarget)回"
    }

    var streakDays: Int {
        let calendar = Calendar.current
        let days = Set(records.map { calendar.startOfDay(for: $0.completedAt) })
        var currentDay = calendar.startOfDay(for: .now)
        var streak = 0

        while days.contains(currentDay) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }
            currentDay = previous
        }

        return streak
    }

    var nextAlarmLabel: String {
        guard isAlarmEnabled else { return "未設定" }
        return alarmTime.formatted(date: .omitted, time: .shortened)
    }

    var primaryTriggerLabel: String {
        switch triggerPreference {
        case .time:
            return nextAlarmLabel
        case .homeArrival:
            return homeTriggerLabel ?? "帰宅後"
        case .both:
            if let homeTriggerLabel {
                return "\(alarmTime.formatted(date: .omitted, time: .shortened)) + \(homeTriggerLabel)"
            }
            return alarmTime.formatted(date: .omitted, time: .shortened)
        }
    }

    var homeTriggerLabel: String? {
        (homeLocation ?? triggerLocations.first)?.triggerSummary
    }

    var hasCompletedToday: Bool {
        let todayKey = Self.dayKey(for: .now)
        return UserDefaults.standard.string(forKey: Self.completedDayKey) == todayKey
    }

    func markAppleSignedIn() {
        didSignInWithApple = true
    }

    func setDataConsent(_ accepted: Bool) {
        dataConsentAccepted = accepted
    }

    func refreshPlanOptions() {
        planOptions = makePlanOptions()
    }

    func deferWeeklyWeightCheckIn() {
        lastWeightPromptAt = .now
    }

    func completeWeeklyWeightCheckIn(weightKg rawWeightKg: Double) {
        let checkedWeight = min(160, max(35, (rawWeightKg * 10).rounded() / 10))
        let previousWeightKg = currentWeightKg
        let previousTargetReps = targetReps

        currentWeightKg = checkedWeight
        lastWeightPromptAt = .now
        refreshSelectedPlanFromProfile()
        syncTargetRepsWithPlan()

        let checkIn = WeightCheckIn(
            weightKg: checkedWeight,
            previousWeightKg: previousWeightKg,
            targetRepsBefore: previousTargetReps,
            targetRepsAfter: targetReps,
            planTitle: selectedPlan?.title
        )
        weightCheckIns.insert(checkIn, at: 0)

        if isAlarmEnabled {
            Task { await scheduleDailyAlarm() }
        }
    }

    func selectPlan(_ plan: TrainingPlan) {
        selectedPlan = plan
        planStartedAt = .now
    }

    func syncTargetRepsWithPlan() {
        guard selectedPlan != nil else { return }
        if planStartedAt == nil {
            planStartedAt = records.last?.completedAt ?? .now
        }
        targetReps = plannedTargetReps
    }

    func upsertTriggerLocation(_ location: HomeLocation) {
        if let index = triggerLocations.firstIndex(where: { $0.id == location.id }) {
            triggerLocations[index] = location
        } else {
            triggerLocations.append(location)
        }

        if location.kind == .home || homeLocation == nil {
            homeLocation = location
        }
    }

    func removeTriggerLocation(_ location: HomeLocation) {
        triggerLocations.removeAll { $0.id == location.id }
        if homeLocation?.id == location.id {
            homeLocation = triggerLocations.first
        }
    }

    func markTutorialCompleted() {
        tutorialCompleted = true
    }

    func applyTutorialCalibration(_ calibration: TutorialCalibration) {
        tutorialCalibration = calibration
        refreshSelectedPlanFromProfile()
        syncTargetRepsWithPlan()
    }

    func completeOnboarding() {
        onboardingCompleted = true
    }

    func scheduleDailyAlarm() async {
        syncTargetRepsWithPlan()
        guard triggerPreference != .homeArrival else {
            await notificationScheduler.cancelDailyWorkout()
            isAlarmEnabled = false
            UserDefaults.standard.removeObject(forKey: Self.pendingShieldStartKey)
            notificationMessage = homeTriggerLabel.map { "\($0)に通知します" } ?? "帰宅後に通知します"
            Haptics.success()
            return
        }

        do {
            let triggerDate = try await notificationScheduler.scheduleWorkout(
                at: alarmTime,
                exercise: selectedExercise,
                targetReps: targetReps,
                after: hasCompletedToday ? Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60) : .now
            )
            schedulePendingShielding(at: triggerDate)
            isAlarmEnabled = true
            notificationMessage = triggerPreference == .both
                ? "毎日 \(nextAlarmLabel) と \(homeTriggerLabel ?? "帰宅後") に通知します"
                : "毎日 \(nextAlarmLabel) に通知します"
            Haptics.success()
        } catch {
            isAlarmEnabled = false
            notificationMessage = "通知設定に失敗しました: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func cancelDailyAlarm() async {
        await notificationScheduler.cancelDailyWorkout()
        isAlarmEnabled = false
        UserDefaults.standard.removeObject(forKey: Self.pendingShieldStartKey)
        notificationMessage = "通知を解除しました"
        Haptics.lightTap()
    }

    func rememberPendingShieldStart(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.pendingShieldStartKey)
    }

    func schedulePendingShielding(at date: Date) {
        Self.scheduleStoredShielding(at: date)
    }

    func applyDueShieldingIfNeeded() {
        Self.applyStoredDueShieldingIfNeeded()
    }

    func resumePendingShieldingIfNeeded() {
        let timestamp = UserDefaults.standard.double(forKey: Self.pendingShieldStartKey)
        guard timestamp > 0 else { return }

        let date = Date(timeIntervalSince1970: timestamp)
        if date <= .now {
            applyDueShieldingIfNeeded()
        } else {
            schedulePendingShielding(at: date)
        }
    }

    static func scheduleStoredShielding(at date: Date) {
        let timestamp = date.timeIntervalSince1970
        UserDefaults.standard.set(timestamp, forKey: Self.pendingShieldStartKey)

        guard UserDefaults.standard.bool(forKey: Self.appBlockingEnabledKey) else { return }

        Task { @MainActor in
            let delay = max(0, date.timeIntervalSinceNow)
            if delay > 0 {
                let nanoseconds = UInt64(min(delay, 7 * 24 * 60 * 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            applyStoredDueShieldingIfNeeded()
        }
    }

    static func cancelStoredShielding(scheduledAt date: Date) {
        let timestamp = UserDefaults.standard.double(forKey: Self.pendingShieldStartKey)
        guard timestamp > 0 else { return }

        let scheduledTimestamp = date.timeIntervalSince1970
        guard abs(timestamp - scheduledTimestamp) < 2 else { return }

        UserDefaults.standard.removeObject(forKey: Self.pendingShieldStartKey)
    }

    static func applyStoredDueShieldingIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.appBlockingEnabledKey) else { return }
        guard UserDefaults.standard.string(forKey: Self.completedDayKey) != Self.dayKey(for: .now) else { return }

        let timestamp = UserDefaults.standard.double(forKey: Self.pendingShieldStartKey)
        guard timestamp > 0, Date().timeIntervalSince1970 >= timestamp else { return }
        ScreenShieldingService.applyStoredShielding(isEnabled: true)
    }

    func completeWorkout(
        actualReps: Int,
        duration: TimeInterval,
        snapshotData: Data?,
        targetReps overrideTargetReps: Int? = nil,
        countsTowardDailyCompletion: Bool = true
    ) {
        let record = WorkoutRecord(
            exercise: selectedExercise,
            targetReps: overrideTargetReps ?? targetReps,
            actualReps: actualReps,
            duration: duration,
            snapshotData: snapshotData
        )
        records.insert(record, at: 0)
        if countsTowardDailyCompletion {
            UserDefaults.standard.set(Self.dayKey(for: record.completedAt), forKey: Self.completedDayKey)
            AppDurableBackup.backupCompletedDay(Self.dayKey(for: record.completedAt))
            UserDefaults.standard.removeObject(forKey: Self.pendingShieldStartKey)
        }
        saveRecords()
        syncTargetRepsWithPlan()
        Task { await WorkoutLiveActivityService.endAll() }

        if isAlarmEnabled {
            Task { await scheduleDailyAlarm() }
        }
    }

    private func loadSettings() {
        guard
            let data = UserDefaults.standard.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(StoredSettings.self, from: data)
        else {
            return
        }

        onboardingCompleted = settings.onboardingCompleted
        didSignInWithApple = settings.didSignInWithApple
        dataConsentAccepted = settings.dataConsentAccepted
        userGender = UserGender(rawValue: settings.userGenderRawValue) ?? .noAnswer
        heightCm = settings.heightCm
        currentWeightKg = settings.currentWeightKg
        goalWeightKg = settings.goalWeightKg
        goalDurationMonths = settings.goalDurationMonths ?? 3
        selectedPlan = settings.selectedPlan
        planStartedAt = settings.planStartedAt
        weightCheckIns = (settings.weightCheckIns ?? []).sorted { $0.loggedAt > $1.loggedAt }
        lastWeightPromptAt = settings.lastWeightPromptAt
        tutorialCompleted = settings.tutorialCompleted
        tutorialCalibration = settings.tutorialCalibration
        triggerPreference = TriggerPreference(rawValue: settings.triggerPreferenceRawValue) ?? .time
        workoutTimeBand = WorkoutTimeBand(rawValue: settings.workoutTimeBandRawValue ?? "") ?? .evening
        homeLocation = settings.homeLocation
        triggerLocations = settings.triggerLocations ?? settings.homeLocation.map { [$0] } ?? []
        appBlockingEnabled = settings.appBlockingEnabled
        selectedExercise = ExerciseKind(rawValue: settings.exerciseRawValue) ?? .squat
        targetReps = settings.targetReps
        isAlarmEnabled = settings.isAlarmEnabled
        inAppLockEnabled = settings.inAppLockEnabled
        workoutMusicEnabled = settings.workoutMusicEnabled ?? true
        selectedMusicTrack = WorkoutMusicTrack(rawValue: settings.selectedMusicTrackRawValue ?? "") ?? .neonDrive
        workoutMusicVolume = min(1, max(0, settings.workoutMusicVolume ?? 0.72))

        if let date = Calendar.current.date(
            bySettingHour: settings.alarmHour,
            minute: settings.alarmMinute,
            second: 0,
            of: .now
        ) {
            alarmTime = date
        }

        syncTargetRepsWithPlan()
    }

    private func normalizeTriggerPreference() {
        if triggerPreference == .both, !triggerLocations.isEmpty {
            triggerPreference = .homeArrival
        }

        guard triggerPreference == .homeArrival else { return }
        isAlarmEnabled = false
        notificationMessage = homeTriggerLabel.map { "\($0)に通知します" } ?? "帰宅後に通知します"
        Task { await notificationScheduler.cancelDailyWorkout() }
    }

    private func saveSettings() {
        guard !isLoadingPersistedState else { return }

        UserDefaults.standard.set(targetReps, forKey: Self.liveActivityTargetRepsKey)
        UserDefaults.standard.set(selectedExercise.rawValue, forKey: Self.liveActivityExerciseKey)
        UserDefaults.standard.set(appBlockingEnabled, forKey: Self.appBlockingEnabledKey)

        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let settings = StoredSettings(
            onboardingCompleted: onboardingCompleted,
            didSignInWithApple: didSignInWithApple,
            dataConsentAccepted: dataConsentAccepted,
            userGenderRawValue: userGender.rawValue,
            heightCm: heightCm,
            currentWeightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            goalDurationMonths: goalDurationMonths,
            selectedPlan: selectedPlan,
            planStartedAt: planStartedAt,
            weightCheckIns: weightCheckIns,
            lastWeightPromptAt: lastWeightPromptAt,
            tutorialCompleted: tutorialCompleted,
            tutorialCalibration: tutorialCalibration,
            triggerPreferenceRawValue: triggerPreference.rawValue,
            workoutTimeBandRawValue: workoutTimeBand.rawValue,
            homeLocation: homeLocation,
            triggerLocations: triggerLocations,
            appBlockingEnabled: appBlockingEnabled,
            exerciseRawValue: selectedExercise.rawValue,
            targetReps: targetReps,
            alarmHour: components.hour ?? 21,
            alarmMinute: components.minute ?? 30,
            isAlarmEnabled: isAlarmEnabled,
            inAppLockEnabled: inAppLockEnabled,
            workoutMusicEnabled: workoutMusicEnabled,
            selectedMusicTrackRawValue: selectedMusicTrack.rawValue,
            workoutMusicVolume: workoutMusicVolume
        )

        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
            AppDurableBackup.backupSettingsData(data)
        }
    }

    private func loadRecords() {
        guard
            let data = UserDefaults.standard.data(forKey: recordsKey),
            let decoded = try? JSONDecoder().decode([WorkoutRecord].self, from: data)
        else {
            return
        }

        records = decoded.sorted { $0.completedAt > $1.completedAt }
    }

    private func saveRecords() {
        guard !isLoadingPersistedState else { return }

        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
            AppDurableBackup.backupRecords(records)
        }
    }

    private func applyWorkoutTimeBand() {
        guard let date = Calendar.current.date(
            bySettingHour: workoutTimeBand.defaultHour,
            minute: 0,
            second: 0,
            of: .now
        ) else {
            return
        }
        alarmTime = date
    }

    private func refreshSelectedPlanFromProfile() {
        let selectedPlanID = selectedPlan?.id
        planOptions = makePlanOptions()

        guard selectedPlan != nil else { return }

        if let selectedPlanID, let matchingPlan = planOptions.first(where: { $0.id == selectedPlanID }) {
            selectedPlan = matchingPlan
        } else {
            selectedPlan = planOptions.first
        }
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func makePlanOptions() -> [TrainingPlan] {
        WorkoutPlanEstimator.makePlans(
            gender: userGender,
            heightCm: heightCm,
            currentWeightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            goalDurationMonths: goalDurationMonths,
            calibration: tutorialCalibration,
            recentRecords: records
        )
    }
}

private enum AppDurableBackup {
    private static let service = "com.kosakanao.WorkoutLock.backup"
    private static let settingsDataKey = "settings-data"
    private static let recordsDataKey = "records-data"
    private static let completedDayKey = "completed-day"
    private static let maximumPortableRecordCount = 500

    static func restoreLocalDataIfNeeded(
        settingsKey: String,
        recordsKey: String,
        completedDayKey localCompletedDayKey: String
    ) {
        let defaults = UserDefaults.standard
        if defaults.data(forKey: settingsKey) == nil, let data = data(for: settingsDataKey) {
            defaults.set(data, forKey: settingsKey)
        }

        if defaults.data(forKey: recordsKey) == nil, let data = data(for: recordsDataKey) {
            defaults.set(data, forKey: recordsKey)
        }

        if
            defaults.string(forKey: localCompletedDayKey) == nil,
            let data = data(for: completedDayKey),
            let completedDay = String(data: data, encoding: .utf8)
        {
            defaults.set(completedDay, forKey: localCompletedDayKey)
        }
    }

    static func backupSettingsData(_ data: Data?) {
        guard let data else { return }
        save(data, for: settingsDataKey)
    }

    static func backupRecords(_ records: [WorkoutRecord]) {
        let portableRecords = records.prefix(maximumPortableRecordCount).map {
            WorkoutRecord(
                id: $0.id,
                completedAt: $0.completedAt,
                exercise: $0.exercise,
                targetReps: $0.targetReps,
                actualReps: $0.actualReps,
                duration: $0.duration,
                snapshotData: nil
            )
        }

        guard let data = try? JSONEncoder().encode(portableRecords) else { return }

        save(data, for: recordsDataKey)
    }

    static func backupCompletedDay(_ dayKey: String?) {
        guard let data = dayKey?.data(using: .utf8) else { return }
        save(data, for: completedDayKey)
    }

    private static func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func save(_ data: Data, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        SecItemAdd(item as CFDictionary, nil)
    }
}

private struct StoredSettings: Codable {
    let onboardingCompleted: Bool
    let didSignInWithApple: Bool
    let dataConsentAccepted: Bool?
    let userGenderRawValue: String
    let heightCm: Double
    let currentWeightKg: Double
    let goalWeightKg: Double
    let goalDurationMonths: Int?
    let selectedPlan: TrainingPlan?
    let planStartedAt: Date?
    let weightCheckIns: [WeightCheckIn]?
    let lastWeightPromptAt: Date?
    let tutorialCompleted: Bool
    let tutorialCalibration: TutorialCalibration?
    let triggerPreferenceRawValue: String
    let workoutTimeBandRawValue: String?
    let homeLocation: HomeLocation?
    let triggerLocations: [HomeLocation]?
    let appBlockingEnabled: Bool
    let exerciseRawValue: String
    let targetReps: Int
    let alarmHour: Int
    let alarmMinute: Int
    let isAlarmEnabled: Bool
    let inAppLockEnabled: Bool
    let workoutMusicEnabled: Bool?
    let selectedMusicTrackRawValue: String?
    let workoutMusicVolume: Double?
}
