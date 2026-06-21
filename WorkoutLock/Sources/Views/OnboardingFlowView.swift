import AuthenticationServices
import MapKit
import SwiftUI
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
#endif

private enum OnboardingStep: Int, CaseIterable {
    case quickTrial
    case signIn
    case consent
    case profile
    case goal
    case plan
    case commitmentBlock
    case commitmentTrigger
    case trigger
}

private enum OnboardingPalette {
    static let ink = WorkoutInk.primary
}

private enum GoalDurationOption: Int, CaseIterable, Identifiable {
    case three = 3
    case six = 6
    case twelve = 12

    var id: Int { rawValue }
    var months: Int { rawValue }

    var title: String {
        "\(rawValue)ヶ月"
    }

    var badge: String? {
        self == .six ? "おすすめ" : nil
    }
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationTrigger: LocationTriggerService
    @StateObject private var shielding = ScreenShieldingService()
    @StateObject private var onboardingMusic = WorkoutMusicPlayer()
    @State private var step: OnboardingStep = .quickTrial
    @State private var showTutorial = false
    @State private var signInErrorMessage: String?
    @State private var showBlockPicker = false
    @State private var isGeneratingPlan = false
    @State private var locationKind: TriggerLocationKind = .home
    @State private var locationDelayMinutes = 10
    @State private var showMapPicker = false
    @State private var buddyPopToken = 0

    var body: some View {
        ZStack {
            WorkoutTheme.background.ignoresSafeArea()
            GlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    storyHeader

                    switch step {
                    case .quickTrial:
                        quickTrialStep
                    case .signIn:
                        signInStep
                    case .consent:
                        consentStep
                    case .profile:
                        profileStep
                    case .goal:
                        goalStep
                    case .plan:
                        planStep
                    case .commitmentBlock:
                        commitmentBlockStep
                    case .commitmentTrigger:
                        commitmentTriggerStep
                    case .trigger:
                        triggerStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            WorkoutSessionView(
                exercise: .squat,
                targetReps: 5,
                tutorialPlan: nil
            ) {
                store.markTutorialCompleted()
                showTutorial = false
                advance(to: .signIn)
            }
            .environmentObject(store)
        }
        .onAppear {
            startOnboardingMusic()
        }
        .onDisappear {
            onboardingMusic.stop()
        }
        .onChange(of: showTutorial) { _, isPresented in
            if isPresented {
                onboardingMusic.stop()
            } else {
                startOnboardingMusic()
            }
        }
        .onChange(of: store.workoutMusicEnabled) { _, isEnabled in
            if isEnabled {
                startOnboardingMusic()
            } else {
                onboardingMusic.stop()
            }
        }
        .onChange(of: store.workoutMusicVolume) { _, volume in
            onboardingMusic.updateVolume(volume)
        }
        .onChange(of: locationTrigger.capturedHomeLocation) { _, location in
            guard let location else { return }
            store.upsertTriggerLocation(location)
        }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .familyActivityPicker(isPresented: $showBlockPicker, selection: $shielding.selection)
        .onChange(of: showBlockPicker) { _, isPresented in
            if !isPresented {
                shielding.applyShielding(isEnabled: store.appBlockingEnabled)
            }
        }
        #endif
        .onChange(of: store.appBlockingEnabled) { _, isEnabled in
            if !isEnabled {
                shielding.applyShielding(isEnabled: false)
            }
        }
        .sheet(isPresented: $showMapPicker) {
            LocationMapPickerView(
                kind: locationKind,
                delayMinutes: locationDelayMinutes
            ) { location in
                store.triggerPreference = .homeArrival
                store.upsertTriggerLocation(location)
                locationTrigger.startMonitoring(locations: store.triggerLocations)
            }
        }
    }

    private var usesHomeTrigger: Bool {
        store.triggerPreference == .homeArrival || store.triggerPreference == .both
    }

    private var stepIndex: Int {
        OnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    private var stepCount: Int {
        OnboardingStep.allCases.count
    }

    private var userAgeBinding: Binding<Double> {
        Binding(
            get: { Double(store.userAge) },
            set: { store.userAge = Int($0.rounded()) }
        )
    }

    private var storyHeader: some View {
        VStack(spacing: 18) {
            HStack(spacing: 5) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? WorkoutTheme.accent : WorkoutInk.secondary.opacity(0.35))
                        .frame(height: 5)
                }
            }

            AnimatedWorkoutBuddyHeader(
                stepIndex: stepIndex,
                stepCount: stepCount,
                isComplete: step == .trigger,
                popToken: buddyPopToken
            )
        }
        .padding(.bottom, 2)
    }

    private func advance(to nextStep: OnboardingStep) {
        guard step != nextStep else { return }
        step = nextStep
        buddyPopToken += 1
        Haptics.lightTap()
    }

    private func startOnboardingMusic() {
        guard store.workoutMusicEnabled, !showTutorial else { return }

        let track = WorkoutMusicTrack.randomWorkoutTrack(fallback: store.selectedMusicTrack)
        let bundledTracks = WorkoutMusicTrack.allCases.filter { $0.bundledURL() != nil }
        let fallbackTracks = (WorkoutMusicTrack.availableRandomPool() + bundledTracks).filter { $0 != track }

        if let startedTrack = onboardingMusic.start(
            track: track,
            volume: store.workoutMusicVolume,
            isEnabled: true,
            fallbackTracks: fallbackTracks
        ) {
            WorkoutMusicTrack.saveLastWorkoutTrack(startedTrack)
        }
    }

    private var quickTrialStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingTitle(
                title: "まず5回だけ",
                subtitle: "カメラで数えます"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .black))
                        .frame(width: 58, height: 58)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("全身が入ればOK")
                            .font(.title3.weight(.black))
                        Text("iPhoneを少し離して置いて、まずは5回だけ。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                }

            }
            .onboardingPanel()

            Button {
                Haptics.mediumTap()
                onboardingMusic.stop()
                showTutorial = true
            } label: {
                FullWidthPrimaryLabel(title: "5回だけ試す", systemImage: "play.fill", minHeight: 72)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                advance(to: .signIn)
            } label: {
                FullWidthSecondaryLabel(title: "設定から始める")
            }
            .buttonStyle(.plain)
        }
    }

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingTitle(
                title: "本人確認",
                subtitle: "記録を端末に紐づけます"
            )

            SignInWithAppleButton(.continue) { request in
                Haptics.selection()
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success:
                    signInErrorMessage = nil
                    store.markAppleSignedIn()
                    advance(to: .consent)
                case .failure(let error):
                    signInErrorMessage = appleSignInErrorMessage(for: error)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(WorkoutInk.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            #if DEBUG
            Button {
                Haptics.selection()
                signInErrorMessage = nil
                store.markAppleSignedIn()
                advance(to: .consent)
            } label: {
                FullWidthSecondaryLabel(title: "Appleログインなしで開発確認")
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private func appleSignInErrorMessage(for error: Error) -> String {
        if let authorizationError = error as? ASAuthorizationError {
            switch authorizationError.code {
            case .canceled:
                return "Appleログインがキャンセルされました。もう一度試すか、開発確認で進めます。"
            case .failed:
                return "Appleログインに失敗しました。SimulatorのApple ID状態、またはApple Developer側のCapabilityを確認してください。"
            case .invalidResponse:
                return "Appleから不正な応答が返りました。少し待って再試行してください。"
            case .notHandled:
                return "Appleログインが処理されませんでした。Simulatorでは開発確認で進めます。"
            case .unknown:
                return "Appleログインで不明なエラーが出ました。Simulatorでは開発確認で進めます。"
            case .notInteractive:
                return "対話式ログインを開始できませんでした。Simulatorを前面にして再試行してください。"
            case .preferSignInWithApple:
                return "この端末ではAppleログインが推奨されています。もう一度Appleログインを試してください。"
            case .deviceNotConfiguredForPasskeyCreation:
                return "端末側のパスキー設定が未完了です。Simulatorでは開発確認で進めます。"
            case .matchedExcludedCredential:
                return "このApple IDではログインを続行できませんでした。"
            case .credentialImport:
                return "認証情報の取り込みに失敗しました。"
            case .credentialExport:
                return "認証情報の書き出しに失敗しました。"
            @unknown default:
                return "Appleログインに失敗しました: \(error.localizedDescription)"
            }
        }

        return "Appleログインに失敗しました: \(error.localizedDescription)"
    }

    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "データの同意",
                subtitle: ""
            )

            VStack(alignment: .leading, spacing: 12) {
                ConsentLine(text: "体重や目標体重からプランを作る")
                ConsentLine(text: "Apple Visionの骨格ログを端末に保存する")
                ConsentLine(text: "ワークアウト完了時のカメラ映像をログに残す")
                ConsentLine(text: "同意しなくても、手動設定で続けられる")
            }
            .onboardingPanel()

            HStack(spacing: 12) {
                Button {
                    Haptics.selection()
                    store.setDataConsent(false)
                    advance(to: .profile)
                } label: {
                    FullWidthSecondaryLabel(title: "同意しない")
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    store.setDataConsent(true)
                    advance(to: .profile)
                } label: {
                    FullWidthPrimaryLabel(title: "同意する", systemImage: "checkmark")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "今の状態",
                subtitle: "ざっくりでOK"
            )

            VStack(spacing: 18) {
                Picker("性別", selection: $store.userGender) {
                    ForEach(UserGender.allCases) { gender in
                        Text(gender.title).tag(gender)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.userGender) { _, _ in
                    Haptics.selection()
                }

                WheelNumberPickerRow(
                    title: "身長",
                    suffix: "cm",
                    value: $store.heightCm,
                    range: 120...220,
                    step: 1,
                    fractionDigits: 0
                )

                WheelNumberPickerRow(
                    title: "現在の体重",
                    suffix: "kg",
                    value: $store.currentWeightKg,
                    range: 35...160,
                    step: 0.5,
                    fractionDigits: 1
                )

                WheelNumberPickerRow(
                    title: "年齢",
                    suffix: "歳",
                    value: userAgeBinding,
                    range: 12...90,
                    step: 1,
                    fractionDigits: 0
                )

                Picker("運動経験", selection: $store.fitnessLevel) {
                    ForEach(FitnessLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.fitnessLevel) { _, _ in
                    Haptics.selection()
                }
            }
            .onboardingPanel()

            Button {
                Haptics.selection()
                advance(to: .goal)
            } label: {
                FullWidthPrimaryLabel(title: "次へ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "目標",
                subtitle: "期間とペースを選ぶ"
            )

            VStack(spacing: 18) {
                WheelNumberPickerRow(
                    title: "目標体重",
                    suffix: "kg",
                    value: $store.goalWeightKg,
                    range: 35...160,
                    step: 0.5,
                    fractionDigits: 1
                )

                HStack {
                    Text("差分")
                    Spacer()
                    Text("\(abs(store.currentWeightKg - store.goalWeightKg), specifier: "%.1f")kg")
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("続ける期間")
                        .font(.headline.weight(.black))

                    HStack(spacing: 10) {
                        ForEach(GoalDurationOption.allCases) { option in
                            GoalDurationOptionButton(
                                option: option,
                                isSelected: store.goalDurationMonths == option.months
                            ) {
                                Haptics.selection()
                                store.goalDurationMonths = option.months
                            }
                        }
                    }
                }

                Picker("食事", selection: $store.foodPreference) {
                    ForEach(FoodPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.foodPreference) { _, _ in
                    Haptics.selection()
                }

                Picker("週の回数", selection: $store.trainingDaysPerWeek) {
                    ForEach(2...5, id: \.self) { days in
                        Text("\(days)日").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.trainingDaysPerWeek) { _, _ in
                    Haptics.selection()
                }

                if let result = store.currentPlanResult {
                    PlanEstimateSummary(
                        result: result,
                        daysPerWeek: store.trainingDaysPerWeek,
                        durationMonths: store.goalDurationMonths
                    )
                }
            }
            .onboardingPanel()

            Button {
                Haptics.mediumTap()
                generatePlan()
            } label: {
                FullWidthPrimaryLabel(title: "予測してプラン作成", systemImage: "sparkles")
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPlan)

            if isGeneratingPlan {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(WorkoutTheme.accent)
                    Text("継続率と負荷を予測中")
                        .font(.headline.weight(.black))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onboardingPanel()
            }
        }
    }

    private func generatePlan() {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true

        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run {
                isGeneratingPlan = false
                Haptics.success()
                advance(to: .plan)
            }
        }
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "このプランで進める",
                subtitle: ""
            )

            if let result = store.currentPlanResult {
                EnginePlanConfirmationCard(
                    result: result,
                    daysPerWeek: store.trainingDaysPerWeek,
                    durationMonths: store.goalDurationMonths
                )
            } else {
                Text("プランを作成できませんでした")
                    .font(.headline.weight(.black))
                    .foregroundStyle(WorkoutInk.primary)
                    .onboardingPanel()
            }

            Button {
                Haptics.mediumTap()
                store.confirmEnginePlan()
                store.appBlockingEnabled = true
                advance(to: .commitmentBlock)
            } label: {
                FullWidthPrimaryLabel(title: "このプランで始める", systemImage: "checkmark")
            }
            .buttonStyle(.plain)
            .disabled(store.currentPlanResult == nil)
        }
    }

    private var commitmentBlockStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "縛りをつける",
                subtitle: "逃げ道アプリをロック"
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 38, weight: .black))
                        .frame(width: 62, height: 62)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("アプリブロック")
                            .font(.title2.weight(.black))
                        Text(store.appBlockingEnabled ? "オン" : "オフ")
                            .font(.headline.weight(.black))
                            .foregroundStyle(store.appBlockingEnabled ? WorkoutInk.primary : WorkoutInk.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $store.appBlockingEnabled)
                        .labelsHidden()
                        .onChange(of: store.appBlockingEnabled) { _, _ in
                            Haptics.selection()
                        }
                }

                SettingsLineLike(
                    title: "ロック状態",
                    value: shielding.readinessText(isEnabled: store.appBlockingEnabled)
                )

                Button {
                    Haptics.selection()
                    Task {
                        await shielding.requestAuthorization()
                        showBlockPicker = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("ブロック対象を選ぶ", systemImage: "app.badge")
                                .font(.headline.weight(.black))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.black))
                        }

                        Text(shielding.selectionSummary)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(WorkoutInk.primary)

                        Text("SNS・動画・ブラウザなど、逃げ道になるアプリをまとめて選べます。")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.black.opacity(0.18), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    Task {
                        await shielding.requestAuthorization()
                    }
                } label: {
                    HStack {
                        Label("Screen Time権限を確認", systemImage: "checkmark.shield")
                            .font(.subheadline.weight(.black))
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.black))
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(shielding.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)
            }
            .onboardingPanel()

            Button {
                Haptics.selection()
                advance(to: .commitmentTrigger)
            } label: {
                FullWidthPrimaryLabel(title: "次へ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var commitmentTriggerStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "いつ・どこで？",
                subtitle: ""
            )

            triggerSetupPanel

            Button {
                Haptics.selection()
                advance(to: .trigger)
            } label: {
                FullWidthPrimaryLabel(title: "設定確認へ", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var triggerSetupPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("時間帯", selection: $store.workoutTimeBand) {
                    ForEach(WorkoutTimeBand.allCases) { band in
                        Text(band.title).tag(band)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.workoutTimeBand) { _, _ in
                    Haptics.selection()
                }

                Text(store.workoutTimeBand.subtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)

                Stepper("ここに着いてから \(locationDelayMinutes)分後", value: $locationDelayMinutes, in: 10...60, step: 5)
                    .font(.headline.weight(.black))
                    .onChange(of: locationDelayMinutes) { _, _ in
                        Haptics.selection()
                    }

                Picker("場所名", selection: $locationKind) {
                    ForEach(TriggerLocationKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: locationKind) { _, _ in
                    Haptics.selection()
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.selection()
                        store.triggerPreference = .homeArrival
                        locationTrigger.requestLocation(kind: locationKind, delayMinutes: locationDelayMinutes)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .font(.title3.weight(.black))
                            Text("ここでやる")
                                .font(.caption.weight(.black))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(WorkoutTheme.accent)

                    Button {
                        Haptics.selection()
                        showMapPicker = true
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "map.fill")
                                .font(.title3.weight(.black))
                            Text("地図から選ぶ")
                                .font(.caption.weight(.black))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(WorkoutTheme.accent)
                }

                if store.triggerLocations.isEmpty {
                    Text(locationTrigger.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WorkoutInk.secondary)
                } else {
                    ForEach(store.triggerLocations) { location in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(location.triggerSummary)
                                    .font(.subheadline.weight(.black))
                                Text(location.shortLabel)
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(WorkoutInk.secondary)
                            }
                            Spacer()
                            Button {
                                Haptics.lightTap()
                                store.removeTriggerLocation(location)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("その日1回やったら、その日はもう発動しません。")
                    .font(.caption.weight(.black))
                    .foregroundStyle(WorkoutInk.secondary)
            }
            .onboardingPanel()
        }
    }

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(
                title: "設定完了",
                subtitle: "明日から同じ条件でロック"
            )

            VStack(alignment: .leading, spacing: 18) {
                SettingsLineLike(title: "トリガー", value: store.triggerPreference.title)
                if store.triggerPreference == .time || store.triggerPreference == .both {
                    SettingsLineLike(title: "開始時刻", value: store.alarmTime.formatted(date: .omitted, time: .shortened))
                }
                if store.triggerPreference == .homeArrival {
                    SettingsLineLike(title: "開始条件", value: store.homeTriggerLabel ?? "帰宅後")
                }
                SettingsLineLike(title: "登録場所", value: store.triggerLocations.isEmpty ? "未設定" : "\(store.triggerLocations.count)件")
                SettingsLineLike(title: "アプリブロック", value: store.appBlockingEnabled ? "オン" : "オフ")
                SettingsLineLike(title: "ロック状態", value: shielding.readinessText(isEnabled: store.appBlockingEnabled))
                SettingsLineLike(title: "ブロック対象", value: shielding.selectionSummary)

                ForEach(store.triggerLocations) { location in
                    SettingsLineLike(title: location.kind.title, value: location.triggerSummary)
                }

                Text(shielding.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutInk.secondary)
            }
            .onboardingPanel()

            Button {
                Haptics.success()
                store.appBlockingEnabled = true
                shielding.applyShielding(isEnabled: false)
                Task { await store.scheduleDailyAlarm() }
                store.completeOnboarding()
            } label: {
                FullWidthPrimaryLabel(title: "設定完了", systemImage: "checkmark")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AnimatedWorkoutBuddyHeader: View {
    let stepIndex: Int
    let stepCount: Int
    let isComplete: Bool
    let popToken: Int

    @State private var isIdleRaised = false
    @State private var popScale: CGFloat = 1

    var body: some View {
        WorkoutBuddyView(
            phase: .ready,
            progress: Double(stepIndex + 1) / Double(max(1, stepCount)),
            isComplete: isComplete,
            size: .compact
        )
        .frame(height: 96)
        .offset(y: isIdleRaised ? -5 : 3)
        .scaleEffect(popScale)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isIdleRaised = true
            }
        }
        .onChange(of: popToken) { _, _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                popScale = 1.12
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    popScale = 1
                }
            }
        }
    }
}

private struct FullWidthPrimaryLabel: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat = 64

    var body: some View {
        HStack {
            Spacer()
            Label(title, systemImage: systemImage)
                .font(.system(size: 22, weight: .black, design: .rounded))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct FullWidthSecondaryLabel: View {
    let title: String
    var minHeight: CGFloat = 64

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .padding(.horizontal, 16)
        .foregroundStyle(WorkoutInk.primary)
        .liquidGlass(cornerRadius: 20)
        .contentShape(Rectangle())
    }
}

private struct GoalDurationOptionButton: View {
    let option: GoalDurationOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(option.title)
                    .font(.title3.monospacedDigit().weight(.black))
                    .lineLimit(1)

                Text(option.badge ?? " ")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : WorkoutInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .foregroundStyle(isSelected ? .white : OnboardingPalette.ink)
            .background(isSelected ? Color.black.opacity(0.88) : Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.18) : .black.opacity(0.12), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.badge == nil ? option.title : "\(option.title)、\(option.badge!)"))
    }
}

private struct PlanEstimateSummary: View {
    let result: PlanResult
    let daysPerWeek: Int
    let durationMonths: Int

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("目安")
                    .font(.headline.weight(.black))
                    .foregroundStyle(OnboardingPalette.ink)

                Spacer()

                Text("\(durationMonths)ヶ月")
                    .font(.caption.weight(.black))
                    .foregroundStyle(OnboardingPalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.28), in: Capsule())

                Text(result.mode.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(OnboardingPalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.28), in: Capsule())
            }

            LazyVGrid(columns: columns, spacing: 10) {
                PlanEstimateChip(value: "\(result.weekTargetReps(week: 1))", unit: "回", label: "初週")
                PlanEstimateChip(value: "\(result.finalReps)", unit: "回", label: "最終")
                PlanEstimateChip(value: "\(daysPerWeek)", unit: "回", label: "週")
                PlanEstimateChip(value: result.dietLevel.title, unit: "", label: "食事")
            }
        }
        .padding(.top, 2)
    }
}

private struct PlanEstimateChip: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(WorkoutInk.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(OnboardingPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .monospacedDigit()

                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(OnboardingPalette.ink.opacity(0.82))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlass(cornerRadius: 16)
    }
}

private struct EnginePlanConfirmationCard: View {
    let result: PlanResult
    let daysPerWeek: Int
    let durationMonths: Int

    private var durationLabel: String {
        "\(durationMonths)ヶ月 / \(result.weeks)週"
    }

    private var firstWeekReps: Int {
        result.weekTargetReps(week: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("筋トレプラン")
                    .font(.title2.weight(.black))
                Text(durationLabel)
                    .font(.subheadline.monospacedDigit().weight(.black))
                    .foregroundStyle(WorkoutInk.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("初週")
                        .font(.caption.weight(.black))
                        .foregroundStyle(WorkoutInk.secondary)
                    Text("\(firstWeekReps)回")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.headline.weight(.black))
                    .padding(.top, 28)

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("最終")
                        .font(.caption.weight(.black))
                        .foregroundStyle(WorkoutInk.secondary)
                    Text("\(result.finalReps)回")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                }
            }
            .monospacedDigit()

            HStack(spacing: 10) {
                PlanMetric(value: "\(daysPerWeek)回", label: "週")
                PlanMetric(value: result.dietLevel.title, label: "食事")
                PlanMetric(value: result.mode.title, label: "モード")
            }

            Text("期間中で徐々に増加。4週ごとに軽め週。")
                .font(.footnote.weight(.bold))
                .foregroundStyle(WorkoutInk.secondary)
        }
        .foregroundStyle(WorkoutInk.primary)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(WorkoutInk.primary.opacity(0.36), lineWidth: 1.5)
        }
    }
}

private struct LocationMapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: TriggerLocationKind
    let delayMinutes: Int
    let onSelect: (HomeLocation) -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedName: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onMapCameraChange { context in
                        centerCoordinate = context.camera.centerCoordinate
                    }
                    .ignoresSafeArea(edges: .bottom)

                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(WorkoutTheme.accent)
                    .shadow(radius: 2)

                VStack {
                    searchPanel
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Spacer()

                    Button {
                        let location = HomeLocation(
                            name: selectedName ?? kind.title,
                            kind: kind,
                            latitude: centerCoordinate.latitude,
                            longitude: centerCoordinate.longitude,
                            startDelayMinutes: delayMinutes
                        )
                        onSelect(location)
                        Haptics.success()
                        dismiss()
                    } label: {
                        FullWidthPrimaryLabel(title: "地図の中心を登録", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
            }
            .navigationTitle("場所を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.black))
                    .foregroundStyle(WorkoutInk.secondary)

                TextField("場所を検索", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        searchPlaces()
                    }

                if isSearching {
                    ProgressView()
                        .tint(WorkoutTheme.accent)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        selectedName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WorkoutInk.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(WorkoutInk.primary)
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(WorkoutTheme.background, in: RoundedRectangle(cornerRadius: 8))

            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.prefix(5).enumerated()), id: \.offset) { _, item in
                        Button {
                            selectSearchResult(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "名称なし")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(WorkoutInk.primary)
                                Text(item.placemark.title ?? "")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WorkoutInk.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item != searchResults.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(WorkoutTheme.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func searchPlaces() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )

        Task {
            do {
                let response = try await MKLocalSearch(request: request).start()
                await MainActor.run {
                    searchResults = response.mapItems
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedName = item.name ?? kind.title
        centerCoordinate = coordinate
        searchText = item.name ?? searchText
        searchResults = []
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        Haptics.selection()
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(WorkoutInk.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WorkoutInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConsentLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
        }
        .font(.subheadline.weight(.bold))
    }
}

private struct TutorialLine: View {
    let index: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(index)
                .font(.headline.monospacedDigit().weight(.black))
                .frame(width: 34, height: 34)
                .foregroundStyle(.white)
                .background(.black, in: Circle())
            Text(text)
                .font(.headline.weight(.bold))
        }
    }
}

private struct SettingsLineLike: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(WorkoutInk.secondary)
            Spacer()
            Text(value)
                .fontWeight(.black)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline.weight(.bold))
    }
}

private struct WheelNumberPickerRow: View {
    let title: String
    let suffix: String
    @Binding var value: Double
    let range: ClosedRange<Int>
    let step: Double
    let fractionDigits: Int

    private var scale: Int {
        max(1, Int((1 / step).rounded()))
    }

    private var lowerUnit: Int {
        Int((Double(range.lowerBound) * Double(scale)).rounded())
    }

    private var upperUnit: Int {
        Int((Double(range.upperBound) * Double(scale)).rounded())
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                min(max(Int((value * Double(scale)).rounded()), lowerUnit), upperUnit)
            },
            set: { unitValue in
                value = Double(unitValue) / Double(scale)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.black))
                Spacer()
                Text(displayText(for: value))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(suffix)
                    .font(.headline.weight(.black))
                    .foregroundStyle(WorkoutInk.secondary)
            }

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: lowerUnit, through: upperUnit, by: 1)), id: \.self) { unitValue in
                    Text(displayText(for: Double(unitValue) / Double(scale)))
                        .font(.headline.weight(.black))
                        .tag(unitValue)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .clipped()
            .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text(title))
            .onChange(of: value) { _, _ in
                Haptics.selection()
            }
        }
    }

    private func displayText(for number: Double) -> String {
        if fractionDigits == 0 {
            return "\(Int(number.rounded()))"
        }

        return number.formatted(.number.precision(.fractionLength(fractionDigits)))
    }
}

private struct PlanMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(WorkoutInk.secondary)
            Text(value)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(WorkoutInk.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func onboardingPanel() -> some View {
        self
            .padding(18)
            .liquidGlass(cornerRadius: 24)
    }
}

/// 適応背景にぼかした暖色ブロブを置き、すりガラスが映える下地を作る。
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(WorkoutTheme.adaptive(light: "#F5A15F", dark: "#6E351E").opacity(0.72))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -260)
            Circle()
                .fill(WorkoutTheme.adaptive(light: "#FFD7A8", dark: "#3B251B").opacity(0.62))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 130, y: 280)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
